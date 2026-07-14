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
        }

        private void StopTunnel()
        {
            _isTunnelRunning = false;
            _tunnelCts?.Cancel();
            
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
                        _virtualCameraBridge.WriteFrame(width, height, frameBuffer);

                        if (Interlocked.CompareExchange(ref _isRenderingPreview, 1, 0) == 0)
                        {
                            byte[] previewCopy = new byte[frameSize];
                            for (int i = 0; i < frameSize; i += 4)
                            {
                                previewCopy[i] = frameBuffer[i + 2];     // B
                                previewCopy[i + 1] = frameBuffer[i + 1]; // G
                                previewCopy[i + 2] = frameBuffer[i];     // R
                                previewCopy[i + 3] = frameBuffer[i + 3]; // A
                            }
                            
                            Dispatcher.BeginInvoke(new Action(() =>
                            {
                                try
                                {
                                    _previewBitmap?.WritePixels(
                                        new System.Windows.Int32Rect(0, 0, width, height),
                                        previewCopy,
                                        width * 4,
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
