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
        
        // Video loopback TCP connection (Port 6002)
        private TcpClient? _ffmpegClient;
        private Stream? _ffmpegStream;
        
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
        private int _recordWidth = 1280;
        private int _recordHeight = 720;

        public MainWindow()
        {
            InitializeComponent();
            InitializeLibiMobileDevice();

            // Local video preview bitmap init
            _previewBitmap = new WriteableBitmap(1280, 720, 96, 96, System.Windows.Media.PixelFormats.Bgra32, null);
            VideoPreviewImage.Source = _previewBitmap;
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

            // Close local loopback socket to FFmpeg
            if (_ffmpegClient != null)
            {
                try { _ffmpegClient.Close(); } catch { }
                _ffmpegClient = null;
            }
            _ffmpegStream = null;

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

            // Clean up any existing zombie ffmpeg processes first to free up port 6002
            try
            {
                foreach (var p in Process.GetProcessesByName("ffmpeg"))
                {
                    try { p.Kill(); p.WaitForExit(1000); } catch { }
                }
            }
            catch { }
            
            // Reemplazo de stdin: Escuchamos en socket local TCP puerto 6002
            string args = "-probesize 32 -analyzeduration 0 -f h264 -avoid_negative_ts make_zero -fflags nobuffer -flags low_delay -i tcp://127.0.0.1:6002?listen -vsync 0 -threads 1 -vf scale=1280:720 -f rawvideo -pix_fmt rgba pipe:1";

            var startInfo = new ProcessStartInfo
            {
                FileName = "ffmpeg.exe",
                Arguments = args,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = false, // Recibe mediante TCP local
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            _ffmpegProcess = Process.Start(startInfo);
            if (_ffmpegProcess == null)
            {
                throw new Exception("No se pudo arrancar ffmpeg.exe. Verifica que esté en tu PATH.");
            }

            // Establecer el socket de loopback en un hilo separado
            _ = Task.Run(async () =>
            {
                await Task.Delay(150); // Tiempo para que FFmpeg levante la escucha local
                try
                {
                    _ffmpegClient = new TcpClient();
                    await _ffmpegClient.ConnectAsync("127.0.0.1", 6002);
                    _ffmpegStream = _ffmpegClient.GetStream();
                    Log("[+] Loopback de video conectado con éxito a FFmpeg.");
                }
                catch (Exception ex)
                {
                    Log($"[-] Error en loopback TCP local: {ex.Message}");
                }
            }, token);

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
            int width = 1280;
            int height = 720;
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

                    var stream = _ffmpegStream;
                    if (stream != null && _ffmpegProcess != null && !_ffmpegProcess.HasExited)
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
            if (_isUpdatingUi || ResolutionComboBox == null || FpsComboBox == null || _activeControlConn == null) return;

            if (ResolutionComboBox.SelectedItem is System.Windows.Controls.ComboBoxItem resItem && resItem.Tag is string res &&
                FpsComboBox.SelectedItem is System.Windows.Controls.ComboBoxItem fpsItem && fpsItem.Tag is string fpsStr)
            {
                if (double.TryParse(fpsStr, out double fps))
                {
                    string cmd = $"{{\"cmd\":\"setResolution\",\"val\":\"{res}\",\"fps\":{fps}}}";
                    await SendControlCommandAsync(cmd);
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

            // 1. Apply Mirror
            if (_isMirrorActive)
            {
                processed = ApplyMirror(processed, width, height);
            }

            // 2. Apply Rotation
            if (_rotationAngle != 0)
            {
                processed = ApplyRotation(processed, width, height, _rotationAngle, out outWidth, out outHeight);
            }

            // 3. Apply Filters
            if (_activeFilter != "none" && _filterIntensity > 0.0)
            {
                ApplyFilterInPlace(processed, _activeFilter, _filterIntensity);
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
            byte[] tempBuffer = new byte[length];

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

        protected override void OnClosed(EventArgs e)
        {
            StopTunnel();
            _devicePollTimer?.Stop();
            _virtualCameraBridge.Dispose();
            base.OnClosed(e);
        }
    }
}
