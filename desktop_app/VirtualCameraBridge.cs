using System;
using System.IO.MemoryMappedFiles;
using System.Threading;

namespace desktop_app
{
    public class VirtualCameraBridge : IDisposable
    {
        private MemoryMappedFile? _mmf;
        private MemoryMappedViewAccessor? _accessor;
        private Mutex? _mutex;
        private EventWaitHandle? _sentEvent;
        private EventWaitHandle? _wantEvent;
        private const int HeaderSize = 32;
        private bool _isInitialized = false;

        public void Initialize()
        {
            try
            {
                // El tamaño del buffer debe coincidir exactamente con el del driver C++:
                // sizeof(SharedMemHeader) + MAX_SHARED_IMAGE_SIZE
                long maxSize = 3840 * 2160 * 4 * 2; // MAX_SHARED_IMAGE_SIZE para 4K RGBA
                long totalSize = HeaderSize + maxSize;

                // Crear o abrir la memoria mapeada creada por el driver DirectShow
                _mmf = MemoryMappedFile.CreateOrOpen("UnityCapture_Data", totalSize);
                _accessor = _mmf.CreateViewAccessor();

                // Inicializar objetos de sincronización nativos
                _mutex = new Mutex(false, "UnityCapture_Mutx");
                _sentEvent = new EventWaitHandle(false, EventResetMode.AutoReset, "UnityCapture_Sent");
                _wantEvent = new EventWaitHandle(false, EventResetMode.AutoReset, "UnityCapture_Want");
                
                _isInitialized = true;
            }
            catch (Exception)
            {
                _isInitialized = false;
                throw;
            }
        }

        public void WriteFrame(int width, int height, byte[] rgbaData)
        {
            if (!_isInitialized || _accessor == null || _mutex == null || _sentEvent == null) return;

            int stride = width * 4;
            int dataSize = rgbaData.Length;

            // Bloquear el mutex para escritura exclusiva
            _mutex.WaitOne();
            try
            {
                // Escribir cabecera (SharedMemHeader)
                _accessor.Write(0, (uint)(3840 * 2160 * 4 * 2)); // maxSize
                _accessor.Write(4, width);                     // width
                _accessor.Write(8, height);                    // height
                _accessor.Write(12, stride);                   // stride
                _accessor.Write(16, 0);                        // format (FORMAT_UINT8 = 0)
                _accessor.Write(20, 1);                        // resizemode (RESIZEMODE_STRETCH = 1)
                _accessor.Write(24, 0);                        // mirrormode (MIRRORMODE_DISABLED = 0)
                _accessor.Write(28, 1000);                     // timeout (1000ms)

                // Escribir los bytes RGBA de la imagen decodificada
                _accessor.WriteArray(HeaderSize, rgbaData, 0, dataSize);
            }
            finally
            {
                // Liberar mutex
                _mutex.ReleaseMutex();
            }

            // Notificar al driver virtual DirectShow que el nuevo frame está listo
            _sentEvent.Set();
        }

        public void Dispose()
        {
            _accessor?.Dispose();
            _mmf?.Dispose();
            _mutex?.Dispose();
            _sentEvent?.Dispose();
            _wantEvent?.Dispose();
            _isInitialized = false;
        }
    }
}
