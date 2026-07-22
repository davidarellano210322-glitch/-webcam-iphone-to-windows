import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    let controller = window?.rootViewController as! FlutterViewController
    let controlChannel = FlutterMethodChannel(
      name: "com.antigravity.webcam/control",
      binaryMessenger: controller.binaryMessenger
    )
    
    controlChannel.setMethodCallHandler { [weak self] (call, result) in
      if #available(iOS 12.0, *) {
        switch call.method {
        // ─── MÉTODOS EXISTENTES (originales) ──────────────────────────────
        case "startServer":
          WebcamStreamer.shared.startServer()
          result("ok")
        case "stopServer":
          WebcamStreamer.shared.stopServer()
          result("ok")
        case "switchCamera":
          WebcamStreamer.shared.switchCamera()
          result("ok")
        case "toggleFlash":
          WebcamStreamer.shared.setTorch(on: true)
          result("ok")
        case "setLens":
          if let args = call.arguments as? [String: Any],
             let lens = args["lens"] as? String {
            var lType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
            if lens == "0.5x" { lType = .builtInUltraWideCamera }
            else if lens == "3x" { lType = .builtInTelephotoCamera }
            WebcamStreamer.shared.updateCameraConfiguration(
              position: .back, lensType: lType, resolution: nil, fps: nil
            )
          }
          result("ok")
          
        // ─── NUEVOS MÉTODOS: CONTROL DE CÁMARA AVANZADO ────────────────────
        case "setZoom":
          if let args = call.arguments as? [String: Any],
             let zoom = args["zoom"] as? Double {
            WebcamStreamer.shared.setZoom(factor: Float(zoom))
          }
          result("ok")
          
        case "setExposure":
          if let args = call.arguments as? [String: Any],
             let value = args["value"] as? Double {
            WebcamStreamer.shared.setExposure(bias: Float(value))
          }
          result("ok")
          
        case "setISO":
          if let args = call.arguments as? [String: Any],
             let iso = args["iso"] as? Double {
            // Usar exposición custom con ISO: shutter duration por defecto (auto)
            WebcamStreamer.shared.setExposureModeCustom(shutterDurationMs: 0, iso: Float(iso))
          }
          result("ok")
          
        case "setWhiteBalance":
          if let args = call.arguments as? [String: Any],
             let kelvin = args["kelvin"] as? Double {
            // tint = 0 por defecto (solo controlamos temperatura en Kelvin)
            WebcamStreamer.shared.setWhiteBalanceManual(temp: Float(kelvin), tint: 0)
          }
          result("ok")
          
        case "setResolution":
          if let args = call.arguments as? [String: Any] {
            let resStr = args["width"] as? String ?? "1080p"
            let fps = args["fps"] as? Int ?? 30
            WebcamStreamer.shared.updateCameraConfiguration(
              position: nil, lensType: nil, resolution: resStr, fps: Double(fps)
            )
          }
          result("ok")
          
        // ─── NUEVOS MÉTODOS: GRABACIÓN LOCAL ──────────────────────────────
        case "startRecording":
          WebcamStreamer.shared.startRecording()
          result("ok")
          
        case "stopRecording":
          let url = WebcamStreamer.shared.stopRecording()
          result(url?.absoluteString)
          
        // ─── NUEVO MÉTODO: TELEMETRÍA EN TIEMPO REAL ──────────────────────
        case "getTelemetry":
          let telemetry = WebcamStreamer.shared.getTelemetry()
          result(telemetry)
          
        default:
          result(FlutterMethodNotImplemented)
        }
      } else {
        result(FlutterError(code: "UNSUPPORTED", message: "iOS 12+ required", details: nil))
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
