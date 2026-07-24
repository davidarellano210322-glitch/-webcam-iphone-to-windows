using System;
using System.Collections.Concurrent;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using System.Windows.Media.Imaging;
using iMobileDevice;
using iMobileDevice.iDevice;
using Windows.Media.FaceAnalysis;
using Windows.Media;
using Windows.Graphics.Imaging;
using System.Runtime.InteropServices.WindowsRuntime;
using WinForms = System.Windows.Forms;
using Drawing = System.Drawing;

namespace desktop_app
{
    public partial class MainWindow : Window
    {
        private void TitleBar_MouseDown(object sender, System.Windows.Input.MouseButtonEventArgs e)
        {
            if (e.ChangedButton == System.Windows.Input.MouseButton.Left)
            {
                this.DragMove();
            }
        }

        private void MinimizeBtn_Click(object sender, RoutedEventArgs e)
        {
            WindowState = WindowState.Minimized;
        }

        private void MaximizeBtn_Click(object sender, RoutedEventArgs e)
        {
            if (WindowState == WindowState.Maximized)
            {
                WindowState = WindowState.Normal;
                if (MaximizeIconText != null) MaximizeIconText.Text = "🗖";
            }
            else
            {
                WindowState = WindowState.Maximized;
                if (MaximizeIconText != null) MaximizeIconText.Text = "🗗";
            }
        }

        private void CloseBtn_Click(object sender, RoutedEventArgs e)
        {
            Close();
        }
        private bool _isTunnelRunning = false;
        private CancellationTokenSource? _tunnelCts;
        private string? _connectedDeviceUdid;
        private DispatcherTimer? _devicePollTimer;

        // Tareas en segundo plano del túnel de video. Se trackean para poder
        // esperar a que terminen de forma limpia en StopTunnel() y evitar la
        // race condition al cambiar resolución (hilos viejos compitiendo con
        // los nuevos y dejando el preview en estado inconsistente).
        private Task? _streamTask;
        private Task? _controlTask;
        private Task? _decodeReaderTask;
        private Task? _ffmpegStderrTask;
        private readonly object _stopLock = new();

        private VirtualCameraBridge _virtualCameraBridge = new VirtualCameraBridge();
        private Process? _ffmpegProcess;
        
        private int _connectionRetryCount = 0;
        private const int MaxConnectionRetries = 15;
        private const int InitialReadTimeoutMs = 8000;
        private const int StreamReadTimeoutMs = 1000;
        private bool _isInWarmupPhase = false;
        private bool _hasEverReceivedVideo = false;
        
        private iDeviceConnectionHandle? _activeControlConn;
        private readonly SemaphoreSlim _sendSemaphore = new SemaphoreSlim(1, 1);
        private bool _isUpdatingUi = false;
        
        private WriteableBitmap? _previewBitmap;
        private int _isRenderingPreview = 0;
        
        private string _activeFilter = "none";
        private double _filterIntensity = 1.0;
        private bool _isMirrorActive = false;
        private int _rotationAngle = 0;
        
        private bool _isRecording = false;
        private Process? _ffmpegRecorderProcess;
        private Stream? _ffmpegRecorderStdin;
        private int _recordWidth = 1920;
        private int _recordHeight = 1080;
        private int _activeWidth = 1920;
        private int _activeHeight = 1080;

        private FaceTracker? _faceTracker = null;
        private readonly object _faceLock = new object();
        private bool _isDetectingFaces = false;
        private double _smoothFaceX = 0;
        private double _smoothFaceY = 0;
        private double _smoothFaceW = 0;
        private double _smoothFaceH = 0;
        private bool _faceDetected = false;
        private double _smoothZoom = 1.0;
        private DateTime _lastFaceDetectedTime = DateTime.MinValue;
        private bool _isSpotlightEnabled = false;
        private double _spotlightIntensityValue = 48.0;
        private bool _isAutoFramingEnabled = false;
        private bool _isAutoFramingZoomEnabled = false;

        private WinForms.NotifyIcon? _trayIcon;
        private bool _isExiting = false;

        // Recording timer
        private DispatcherTimer? _recTimer;
        private DateTime _recStartTime;

        public MainWindow()
        {
            InitializeComponent();
            InitializeLibiMobileDevice();

            _previewBitmap = new WriteableBitmap(1920, 1080, 96, 96, System.Windows.Media.PixelFormats.Bgra32, null);
            VideoPreviewImage.Source = _previewBitmap;

            _ = InitFaceTrackerAsync();
            InitializeTrayIcon();
        }

        private void InitializeTrayIcon()
        {
            _trayIcon = new WinForms.NotifyIcon
            {
                Text = "NeoCamo Studio",
                Visible = true,
                Icon = Drawing.SystemIcons.Application
            };

            string iconPath = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "app.ico");
            if (System.IO.File.Exists(iconPath))
            {
                try { _trayIcon.Icon = new Drawing.Icon(iconPath); } catch { }
            }

            var contextMenu = new WinForms.ContextMenuStrip();
            contextMenu.Items.Add("Mostrar", null, (s, e) => ShowFromTray());
            contextMenu.Items.Add("Salir", null, (s, e) => ExitApplication());
            _trayIcon.ContextMenuStrip = contextMenu;
            _trayIcon.DoubleClick += (s, e) => ShowFromTray();
        }

        private void ShowFromTray()
        {
            Show();
            WindowState = WindowState.Normal;
            Activate();
        }

        private void ExitApplication()
        {
            _isExiting = true;
            _trayIcon?.Dispose();
            _trayIcon = null;
            Close();
        }

        protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
        {
            if (!_isExiting)
            {
                e.Cancel = true;
                Hide();
            }
            else
            {
                base.OnClosing(e);
            }
        }

        private void InitializeLibiMobileDevice()
        {
            try
            {
                Log("Inicializando librerías nativas de Apple (imobiledevice-net)...");
                NativeLibraries.Load();
                Log("[+] Librerías nativas cargadas con éxito.");

                try
                {
                    _virtualCameraBridge.Initialize();
                    Log("[+] Puente de cámara virtual DirectShow (UnityCapture) inicializado.");
                    CheckUnityCaptureDriver();
                }
                catch (Exception ex)
                {
                    Log($"[-] ADVERTENCIA: No se pudo inicializar la cámara virtual: {ex.Message}");
                }

                _devicePollTimer = new DispatcherTimer();
                _devicePollTimer.Interval = TimeSpan.FromSeconds(1);
                _devicePollTimer.Tick += (s, e) => PollDevices();
                _devicePollTimer.Start();
                Log("[*] Buscador automático de iPhone/iOS activo.");
            }
            catch (Exception ex)
            {
                Log($"[-] ERROR de inicialización: {ex.Message}");
            }
        }

        private void Log(string message)
        {
            if (!Dispatcher.CheckAccess())
            {
                Dispatcher.Invoke(() => Log(message));
                return;
            }

            string timeStamp = DateTime.Now.ToString("HH:mm:ss");
            LogTextBox.AppendText($"[{timeStamp}] {message}\n");
            LogTextBox.ScrollToEnd();

            try
            {
                string logPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "camo_log.txt");
                File.AppendAllText(logPath, $"[{timeStamp}] {message}\r\n");
            }
            catch { }
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
                        Log($"[+] iPhone detectado físicamente por USB (UDID: {activeUdid})");
                        
                        if (DeviceComboBox != null)
                        {
                            DeviceComboBox.Text = $"iPhone ({activeUdid.Substring(0, 8)})";
                        }
                        if (DeviceDetailsText != null)
                        {
                            DeviceDetailsText.Text = "USB Conectado";
                        }
                    }

                    if (!_isTunnelRunning)
                    {
                        StartTunnel();
                    }
                }
                else
                {
                    if (_connectedDeviceUdid != null)
                    {
                        _connectedDeviceUdid = null;
                        Log("[-] iPhone desconectado del cable USB.");
                        if (DeviceComboBox != null) DeviceComboBox.Text = "Sin iPhone";
                        if (DeviceDetailsText != null) DeviceDetailsText.Text = "Desconectado";
                        if (_isTunnelRunning)
                        {
                            _ = StopTunnel();
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

        private async void StartTunnelBtn_Click(object sender, RoutedEventArgs e)
        {
            if (_isTunnelRunning)
            {
                await StopTunnel();
            }
            else
            {
                if (string.IsNullOrEmpty(_connectedDeviceUdid))
                {
                    System.Windows.MessageBox.Show("Por favor, conecta un iPhone por cable USB primero.", "Dispositivo no detectado", MessageBoxButton.OK, MessageBoxImage.Warning);
                    return;
                }
                StartTunnel();
            }
        }

        private void StartTunnel()
        {
            _isTunnelRunning = true;
            _tunnelCts = new CancellationTokenSource();
            StartTunnelBtn.Background = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#475569")!;

            ushort videoPort = 6000;
            ushort controlPort = 6001;

            try
            {
                StartFFmpegDecoder(_tunnelCts.Token);
            }
            catch (Exception ex)
            {
                Log($"[-] ERROR al iniciar decodificador FFmpeg: {ex.Message}");
                _ = StopTunnel();
                return;
            }

            Log($"[*] Conectando puerto de video H.264 (iPhone:{videoPort})...");
            _streamTask = Task.Run(() => ConnectAndStreamFromIphoneAsync(_connectedDeviceUdid!, videoPort, _tunnelCts.Token));

            Log($"[*] Conectando puerto de control bidireccional (iPhone:{controlPort})...");
            _controlTask = Task.Run(() => ConnectControlChannelAsync(_connectedDeviceUdid!, controlPort, _tunnelCts.Token));

            RecordBtn.Visibility = Visibility.Visible;
        }

        private async Task StopTunnel()
        {
            Task? streamTask = null;
            Task? controlTask = null;
            Task? decodeTask = null;
            Task? stderrTask = null;

            // Se serializa con un lock para evitar que dos StopTunnel concurrentes
            // (p.ej. cambio de resolución + desconexión de USB) pisén el estado.
            lock (_stopLock)
            {
                _isTunnelRunning = false;
                _tunnelCts?.Cancel();

                if (_isRecording)
                {
                    StopRecording();
                }

                if (_ffmpegProcess != null && !_ffmpegProcess.HasExited)
                {
                    try { _ffmpegProcess.Kill(); } catch { }
                }
                _ffmpegProcess?.Dispose();
                _ffmpegProcess = null;

                _activeControlConn = null;

                // Capturamos referencias locales y reiniciamos para que el siguiente
                // StartTunnel arranque limpio (evita race condition al cambiar resolución
                // donde hilos viejos compiten con los nuevos).
                streamTask = _streamTask;
                controlTask = _controlTask;
                decodeTask = _decodeReaderTask;
                stderrTask = _ffmpegStderrTask;
                _streamTask = null;
                _controlTask = null;
                _decodeReaderTask = null;
                _ffmpegStderrTask = null;

                // Liberar el flag de render para que el siguiente Start no quede
                // atascado si un frame se quedó a medio renderizar.
                Interlocked.Exchange(ref _isRenderingPreview, 0);
            }

            // Esperar a que los hilos terminen sin bloquear el UI thread.
            // decodeReader/stderr terminan rápido (EOF al morir FFmpeg);
            // stream/control terminan al ver el token cancelado.
            try
            {
                if (decodeTask != null) await Task.WhenAny(decodeTask, Task.Delay(2000));
                if (stderrTask != null) await Task.WhenAny(stderrTask, Task.Delay(1000));
                if (streamTask != null) await Task.WhenAny(streamTask, Task.Delay(3000));
                if (controlTask != null) await Task.WhenAny(controlTask, Task.Delay(2000));
            }
            catch { }

            // Actualizar UI en el hilo correcto
            Dispatcher.Invoke(() =>
            {
                if (StartTunnelBtn != null)
                {
                    StartTunnelBtn.Background = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#55EE71")!;
                }
                if (RecordBtn != null)
                {
                    RecordBtn.Visibility = Visibility.Collapsed;
                }
                if (PlaceholderGrid != null)
                {
                    PlaceholderGrid.Visibility = Visibility.Visible;
                }
                if (StatusIndicatorDot != null)
                {
                    StatusIndicatorDot.Fill = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#DC2626")!;
                }
                if (StatusBadgeText != null)
                {
                    StatusBadgeText.Text = "SIN SEÑAL";
                    StatusBadgeText.Foreground = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#DC2626")!;
                }
                if (LiveBadge != null)
                {
                    LiveBadge.Visibility = Visibility.Collapsed;
                }
            });

            Log("[-] Servidor de túnel USB y decodificador detenidos.");
        }

        private void StartFFmpegDecoder(CancellationToken token)
        {
            Log("[*] Iniciando decodificador FFmpeg por hardware (low-delay)...");

            string ffmpegPath = FindFFmpegExecutable();
            if (ffmpegPath == null)
            {
                throw new Exception("ffmpeg.exe no encontrado. Descárgalo desde https://ffmpeg.org/download.html y agrégalo al PATH, o colócalo en la carpeta de la aplicación.");
            }
            Log($"[+] FFmpeg encontrado en: {ffmpegPath}");

            int width = 1920;
            int height = 1080;

            if (ResolutionComboBox != null && ResolutionComboBox.SelectedItem is System.Windows.Controls.ComboBoxItem item && item.Tag is string tag)
            {
                string tagLower = tag.ToLowerInvariant();
                if (tagLower == "720p")
                {
                    width = 1280; height = 720;
                }
                else if (tagLower == "1080p")
                {
                    width = 1920; height = 1080;
                }
                else if (tagLower == "4k")
                {
                    width = 3840; height = 2160;
                }
            }

            _activeWidth = width;
            _activeHeight = height;

            try
            {
                foreach (var p in Process.GetProcessesByName("ffmpeg"))
                {
                    try { p.Kill(); p.WaitForExit(1000); } catch { }
                }
            }
            catch { }
            
            string args = $"-rtbufsize 1M -max_delay 0 -probesize 32 -analyzeduration 0 -f h264 -fflags +nobuffer+discardcorrupt -flags +low_delay -avoid_negative_ts make_zero -i pipe:0 -threads 1 -fps_mode passthrough -vsync 0 -vf scale={width}:{height}:flags=fast_bilinear -flush_packets 1 -f rawvideo -pix_fmt rgba pipe:1";

            var startInfo = new ProcessStartInfo
            {
                FileName = ffmpegPath,
                Arguments = args,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            _ffmpegProcess = Process.Start(startInfo);
            if (_ffmpegProcess == null)
            {
                throw new Exception($"No se pudo arrancar {ffmpegPath}.");
            }

            _ffmpegStderrTask = Task.Run(() => ReadFFmpegStderrAsync(_ffmpegProcess.StandardError, token));
            _decodeReaderTask = Task.Run(() => ReadDecodedFrames(_ffmpegProcess.StandardOutput.BaseStream, token));
        }

        private async Task ReadFFmpegStderrAsync(StreamReader stderrReader, CancellationToken token)
        {
            try
            {
                string? line;
                while (!token.IsCancellationRequested && (line = await stderrReader.ReadLineAsync(token)) != null)
                {
                    string logLine = line;
                    if (!string.IsNullOrWhiteSpace(logLine) && 
                        (logLine.Contains("error", StringComparison.OrdinalIgnoreCase) || 
                         logLine.Contains("fail", StringComparison.OrdinalIgnoreCase) ||
                         logLine.Contains("warning", StringComparison.OrdinalIgnoreCase)))
                    {
                        Dispatcher.Invoke(() => Log($"[FFmpeg] {logLine}"));
                    }
                }
            }
            catch { }
        }

        private void ReadDecodedFrames(Stream ffmpegStdout, CancellationToken token)
        {
            int width = _activeWidth;
            int height = _activeHeight;
            int frameSize = width * height * 4;
            byte[] frameBuffer = new byte[frameSize];

            try
            {
                while (!token.IsCancellationRequested)
                {
                    int totalRead = 0;
                    while (totalRead < frameSize && !token.IsCancellationRequested)
                    {
                        int read = ffmpegStdout.Read(frameBuffer, totalRead, frameSize - totalRead);
                        if (read == 0) break;
                        totalRead += read;
                    }

                    if (totalRead == frameSize)
                    {
                        int outWidth, outHeight;
                        byte[] processedFrame = ApplyFrameProcessing(frameBuffer, width, height, out outWidth, out outHeight);

                        _virtualCameraBridge.WriteFrame(outWidth, outHeight, processedFrame);

                        if (_isRecording && _ffmpegRecorderStdin != null && outWidth == _recordWidth && outHeight == _recordHeight)
                        {
                            try
                            {
                                _ffmpegRecorderStdin.Write(processedFrame, 0, processedFrame.Length);
                            }
                            catch (Exception recEx)
                            {
                                Log($"[-] Error al escribir frame en grabadora: {recEx.Message}");
                            }
                        }

                        if (Interlocked.CompareExchange(ref _isRenderingPreview, 1, 0) == 0)
                        {
                            int processedSize = outWidth * outHeight * 4;
                            byte[] previewCopy = new byte[processedSize];
                            for (int i = 0; i < processedSize; i += 4)
                            {
                                previewCopy[i] = processedFrame[i + 2];     // B
                                previewCopy[i + 1] = processedFrame[i + 1]; // G
                                previewCopy[i + 2] = processedFrame[i];     // R
                                previewCopy[i + 3] = processedFrame[i + 3]; // A
                            }
                            
                            Dispatcher.BeginInvoke(new Action(() =>
                            {
                                try
                                {
                                    if (_previewBitmap == null || _previewBitmap.PixelWidth != outWidth || _previewBitmap.PixelHeight != outHeight)
                                    {
                                        _previewBitmap = new WriteableBitmap(outWidth, outHeight, 96, 96, System.Windows.Media.PixelFormats.Bgra32, null);
                                        VideoPreviewImage.Source = _previewBitmap;
                                    }
                                    _previewBitmap.WritePixels(
                                        new System.Windows.Int32Rect(0, 0, outWidth, outHeight),
                                        previewCopy,
                                        outWidth * 4,
                                        0
                                    );
                                }
                                catch { }
                                finally
                                {
                                    Interlocked.Exchange(ref _isRenderingPreview, 0);
                                }
                            }));
                        }
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

        private async Task ConnectAndStreamFromIphoneAsync(string udid, ushort targetPort, CancellationToken token)
        {
            var idevice = LibiMobileDevice.Instance.iDevice;
            var packetQueue = new BlockingCollection<byte[]>(new ConcurrentQueue<byte[]>(), 2);
            byte[] lengthBuf = new byte[4];
            byte[] startCode = new byte[] { 0, 0, 0, 1 };
            
            _connectionRetryCount = 0;
            _isInWarmupPhase = true;
            _hasEverReceivedVideo = false;

            Dispatcher.Invoke(() => {
                Log("[*] Iniciando ciclo de conexión con reintentos...");
                if (StatusBadgeText != null)
                {
                    StatusBadgeText.Text = "CONECTANDO...";
                    StatusBadgeText.Foreground = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#f59e0b")!;
                }
            });

            var writeTask = Task.Run(() =>
            {
                try
                {
                    foreach (var packetBuffer in packetQueue.GetConsumingEnumerable(token))
                    {
                        var stream = _ffmpegProcess?.StandardInput.BaseStream;
                        if (stream != null && _ffmpegProcess != null && !_ffmpegProcess.HasExited)
                        {
                            int packetLength = packetBuffer.Length;
                            if (packetLength >= 4)
                            {
                                uint firstVal = (uint)((packetBuffer[0] << 24) | (packetBuffer[1] << 16) | (packetBuffer[2] << 8) | packetBuffer[3]);
                                
                                if (firstVal > 0 && firstVal + 4 <= packetLength)
                                {
                                    int offset = 0;
                                    while (offset + 4 <= packetLength)
                                    {
                                        uint nalLen = (uint)((packetBuffer[offset] << 24) | (packetBuffer[offset + 1] << 16) | (packetBuffer[offset + 2] << 8) | packetBuffer[offset + 3]);
                                        if (offset + 4 + nalLen > packetLength) break;
                                        
                                        stream.Write(startCode, 0, 4);
                                        stream.Write(packetBuffer, offset + 4, (int)nalLen);
                                        
                                        offset += 4 + (int)nalLen;
                                    }
                                }
                                else
                                {
                                    stream.Write(startCode, 0, 4);
                                    stream.Write(packetBuffer, 0, packetLength);
                                }
                            }
                            stream.Flush();
                        }
                    }
                }
                catch (OperationCanceledException) { }
                catch (Exception wEx)
                {
                    Log($"[-] Error en hilo de escritura FFmpeg: {wEx.Message}");
                }
            }, token);

            while (!token.IsCancellationRequested && _connectionRetryCount < MaxConnectionRetries)
            {
                iDeviceHandle? deviceHandle = null;
                iDeviceConnectionHandle? deviceConnHandle = null;

                try
                {
                    var err = idevice.idevice_new(out deviceHandle, udid);
                    if (err != iDeviceError.Success) throw new Exception($"Error abriendo dispositivo: {err}");

                    err = idevice.idevice_connect(deviceHandle, targetPort, out deviceConnHandle);
                    if (err != iDeviceError.Success) throw new Exception($"Error conectando al puerto {targetPort}: {err}");

                    Dispatcher.Invoke(() => {
                        Log($"[+] Intento {_connectionRetryCount + 1}: Conectado al puerto {targetPort}. Esperando primer paquete de video...");
                    });

                    while (!token.IsCancellationRequested)
                    {
                        int readTimeout = _isInWarmupPhase ? InitialReadTimeoutMs : StreamReadTimeoutMs;
                        
                        var rErr = ReadExactBytes(deviceConnHandle, lengthBuf, 4, token, readTimeout);
                        if (rErr != iDeviceError.Success)
                        {
                            if (_hasEverReceivedVideo)
                                throw new IOException($"Error de lectura en cabecera USB: {rErr}");
                            else
                                throw new TimeoutException($"Timeout esperando primer paquete de video (timeout={readTimeout}ms)");
                        }

                        uint packetLength = (uint)((lengthBuf[0] << 24) | (lengthBuf[1] << 16) | (lengthBuf[2] << 8) | lengthBuf[3]);
                        if (packetLength == 0) continue;

                        byte[] packetBuffer = new byte[packetLength];
                        rErr = ReadExactBytes(deviceConnHandle, packetBuffer, (int)packetLength, token, readTimeout);
                        if (rErr != iDeviceError.Success)
                        {
                            if (_hasEverReceivedVideo)
                                throw new IOException($"Error de lectura en payload USB: {rErr}");
                            else
                                throw new TimeoutException($"Timeout leyendo payload de video (timeout={readTimeout}ms)");
                        }

                        if (_isInWarmupPhase)
                        {
                            _isInWarmupPhase = false;
                            _hasEverReceivedVideo = true;
                            _connectionRetryCount = 0;
                            Dispatcher.Invoke(() => {
                                Log("[+] ¡Primer paquete de video recibido! Streaming estable.");
                                if (PlaceholderGrid != null) PlaceholderGrid.Visibility = Visibility.Collapsed;
                                if (StatusIndicatorDot != null) StatusIndicatorDot.Fill = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#55EE71")!;
                                if (StatusBadgeText != null)
                                {
                                    StatusBadgeText.Text = "TRANSMITIENDO";
                                    StatusBadgeText.Foreground = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#55EE71")!;
                                }
                                if (LiveBadge != null)
                                {
                                    LiveBadge.Visibility = Visibility.Visible;
                                }
                            });
                        }

                        while (packetQueue.Count >= 2)
                        {
                            packetQueue.TryTake(out _);
                        }
                        packetQueue.TryAdd(packetBuffer);
                    }
                }
                catch (OperationCanceledException) { break; }
                catch (Exception ex)
                {
                    _connectionRetryCount++;
                    Dispatcher.Invoke(() => {
                        Log($"[-] Intento {_connectionRetryCount}/{MaxConnectionRetries}: {ex.GetType().Name} - {ex.Message}");
                    });

                    if (_connectionRetryCount >= MaxConnectionRetries)
                    {
                        Dispatcher.Invoke(() => {
                            Log($"[-] Se agotaron los {MaxConnectionRetries} reintentos. Deteniendo túnel.");
                            _ = StopTunnel();
                        });
                        break;
                    }

                    int delay = Math.Min(1000 * _connectionRetryCount, 5000);
                    try { await Task.Delay(delay, token); } catch { break; }
                }
                finally
                {
                    deviceConnHandle?.Dispose();
                    deviceHandle?.Dispose();
                    deviceConnHandle = null;
                    deviceHandle = null;
                }
            }

            packetQueue.CompleteAdding();
            try { await writeTask; } catch { }
            packetQueue.Dispose();
        }

        private async Task ConnectControlChannelAsync(string udid, ushort targetPort, CancellationToken token)
        {
            await Task.Yield();
            var idevice = LibiMobileDevice.Instance.iDevice;
            iDeviceHandle? deviceHandle = null;
            iDeviceConnectionHandle? deviceConnHandle = null;

            try
            {
                var err = idevice.idevice_new(out deviceHandle, udid);
                if (err != iDeviceError.Success) return;

                err = idevice.idevice_connect(deviceHandle, targetPort, out deviceConnHandle);
                if (err != iDeviceError.Success)
                {
                    Log($"[-] Canal de control no disponible en puerto {targetPort}.");
                    return;
                }

                _activeControlConn = deviceConnHandle;
                Log("[+] Canal de Control USB conectado correctamente.");
                
                byte[] lengthBuf = new byte[4];
                while (!token.IsCancellationRequested)
                {
                    var rErr = ReadExactBytes(deviceConnHandle, lengthBuf, 4, token);
                    if (rErr != iDeviceError.Success) break;

                    uint packetLength = (uint)((lengthBuf[0] << 24) | (lengthBuf[1] << 16) | (lengthBuf[2] << 8) | lengthBuf[3]);
                    if (packetLength == 0) continue;

                    byte[] packetBuffer = new byte[packetLength];
                    rErr = ReadExactBytes(deviceConnHandle, packetBuffer, (int)packetLength, token);
                    if (rErr != iDeviceError.Success) break;

                    string jsonStr = System.Text.Encoding.UTF8.GetString(packetBuffer);
                    ProcessControlMessageFromIphone(jsonStr);
                }
            }
            catch (Exception ex)
            {
                Log($"[-] Canal de Control desconectado: {ex.Message}");
            }
            finally
            {
                _activeControlConn = null;
                deviceConnHandle?.Dispose();
                deviceHandle?.Dispose();
            }
        }

        private void ProcessControlMessageFromIphone(string jsonStr)
        {
            try
            {
                using JsonDocument doc = JsonDocument.Parse(jsonStr);
                JsonElement root = doc.RootElement;
                if (root.TryGetProperty("event", out var evProp))
                {
                    string eventType = evProp.GetString() ?? "";

                    if (eventType == "ready")
                    {
                        string resolution = root.TryGetProperty("resolution", out var resProp) ? resProp.GetString() ?? "?" : "?";
                        double fps = root.TryGetProperty("fps", out var fpsProp) ? fpsProp.GetDouble() : 0;
                        string lens = root.TryGetProperty("lens", out var lensProp) ? lensProp.GetString() ?? "?" : "?";
                        Dispatcher.Invoke(() =>
                        {
                            Log($"[+] Señal 'ready' desde iOS: {resolution} @ {fps}FPS, lente: {lens}");
                        });
                        return;
                    }

                    if (eventType == "deviceInfo")
                    {
                        int batteryLevel = root.GetProperty("batteryLevel").GetInt32();
                        bool isCharging = root.GetProperty("isCharging").GetBoolean();
                        string deviceName = root.GetProperty("deviceName").GetString();
                        string systemVersion = root.GetProperty("systemVersion").GetString();
                        string lens = root.GetProperty("lens").GetString();
                        string resolution = root.GetProperty("resolution").GetString();
                        double fps = root.GetProperty("fps").GetDouble();

                        Dispatcher.Invoke(() =>
                        {
                            _isUpdatingUi = true;

                            if (BatteryPercentageText != null)
                                BatteryPercentageText.Text = $"{batteryLevel}%";
                            if (BatteryIcon != null)
                                BatteryIcon.Text = isCharging ? "⚡" : "🔋";
                            if (DeviceDetailsText != null)
                                DeviceDetailsText.Text = $"iOS {systemVersion} • USB";
                            if (DeviceComboBox != null)
                                DeviceComboBox.Text = deviceName;

                            // Update right panel battery bar
                            if (BatteryBarFill != null)
                                BatteryBarFill.Width = batteryLevel * 1.8; // max 180px
                            if (BatteryText != null)
                                BatteryText.Text = $"{batteryLevel}%";

                            _isUpdatingUi = false;
                        });
                    }
                }
            }
            catch { }
        }

        private async Task SendControlCommandAsync(string jsonCmd)
        {
            var conn = _activeControlConn;
            if (conn == null) return;

            await _sendSemaphore.WaitAsync();
            try
            {
                byte[] payload = System.Text.Encoding.UTF8.GetBytes(jsonCmd);
                byte[] lengthHeader = new byte[4];
                uint len = (uint)payload.Length;
                lengthHeader[0] = (byte)((len >> 24) & 0xFF);
                lengthHeader[1] = (byte)((len >> 16) & 0xFF);
                lengthHeader[2] = (byte)((len >> 8) & 0xFF);
                lengthHeader[3] = (byte)(len & 0xFF);

                var idevice = LibiMobileDevice.Instance.iDevice;
                uint sent = 0;
                
                var err = idevice.idevice_connection_send(conn, lengthHeader, 4, ref sent);
                if (err != iDeviceError.Success) throw new Exception($"Error enviando cabecera: {err}");

                err = idevice.idevice_connection_send(conn, payload, (uint)payload.Length, ref sent);
                if (err != iDeviceError.Success) throw new Exception($"Error enviando payload: {err}");
            }
            catch (Exception ex)
            {
                Log($"[-] Error al enviar control: {ex.Message}");
            }
            finally
            {
                _sendSemaphore.Release();
            }
        }

        // ═════ CONTROL EVENT HANDLERS ═════

        private async void LensButton_Click(object sender, RoutedEventArgs e)
        {
            if (_isUpdatingUi || _activeControlConn == null) return;
            if (sender is System.Windows.Controls.RadioButton btn && btn.Tag is string tag)
            {
                string cmd = $"{{\"cmd\":\"setCamera\",\"val\":\"{tag}\"}}";
                await SendControlCommandAsync(cmd);
            }
        }

        private async void FocusControl_Changed(object sender, RoutedEventArgs e)
        {
            if (_isUpdatingUi || AutofocusCheckBox == null || FocusSlider == null || _activeControlConn == null) return;

            bool isAuto = AutofocusCheckBox.IsChecked == true;
            FocusSlider.IsEnabled = !isAuto;

            double val = FocusSlider.Value;
            string mode = isAuto ? "auto" : "manual";
            string cmd = $"{{\"cmd\":\"setFocus\",\"mode\":\"{mode}\",\"val\":{val:F2}}}";
            await SendControlCommandAsync(cmd);
        }

        private async void ResolutionComboBox_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
        {
            if (_isUpdatingUi || ResolutionComboBox == null || FpsComboBox == null) return;

            if (ResolutionComboBox.SelectedItem is System.Windows.Controls.ComboBoxItem resItem && resItem.Tag is string res &&
                FpsComboBox.SelectedItem is System.Windows.Controls.ComboBoxItem fpsItem && fpsItem.Tag is string fpsStr)
            {
                if (double.TryParse(fpsStr, out double fps))
                {
                    if (_activeControlConn != null)
                    {
                        string cmd = $"{{\"cmd\":\"setResolution\",\"val\":\"{res}\",\"fps\":{fps}}}";
                        await SendControlCommandAsync(cmd);
                    }

                    if (_isTunnelRunning)
                    {
                        Log("[*] Reiniciando conexión de video para aplicar nueva resolución...");
                        await StopTunnel();
                        await Task.Delay(400);
                        StartTunnel();
                    }
                }
            }
        }

        private async void TorchControl_Changed(object sender, RoutedEventArgs e)
        {
            if (_isUpdatingUi || TorchCheckBox == null || _activeControlConn == null) return;
            
            bool isOn = TorchCheckBox.IsChecked == true;
            string cmd = $"{{\"cmd\":\"setTorch\",\"val\":{(isOn ? "true" : "false")}}}";
            await SendControlCommandAsync(cmd);
        }

        private async void BrightnessSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            if (_isUpdatingUi || BrightnessSlider == null || _activeControlConn == null) return;

            double val = BrightnessSlider.Value;
            string cmd = $"{{\"cmd\":\"setBrightness\",\"val\":{val:F2}}}";
            await SendControlCommandAsync(cmd);
            
            if (BrightnessValueText != null)
                BrightnessValueText.Text = val.ToString("F1");
        }

        private async void ExposureControl_Changed(object sender, RoutedEventArgs e)
        {
            if (_isUpdatingUi || ExposureCheckBox == null || ShutterSlider == null || IsoSlider == null || _activeControlConn == null) return;

            bool isCustom = ExposureCheckBox.IsChecked == true;
            ShutterSlider.IsEnabled = isCustom;
            IsoSlider.IsEnabled = isCustom;

            string cmd;
            if (isCustom)
            {
                double shutter = ShutterSlider.Value;
                double iso = IsoSlider.Value;
                cmd = $"{{\"cmd\":\"setExposure\",\"mode\":\"manual\",\"shutter\":{shutter:F2},\"iso\":{iso:F2}}}";
                if (IsoValueText != null) IsoValueText.Text = $"ISO: {iso:F0}";
            }
            else
            {
                cmd = "{\"cmd\":\"setExposure\",\"mode\":\"auto\"}";
            }
            await SendControlCommandAsync(cmd);
        }

        private async void WhiteBalanceControl_Changed(object sender, RoutedEventArgs e)
        {
            if (_isUpdatingUi || WhiteBalanceCheckBox == null || TemperatureSlider == null || TintSlider == null || _activeControlConn == null) return;

            bool isManual = WhiteBalanceCheckBox.IsChecked == true;
            TemperatureSlider.IsEnabled = isManual;
            TintSlider.IsEnabled = isManual;

            string cmd;
            if (isManual)
            {
                double temp = TemperatureSlider.Value;
                double tint = TintSlider.Value;
                cmd = $"{{\"cmd\":\"setWhiteBalance\",\"mode\":\"manual\",\"temp\":{temp:F2},\"tint\":{tint:F2}}}";
                if (TempValueText != null) TempValueText.Text = $"{temp:F0}K";
            }
            else
            {
                cmd = "{\"cmd\":\"setWhiteBalance\",\"mode\":\"auto\"}";
            }
            await SendControlCommandAsync(cmd);
        }

        private async void ZoomSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            if (_isUpdatingUi || ZoomSlider == null || _activeControlConn == null) return;

            double val = ZoomSlider.Value;
            string cmd = $"{{\"cmd\":\"setZoom\",\"val\":{val:F2}}}";
            await SendControlCommandAsync(cmd);
            
            if (ZoomValueText != null) ZoomValueText.Text = $"{val:F1}x";
            if (PropZoom != null) PropZoom.Text = $"{val:F1}x";
        }

        private void FilterComboBox_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
        {
            if (FilterComboBox != null && FilterComboBox.SelectedItem is System.Windows.Controls.ComboBoxItem item && item.Tag is string tag)
            {
                _activeFilter = tag;
                if (PropFilter != null) PropFilter.Text = item.Content.ToString();
            }
        }

        private void FilterIntensitySlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            if (FilterIntensitySlider != null)
            {
                _filterIntensity = FilterIntensitySlider.Value / 100.0;
            }
        }

        private void SceneThumb_Click(object sender, System.Windows.Input.MouseButtonEventArgs e)
        {
            // Reset all scenes
            if (Scene1Thumb != null) { Scene1Thumb.BorderBrush = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#1AFFFFFF")!; Scene1Thumb.Opacity = 0.6; }
            if (Scene2Thumb != null) { Scene2Thumb.BorderBrush = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#1AFFFFFF")!; Scene2Thumb.Opacity = 0.6; }
            if (Scene3Thumb != null) { Scene3Thumb.BorderBrush = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#1AFFFFFF")!; Scene3Thumb.Opacity = 0.6; }

            // Activate selected
            if (sender is System.Windows.Controls.Border border)
            {
                border.BorderBrush = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#55EE71")!;
                border.Opacity = 1.0;
            }
        }

        private void RecordBtn_Click(object sender, RoutedEventArgs e)
        {
            if (_isRecording)
            {
                StopRecording();
            }
            else
            {
                int currentW = 1280;
                int currentH = 720;
                if (_previewBitmap != null)
                {
                    currentW = _previewBitmap.PixelWidth;
                    currentH = _previewBitmap.PixelHeight;
                }
                StartRecording(currentW, currentH);
            }
        }

        private void StartRecording(int width, int height)
        {
            _recordWidth = width;
            _recordHeight = height;

            try
            {
                string videosFolder = Environment.GetFolderPath(Environment.SpecialFolder.MyVideos);
                if (string.IsNullOrEmpty(videosFolder))
                {
                    videosFolder = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Recordings");
                }

                if (!Directory.Exists(videosFolder))
                {
                    Directory.CreateDirectory(videosFolder);
                }

                string timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
                string filePath = Path.Combine(videosFolder, $"NeoCamo_{timestamp}.mp4");

                Log($"[*] Iniciando grabación local en: {filePath}");

                string args = $"-f rawvideo -pix_fmt rgba -s {width}x{height} -r 30 -i pipe:0 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -y \"{filePath}\"";

                var startInfo = new ProcessStartInfo
                {
                    FileName = "ffmpeg.exe",
                    Arguments = args,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardInput = true,
                    RedirectStandardOutput = false,
                    RedirectStandardError = false
                };

                _ffmpegRecorderProcess = Process.Start(startInfo);
                if (_ffmpegRecorderProcess == null)
                {
                    throw new Exception("No se pudo iniciar ffmpeg.exe para la grabación.");
                }

                _ffmpegRecorderStdin = _ffmpegRecorderProcess.StandardInput.BaseStream;
                _isRecording = true;

                _recStartTime = DateTime.Now;
                _recTimer = new DispatcherTimer();
                _recTimer.Interval = TimeSpan.FromSeconds(1);
                _recTimer.Tick += (s, e) => {
                    if (RecTimeText != null)
                        RecTimeText.Text = (DateTime.Now - _recStartTime).ToString(@"hh\:mm\:ss");
                };
                _recTimer.Start();

                RecordBtn.Content = "■ DETENER";
                Log("[+] Grabación de video iniciada con éxito.");
            }
            catch (Exception ex)
            {
                Log($"[-] ERROR al iniciar grabación: {ex.Message}");
                StopRecording();
            }
        }

        private void StopRecording()
        {
            _isRecording = false;
            _recTimer?.Stop();
            _recTimer = null;

            if (_ffmpegRecorderStdin != null)
            {
                try { _ffmpegRecorderStdin.Close(); } catch { }
                _ffmpegRecorderStdin = null;
            }

            if (_ffmpegRecorderProcess != null)
            {
                try
                {
                    if (!_ffmpegRecorderProcess.HasExited)
                    {
                        _ffmpegRecorderProcess.WaitForExit(3000);
                        if (!_ffmpegRecorderProcess.HasExited)
                        {
                            _ffmpegRecorderProcess.Kill();
                        }
                    }
                }
                catch { }
                _ffmpegRecorderProcess.Dispose();
                _ffmpegRecorderProcess = null;
            }

            Dispatcher.Invoke(() =>
            {
                if (RecordBtn != null)
                {
                    RecordBtn.Content = "● REC";
                }
                if (RecTimeText != null)
                    RecTimeText.Text = "00:00:00";
            });

            Log("[+] Grabación guardada y finalizada correctamente.");
        }

        private void TransformControl_Changed(object sender, RoutedEventArgs e)
        {
            if (MirrorCheckBox != null)
            {
                _isMirrorActive = MirrorCheckBox.IsChecked == true;
                if (PropMirror != null) PropMirror.Text = _isMirrorActive ? "ON" : "OFF";
            }
            if (RotationComboBox != null && RotationComboBox.SelectedItem is System.Windows.Controls.ComboBoxItem item && item.Tag is string tag && int.TryParse(tag, out int angle))
            {
                _rotationAngle = angle;
                if (PropRotation != null) PropRotation.Text = $"{angle}°";
            }

            if (VideoPreviewImage != null)
            {
                var scale = new System.Windows.Media.ScaleTransform(_isMirrorActive ? -1 : 1, 1);
                scale.CenterX = 0.5;
                VideoPreviewImage.RenderTransform = scale;
                VideoPreviewImage.RenderTransformOrigin = new System.Windows.Point(0.5, 0.5);
            }
        }

        private byte[] ApplyFrameProcessing(byte[] inputRgba, int width, int height, out int outWidth, out int outHeight)
        {
            outWidth = width;
            outHeight = height;

            bool needsProcessing = _rotationAngle != 0 || 
                                   (_activeFilter != "none" && _filterIntensity > 0.0) ||
                                   (_isSpotlightEnabled && _faceDetected) ||
                                   (_isAutoFramingEnabled && _faceDetected);

            if (!needsProcessing)
            {
                return inputRgba;
            }

            byte[] processed = new byte[inputRgba.Length];
            Buffer.BlockCopy(inputRgba, 0, processed, 0, inputRgba.Length);

            if (_isSpotlightEnabled || _isAutoFramingEnabled)
            {
                TriggerFaceDetection(inputRgba, width, height);
            }

            if (_isSpotlightEnabled && _faceDetected)
            {
                ApplySpotlightInPlace(processed, width, height, _smoothFaceX, _smoothFaceY, _smoothFaceW, _smoothFaceH, _spotlightIntensityValue);
            }

            if (_rotationAngle != 0)
            {
                processed = ApplyRotation(processed, width, height, _rotationAngle, out outWidth, out outHeight);
            }

            if (_activeFilter != "none" && _filterIntensity > 0.0)
            {
                ApplyFilterInPlace(processed, _activeFilter, _filterIntensity);
            }

            if (_isAutoFramingEnabled && _faceDetected)
            {
                processed = ApplyAutoFraming(processed, outWidth, outHeight, _smoothFaceX * (outWidth / (double)width), _smoothFaceY * (outHeight / (double)height), _smoothFaceW * (outWidth / (double)width), _smoothFaceH * (outHeight / (double)height), _isAutoFramingZoomEnabled, out outWidth, out outHeight);
            }

            return processed;
        }

        private byte[] ApplyRotation(byte[] rgba, int width, int height, int angle, out int outWidth, out int outHeight)
        {
            if (angle == 90)
            {
                outWidth = height; outHeight = width;
                byte[] output = new byte[rgba.Length];
                for (int y = 0; y < height; y++)
                {
                    for (int x = 0; x < width; x++)
                    {
                        int srcIndex = (y * width + x) * 4;
                        int destX = height - 1 - y;
                        int destY = x;
                        int destIndex = (destY * outWidth + destX) * 4;
                        output[destIndex] = rgba[srcIndex];
                        output[destIndex + 1] = rgba[srcIndex + 1];
                        output[destIndex + 2] = rgba[srcIndex + 2];
                        output[destIndex + 3] = rgba[srcIndex + 3];
                    }
                }
                return output;
            }
            else if (angle == 180)
            {
                outWidth = width; outHeight = height;
                byte[] output = new byte[rgba.Length];
                int totalPixels = width * height;
                for (int i = 0; i < totalPixels; i++)
                {
                    int srcIndex = i * 4;
                    int destIndex = (totalPixels - 1 - i) * 4;
                    output[destIndex] = rgba[srcIndex];
                    output[destIndex + 1] = rgba[srcIndex + 1];
                    output[destIndex + 2] = rgba[srcIndex + 2];
                    output[destIndex + 3] = rgba[srcIndex + 3];
                }
                return output;
            }
            else if (angle == 270)
            {
                outWidth = height; outHeight = width;
                byte[] output = new byte[rgba.Length];
                for (int y = 0; y < height; y++)
                {
                    for (int x = 0; x < width; x++)
                    {
                        int srcIndex = (y * width + x) * 4;
                        int destX = y;
                        int destY = width - 1 - x;
                        int destIndex = (destY * outWidth + destX) * 4;
                        output[destIndex] = rgba[srcIndex];
                        output[destIndex + 1] = rgba[srcIndex + 1];
                        output[destIndex + 2] = rgba[srcIndex + 2];
                        output[destIndex + 3] = rgba[srcIndex + 3];
                    }
                }
                return output;
            }
            else
            {
                outWidth = width; outHeight = height;
                return rgba;
            }
        }

        private void ApplyFilterInPlace(byte[] rgba, string filter, double intensity)
        {
            for (int i = 0; i < rgba.Length; i += 4)
            {
                byte r = rgba[i];
                byte g = rgba[i + 1];
                byte b = rgba[i + 2];

                byte targetR = r, targetG = g, targetB = b;

                switch (filter)
                {
                    case "mono":
                        byte gray = (byte)(0.299 * r + 0.587 * g + 0.114 * b);
                        targetR = gray; targetG = gray; targetB = gray;
                        break;
                    case "sepia":
                        targetR = (byte)Math.Min(255, 0.393 * r + 0.769 * g + 0.189 * b);
                        targetG = (byte)Math.Min(255, 0.349 * r + 0.686 * g + 0.168 * b);
                        targetB = (byte)Math.Min(255, 0.272 * r + 0.534 * g + 0.131 * b);
                        break;
                    case "negative":
                        targetR = (byte)(255 - r); targetG = (byte)(255 - g); targetB = (byte)(255 - b);
                        break;
                    case "vintage":
                        targetR = (byte)Math.Min(255, r * 1.1 + 10);
                        targetG = (byte)Math.Min(255, g * 1.05 + 5);
                        targetB = (byte)(b * 0.9);
                        break;
                    case "cool":
                        targetR = (byte)(r * 0.9);
                        targetG = (byte)Math.Min(255, g * 1.02);
                        targetB = (byte)Math.Min(255, b * 1.15 + 10);
                        break;
                }

                if (intensity < 1.0)
                {
                    rgba[i] = (byte)(r + (targetR - r) * intensity);
                    rgba[i + 1] = (byte)(g + (targetG - g) * intensity);
                    rgba[i + 2] = (byte)(b + (targetB - b) * intensity);
                }
                else
                {
                    rgba[i] = targetR; rgba[i + 1] = targetG; rgba[i + 2] = targetB;
                }
            }
        }

        private void CheckUnityCaptureDriver()
        {
            try
            {
                using var testMmf = System.IO.MemoryMappedFiles.MemoryMappedFile.OpenExisting("UnityCapture_Data");
                Log("[+] Driver UnityCapture detectado. Cámara virtual disponible.");
            }
            catch (FileNotFoundException)
            {
                Log("[-] Driver UnityCapture NO registrado. La cámara virtual no estará disponible.");
                Log("    Para activarla, ejecuta 'InstallVirtualCamera.bat' como ADMINISTRADOR.");
            }
        }

        private string? FindFFmpegExecutable()
        {
            string appDir = AppDomain.CurrentDomain.BaseDirectory;
            string localPath = Path.Combine(appDir, "ffmpeg.exe");
            if (File.Exists(localPath)) return localPath;

            try
            {
                var process = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = "where",
                        Arguments = "ffmpeg.exe",
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        CreateNoWindow = true
                    }
                };
                process.Start();
                string output = process.StandardOutput.ReadLine() ?? "";
                process.WaitForExit(3000);
                if (!string.IsNullOrEmpty(output) && File.Exists(output.Trim()))
                    return output.Trim();
            }
            catch { }

            string[] commonPaths = {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "ffmpeg", "bin", "ffmpeg.exe"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "ffmpeg", "bin", "ffmpeg.exe"),
                @"C:\ffmpeg\bin\ffmpeg.exe",
                @"C:\tools\ffmpeg\bin\ffmpeg.exe"
            };
            foreach (var path in commonPaths)
            {
                if (File.Exists(path)) return path;
            }

            return null;
        }

        private iDeviceError ReadExactBytes(iDeviceConnectionHandle connection, byte[] targetBuffer, int length, CancellationToken token, int timeoutMs = 1000)
        {
            var idevice = LibiMobileDevice.Instance.iDevice;
            int totalRead = 0;
            byte[] tempBuffer = new byte[length];
            int consecutiveZeroReads = 0;

            while (totalRead < length && !token.IsCancellationRequested)
            {
                uint readThisTime = 0;
                uint toRead = (uint)(length - totalRead);
                
                var err = idevice.idevice_connection_receive_timeout(connection, tempBuffer, toRead, ref readThisTime, (uint)timeoutMs);
                if (err != iDeviceError.Success) return err;

                if (readThisTime > 0)
                {
                    Buffer.BlockCopy(tempBuffer, 0, targetBuffer, totalRead, (int)readThisTime);
                    totalRead += (int)readThisTime;
                    consecutiveZeroReads = 0;
                }
                else
                {
                    consecutiveZeroReads++;
                    // Back-off progresivo: más tiempo de espera por cada lectura fallida consecutiva
                    int sleepMs = Math.Min(consecutiveZeroReads * 5, 100);
                    Thread.Sleep(sleepMs);
                }
            }
            return iDeviceError.Success;
        }

        private async Task InitFaceTrackerAsync()
        {
            try
            {
                if (FaceTracker.IsSupported)
                {
                    _faceTracker = await FaceTracker.CreateAsync();
                    Log("[+] Windows FaceTracker (detección facial por hardware) inicializado.");
                }
                else
                {
                    Log("[-] Windows FaceTracker no está soportado en este equipo.");
                }
            }
            catch (Exception ex)
            {
                Log($"[-] Error inicializando FaceTracker: {ex.Message}");
            }
        }

        private void TriggerFaceDetection(byte[] frame, int width, int height)
        {
            if (_faceTracker == null) return;

            lock (_faceLock)
            {
                if (_isDetectingFaces) return;
                _isDetectingFaces = true;
            }

            byte[] frameCopy = new byte[frame.Length];
            Buffer.BlockCopy(frame, 0, frameCopy, 0, frame.Length);

            Task.Run(async () =>
            {
                try
                {
                    var buffer = frameCopy.AsBuffer();
                    var softwareBitmap = SoftwareBitmap.CreateCopyFromBuffer(buffer, BitmapPixelFormat.Rgba8, width, height);
                    using (var videoFrame = VideoFrame.CreateWithSoftwareBitmap(softwareBitmap))
                    {
                        var faces = await _faceTracker.ProcessNextFrameAsync(videoFrame);

                        lock (_faceLock)
                        {
                            if (faces != null && faces.Count > 0)
                            {
                                var face = faces[0];
                                double targetX = face.FaceBox.X;
                                double targetY = face.FaceBox.Y;
                                double targetW = face.FaceBox.Width;
                                double targetH = face.FaceBox.Height;

                                if (!_faceDetected)
                                {
                                    _smoothFaceX = targetX;
                                    _smoothFaceY = targetY;
                                    _smoothFaceW = targetW;
                                    _smoothFaceH = targetH;
                                    _faceDetected = true;
                                }
                                else
                                {
                                    double lerp = 0.25;
                                    _smoothFaceX += (targetX - _smoothFaceX) * lerp;
                                    _smoothFaceY += (targetY - _smoothFaceY) * lerp;
                                    _smoothFaceW += (targetW - _smoothFaceW) * lerp;
                                    _smoothFaceH += (targetH - _smoothFaceH) * lerp;
                                }
                                _lastFaceDetectedTime = DateTime.Now;
                            }
                            else
                            {
                                if (DateTime.Now - _lastFaceDetectedTime > TimeSpan.FromSeconds(1.5))
                                {
                                    _faceDetected = false;
                                }
                            }
                        }
                    }
                }
                catch { }
                finally
                {
                    lock (_faceLock)
                    {
                        _isDetectingFaces = false;
                    }
                }
            });
        }

        private void ApplySpotlightInPlace(byte[] rgba, int width, int height, double faceX, double faceY, double faceW, double faceH, double intensity)
        {
            double centerX = faceX + faceW / 2;
            double centerY = faceY + faceH / 2;
            double radiusX = faceW * 1.3;
            double radiusY = faceH * 1.3;

            double maxDim = Math.Max(radiusX, radiusY);
            double radiusSq = maxDim * maxDim;
            double dimFactor = (intensity / 100.0) * 0.75;

            Parallel.For(0, height, y =>
            {
                int rowStart = y * width * 4;
                double dy = y - centerY;
                double dySq = dy * dy;

                for (int x = 0; x < width; x++)
                {
                    int idx = rowStart + x * 4;
                    double dx = x - centerX;
                    double dxSq = dx * dx;

                    double distanceSq = dxSq + dySq;

                    if (distanceSq > radiusSq)
                    {
                        rgba[idx] = (byte)(rgba[idx] * (1.0 - dimFactor));
                        rgba[idx + 1] = (byte)(rgba[idx + 1] * (1.0 - dimFactor));
                        rgba[idx + 2] = (byte)(rgba[idx + 2] * (1.0 - dimFactor));
                    }
                    else
                    {
                        double distance = Math.Sqrt(distanceSq);
                        double radius = maxDim;
                        double innerRadius = radius * 0.6;
                        if (distance > innerRadius)
                        {
                            double t = (distance - innerRadius) / (radius - innerRadius);
                            t = Math.Max(0.0, Math.Min(1.0, t));
                            double currentDim = dimFactor * t;
                            rgba[idx] = (byte)(rgba[idx] * (1.0 - currentDim));
                            rgba[idx + 1] = (byte)(rgba[idx + 1] * (1.0 - currentDim));
                            rgba[idx + 2] = (byte)(rgba[idx + 2] * (1.0 - currentDim));
                        }
                    }
                }
            });
        }

        private byte[] ApplyAutoFraming(byte[] rgba, int width, int height, double faceX, double faceY, double faceW, double faceH, bool useZoom, out int outWidth, out int outHeight)
        {
            double zoom = 1.35;
            if (useZoom)
            {
                double targetFaceHeight = height * 0.35;
                zoom = targetFaceHeight / faceH;
                zoom = Math.Max(1.0, Math.Min(3.0, zoom));
            }

            _smoothZoom += (zoom - _smoothZoom) * 0.08;

            int cropW = (int)(width / _smoothZoom);
            int cropH = (int)(height / _smoothZoom);

            double faceCenterX = faceX + faceW / 2;
            double faceCenterY = faceY + faceH / 2;

            int cropX = (int)(faceCenterX - cropW / 2.0);
            int cropY = (int)(faceCenterY - cropH / 2.0);

            cropX = Math.Max(0, Math.Min(width - cropW, cropX));
            cropY = Math.Max(0, Math.Min(height - cropH, cropY));

            outWidth = width;
            outHeight = height;

            return CropAndScale(rgba, width, height, cropX, cropY, cropW, cropH, width, height);
        }

        private byte[] CropAndScale(byte[] rgba, int srcW, int srcH, int cropX, int cropY, int cropW, int cropH, int destW, int destH)
        {
            byte[] output = new byte[destW * destH * 4];
            double scaleX = (double)cropW / destW;
            double scaleY = (double)cropH / destH;

            Parallel.For(0, destH, dy =>
            {
                double sy = cropY + dy * scaleY;
                int y_low = (int)Math.Floor(sy);
                int y_high = Math.Min(srcH - 1, y_low + 1);
                double ty = sy - y_low;

                int destRowStart = dy * destW * 4;
                int srcRowLowStart = y_low * srcW * 4;
                int srcRowHighStart = y_high * srcW * 4;

                for (int dx = 0; dx < destW; dx++)
                {
                    double sx = cropX + dx * scaleX;
                    int x_low = (int)Math.Floor(sx);
                    int x_high = Math.Min(srcW - 1, x_low + 1);
                    double tx = sx - x_low;

                    int idx_00 = srcRowLowStart + x_low * 4;
                    int idx_10 = srcRowLowStart + x_high * 4;
                    int idx_01 = srcRowHighStart + x_low * 4;
                    int idx_11 = srcRowHighStart + x_high * 4;

                    int destIdx = destRowStart + dx * 4;

                    for (int c = 0; c < 4; c++)
                    {
                        double val = (1 - tx) * (1 - ty) * rgba[idx_00 + c] +
                                     tx * (1 - ty) * rgba[idx_10 + c] +
                                     (1 - tx) * ty * rgba[idx_01 + c] +
                                     tx * ty * rgba[idx_11 + c];
                        output[destIdx + c] = (byte)val;
                    }
                }
            });

            return output;
        }

        private void AutoFramingControl_Changed(object sender, RoutedEventArgs e)
        {
            if (AutoFramingCheckBox != null)
            {
                _isAutoFramingEnabled = AutoFramingCheckBox.IsChecked == true;
            }
            if (AutoFramingZoomCheckBox != null)
            {
                _isAutoFramingZoomEnabled = AutoFramingZoomCheckBox.IsChecked == true;
                AutoFramingZoomCheckBox.IsEnabled = _isAutoFramingEnabled;
            }
        }

        private void SpotlightCheckBox_Changed(object sender, RoutedEventArgs e)
        {
            if (SpotlightCheckBox != null)
            {
                _isSpotlightEnabled = SpotlightCheckBox.IsChecked == true;
            }
        }

        private void SpotlightSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            if (SpotlightSlider != null)
            {
                _spotlightIntensityValue = SpotlightSlider.Value;
            }
        }

        private void ShowLogsCheckBox_Changed(object sender, RoutedEventArgs e)
        {
            if (LogBorder == null) return;
            LogBorder.Visibility = ShowLogsCheckBox.IsChecked == true ? Visibility.Visible : Visibility.Collapsed;
        }

        protected override void OnClosed(EventArgs e)
        {
            _ = StopTunnel();
            _devicePollTimer?.Stop();
            _virtualCameraBridge.Dispose();
            _trayIcon?.Dispose();
            base.OnClosed(e);
        }
    }
}
