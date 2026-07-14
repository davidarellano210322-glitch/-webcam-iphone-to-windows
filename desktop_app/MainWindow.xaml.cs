using System;
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

namespace desktop_app
{
    public partial class MainWindow : Window
    {
        private bool _isTunnelRunning = false;
        private CancellationTokenSource? _tunnelCts;
        private string? _connectedDeviceUdid;
        private DispatcherTimer? _devicePollTimer;
        
        private VirtualCameraBridge _virtualCameraBridge = new VirtualCameraBridge();
        private Process? _ffmpegProcess;
        

        
        // Dynamic control USB connection (Port 6001)
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

        // WinRT Face Analysis variables
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

        public MainWindow()
        {
            InitializeComponent();
            InitializeLibiMobileDevice();

            // Local video preview bitmap init (1080p FHD by default)
            _previewBitmap = new WriteableBitmap(1920, 1080, 96, 96, System.Windows.Media.PixelFormats.Bgra32, null);
            VideoPreviewImage.Source = _previewBitmap;

            // Start hardware-accelerated face tracker initialization
            _ = InitFaceTrackerAsync();
        }

        private void InitializeLibiMobileDevice()
        {
            try
            {
                Log("Inicializando librerías nativas de Apple (imobiledevice-net)...");
                NativeLibraries.Load();
                Log("[+] Librerías nativas cargadas con éxito.");

                // Initialize UnityCapture Virtual Camera
                _virtualCameraBridge.Initialize();
                Log("[+] Puente de cámara virtual DirectShow (UnityCapture) inicializado.");

                // Start device polling
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
                        
                        // Device detected, update UI dropdown content (temporary placeholder until control channel updates it)
                        if (DeviceComboBox != null && DeviceComboBox.Items.Count > 0 && DeviceComboBox.Items[0] is System.Windows.Controls.ComboBoxItem firstItem)
                        {
                            firstItem.Content = $"iPhone ({activeUdid.Substring(0, 8)})";
                        }
                    }

                    // Auto-start tunnel if not currently running
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
            StartTunnelBtn.Background = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#475569")!;

            ushort videoPort = 6000;
            ushort controlPort = 6001;

            // 1. Start low-latency FFmpeg decoder using local loopback input
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

            // 2. Start direct connection task for video stream (Port 6000)
            Log($"[*] Conectando puerto de video H.264 (iPhone:{videoPort})...");
            _ = Task.Run(() => ConnectAndStreamFromIphoneAsync(_connectedDeviceUdid!, videoPort, _tunnelCts.Token));

            // 3. Start direct connection task for dynamic control commands (Port 6001)
            Log($"[*] Conectando puerto de control bidireccional (iPhone:{controlPort})...");
            _ = Task.Run(() => ConnectControlChannelAsync(_connectedDeviceUdid!, controlPort, _tunnelCts.Token));

            RecordBtn.Visibility = Visibility.Visible;
        }

        private void StopTunnel()
        {
            _isTunnelRunning = false;
            _tunnelCts?.Cancel();

            // Stop local recording if active
            if (_isRecording)
            {
                StopRecording();
            }
            
            // Close FFmpeg process
            if (_ffmpegProcess != null && !_ffmpegProcess.HasExited)
            {
                try { _ffmpegProcess.Kill(); } catch { }
                _ffmpegProcess.Dispose();
                _ffmpegProcess = null;
            }



            // Clear control handle
            _activeControlConn = null;

            Dispatcher.Invoke(() =>
            {
                if (StartTunnelBtn != null)
                {
                    StartTunnelBtn.Content = "Iniciar Servidor USB";
                    StartTunnelBtn.Background = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#e11d48")!;
                }
                if (RecordBtn != null)
                {
                    RecordBtn.Visibility = Visibility.Collapsed;
                    RecordBtn.Content = "Grabar (REC)";
                    RecordBtn.Background = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#e11d48")!;
                }
                if (PlaceholderGrid != null)
                {
                    PlaceholderGrid.Visibility = Visibility.Visible;
                }
                if (StatusIndicatorDot != null)
                {
                    StatusIndicatorDot.Fill = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#ef4444")!;
                }
                if (StatusBadgeText != null)
                {
                    StatusBadgeText.Text = "SIN SEÑAL";
                    StatusBadgeText.Foreground = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#ef4444")!;
                }
            });

            Log("[-] Servidor de túnel USB y decodificador detenidos.");
        }

        private void StartFFmpegDecoder(CancellationToken token)
        {
            Log("[*] Iniciando decodificador FFmpeg por hardware (low-delay)...");

            int width = 1920;
            int height = 1080;

            if (ResolutionComboBox != null && ResolutionComboBox.SelectedItem is System.Windows.Controls.ComboBoxItem item && item.Tag is string tag)
            {
                string tagLower = tag.ToLowerInvariant();
                if (tagLower == "720p")
                {
                    width = 1280;
                    height = 720;
                }
                else if (tagLower == "1080p")
                {
                    width = 1920;
                    height = 1080;
                }
                else if (tagLower == "4k")
                {
                    width = 3840;
                    height = 2160;
                }
            }

            _activeWidth = width;
            _activeHeight = height;

            // Clean up any existing zombie ffmpeg processes first to free up port 6002
            try
            {
                foreach (var p in Process.GetProcessesByName("ffmpeg"))
                {
                    try { p.Kill(); p.WaitForExit(1000); } catch { }
                }
            }
            catch { }
            
            // Recibe mediante stdin (pipe:0)
            string args = $"-probesize 32 -analyzeduration 0 -f h264 -avoid_negative_ts make_zero -fflags nobuffer -flags low_delay -i pipe:0 -vsync 0 -threads 1 -vf scale={width}:{height} -f rawvideo -pix_fmt rgba pipe:1";

            var startInfo = new ProcessStartInfo
            {
                FileName = "ffmpeg.exe",
                Arguments = args,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true, // Recibe mediante StandardInput
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            _ffmpegProcess = Process.Start(startInfo);
            if (_ffmpegProcess == null)
            {
                throw new Exception("No se pudo arrancar ffmpeg.exe. Verifica que esté en tu PATH.");
            }

            // Leer stderr
            _ = Task.Run(() => ReadFFmpegStderrAsync(_ffmpegProcess.StandardError, token));

            // Leer frames decodificados
            _ = Task.Run(() => ReadDecodedFramesAsync(_ffmpegProcess.StandardOutput.BaseStream, token));
        }

        private async Task ReadFFmpegStderrAsync(StreamReader stderrReader, CancellationToken token)
        {
            try
            {
                string? line;
                while (!token.IsCancellationRequested && (line = await stderrReader.ReadLineAsync(token)) != null)
                {
                    string logLine = line;
                    if (!string.IsNullOrWhiteSpace(logLine))
                    {
                        Dispatcher.Invoke(() => Log($"[FFmpeg] {logLine}"));
                    }
                }
            }
            catch { }
        }

        private async Task ReadDecodedFramesAsync(Stream ffmpegStdout, CancellationToken token)
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
                        int read = await ffmpegStdout.ReadAsync(frameBuffer, totalRead, frameSize - totalRead, token);
                        if (read == 0) break;
                        totalRead += read;
                    }

                    if (totalRead == frameSize)
                    {
                        int outWidth, outHeight;
                        byte[] processedFrame = ApplyFrameProcessing(frameBuffer, width, height, out outWidth, out outHeight);

                        _virtualCameraBridge.WriteFrame(outWidth, outHeight, processedFrame);

                        // Feed the recorder if active
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
            iDeviceHandle? deviceHandle = null;
            iDeviceConnectionHandle? deviceConnHandle = null;

            try
            {
                var err = idevice.idevice_new(out deviceHandle, udid);
                if (err != iDeviceError.Success) throw new Exception($"Error abriendo dispositivo: {err}");

                err = idevice.idevice_connect(deviceHandle, targetPort, out deviceConnHandle);
                if (err != iDeviceError.Success) throw new Exception($"Error conectando al puerto {targetPort}: {err}");

                Dispatcher.Invoke(() => {
                    Log("[+] Flujo de video USB establecido.");
                    if (PlaceholderGrid != null) PlaceholderGrid.Visibility = Visibility.Collapsed;
                    if (StatusIndicatorDot != null) StatusIndicatorDot.Fill = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#4ade80")!;
                    if (StatusBadgeText != null)
                    {
                        StatusBadgeText.Text = "TRANSMITIENDO";
                        StatusBadgeText.Foreground = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#4ade80")!;
                    }
                });

                byte[] lengthBuf = new byte[4];
                byte[] startCode = new byte[] { 0, 0, 0, 1 };

                while (!token.IsCancellationRequested)
                {
                    var rErr = ReadExactBytes(deviceConnHandle, lengthBuf, 4, token);
                    if (rErr != iDeviceError.Success) throw new IOException($"Error de lectura en cabecera USB: {rErr}");

                    uint packetLength = (uint)((lengthBuf[0] << 24) | (lengthBuf[1] << 16) | (lengthBuf[2] << 8) | lengthBuf[3]);
                    if (packetLength == 0) continue;

                    byte[] packetBuffer = new byte[packetLength];
                    rErr = ReadExactBytes(deviceConnHandle, packetBuffer, (int)packetLength, token);
                    if (rErr != iDeviceError.Success) throw new IOException($"Error de lectura en payload USB: {rErr}");

                    var stream = _ffmpegProcess?.StandardInput.BaseStream;
                    if (stream != null && !_ffmpegProcess.HasExited)
                    {
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
                                    
                                    await stream.WriteAsync(startCode, 0, 4, token);
                                    await stream.WriteAsync(packetBuffer, offset + 4, (int)nalLen, token);
                                    
                                    offset += 4 + (int)nalLen;
                                }
                            }
                            else
                            {
                                await stream.WriteAsync(startCode, 0, 4, token);
                                await stream.WriteAsync(packetBuffer, 0, (int)packetLength, token);
                            }
                        }
                        await stream.FlushAsync(token);
                    }
                }
            }
            catch (Exception ex)
            {
                Dispatcher.Invoke(() => {
                    Log($"[-] Transmisión finalizada: {ex.Message}");
                    StopTunnel();
                });
            }
            finally
            {
                deviceConnHandle?.Dispose();
                deviceHandle?.Dispose();
            }
        }

        // Conectar el socket del canal de control bidireccional (Puerto 6001)
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
                    Log($"[-] Canal de control no disponible en puerto {targetPort} (¿App de iOS desactualizada?)");
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
                if (root.TryGetProperty("event", out var evProp) && evProp.GetString() == "deviceInfo")
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
                        
                        // Update Battery Telemetry
                        BatteryPercentageText.Text = $"{batteryLevel}%";
                        BatteryIcon.Text = isCharging ? "⚡" : "🔋";
                        
                        // System info label
                        DeviceDetailsText.Text = $"iOS {systemVersion} • USB Conectado";

                        // Update device combobox name
                        if (DeviceComboBox.Items.Count > 0 && DeviceComboBox.Items[0] is System.Windows.Controls.ComboBoxItem firstItem)
                        {
                            firstItem.Content = deviceName;
                        }

                        // Sync Lens selector dropdown
                        foreach (System.Windows.Controls.ComboBoxItem item in LensComboBox.Items)
                        {
                            if (item.Tag?.ToString() == lens)
                            {
                                LensComboBox.SelectedItem = item;
                                break;
                            }
                        }

                        // Sync Resolution selector dropdown
                        foreach (System.Windows.Controls.ComboBoxItem item in ResolutionComboBox.Items)
                        {
                            if (item.Tag?.ToString() == resolution)
                            {
                                ResolutionComboBox.SelectedItem = item;
                                break;
                            }
                        }

                        // Sync FPS selector dropdown
                        foreach (System.Windows.Controls.ComboBoxItem item in FpsComboBox.Items)
                        {
                            if (item.Tag?.ToString() == fps.ToString())
                            {
                                FpsComboBox.SelectedItem = item;
                                break;
                            }
                        }

                        _isUpdatingUi = false;
                    });
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
                
                // Write header
                var err = idevice.idevice_connection_send(conn, lengthHeader, 4, ref sent);
                if (err != iDeviceError.Success) throw new Exception($"Error enviando cabecera: {err}");

                // Write payload
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

        // Action listeners wired to WPF controls
        private async void LensComboBox_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
        {
            if (_isUpdatingUi || LensComboBox == null || _activeControlConn == null) return;
            if (LensComboBox.SelectedItem is System.Windows.Controls.ComboBoxItem item && item.Tag is string tag)
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
                        StopTunnel();
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
                double shutter = ShutterSlider.Value; // milliseconds
                double iso = IsoSlider.Value;
                cmd = $"{{\"cmd\":\"setExposure\",\"mode\":\"manual\",\"shutter\":{shutter:F2},\"iso\":{iso:F2}}}";
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
        }
        private void FilterComboBox_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
        {
            if (FilterComboBox != null && FilterComboBox.SelectedItem is System.Windows.Controls.ComboBoxItem item && item.Tag is string tag)
            {
                _activeFilter = tag;
            }
        }

        private void FilterIntensitySlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            if (FilterIntensitySlider != null)
            {
                _filterIntensity = FilterIntensitySlider.Value / 100.0;
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
                string filePath = Path.Combine(videosFolder, $"CamoStream_{timestamp}.mp4");

                Log($"[*] Iniciando grabación local en: {filePath}");

                // FFmpeg command to record raw video to mp4 with H.264 compression
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

                RecordBtn.Content = "Detener REC";
                RecordBtn.Background = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#ef4444")!;
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
                    RecordBtn.Content = "Grabar (REC)";
                    RecordBtn.Background = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFrom("#e11d48")!;
                }
            });

            Log("[+] Grabación guardada y finalizada correctamente.");
        }

        private void TransformControl_Changed(object sender, RoutedEventArgs e)
        {
            if (MirrorCheckBox != null)
            {
                _isMirrorActive = MirrorCheckBox.IsChecked == true;
            }
            if (RotationComboBox != null && RotationComboBox.SelectedItem is System.Windows.Controls.ComboBoxItem item && item.Tag is string tag && int.TryParse(tag, out int angle))
            {
                _rotationAngle = angle;
            }
        }

        private byte[] ApplyFrameProcessing(byte[] inputRgba, int width, int height, out int outWidth, out int outHeight)
        {
            outWidth = width;
            outHeight = height;
            byte[] processed = inputRgba;

            // Trigger asynchronous WinRT face detection
            TriggerFaceDetection(inputRgba, width, height);

            // 1. Apply Spotlight (Face Highlight)
            if (_isSpotlightEnabled && _faceDetected)
            {
                ApplySpotlightInPlace(processed, width, height, _smoothFaceX, _smoothFaceY, _smoothFaceW, _smoothFaceH, _spotlightIntensityValue);
            }

            // 2. Apply Mirror
            if (_isMirrorActive)
            {
                processed = ApplyMirror(processed, width, height);
            }

            // 3. Apply Rotation
            if (_rotationAngle != 0)
            {
                processed = ApplyRotation(processed, width, height, _rotationAngle, out outWidth, out outHeight);
            }

            // 4. Apply Filters
            if (_activeFilter != "none" && _filterIntensity > 0.0)
            {
                ApplyFilterInPlace(processed, _activeFilter, _filterIntensity);
            }

            // 5. Apply Auto Framing (Zoom & Center on Face)
            if (_isAutoFramingEnabled && _faceDetected)
            {
                processed = ApplyAutoFraming(processed, outWidth, outHeight, _smoothFaceX * (outWidth / (double)width), _smoothFaceY * (outHeight / (double)height), _smoothFaceW * (outWidth / (double)width), _smoothFaceH * (outHeight / (double)height), _isAutoFramingZoomEnabled, out outWidth, out outHeight);
            }

            return processed;
        }

        private byte[] ApplyMirror(byte[] rgba, int width, int height)
        {
            byte[] output = new byte[rgba.Length];
            int rowSize = width * 4;
            for (int y = 0; y < height; y++)
            {
                int srcRowStart = y * rowSize;
                for (int x = 0; x < width; x++)
                {
                    int srcPixel = srcRowStart + x * 4;
                    int destPixel = srcRowStart + (width - 1 - x) * 4;
                    output[destPixel] = rgba[srcPixel];
                    output[destPixel + 1] = rgba[srcPixel + 1];
                    output[destPixel + 2] = rgba[srcPixel + 2];
                    output[destPixel + 3] = rgba[srcPixel + 3];
                }
            }
            return output;
        }

        private byte[] ApplyRotation(byte[] rgba, int width, int height, int angle, out int outWidth, out int outHeight)
        {
            if (angle == 90)
            {
                outWidth = height;
                outHeight = width;
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
                outWidth = width;
                outHeight = height;
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
                outWidth = height;
                outHeight = width;
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
                outWidth = width;
                outHeight = height;
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

                byte targetR = r;
                byte targetG = g;
                byte targetB = b;

                switch (filter)
                {
                    case "mono":
                        byte gray = (byte)(0.299 * r + 0.587 * g + 0.114 * b);
                        targetR = gray;
                        targetG = gray;
                        targetB = gray;
                        break;
                    case "sepia":
                        targetR = (byte)Math.Min(255, 0.393 * r + 0.769 * g + 0.189 * b);
                        targetG = (byte)Math.Min(255, 0.349 * r + 0.686 * g + 0.168 * b);
                        targetB = (byte)Math.Min(255, 0.272 * r + 0.534 * g + 0.131 * b);
                        break;
                    case "negative":
                        targetR = (byte)(255 - r);
                        targetG = (byte)(255 - g);
                        targetB = (byte)(255 - b);
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
                    rgba[i] = targetR;
                    rgba[i + 1] = targetG;
                    rgba[i + 2] = targetB;
                }
            }
        }
        private iDeviceError ReadExactBytes(iDeviceConnectionHandle connection, byte[] targetBuffer, int length, CancellationToken token)
        {
            var idevice = LibiMobileDevice.Instance.iDevice;
            int totalRead = 0;
            byte[] tempBuffer = System.Buffers.ArrayPool<byte>.Shared.Rent(length);

            try
            {
                while (totalRead < length && !token.IsCancellationRequested)
                {
                    uint readThisTime = 0;
                    uint toRead = (uint)(length - totalRead);
                    
                    var err = idevice.idevice_connection_receive_timeout(connection, tempBuffer, toRead, ref readThisTime, 1000);
                    if (err != iDeviceError.Success) return err;

                    if (readThisTime > 0)
                    {
                        Buffer.BlockCopy(tempBuffer, 0, targetBuffer, totalRead, (int)readThisTime);
                        totalRead += (int)readThisTime;
                    }
                    else
                    {
                        Thread.Sleep(1);
                    }
                }
                return iDeviceError.Success;
            }
            finally
            {
                System.Buffers.ArrayPool<byte>.Shared.Return(tempBuffer);
            }
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

            // Copy frame for thread safety
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
            StopTunnel();
            _devicePollTimer?.Stop();
            _virtualCameraBridge.Dispose();
            base.OnClosed(e);
        }
    }
}
