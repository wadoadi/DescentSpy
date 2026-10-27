import CoreMotion
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.pluginRegistry
      .registrar(forPlugin: "DescentSpyBarometer")!.messenger()
    FlutterMethodChannel(
      name: "com.example.descent_spy/barometer",
      binaryMessenger: messenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        result(CMAltimeter.isRelativeAltitudeAvailable())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    FlutterEventChannel(
      name: "com.example.descent_spy/barometer_pressure",
      binaryMessenger: messenger
    ).setStreamHandler(BarometerStreamHandler())
  }
}

/// Streams pressure in hPa (CMAltitudeData gives kPa) and the relative altitude in metres.
final class BarometerStreamHandler: NSObject, FlutterStreamHandler {
  private let altimeter = CMAltimeter()

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    guard CMAltimeter.isRelativeAltitudeAvailable() else {
      return FlutterError(code: "unavailable", message: "Barometer is not available.", details: nil)
    }
    altimeter.startRelativeAltitudeUpdates(to: .main) { data, error in
      if let error = error {
        events(FlutterError(code: "barometer_error", message: error.localizedDescription, details: nil))
        return
      }
      guard let data = data else { return }
      events([
        "hPa": data.pressure.doubleValue * 10,
        "relativeAltitudeM": data.relativeAltitude.doubleValue,
        "elapsedMs": Int(ProcessInfo.processInfo.systemUptime * 1000),
      ])
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    altimeter.stopRelativeAltitudeUpdates()
    return nil
  }
}
