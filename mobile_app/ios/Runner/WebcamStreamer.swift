import Foundation
import AVFoundation
import VideoToolbox
import Network

@available(iOS 12.0, *)
class WebcamStreamer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    static let shared = WebcamStreamer()
    
    private var captureSession: AVCaptureSession?
    private var compressionSession: VTCompressionSession?
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private var isStreaming = false
    
    private let queue = DispatchQueue(label: "com.antigravity.webcam.streamqueue")
    private let socketQueue = DispatchQueue(label: "com.antigravity.webcam.socketqueue")
    
    // Iniciar el servidor TCP en el puerto 6000
    func startServer() {
        do {
            let port = NWEndpoint.Port(rawValue: 6000)!
            let parameters = NWParameters.tcp
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
            print("[-] Error al crear NWListener: \(error)")
        }
    }
    
    func stopServer() {
        stopStreaming()
        listener?.cancel()
        listener = nil
    }

    func switchCamera() {
        queue.async { [weak self] in
            guard let self = self, let session = self.captureSession else { return }
            
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            
            guard let currentInput = session.inputs.first as? AVCaptureDeviceInput else { return }
            session.removeInput(currentInput)
            
            let newPosition: AVCaptureDevice.Position = (currentInput.device.position == .back) ? .front : .back
            
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
                print("[-] No se pudo acceder a la cámara seleccionada (\(newPosition))")
                session.addInput(currentInput)
                return
            }
            
            do {
                let input = try AVCaptureDeviceInput(device: camera)
                if session.canAddInput(input) {
                    session.addInput(input)
                    print("[+] Cambiado a cámara: \(newPosition == .back ? "Trasera" : "Frontal")")
                } else {
                    session.addInput(currentInput)
                }
            } catch {
                print("[-] Error al cambiar de cámara: \(error)")
                session.addInput(currentInput)
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
    
    // Iniciar la cámara y la compresión
    private func startStreaming() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.isStreaming { return }
            
            print("[*] Iniciando captura de cámara nativa y codificador VideoToolbox...")
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
    
    // Configurar AVCaptureSession para obtener frames en bruto de la cámara trasera
    private func setupCaptureSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720 // Resolución por defecto
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("[-] No se pudo acceder a la cámara trasera.")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            // Configurar salida de datos
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange // NV12
            ]
            
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            // Ajustar FPS de la cámara a 60 FPS si es compatible, si no a 30 FPS
            try camera.lockForConfiguration()
            let optimalFormat = camera.formats.first { format in
                let ranges = format.videoSupportedFrameRateRanges
                return ranges.first?.maxFrameRate == 60.0
            }
            
            if let format = optimalFormat {
                camera.activeFormat = format
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
                camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
                print("[+] Cámara configurada a 60 FPS.")
            } else {
                camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
                print("[+] Cámara configurada a 30 FPS.")
            }
            camera.unlockForConfiguration()
            
            self.captureSession = session
        } catch {
            print("[-] Error al configurar cámara: \(error)")
        }
    }
    
    // Configurar el codificador de hardware H.264 (VideoToolbox)
    private func setupCompressionSession() {
        let width: Int32 = 1280
        let height: Int32 = 720
        
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
        
        // Propiedades para baja latencia en tiempo real
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse) // Desactivar B-frames
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 30 as CFNumber) // I-Frame cada 30 frames
        
        VTCompressionSessionPrepareToEncodeFrames(session)
        print("[+] Codificador VideoToolbox H.264 inicializado.")
    }
    
    // Callback de AVCaptureSession: recibe cada frame en bruto de la cámara
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer), isStreaming else { return }
        guard let session = compressionSession else { return }
        
        let presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        
        // Enviar a codificar
        let flags = VTEncodeInfoFlags()
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }
    
    
    // Enviar el frame H.264 codificado por el socket TCP
    private func sendCompressedFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let connection = activeConnection else { return }
        
        // 1. Verificar si el frame es un Keyframe (I-frame) y extraer SPS/PPS si es necesario
        let isKeyframe = !CFAttachmentsGetKeyframeStatus(sampleBuffer)
        
        if isKeyframe {
            if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
                var parameterSetCount: Int = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &parameterSetCount, nalUnitHeaderLengthOut: nil)
                
                // Enviar SPS (índice 0) y PPS (índice 1) para inicializar el decodificador
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
        
        // 2. Extraer los datos del video comprimido (unidades NAL H.264)
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>? = nil
        
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        
        if status == noErr, let pointer = dataPointer {
            // El buffer de VideoToolbox viene en formato AVCC (longitud de 4 bytes + bytes del NAL)
            // Mandamos los bytes directo al túnel USB
            let data = Data(bytes: pointer, count: totalLength)
            sendPacket(data)
        }
    }
    
    // Enmarcar y enviar los bytes por socket: [Tamaño (4 bytes)][Bytes del H.264 NAL]
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
    
    // Función auxiliar para saber si es un Keyframe
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
