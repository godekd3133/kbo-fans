import Flutter
import ActivityKit
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    setUpLiveActivityChannel()
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func setUpLiveActivityChannel() {
    DispatchQueue.main.async { [weak self] in
      guard
        let self,
        let controller = self.flutterViewController()
      else {
        return
      }

      let channel = FlutterMethodChannel(
        name: "kbo_fans/live_activity",
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler { [weak self] call, result in
        guard let self else {
          result(
            FlutterError(
              code: "unavailable",
              message: "AppDelegate released",
              details: nil
            )
          )
          return
        }

        switch call.method {
        case "syncCurrentScore":
          guard let args = call.arguments as? [String: Any] else {
            result(
              FlutterError(
                code: "bad_args",
                message: "Expected score payload",
                details: nil
              )
            )
            return
          }
          self.syncCurrentScoreActivity(arguments: args, result: result)
        case "endCurrentScore":
          self.endCurrentScoreActivity(result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  private func syncCurrentScoreActivity(
    arguments: [String: Any],
    result: @escaping FlutterResult
  ) {
    guard #available(iOS 16.1, *) else {
      result(false)
      return
    }

    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      result(false)
      return
    }

    guard
      let gameId = arguments["gameId"] as? String,
      let awayTeam = arguments["awayTeam"] as? String,
      let homeTeam = arguments["homeTeam"] as? String,
      let inning = arguments["inning"] as? String,
      let stadium = arguments["stadium"] as? String,
      let updatedAt = arguments["updatedAt"] as? String,
      let awayScore = arguments["awayScore"] as? Int,
      let homeScore = arguments["homeScore"] as? Int
    else {
      result(
        FlutterError(
          code: "bad_args",
          message: "Missing live activity fields",
          details: arguments
        )
      )
      return
    }

    let attributes = KboFansScoreAttributes(gameId: gameId)
      let state = KboFansScoreAttributes.ContentState(
        awayTeam: awayTeam,
        homeTeam: homeTeam,
        awayScore: awayScore,
        homeScore: homeScore,
        inning: inning,
        batter: arguments["batter"] as? String ?? "",
        pitcher: arguments["pitcher"] as? String ?? "",
        stadium: stadium,
        updatedAt: updatedAt
      )

    Task {
      do {
        let existingActivities = Activity<KboFansScoreAttributes>.activities
        if let existing = existingActivities.first(where: { $0.attributes.gameId == gameId }) {
          await existing.update(using: state)
        } else {
          for activity in existingActivities {
            await activity.end(dismissalPolicy: .immediate)
          }
          _ = try Activity<KboFansScoreAttributes>.request(
            attributes: attributes,
            contentState: state,
            pushType: nil
          )
        }
        result(true)
      } catch {
        result(
          FlutterError(
            code: "activity_error",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }

  private func endCurrentScoreActivity(result: @escaping FlutterResult) {
    guard #available(iOS 16.1, *) else {
      result(false)
      return
    }

    Task {
      for activity in Activity<KboFansScoreAttributes>.activities {
        await activity.end(dismissalPolicy: .immediate)
      }
      result(true)
    }
  }

  private func flutterViewController() -> FlutterViewController? {
    if let controller = window?.rootViewController as? FlutterViewController {
      return controller
    }

    let scenes = UIApplication.shared.connectedScenes.compactMap {
      $0 as? UIWindowScene
    }
    for scene in scenes {
      if let controller = scene.windows.first(where: \.isKeyWindow)?.rootViewController as? FlutterViewController {
        return controller
      }
      if let controller = scene.windows.first?.rootViewController as? FlutterViewController {
        return controller
      }
    }
    return nil
  }
}
