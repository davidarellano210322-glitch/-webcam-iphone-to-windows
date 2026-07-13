using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using iMobileDevice;
using iMobileDevice.iDevice;

namespace desktop_app
{
    public partial class MainWindow : Window
    {
        private bool _isTunnelRunning = false;
        private CancellationTokenSource? _tunnelCts;
        private string? _connectedDeviceUdid;
        private DispatcherTimer? _devicePollTimer;
        private TcpListener? _tcpListener;
        
        private VirtualCameraBridge _virtualCameraBridge = new VirtualCameraBridge();
        private Process? _ffmpegProcess;
        private Stream? _ffmpegStdin;

        public MainWindow()
        {
            InitializeComponent();
            InitializeLibiMobileDevice();
        }

        private void InitializeLibiMobileDevice()
        {
            try
            {
                Log("Inicializando librerías nativas de Apple (imobiledevice-net)...");
                NativeLibraries.Load();
                Log("[+] Librerías nativas cargadas con éxito.");

                // Inicializar el puente de cámara virtual
                _virtualCameraBridge.Initialize();
                Log("[+] Puente de cámara virtual DirectShow (UnityCapture) inicializado.");

                // Iniciar polling para detectar dispositivos
                _devicePollTimer = new DispatcherTimer();
                _devicePollTimer.Interval = TimeSpan.FromSeconds(1);
                _devicePollTimer.Tick += (s, e) => PollDevices();
                _devicePollTimer.Start();
                Log("[*] Buscador automático de iPhone/iOS activo.");
            }
            catch (Exception ex)
            {
                Log($"[-] ERROR de inicialización: {ex.Message}");
                Log("    Por favor, asegúrate de que iTunes esté instalado en tu PC y el driver registrado.");
            }
        }

        private void Log(string message)
        {
            string timeStamp = DateTime.Now.ToString("HH:mm:ss");
            LogTextBox.AppendText($"[{timeStamp}] {message}\n");
            LogTextBox.ScrollToEnd();
        }

        private void PollDevices()
        {
            try
            {
                var idevice = LibiMobileDevice.Instance.iDevice;
                ReadOnlyCollection<string> udids;
                int count = 0;
                
                var ret = idevice.idevice_get_device_list(out udids, ref count);

                if (ret == iDeviceError.Success && count > 0)
                {
                    string activeUdid = udids[0];
                    if (_connectedDeviceUdid != activeUdid)
                    {
                        _connectedDeviceUdid = activeUdid;
                        DeviceStatusText.Text = "Conectado";
                        DeviceStatusText.Foreground = System.Windows.Media.Brushes.Green;
                        DeviceDetailsText.Text = $"UDID: {activeUdid}\n(Conectado por cable USB)";
                        Log($"[+] iPhone detectado físicamente por USB (UDID: {activeUdid})");
                    }
                }
                else
                {
                    if (_connectedDeviceUdid != null)
                    {
                        _connectedDeviceUdid = null;
                        DeviceStatusText.Text = "Desconectado";
                        DeviceStatusText.Foreground = System.Windows.Media.Brushes.Red;
                        DeviceDetailsText.Text = "Enchufa tu iPhone por USB";
                        Log("[-] iPhone desconectado del cable USB.");
                        if (_isTunnelRunning)
                        {
                            StopTunnel();
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _devicePollTimer?.Stop();
                Log($"[-] Error al consultar usbmuxd: {ex.Message}");
            }
        }

        private void StartTunnelBtn_Click(object sender, RoutedEventArgs e)
        {
            if (_isTunnelRunning)
            {
                StopTunnel();
            }
            else
            {
                if (string.IsNullOrEmpty(_connectedDeviceUdid))
                {
                    MessageBox.Show("Por favor, conecta un iPhone por cable USB primero.", "Dispositivo no detectado", MessageBoxButton.OK, MessageBoxImage.Warning);
                    return;
                }
                StartTunnel();
            }
        }

        private void StartTunnel()
        {
            _isTunnelRunning = true;
            _tunnelCts = new CancellationTokenSource();
            StartTunnelBtn.Content = "Detener Servidor USB";
            StartTunnelBtn.Background = System.Windows.Media.Brushes.Red;

            int localPort = 6000;
            ushort remotePort = 6000;

            // 1. Iniciar proceso decodificador FFmpeg por GPU
            try
            {
                StartFFmpegDecoder(_tunnelCts.Token);
            }
            catch (Exception ex)
            {
                Log($"[-] ERROR al iniciar decodificador FFmpeg: {ex.Message}");
                StopTunnel();
                return;
            }

            // 2. Iniciar el listener TCP local de Windows
            _tcpListener = new TcpListener(IPAddress.Loopback, localPort);
            try
            {
                _tcpListener.Start();
                Log($"[*] Servidor de túnel USB iniciado en localhost:{localPort} -> puerto iPhone:{remotePort}");
                
                // Iniciar loop de aceptación en segundo plano
                Task.Run(() => AcceptConnectionsAsync(_tcpListener, _connectedDeviceUdid!, remotePort, _tunnelCts.Token));
            }
            catch (Exception ex)
            {
                Log($"[-] Error al iniciar servidor local en puerto {localPort}: {ex.Message}");
                StopTunnel();
            }
        }

        private void StopTunnel()
        {
            _isTunnelRunning = false;
            _tunnelCts?.Cancel();
            _tcpListener?.Stop();
            
            // Cerrar FFmpeg
            if (_ffmpegProcess != null && !_ffmpegProcess.HasExited)
            {
                try { _ffmpegProcess.Kill(); } catch { }
                _ffmpegProcess.Dispose();
                _ffmpegProcess = null;
            }
            _ffmpegStdin = null;

            StartTunnelBtn.Content = "Iniciar Servidor USB";
            StartTunnelBtn.Background = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#0284c7")!;
            Log("[-] Servidor de túnel USB y decodificador detenidos.");
        }

        private void StartFFmpegDecoder(CancellationToken token)
        {
            Log("[*] Iniciando decodificador FFmpeg por hardware (low-delay)...");
            
            // Argumentos optimizados para baja latencia (lee H.264 de stdin, escribe RGBA en stdout)
            string args = "-f h264 -avoid_negative_ts make_zero -fflags nobuffer -flags low_delay -i pipe:0 -f rawvideo -pix_fmt rgba pipe:1";

            var startInfo = new ProcessStartInfo
            {
                FileName = "ffmpeg.exe",
                Arguments = args,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = false
            };

            _ffmpegProcess = Process.Start(startInfo);
            if (_ffmpegProcess == null)
            {
                throw new Exception("No se pudo arrancar ffmpeg.exe. Verifica que esté en tu PATH.");
            }

            _ffmpegStdin = _ffmpegProcess.StandardInput.BaseStream;

            // Iniciar tarea para leer los frames decodificados RGBA de FFmpeg
            Task.Run(() => ReadDecodedFramesAsync(_ffmpegProcess.StandardOutput.BaseStream, token));
        }

        private async Task ReadDecodedFramesAsync(Stream ffmpegStdout, CancellationToken token)
        {
            int width = 1280;
            int height = 720;
            int frameSize = width * height * 4; // RGBA = 4 bytes por píxel
            byte[] frameBuffer = new byte[frameSize];

            try
            {
                while (!token.IsCancellationRequested)
                {
                    int totalRead = 0;
                    while (totalRead < frameSize && !token.IsCancellationRequested)
                    {
                        int read = await ffmpegStdout.ReadAsync(frameBuffer, totalRead, frameSize - totalRead, token);
                        if (read == 0) break; // Fin del stream (FFmpeg cerrado)
                        totalRead += read;
                    }

                    if (totalRead == frameSize)
                    {
                        // Escribir el frame en la cámara virtual DirectShow
                        _virtualCameraBridge.WriteFrame(width, height, frameBuffer);
                    }
                    else
                    {
                        break;
                    }
                }
            }
            catch (Exception ex)
            {
                Dispatcher.Invoke(() => Log($"[-] Error al leer frames decodificados: {ex.Message}"));
            }
        }

        private async Task AcceptConnectionsAsync(TcpListener listener, string udid, ushort targetPort, CancellationToken token)
        {
            try
            {
                while (!token.IsCancellationRequested)
                {
                    TcpClient localClient = await listener.AcceptTcpClientAsync(token);
                    _ = Task.Run(() => HandleClientAsync(localClient, udid, targetPort, token));
                }
            }
            catch (Exception)
            {
                // Silenciar al detener
            }
        }

        private async Task HandleClientAsync(TcpClient localClient, string udid, ushort targetPort, CancellationToken token)
        {
            Dispatcher.Invoke(() => Log("[+] Nueva conexión USB establecida. Leyendo stream del iPhone..."));
            
            var idevice = LibiMobileDevice.Instance.iDevice;
            iDeviceHandle? deviceHandle = null;
            iDeviceConnectionHandle? deviceConnHandle = null;

            try
            {
                var err = idevice.idevice_new(out deviceHandle, udid);
                if (err != iDeviceError.Success)
                {
                    throw new Exception($"No se pudo abrir el dispositivo iOS (Error: {err})");
                }

                err = idevice.idevice_connect(deviceHandle, targetPort, out deviceConnHandle);
                if (err != iDeviceError.Success)
                {
                    throw new Exception($"No se pudo conectar al puerto {targetPort} del iPhone (Error: {err}). ¿Está la app corriendo en el celular?");
                }

                // Iniciar lectura de bytes desde el USB e inyección en FFmpeg
                byte[] lengthBuf = new byte[4];
                byte[] startCode = new byte[] { 0, 0, 0, 1 }; // H.264 Annex B start code

                while (!token.IsCancellationRequested)
                {
                    // 1. Leer tamaño del NAL Unit (4 bytes)
                    var rErr = ReadExactBytes(deviceConnHandle, lengthBuf, 4, token);
                    if (rErr != iDeviceError.Success) throw new IOException($"Error leyendo cabecera del USB: {rErr}");

                    // Convertir big-endian
                    uint nalLength = (uint)((lengthBuf[0] << 24) | (lengthBuf[1] << 16) | (lengthBuf[2] << 8) | lengthBuf[3]);
                    if (nalLength == 0) continue;

                    // 2. Leer los bytes del NAL unit
                    byte[] nalBuffer = new byte[nalLength];
                    rErr = ReadExactBytes(deviceConnHandle, nalBuffer, (int)nalLength, token);
                    if (rErr != iDeviceError.Success) throw new IOException($"Error leyendo payload NAL del USB: {rErr}");

                    // 3. Escribir en FFmpeg (Start Code + NAL bytes)
                    if (_ffmpegStdin != null && _ffmpegProcess != null && !_ffmpegProcess.HasExited)
                    {
                        await _ffmpegStdin.WriteAsync(startCode, 0, 4, token);
                        await _ffmpegStdin.WriteAsync(nalBuffer, 0, (int)nalLength, token);
                        await _ffmpegStdin.FlushAsync(token); // Minimizar buffer para latencia
                    }
                }
            }
            catch (Exception ex)
            {
                Dispatcher.Invoke(() => Log($"[-] Conexión con iPhone finalizada: {ex.Message}"));
            }
            finally
            {
                deviceConnHandle?.Dispose();
                deviceHandle?.Dispose();
                localClient.Close();
            }
        }

        private iDeviceError ReadExactBytes(iDeviceConnectionHandle connection, byte[] targetBuffer, int length, CancellationToken token)
        {
            var idevice = LibiMobileDevice.Instance.iDevice;
            int totalRead = 0;
            byte[] tempBuffer = new byte[length];

            while (totalRead < length && !token.IsCancellationRequested)
            {
                uint readThisTime = 0;
                uint toRead = (uint)(length - totalRead);
                
                // Llamamos a la API de imobiledevice-net con 5 argumentos
                var err = idevice.idevice_connection_receive_timeout(connection, tempBuffer, toRead, ref readThisTime, 1000);
                if (err != iDeviceError.Success)
                {
                    return err;
                }

                if (readThisTime > 0)
                {
                    Buffer.BlockCopy(tempBuffer, 0, targetBuffer, totalRead, (int)readThisTime);
                    totalRead += (int)readThisTime;
                }
                else
                {
                    // Si se hace un timeout sin bytes leídos, dormir un milisegundo para no congelar la CPU
                    Thread.Sleep(1);
                }
            }
            
            return iDeviceError.Success;
        }


        protected override void OnClosed(EventArgs e)
        {
            StopTunnel();
            _devicePollTimer?.Stop();
            _virtualCameraBridge.Dispose();
            base.OnClosed(e);
        }
    }
}
