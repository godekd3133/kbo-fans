import Flutter
import ActivityKit
import UIKit
import workmanager_apple

private struct LiveActivityBackendContext {
  let apiBaseUrl: String
}

private let widgetRefreshTaskIdentifier = "kbo-widget-periodic"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let startupBeganAt = CFAbsoluteTimeGetCurrent()
  private var liveActivityChannel: FlutterMethodChannel?
  private var liveActivityTokenTasks: [String: Task<Void, Never>] = [:]
  private var liveActivityStateTasks: [String: Task<Void, Never>] = [:]
  private var liveActivityBackendContexts: [String: LiveActivityBackendContext] = [:]
  private var liveActivityLastTokens: [String: String] = [:]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    logStartup("didFinishLaunching start")
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: widgetRefreshTaskIdentifier,
      frequency: NSNumber(value: 15 * 60)
    )

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
      self.liveActivityChannel = channel

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
      result(["gameId": "", "activityId": "", "activityPushToken": ""])
      return
    }

    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      NSLog("[KBOFansLiveActivity] Activities disabled in system settings")
      result(["gameId": "", "activityId": "", "activityPushToken": ""])
      return
    }

    guard
      let gameId = arguments["gameId"] as? String,
      let awayTeamId = arguments["awayTeamId"] as? String,
      let awayTeam = arguments["awayTeam"] as? String,
      let homeTeamId = arguments["homeTeamId"] as? String,
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
    let backendContext = LiveActivityBackendContext(
      apiBaseUrl: arguments["apiBaseUrl"] as? String ?? ""
    )

    let attributes = KboFansScoreAttributes(gameId: gameId)
    let state = KboFansScoreAttributes.ContentState(
      awayTeamId: awayTeamId,
      awayTeam: awayTeam,
      homeTeamId: homeTeamId,
      homeTeam: homeTeam,
      awayScore: awayScore,
      homeScore: homeScore,
      inning: inning,
      batter: arguments["batter"] as? String ?? "",
      pitcher: arguments["pitcher"] as? String ?? "",
      pitchCount: arguments["pitchCount"] as? Int ?? 0,
      balls: arguments["balls"] as? Int ?? 0,
      strikes: arguments["strikes"] as? Int ?? 0,
      outs: arguments["outs"] as? Int ?? 0,
      stadium: stadium,
      updatedAt: updatedAt,
      situationText: arguments["situationText"] as? String,
      playText: arguments["playText"] as? String
    )

    Task {
      do {
        let existingActivities = Activity<KboFansScoreAttributes>.activities
        if let existing = existingActivities.first(where: { $0.attributes.gameId == gameId }),
           existing.pushToken != nil {
          await existing.update(using: state)
          self.observeLiveActivity(existing, gameId: gameId, context: backendContext)
          NSLog("[KBOFansLiveActivity] updated existing activity for %@", gameId)
        } else {
          for activity in existingActivities {
            if activity.attributes.gameId == gameId {
              self.unregisterLiveActivityFromBackend(activity: activity, gameId: gameId)
            }
            await activity.end(dismissalPolicy: .immediate)
          }
          let activity = try Activity<KboFansScoreAttributes>.request(
            attributes: attributes,
            contentState: state,
            pushType: .token
          )
          self.observeLiveActivity(activity, gameId: gameId, context: backendContext)
          NSLog("[KBOFansLiveActivity] started new activity for %@", gameId)
        }
        if let activity = Activity<KboFansScoreAttributes>.activities.first(where: { $0.attributes.gameId == gameId }) {
          result(self.liveActivityResponse(activity: activity, gameId: gameId))
        } else {
          result(["gameId": gameId, "activityId": "", "activityPushToken": ""])
        }
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
        self.unregisterLiveActivityFromBackend(activity: activity, gameId: activity.attributes.gameId)
        await activity.end(dismissalPolicy: .immediate)
        self.stopObservingLiveActivity(activity.id)
      }
      NSLog("[KBOFansLiveActivity] ended %ld activities", Activity<KboFansScoreAttributes>.activities.count)
      result(true)
    }
  }

  @available(iOS 16.1, *)
  private func observeLiveActivity(
    _ activity: Activity<KboFansScoreAttributes>,
    gameId: String,
    context: LiveActivityBackendContext
  ) {
    liveActivityBackendContexts[activity.id] = context
    if let token = activity.pushToken {
      handleLiveActivityPushToken(
        token.hexString,
        activityId: activity.id,
        gameId: gameId,
        context: context
      )
    }

    if liveActivityTokenTasks[activity.id] == nil {
      liveActivityTokenTasks[activity.id] = Task { [weak self] in
        for await token in activity.pushTokenUpdates {
          let tokenString = token.hexString
          DispatchQueue.main.async {
            guard let self else { return }
            self.handleLiveActivityPushToken(
              tokenString,
              activityId: activity.id,
              gameId: gameId,
              context: context
            )
          }
        }
      }
    }

    if liveActivityStateTasks[activity.id] == nil {
      liveActivityStateTasks[activity.id] = Task { [weak self] in
        for await state in activity.activityStateUpdates {
          if state == .ended || state == .dismissed {
            DispatchQueue.main.async {
              guard let self else { return }
              self.unregisterLiveActivityFromBackend(
                activity: activity,
                gameId: gameId
              )
              self.stopObservingLiveActivity(activity.id)
            }
            break
          }
        }
      }
    }
  }

  private func handleLiveActivityPushToken(
    _ token: String,
    activityId: String,
    gameId: String,
    context: LiveActivityBackendContext
  ) {
    let previousToken = liveActivityLastTokens[activityId]
    if previousToken == token {
      return
    }
    liveActivityLastTokens[activityId] = token

    liveActivityChannel?.invokeMethod(
      "liveActivityPushToken",
      arguments: [
        "gameId": gameId,
        "activityId": activityId,
        "activityPushToken": token,
        "previousActivityPushToken": previousToken ?? ""
      ]
    )
    sendLiveActivityTokenToBackend(
      gameId: gameId,
      activityId: activityId,
      activityPushToken: token,
      previousActivityPushToken: previousToken,
      context: context
    )
  }

  @available(iOS 16.1, *)
  private func unregisterLiveActivityFromBackend(
    activity: Activity<KboFansScoreAttributes>,
    gameId: String
  ) {
    guard let context = liveActivityBackendContexts[activity.id] else {
      return
    }
    sendLiveActivityUnregisterToBackend(
      gameId: gameId,
      activityId: activity.id,
      activityPushToken: activity.pushToken?.hexString,
      context: context
    )
  }

  private func sendLiveActivityTokenToBackend(
    gameId: String,
    activityId: String,
    activityPushToken: String,
    previousActivityPushToken: String?,
    context: LiveActivityBackendContext
  ) {
    let body: [String: Any] = [
      "gameId": gameId,
      "activityId": activityId,
      "activityPushToken": activityPushToken,
      "previousActivityPushToken": previousActivityPushToken ?? "",
      "platform": "ios"
    ]
    postLiveActivityPayload(
      path: "/push/live-activity/register",
      body: body,
      context: context
    )
  }

  private func sendLiveActivityUnregisterToBackend(
    gameId: String,
    activityId: String,
    activityPushToken: String?,
    context: LiveActivityBackendContext
  ) {
    let body: [String: Any] = [
      "gameId": gameId,
      "activityId": activityId,
      "activityPushToken": activityPushToken ?? ""
    ]
    postLiveActivityPayload(
      path: "/push/live-activity/unregister",
      body: body,
      context: context
    )
  }

  private func postLiveActivityPayload(
    path: String,
    body: [String: Any],
    context: LiveActivityBackendContext
  ) {
    guard !context.apiBaseUrl.isEmpty, let url = apiURL(base: context.apiBaseUrl, path: path) else {
      NSLog("[KBOFansLiveActivity] backend token sync skipped: missing API base URL")
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    URLSession.shared.dataTask(with: request) { _, response, error in
      if let error {
        NSLog("[KBOFansLiveActivity] backend token sync failed: %@", error.localizedDescription)
        return
      }
      let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
      if statusCode >= 400 {
        NSLog("[KBOFansLiveActivity] backend token sync failed: HTTP %ld", statusCode)
      }
    }.resume()
  }

  private func apiURL(base: String, path: String) -> URL? {
    let trimmedBase = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return URL(string: "\(trimmedBase)\(path)")
  }

  @available(iOS 16.1, *)
  private func liveActivityResponse(
    activity: Activity<KboFansScoreAttributes>,
    gameId: String
  ) -> [String: String] {
    [
      "gameId": gameId,
      "activityId": activity.id,
      "activityPushToken": activity.pushToken?.hexString ?? ""
    ]
  }

  private func stopObservingLiveActivity(_ activityId: String) {
    liveActivityTokenTasks[activityId]?.cancel()
    liveActivityTokenTasks.removeValue(forKey: activityId)
    liveActivityStateTasks[activityId]?.cancel()
    liveActivityStateTasks.removeValue(forKey: activityId)
    liveActivityBackendContexts.removeValue(forKey: activityId)
    liveActivityLastTokens.removeValue(forKey: activityId)
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

private extension Data {
  var hexString: String {
    map { String(format: "%02x", $0) }.joined()
  }
}
