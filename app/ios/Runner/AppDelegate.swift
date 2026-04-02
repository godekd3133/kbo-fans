import Flutter
import ActivityKit
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let startupBeganAt = CFAbsoluteTimeGetCurrent()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    logStartup("didFinishLaunching start")
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    let superStartedAt = CFAbsoluteTimeGetCurrent()
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    logStartup(
      "super.application finished (\(elapsedMs(since: superStartedAt))ms)"
    )
    setUpLiveActivityChannel()
    logStartup("didFinishLaunching end")
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let startedAt = CFAbsoluteTimeGetCurrent()
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    logStartup(
      "implicit engine plugin registration finished (\(elapsedMs(since: startedAt))ms)"
    )
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
          NSLog("[KBOFansLiveActivity] syncCurrentScore call received")
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
          NSLog("[KBOFansLiveActivity] endCurrentScore call received")
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
      NSLog("[KBOFansLiveActivity] ActivityKit unavailable on this iOS version")
      result(false)
      return
    }

    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      NSLog("[KBOFansLiveActivity] Activities disabled in system settings")
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
        balls: arguments["balls"] as? Int ?? 0,
        strikes: arguments["strikes"] as? Int ?? 0,
        outs: arguments["outs"] as? Int ?? 0,
        stadium: stadium,
        updatedAt: updatedAt
      )

    Task {
      do {
        let existingActivities = Activity<KboFansScoreAttributes>.activities
        if let existing = existingActivities.first(where: { $0.attributes.gameId == gameId }) {
          await existing.update(using: state)
          NSLog("[KBOFansLiveActivity] updated existing activity for %@", gameId)
        } else {
          for activity in existingActivities {
            await activity.end(dismissalPolicy: .immediate)
          }
          _ = try Activity<KboFansScoreAttributes>.request(
            attributes: attributes,
            contentState: state,
            pushType: nil
          )
          NSLog("[KBOFansLiveActivity] started new activity for %@", gameId)
        }
        result(true)
      } catch {
        NSLog("[KBOFansLiveActivity] sync failed: %@", error.localizedDescription)
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
      NSLog("[KBOFansLiveActivity] end ignored: ActivityKit unavailable")
      result(false)
      return
    }

    Task {
      for activity in Activity<KboFansScoreAttributes>.activities {
        await activity.end(dismissalPolicy: .immediate)
      }
      NSLog("[KBOFansLiveActivity] ended %ld activities", Activity<KboFansScoreAttributes>.activities.count)
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

  private func logStartup(_ message: String) {
    NSLog(
      "[KBOFansStartup] %@ | +%@ms",
      message,
      elapsedMs(since: startupBeganAt)
    )
  }

  private func elapsedMs(since start: CFAbsoluteTime) -> String {
    String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - start) * 1000)
  }
}
