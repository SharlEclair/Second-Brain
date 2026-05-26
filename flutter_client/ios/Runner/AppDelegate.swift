import Flutter
import UIKit
import ActivityKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  /// Stores the current Live Activity so we can update/end it later.
  private var currentActivity: Any? = nil

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Register the Live Activity MethodChannel
    if let controller = window?.rootViewController as? FlutterViewController {
      let liveActivityChannel = FlutterMethodChannel(
        name: "com.example.second_brain/live_activity",
        binaryMessenger: controller.binaryMessenger
      )

      liveActivityChannel.setMethodCallHandler { [weak self] (call, result) in
        guard let self = self else { return }
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary arguments", details: nil))
          return
        }

        switch call.method {
        case "startLiveActivity":
          self.startLiveActivity(args: args, result: result)
        case "updateLiveActivity":
          self.updateLiveActivity(args: args, result: result)
        case "endLiveActivity":
          self.endLiveActivity(args: args, result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - Live Activity Helpers

  private func startLiveActivity(args: [String: Any], result: @escaping FlutterResult) {
    if #available(iOS 16.1, *) {
      let title = args["title"] as? String ?? "Ingesting Link..."
      let url = args["url"] as? String ?? ""
      let status = args["status"] as? String ?? "Processing..."
      let progress = args["progress"] as? Double ?? 0.1

      let attributes = IngestionAttributes(title: title, url: url)
      let contentState = IngestionAttributes.ContentState(status: status, progress: progress)

      do {
        let activity = try Activity<IngestionAttributes>.request(
          attributes: attributes,
          contentState: contentState,
          pushType: nil
        )
        currentActivity = activity
        result(true)
      } catch {
        result(FlutterError(code: "LIVE_ACTIVITY_ERROR", message: error.localizedDescription, details: nil))
      }
    } else {
      result(FlutterError(code: "UNSUPPORTED", message: "Live Activities require iOS 16.1+", details: nil))
    }
  }

  private func updateLiveActivity(args: [String: Any], result: @escaping FlutterResult) {
    if #available(iOS 16.1, *) {
      guard let activity = currentActivity as? Activity<IngestionAttributes> else {
        result(FlutterError(code: "NO_ACTIVITY", message: "No active Live Activity to update", details: nil))
        return
      }

      let status = args["status"] as? String ?? "Processing..."
      let progress = args["progress"] as? Double ?? 0.5
      let contentState = IngestionAttributes.ContentState(status: status, progress: progress)

      Task {
        await activity.update(using: contentState)
        result(true)
      }
    } else {
      result(FlutterError(code: "UNSUPPORTED", message: "Live Activities require iOS 16.1+", details: nil))
    }
  }

  private func endLiveActivity(args: [String: Any], result: @escaping FlutterResult) {
    if #available(iOS 16.1, *) {
      guard let activity = currentActivity as? Activity<IngestionAttributes> else {
        result(FlutterError(code: "NO_ACTIVITY", message: "No active Live Activity to end", details: nil))
        return
      }

      let status = args["status"] as? String ?? "Done"
      let progress = args["progress"] as? Double ?? 1.0
      let finalState = IngestionAttributes.ContentState(status: status, progress: progress)

      Task {
        await activity.end(using: finalState, dismissalPolicy: .default)
        self.currentActivity = nil
        result(true)
      }
    } else {
      result(FlutterError(code: "UNSUPPORTED", message: "Live Activities require iOS 16.1+", details: nil))
    }
  }
}
