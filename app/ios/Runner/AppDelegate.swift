import Flutter
import ActivityKit
import UIKit
import workmanager_apple

private struct LiveActivityBackendContext {
  let apiBaseUrl: String
  let installationId: String
}

private let widgetRefreshTaskIdentifier = "kbo-widget-periodic"
private let liveActivityApiBaseUrlDefaultsKey = "kbo_fans.live_activity.api_base_url"
private let liveActivityInstallationIdDefaultsKey = "kbo_fans.live_activity.installation_id"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let startupBeganAt = CFAbsoluteTimeGetCurrent()
  private var liveActivityChannel: FlutterMethodChannel?
  private var liveActivityTokenTasks: [String: Task<Void, Never>] = [:]
  private var liveActivityStateTasks: [String: Task<Void, Never>] = [:]
  private var liveActivityBackendContexts: [String: LiveActivityBackendContext] = [:]
  private var liveActivityLastTokens: [String: String] = [:]
  private var liveActivityUpdatesTask: Task<Void, Never>?
  private var liveActivityPushToStartTokenTask: Task<Void, Never>?
  private var liveActivityLastPushToStartToken: String?

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
        case "syncPushToStartToken":
          NSLog("[KBOFansLiveActivity] syncPushToStartToken call received")
          let args = call.arguments as? [String: Any] ?? [:]
          self.syncPushToStartToken(arguments: args, result: result)
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

  private func syncPushToStartToken(
    arguments: [String: Any],
    result: @escaping FlutterResult
  ) {
    guard #available(iOS 17.2, *) else {
      NSLog("[KBOFansLiveActivity] push-to-start unavailable on this iOS version")
      result(["supported": false, "pushToStartToken": ""])
      return
    }

    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      NSLog("[KBOFansLiveActivity] push-to-start skipped: Activities disabled")
      result(["supported": true, "pushToStartToken": ""])
      return
    }

    let backendContext = rememberLiveActivityBackendContext(
      apiBaseUrl: arguments["apiBaseUrl"] as? String,
      installationId: arguments["installationId"] as? String
    )
    observeExistingLiveActivities(context: backendContext)
    observeLiveActivityUpdates(context: backendContext)
    observeLiveActivityPushToStartTokenUpdates()
    if let token = Activity<KboFansScoreAttributes>.pushToStartToken {
      let tokenString = token.hexString
      let previousToken = liveActivityLastPushToStartToken
      liveActivityLastPushToStartToken = tokenString
      result(
        [
          "supported": true,
          "pushToStartToken": tokenString,
          "previousPushToStartToken": previousToken ?? ""
        ]
      )
      return
    }

    result(["supported": true, "pushToStartToken": ""])
  }

  @available(iOS 16.1, *)
  private func observeExistingLiveActivities(context: LiveActivityBackendContext) {
    for activity in Activity<KboFansScoreAttributes>.activities {
      observeLiveActivity(
        activity,
        gameId: activity.attributes.gameId,
        context: context
      )
    }
  }

  @available(iOS 16.1, *)
  private func observeLiveActivityUpdates(context: LiveActivityBackendContext) {
    if liveActivityUpdatesTask != nil {
      return
    }

    liveActivityUpdatesTask = Task { [weak self] in
      for await activity in Activity<KboFansScoreAttributes>.activityUpdates {
        DispatchQueue.main.async {
          guard let self else { return }
          self.observeLiveActivity(
            activity,
            gameId: activity.attributes.gameId,
            context: context
          )
        }
      }
    }
  }

  @available(iOS 17.2, *)
  private func observeLiveActivityPushToStartTokenUpdates() {
    if liveActivityPushToStartTokenTask != nil {
      return
    }

    liveActivityPushToStartTokenTask = Task { [weak self] in
      for await token in Activity<KboFansScoreAttributes>.pushToStartTokenUpdates {
        let tokenString = token.hexString
        DispatchQueue.main.async {
          self?.handleLiveActivityPushToStartToken(tokenString)
        }
      }
    }
  }

  private func handleLiveActivityPushToStartToken(_ token: String) {
    let previousToken = liveActivityLastPushToStartToken
    if previousToken == token {
      return
    }
    liveActivityLastPushToStartToken = token

    liveActivityChannel?.invokeMethod(
      "liveActivityPushToStartToken",
      arguments: [
        "pushToStartToken": token,
        "previousPushToStartToken": previousToken ?? ""
      ]
    )
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
    let backendContext = rememberLiveActivityBackendContext(
      apiBaseUrl: arguments["apiBaseUrl"] as? String,
      installationId: arguments["installationId"] as? String
    )

    let attributes = KboFansScoreAttributes(gameId: gameId)
    let state = KboFansScoreAttributes.ContentState(
      awayTeamId: awayTeamId,
      awayTeam: awayTeam,
      homeTeamId: homeTeamId,
      homeTeam: homeTeam,
      awayScore: awayScore,
      homeScore: homeScore,
      scoreAvailable: arguments["scoreAvailable"] as? Bool ?? true,
      inning: inning,
      batter: arguments["batter"] as? String ?? "",
      batterAverage: arguments["batterAverage"] as? String,
      pitcher: arguments["pitcher"] as? String ?? "",
      pitcherEra: arguments["pitcherEra"] as? String,
      pitchCount: arguments["pitchCount"] as? Int ?? 0,
      balls: arguments["balls"] as? Int ?? 0,
      strikes: arguments["strikes"] as? Int ?? 0,
      outs: arguments["outs"] as? Int ?? 0,
      stadium: stadium,
      updatedAt: updatedAt,
      situationText: arguments["situationText"] as? String,
      playText: arguments["playText"] as? String,
      isPregame: arguments["isPregame"] as? Bool,
      awayRankText: arguments["awayRankText"] as? String,
      homeRankText: arguments["homeRankText"] as? String
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
              context: self.liveActivityBackendContext(for: activity.id)
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
    let context = liveActivityBackendContext(for: activity.id)
    let activityPushToken = activity.pushToken?.hexString ?? liveActivityLastTokens[activity.id]
    guard activityPushToken != nil, !context.installationId.isEmpty else {
      NSLog("[KBOFansLiveActivity] backend unregister skipped: missing owner identity")
      return
    }
    sendLiveActivityUnregisterToBackend(
      gameId: gameId,
      activityId: activity.id,
      activityPushToken: activityPushToken,
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
      "installationId": context.installationId,
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
      "activityPushToken": activityPushToken ?? "",
      "installationId": context.installationId
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

  private func rememberLiveActivityBackendContext(
    apiBaseUrl: String?,
    installationId: String?
  ) -> LiveActivityBackendContext {
    let apiCandidate = apiBaseUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let installationCandidate =
      installationId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !apiCandidate.isEmpty {
      UserDefaults.standard.set(apiCandidate, forKey: liveActivityApiBaseUrlDefaultsKey)
    }
    if !installationCandidate.isEmpty {
      UserDefaults.standard.set(
        installationCandidate,
        forKey: liveActivityInstallationIdDefaultsKey
      )
    }

    let storedApiBaseUrl = UserDefaults.standard.string(
      forKey: liveActivityApiBaseUrlDefaultsKey
    ) ?? ""
    let storedInstallationId = UserDefaults.standard.string(
      forKey: liveActivityInstallationIdDefaultsKey
    ) ?? ""
    return LiveActivityBackendContext(
      apiBaseUrl: apiCandidate.isEmpty ? storedApiBaseUrl : apiCandidate,
      installationId: installationCandidate.isEmpty
        ? storedInstallationId
        : installationCandidate
    )
  }

  private func liveActivityBackendContext(
    for activityId: String
  ) -> LiveActivityBackendContext {
    if let current = liveActivityBackendContexts[activityId],
       !current.apiBaseUrl.isEmpty,
       !current.installationId.isEmpty {
      return current
    }
    return rememberLiveActivityBackendContext(apiBaseUrl: nil, installationId: nil)
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
