import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    if let controller = window?.rootViewController as? FlutterViewController {
      let controlChannel = FlutterMethodChannel(name: "com.antigravity.webcam/control",
                                                binaryMessenger: controller.binaryMessenger)
      
      controlChannel.setMethodCallHandler({
        (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
        if call.method == "startServer" {
          if #available(iOS 12.0, *) {
            WebcamStreamer.shared.startServer()
            result("Servidor iniciado")
          } else {
            result(FlutterError(code: "UNSUPPORTED", message: "iOS 12 o superior es requerido", details: nil))
          }
        } else if call.method == "stopServer" {
          if #available(iOS 12.0, *) {
            WebcamStreamer.shared.stopServer()
            result("Servidor detenido")
          } else {
            result("Detenido")
          }
        } else if call.method == "switchCamera" {
          if #available(iOS 12.0, *) {
            WebcamStreamer.shared.switchCamera()
            result("Cámara cambiada")
          } else {
            result("No soportado")
          }
        } else if call.method == "toggleFlash" {
          if #available(iOS 12.0, *) {
            WebcamStreamer.shared.setTorch(on: true)
            result("Flash cambiado")
          } else {
            result("No soportado")
          }
        } else if call.method == "setLens" {
          if let args = call.arguments as? [String: Any], let lens = args["lens"] as? String {
            if #available(iOS 12.0, *) {
              var pos: AVCaptureDevice.Position = .back
              var lType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
              if lens == "0.5x" {
                lType = .builtInUltraWideCamera
              } else if lens == "3x" {
                lType = .builtInTelephotoCamera
              }
              WebcamStreamer.shared.updateCameraConfiguration(position: pos, lensType: lType, resolution: nil, fps: nil)
            }
          }
          result("Lente cambiado")
        } else {
          result(FlutterMethodNotImplemented)
        }
      })
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
