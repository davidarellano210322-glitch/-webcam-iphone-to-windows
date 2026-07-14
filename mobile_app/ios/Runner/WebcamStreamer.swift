import Foundation
import AVFoundation
import VideoToolbox
import Network
import UIKit

@available(iOS 12.0, *)
class WebcamStreamer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    static let shared = WebcamStreamer()
    
    private var captureSession: AVCaptureSession?
    private var compressionSession: VTCompressionSession?
    
    // Video streaming socket variables (Port 6000)
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    
    // Bidirectional control socket variables (Port 6001)
    private var controlListener: NWListener?
    private var activeControlConnection: NWConnection?
    
    private var isStreaming = false
    private var batteryTimer: Timer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    private let queue = DispatchQueue(label: "com.antigravity.webcam.streamqueue")
    private let socketQueue = DispatchQueue(label: "com.antigravity.webcam.socketqueue")
    
    // Active camera configuration parameters
    private var currentPosition: AVCaptureDevice.Position = .back
    private var currentLensType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
    private var currentResolution: String = "720p"
    private var currentFPS: Double = 30.0
    
    // Iniciar servidores TCP
    func startServer() {
        // 1. Iniciar socket de video en puerto 6000
        do {
            let port = NWEndpoint.Port(rawValue: 6000)!
            let parameters = NWParameters.tcp
            if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
                tcpOptions.noDelay = true // Evitar Nagle's algorithm para video en tiempo real
            }
            listener = try NWListener(using: parameters, on: port)
            
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[+] Servidor TCP de iOS listo y escuchando en puerto 6000")
                case .failed(let error):
                    print("[-] Error en el servidor TCP de iOS: \(error)")
                default:
                    break
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener?.start(queue: socketQueue)
        } catch {
            print("[-] Error al crear NWListener de video: \(error)")
        }
        
        // 2. Iniciar socket de control en puerto 6001
        startControlServer()
    }
    
    func stopServer() {
        stopStreaming()
        
        listener?.cancel()
        listener = nil
        
        controlListener?.cancel()
        controlListener = nil
        
        activeControlConnection?.cancel()
        activeControlConnection = nil
        
        DispatchQueue.main.async { [weak self] in
            self?.batteryTimer?.invalidate()
            self?.batteryTimer = nil
        }
    }
    
    func switchCamera() {
        let newPosition: AVCaptureDevice.Position = (currentPosition == .back) ? .front : .back
        updateCameraConfiguration(position: newPosition, lensType: .builtInWideAngleCamera, resolution: nil, fps: nil)
    }
    
    // Configurar canal de control bidireccional (Puerto 6001)
    private func startControlServer() {
        do {
            let port = NWEndpoint.Port(rawValue: 6001)!
            let parameters = NWParameters.tcp
            if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
                tcpOptions.noDelay = true // Latencia ultra-baja para comandos de control
            }
            controlListener = try NWListener(using: parameters, on: port)
            
            controlListener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[+] Servidor de Control listo y escuchando en puerto 6001")
                case .failed(let error):
                    print("[-] Error en el servidor de control: \(error)")
                default:
                    break
                }
            }
            
            controlListener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewControlConnection(connection)
            }
            
            controlListener?.start(queue: socketQueue)
        } catch {
            print("[-] Error al crear control NWListener: \(error)")
        }
    }
    
    private func handleNewControlConnection(_ connection: NWConnection) {
        socketQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.activeControlConnection != nil {
                print("[*] Canal de control ya está activo. Rechazando nueva conexion.")
                connection.cancel()
                return
            }
            
            print("[+] Canal de Control establecido con Windows.")
            self.activeControlConnection = connection
            
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed, .cancelled:
                    print("[-] Canal de Control cerrado.")
                    self?.activeControlConnection = nil
                default:
                    break
                }
            }
            
            self.listenForControlMessages(connection)
            connection.start(queue: self.socketQueue)
            
            // Enviar datos del dispositivo iniciales
            self.sendDeviceInfo()
            
            // Iniciar timer de batería periódico
            DispatchQueue.main.async {
                self.batteryTimer?.invalidate()
                self.batteryTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { _ in
                    self.socketQueue.async {
                        self.sendDeviceInfo()
                    }
                }
            }
        }
    }
    
    private func listenForControlMessages(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, context, isComplete, error in
            guard let self = self, error == nil, let data = content else {
                connection.cancel()
                return
            }
            
            // Procesar el mensaje recibido
            self.processControlMessage(data)
            
            if !isComplete {
                self.listenForControlMessages(connection)
            }
        }
    }
    
    private func processControlMessage(_ data: Data) {
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let cmd = json["cmd"] as? String {
                
                print("[*] Comando de control recibido: \(cmd)")
                switch cmd {
                case "setCamera":
                    if let val = json["val"] as? String {
                        var lens: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
                        var position: AVCaptureDevice.Position = .back
                        
                        if val == "front" {
                            position = .front
                        } else {
                            position = .back
                            if val == "telephoto" {
                                lens = .builtInTelephotoCamera
                            } else if val == "ultrawide" {
                                lens = .builtInUltraWideCamera
                            }
                        }
                        self.updateCameraConfiguration(position: position, lensType: lens, resolution: nil, fps: nil)
                    }
                    
                case "setFocus":
                    if let mode = json["mode"] as? String,
                       let val = json["val"] as? Double {
                        self.setFocus(mode: mode, position: Float(val))
                    }
                    
                case "setTorch":
                    if let val = json["val"] as? Bool {
                        self.setTorch(on: val)
                    }
                    
                case "setBrightness":
                    if let val = json["val"] as? Double {
                        self.setExposure(bias: Float(val))
                    }
                    
                case "setExposure":
                    if let mode = json["mode"] as? String {
                        if mode == "auto" {
                            self.setExposureModeAuto()
                        } else if let duration = json["shutter"] as? Double,
                                  let iso = json["iso"] as? Double {
                            self.setExposureModeCustom(shutterDurationMs: duration, iso: Float(iso))
                        }
                    }

                case "setWhiteBalance":
                    if let mode = json["mode"] as? String {
                        if mode == "auto" {
                            self.setWhiteBalanceModeAuto()
                        } else if let temp = json["temp"] as? Double,
                                  let tint = json["tint"] as? Double {
                            self.setWhiteBalanceManual(temp: Float(temp), tint: Float(tint))
                        }
                    }

                case "setZoom":
                    if let val = json["val"] as? Double {
                        self.setZoom(factor: Float(val))
                    }

                case "setResolution":
                    if let val = json["val"] as? String,
                       let fps = json["fps"] as? Double {
                        self.updateCameraConfiguration(position: nil, lensType: nil, resolution: val, fps: fps)
                    }
                    
                default:
                    break
                }
            }
        } catch {
            print("[-] Error parseando mensaje de control: \(error)")
        }
    }
    
    // Enviar estado de batería y detalles del iPhone al canal de control en Windows
    func sendDeviceInfo() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            UIDevice.current.isBatteryMonitoringEnabled = true
            let batteryLevel = Int(UIDevice.current.batteryLevel * 100)
            let isCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
            let deviceName = UIDevice.current.name
            let sysVersion = UIDevice.current.systemVersion
            
            self.socketQueue.async {
                let info: [String: Any] = [
                    "event": "deviceInfo",
                    "batteryLevel": batteryLevel,
                    "isCharging": isCharging,
                    "deviceName": deviceName,
                    "systemVersion": sysVersion,
                    "lens": self.currentLensType == .builtInTelephotoCamera ? "telephoto" :
                            self.currentLensType == .builtInUltraWideCamera ? "ultrawide" :
                            self.currentPosition == .front ? "front" : "wide",
                    "resolution": self.currentResolution,
                    "fps": self.currentFPS
                ]
                
                if let data = try? JSONSerialization.data(withJSONObject: info, options: []),
                   let conn = self.activeControlConnection {
                    var length = UInt32(data.count).bigEndian
                    let header = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
                    let packet = header + data
                    conn.send(content: packet, completion: .contentProcessed({ _ in }))
                }
            }
        }
    }
    
    // Métodos para cambiar la configuración del sensor dinámicamente
    private func getActiveCamera() -> AVCaptureDevice? {
        guard let input = captureSession?.inputs.first as? AVCaptureDeviceInput else { return nil }
        return input.device
    }
    
    func setTorch(on: Bool) {
        queue.async { [weak self] in
            guard let self = self, let camera = self.getActiveCamera() else { return }
            guard camera.hasTorch else { return }
            do {
                try camera.lockForConfiguration()
                camera.torchMode = on ? .on : .off
                camera.unlockForConfiguration()
                print("[+] Linterna configurada a: \(on ? "Encendido" : "Apagado")")
            } catch {
                print("[-] Error configurando linterna: \(error)")
            }
        }
    }
    
    func setFocus(mode: String, position: Float) {
        queue.async { [weak self] in
            guard let self = self, let camera = self.getActiveCamera() else { return }
            do {
                try camera.lockForConfiguration()
                if mode == "auto" {
                    if camera.isFocusModeSupported(.continuousAutoFocus) {
                        camera.focusMode = .continuousAutoFocus
                        print("[+] Enfoque automático continuo activo.")
                    }
                } else {
                    if camera.isFocusModeSupported(.locked) {
                        camera.focusMode = .locked
                        camera.setFocusModeLocked(lensPosition: position, completionHandler: nil)
                        print("[+] Enfoque manual bloqueado en posición: \(position)")
                    }
                }
                camera.unlockForConfiguration()
            } catch {
                print("[-] Error configurando enfoque: \(error)")
            }
        }
    }
    
    func setExposure(bias: Float) {
        queue.async { [weak self] in
            guard let self = self, let camera = self.getActiveCamera() else { return }
            do {
                try camera.lockForConfiguration()
                let clampedBias = max(camera.minExposureTargetBias, min(camera.maxExposureTargetBias, bias))
                camera.setExposureTargetBias(clampedBias, completionHandler: nil)
                camera.unlockForConfiguration()
                print("[+] Brillo de exposición configurado a: \(clampedBias)")
            } catch {
                print("[-] Error configurando exposición: \(error)")
            }
        }
    }

    func setExposureModeAuto() {
        queue.async { [weak self] in
            guard let self = self, let camera = self.getActiveCamera() else { return }
            do {
                try camera.lockForConfiguration()
                if camera.isExposureModeSupported(.continuousAutoExposure) {
                    camera.exposureMode = .continuousAutoExposure
                    print("[+] Exposición configurada a: Auto")
                }
                camera.unlockForConfiguration()
            } catch {
                print("[-] Error configurando exposición auto: \(error)")
            }
        }
    }

    func setExposureModeCustom(shutterDurationMs: Double, iso: Float) {
        queue.async { [weak self] in
            guard let self = self, let camera = self.getActiveCamera() else { return }
            do {
                try camera.lockForConfiguration()
                // Convert duration in milliseconds to CMTime
                let duration = CMTime(value: CMTimeValue(max(1.0, shutterDurationMs)), timescale: 1000)
                let clampedDuration = max(camera.activeFormat.minExposureDuration, min(camera.activeFormat.maxExposureDuration, duration))
                let clampedISO = max(camera.activeFormat.minISO, min(camera.activeFormat.maxISO, iso))
                
                if camera.isExposureModeSupported(.custom) {
                    camera.setExposureModeCustom(duration: clampedDuration, iso: clampedISO, completionHandler: nil)
                    print("[+] Exposición custom configurada: Shutter=\(shutterDurationMs)ms, ISO=\(clampedISO)")
                }
                camera.unlockForConfiguration()
            } catch {
                print("[-] Error configurando exposición custom: \(error)")
            }
        }
    }

    func setWhiteBalanceModeAuto() {
        queue.async { [weak self] in
            guard let self = self, let camera = self.getActiveCamera() else { return }
            do {
                try camera.lockForConfiguration()
                if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    camera.whiteBalanceMode = .continuousAutoWhiteBalance
                    print("[+] Balance de blancos configurado a: Auto")
                }
                camera.unlockForConfiguration()
            } catch {
                print("[-] Error configurando balance de blancos auto: \(error)")
            }
        }
    }

    func setWhiteBalanceManual(temp: Float, tint: Float) {
        queue.async { [weak self] in
            guard let self = self, let camera = self.getActiveCamera() else { return }
            do {
                try camera.lockForConfiguration()
                let tempTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: temp, tint: tint)
                var gains = camera.deviceWhiteBalanceGains(for: tempTint)
                
                let maxGain = camera.maxWhiteBalanceGain
                gains.redGain = max(1.0, min(maxGain, gains.redGain))
                gains.greenGain = max(1.0, min(maxGain, gains.greenGain))
                gains.blueGain = max(1.0, min(maxGain, gains.blueGain))
                
                camera.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
                camera.unlockForConfiguration()
                print("[+] Balance de blancos manual: Temp=\(temp), Tint=\(tint)")
            } catch {
                print("[-] Error configurando balance de blancos manual: \(error)")
            }
        }
    }

    func setZoom(factor: Float) {
        queue.async { [weak self] in
            guard let self = self, let camera = self.getActiveCamera() else { return }
            do {
                try camera.lockForConfiguration()
                let clampedFactor = max(1.0, min(camera.activeFormat.videoMaxZoomFactor, CGFloat(factor)))
                camera.videoZoomFactor = clampedFactor
                camera.unlockForConfiguration()
                print("[+] Zoom configurado a: \(clampedFactor)x")
            } catch {
                print("[-] Error configurando zoom: \(error)")
            }
        }
    }
    
    // Cambiar la resolución, cámara física o framerate
    func updateCameraConfiguration(position: AVCaptureDevice.Position?, lensType: AVCaptureDevice.DeviceType?, resolution: String?, fps: Double?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            var changed = false
            if let pos = position, pos != self.currentPosition {
                self.currentPosition = pos
                changed = true
            }
            if let lens = lensType, lens != self.currentLensType {
                self.currentLensType = lens
                changed = true
            }
            if let res = resolution, res != self.currentResolution {
                self.currentResolution = res
                changed = true
            }
            if let f = fps, f != self.currentFPS {
                self.currentFPS = f
                changed = true
            }
            
            if changed {
                print("[*] Aplicando cambios de cámara: Posición=\(self.currentPosition.rawValue), Lente=\(self.currentLensType.rawValue), Resolución=\(self.currentResolution), FPS=\(self.currentFPS)")
                
                if self.isStreaming {
                    // Detener streaming temporalmente
                    self.captureSession?.stopRunning()
                    self.captureSession = nil
                    
                    if let session = self.compressionSession {
                        VTCompressionSessionInvalidate(session)
                        self.compressionSession = nil
                    }
                    
                    // Reconfigurar con nuevos parámetros
                    self.setupCaptureSession()
                    self.setupCompressionSession()
                    
                    self.captureSession?.startRunning()
                    
                    // Notificar cambios de vuelta a Windows
                    self.sendDeviceInfo()
                }
            }
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        socketQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.activeConnection != nil {
                print("[*] Rechazando nueva conexión USB: ya hay una activa.")
                connection.cancel()
                return
            }
            
            print("[+] PC conectada a través del túnel USB.")
            self.activeConnection = connection
            
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.startStreaming()
                case .failed, .cancelled:
                    print("[-] Conexión USB cerrada.")
                    self?.stopStreaming()
                default:
                    break
                }
            }
            
            connection.start(queue: self.socketQueue)
        }
    }
    
    private func startStreaming() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.isStreaming { return }
            
            print("[*] Iniciando captura de cámara nativa y codificador VideoToolbox...")
            
            // Prevent device screen from dimming/sleeping and begin background task
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                UIApplication.shared.isIdleTimerDisabled = true
                self.backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "WebcamStreamerBackground") { [weak self] in
                    self?.stopStreaming()
                }
            }
            
            self.setupCaptureSession()
            self.setupCompressionSession()
            
            self.captureSession?.startRunning()
            self.isStreaming = true
        }
    }
    
    private func stopStreaming() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if !self.isStreaming { return }
            
            print("[*] Deteniendo captura y codificador...")
            self.isStreaming = false
            
            // Restore default idle timer behavior and end background task on main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                UIApplication.shared.isIdleTimerDisabled = false
                if self.backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                    self.backgroundTaskID = .invalid
                }
            }
            
            self.captureSession?.stopRunning()
            self.captureSession = nil
            
            if let session = self.compressionSession {
                VTCompressionSessionInvalidate(session)
                self.compressionSession = nil
            }
            
            self.activeConnection?.cancel()
            self.activeConnection = nil
        }
    }
    
    private func setupCaptureSession() {
        let session = AVCaptureSession()
        
        // Ajustar preset según resolución configurada
        var width: Int32 = 1280
        var height: Int32 = 720
        
        if currentResolution.lowercased() == "4k" {
            session.sessionPreset = .hd4K3840x2160
            width = 3840
            height = 2160
        } else if currentResolution == "1080p" {
            session.sessionPreset = .hd1920x1080
            width = 1920
            height = 1080
        } else {
            session.sessionPreset = .hd1280x720
            width = 1280
            height = 720
        }
        
        // Encontrar dispositivo de cámara
        var selectedCamera: AVCaptureDevice? = AVCaptureDevice.default(currentLensType, for: .video, position: currentPosition)
        if selectedCamera == nil {
            print("[-] Lente \(currentLensType.rawValue) no compatible. Usando lente por defecto.")
            selectedCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition)
            self.currentLensType = .builtInWideAngleCamera
        }
        
        guard let camera = selectedCamera else {
            print("[-] No se pudo acceder a ninguna cámara.")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange // NV12
            ]
            
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            // Configurar FPS
            try camera.lockForConfiguration()
            
            var optimalFormat: AVCaptureDevice.Format? = nil
            for format in camera.formats {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                if dimensions.width == width && dimensions.height == height {
                    if optimalFormat == nil {
                        optimalFormat = format
                    } else {
                        let currentMaxFPS = optimalFormat!.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30.0
                        let newMaxFPS = format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30.0
                        if newMaxFPS > currentMaxFPS {
                            optimalFormat = format
                        }
                    }
                }
            }
            
            if let format = optimalFormat {
                camera.activeFormat = format
                let maxFPS = format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30.0
                let targetFPS = min(maxFPS, currentFPS)
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(targetFPS))
                camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(targetFPS))
                print("[+] Cámara configurada a \(targetFPS) FPS en resolución \(width)x\(height).")
            } else {
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(currentFPS))
                camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(currentFPS))
            }
            
            // Desactivar autofocus continuo si configuramos foco manual previamente
            camera.unlockForConfiguration()
            self.captureSession = session
        } catch {
            print("[-] Error al configurar cámara: \(error)")
        }
    }
    
    private func setupCompressionSession() {
        var width: Int32 = 1280
        var height: Int32 = 720
        
        if currentResolution.lowercased() == "4k" {
            width = 3840
            height = 2160
        } else if currentResolution == "1080p" {
            width = 1920
            height = 1080
        }
        
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: { (outputCallbackRefCon: UnsafeMutableRawPointer?, sourceFrameRefCon: UnsafeMutableRawPointer?, status: OSStatus, infoFlags: VTEncodeInfoFlags, sampleBuffer: CMSampleBuffer?) in
                guard status == noErr, let sampleBuffer = sampleBuffer else { return }
                let streamer = Unmanaged<WebcamStreamer>.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()
                streamer.sendCompressedFrame(sampleBuffer)
            },
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &compressionSession
        )
        
        if status != noErr {
            print("[-] Error al crear VTCompressionSession: \(status)")
            return
        }
        
        guard let session = compressionSession else { return }
        
        // Propiedades de compresión para ultra-baja latencia
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: (60 as NSNumber) as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: (0 as NSNumber) as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: (currentFPS as NSNumber) as CFNumber)
        
        let rawBitrate: Int = currentResolution.lowercased() == "4k" ? 12_000_000 : (currentResolution == "1080p" ? 4_500_000 : 2_500_000)
        let targetBitrate = (rawBitrate as NSNumber) as CFNumber
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: targetBitrate)
        
        let limitBytes = ((rawBitrate / 8) as NSNumber) as CFNumber
        let limitWindow = (1.0 as NSNumber) as CFNumber
        let limits = [limitBytes, limitWindow] as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limits)
        
        VTCompressionSessionPrepareToEncodeFrames(session)
        print("[+] Codificador VideoToolbox optimizado para \(currentResolution) a \(currentFPS) FPS.")
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), isStreaming else { return }
        guard let session = compressionSession else { return }
        
        let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
        if status != noErr {
            print("[-] Error en VTCompressionSessionEncodeFrame: \(status)")
        }
    }
    
    private func sendCompressedFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let connection = activeConnection else { return }
        
        let isKeyframe = !CFAttachmentsGetKeyframeStatus(sampleBuffer)
        
        if isKeyframe {
            if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
                var parameterSetCount: Int = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &parameterSetCount, nalUnitHeaderLengthOut: nil)
                
                for i in 0..<parameterSetCount {
                    var parameterSetPointer: UnsafePointer<UInt8>? = nil
                    var parameterSetSize: Int = 0
                    CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: i, parameterSetPointerOut: &parameterSetPointer, parameterSetSizeOut: &parameterSetSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                    
                    if let pointer = parameterSetPointer {
                        let data = Data(bytes: pointer, count: parameterSetSize)
                        sendPacket(data)
                    }
                }
            }
        }
        
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>? = nil
        
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        
        if status == noErr, let pointer = dataPointer {
            let data = Data(bytes: pointer, count: totalLength)
            sendPacket(data)
        }
    }
    
    private func sendPacket(_ data: Data) {
        guard let connection = activeConnection else { return }
        
        var length = UInt32(data.count).bigEndian
        let header = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        let packet = header + data
        
        connection.send(content: packet, completion: .contentProcessed({ error in
            if let error = error {
                print("[-] Error enviando paquete por socket USB: \(error)")
            }
        }))
    }
    
    private func CFAttachmentsGetKeyframeStatus(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [NSDictionary],
              let attachment = attachments.first as? [String: Any] else {
            return false
        }
        
        if let dependsOnOthers = attachment[kCMSampleAttachmentKey_DependsOnOthers as String] as? Bool {
            return dependsOnOthers
        }
        return false
    }
}
