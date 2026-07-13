import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
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
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
