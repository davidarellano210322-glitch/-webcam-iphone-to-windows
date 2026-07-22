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
