import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kbo_fans/core/config/app_config.dart';
import 'package:kbo_fans/data/models/game.dart';
import 'package:kbo_fans/data/models/relay.dart';
import 'package:kbo_fans/data/models/schedule.dart';
import 'package:kbo_fans/services/live_activity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(AppConfig.initialize);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LiveActivityService.instance.unregisterRequestSenderForTesting = null;
    LiveActivityService.instance.registerRequestSenderForTesting = null;
    LiveActivityService.instance.startTokenRegisterRequestSenderForTesting =
        null;
  });

  test('Live Activity updatedAt text uses KST', () {
    expect(
      liveActivityUpdatedAtTextForTesting(DateTime.utc(2026, 7, 12, 19, 5, 6)),
      '04:05:06',
    );
  });

  test('Android notification stop action clears followed game', () async {
    await LiveActivityService.instance.followGame('20260520LGKT0');

    await LiveActivityService.handleAndroidNotificationResponseForTesting(
      const NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: 'stop_following_game',
      ),
    );

    expect(await LiveActivityService.instance.followedGameId(), isNull);
  });

  test('other Android notification actions keep followed game', () async {
    await LiveActivityService.instance.followGame('20260520LGKT0');

    await LiveActivityService.handleAndroidNotificationResponseForTesting(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
      ),
    );

    expect(
      await LiveActivityService.instance.followedGameId(),
      '20260520LGKT0',
    );
  });

  test('iOS push-to-start sync hands the backend URL to native', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    MethodCall? capturedCall;
    const channel = MethodChannel('kbo_fans/live_activity');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          capturedCall = call;
          return <String, dynamic>{'supported': true, 'pushToStartToken': ''};
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await LiveActivityService.instance.syncPushToStartToken();

    expect(capturedCall?.method, 'syncPushToStartToken');
    final arguments = Map<String, dynamic>.from(capturedCall?.arguments as Map);
    expect(arguments['apiBaseUrl'], AppConfig.instance.apiBaseUrl);
    expect(arguments['installationId'], startsWith('kbo-'));
  });

  test(
    'iOS push-to-start sync does not wait for pending unregister network drain',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      SharedPreferences.setMockInitialValues({
        'live_activity.pending_unregister_requests': <String>[
          jsonEncode({
            'gameId': '20260520LGKT0',
            'activityPushToken': 'old-token',
            'activityId': 'old-activity',
            'installationId': 'install-owner',
          }),
        ],
      });
      final unregisterStarted = Completer<void>();
      final releaseUnregister = Completer<void>();
      LiveActivityService.instance.unregisterRequestSenderForTesting =
          (_) async {
            if (!unregisterStarted.isCompleted) {
              unregisterStarted.complete();
            }
            await releaseUnregister.future;
          };

      MethodCall? capturedCall;
      const channel = MethodChannel('kbo_fans/live_activity');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            capturedCall = call;
            return <String, dynamic>{'supported': true, 'pushToStartToken': ''};
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final sync = LiveActivityService.instance.syncPushToStartToken();
      await unregisterStarted.future.timeout(const Duration(seconds: 2));
      try {
        final completedBeforeRelease = await Future.any<bool>([
          sync.then((_) => true),
          Future<bool>.delayed(const Duration(seconds: 1), () => false),
        ]);
        expect(completedBeforeRelease, isTrue);
        expect(capturedCall?.method, 'syncPushToStartToken');
      } finally {
        releaseUnregister.complete();
        await sync;
      }
    },
  );

  test(
    'empty native previous token falls back to the persisted activity token',
    () async {
      const gameId = '20260520LGKT0';
      const tokenKey = 'live_activity.activity_push_token.$gameId';
      const activityIdKey = 'live_activity.activity_id.$gameId';
      SharedPreferences.setMockInitialValues({
        tokenKey: 'token-before-restart',
        activityIdKey: 'same-activity',
        'push_notifications.installation_id': 'install-owner',
      });
      final captured = <Map<String, dynamic>>[];
      LiveActivityService.instance.registerRequestSenderForTesting =
          (request) async => captured.add(Map<String, dynamic>.from(request));

      await LiveActivityService.instance.registerLiveActivityTokenForTesting(
        gameId: gameId,
        activityId: 'same-activity',
        activityPushToken: 'token-after-restart',
        previousActivityPushToken: '',
      );

      expect(captured, hasLength(1));
      expect(captured.single, {
        'gameId': gameId,
        'activityId': 'same-activity',
        'activityPushToken': 'token-after-restart',
        'previousActivityPushToken': 'token-before-restart',
        'installationId': 'install-owner',
        'platform': 'ios',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(tokenKey), 'token-after-restart');
      expect(prefs.getString(activityIdKey), 'same-activity');
    },
  );

  test(
    'activity token rotations are serialized before persisted owner advances',
    () async {
      const gameId = '20260520LGKT0';
      const tokenKey = 'live_activity.activity_push_token.$gameId';
      SharedPreferences.setMockInitialValues({
        tokenKey: 'activity-token-a',
        'live_activity.activity_id.$gameId': 'same-activity',
        'push_notifications.installation_id': 'install-owner',
      });
      final firstSend = Completer<void>();
      final captured = <Map<String, dynamic>>[];
      LiveActivityService.instance.registerRequestSenderForTesting =
          (request) async {
            captured.add(Map<String, dynamic>.from(request));
            if (captured.length == 1) {
              await firstSend.future;
            }
          };

      final registerB = LiveActivityService.instance
          .registerLiveActivityTokenForTesting(
            gameId: gameId,
            activityId: 'same-activity',
            activityPushToken: 'activity-token-b',
            previousActivityPushToken: '',
          );
      await Future<void>.delayed(Duration.zero);
      final registerC = LiveActivityService.instance
          .registerLiveActivityTokenForTesting(
            gameId: gameId,
            activityId: 'same-activity',
            activityPushToken: 'activity-token-c',
            previousActivityPushToken: 'activity-token-b',
          );
      await Future<void>.delayed(Duration.zero);

      expect(captured, hasLength(1));
      expect(captured.single['previousActivityPushToken'], 'activity-token-a');

      firstSend.complete();
      await Future.wait([registerB, registerC]);

      expect(captured, hasLength(2));
      expect(captured.last['activityPushToken'], 'activity-token-c');
      expect(captured.last['previousActivityPushToken'], 'activity-token-b');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(tokenKey), 'activity-token-c');
    },
  );

  test(
    'empty native previous push-to-start token falls back to persisted owner token',
    () async {
      SharedPreferences.setMockInitialValues({
        'live_activity.push_to_start_token': 'start-token-before-restart',
        'push_notifications.installation_id': 'install-owner',
      });
      final captured = <Map<String, dynamic>>[];
      LiveActivityService.instance.startTokenRegisterRequestSenderForTesting =
          (request) async => captured.add(Map<String, dynamic>.from(request));

      await LiveActivityService.instance.registerPushToStartTokenForTesting(
        pushToStartToken: 'start-token-after-restart',
        previousPushToStartToken: '',
      );

      expect(captured, [
        {
          'pushToStartToken': 'start-token-after-restart',
          'previousPushToStartToken': 'start-token-before-restart',
          'installationId': 'install-owner',
          'platform': 'ios',
        },
      ]);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('live_activity.push_to_start_token'),
        'start-token-after-restart',
      );
    },
  );

  test(
    'push-to-start rotations are serialized before the persisted owner advances',
    () async {
      SharedPreferences.setMockInitialValues({
        'live_activity.push_to_start_token': 'start-token-a',
        'push_notifications.installation_id': 'install-owner',
      });
      final firstSend = Completer<void>();
      final captured = <Map<String, dynamic>>[];
      LiveActivityService.instance.startTokenRegisterRequestSenderForTesting =
          (request) async {
            captured.add(Map<String, dynamic>.from(request));
            if (captured.length == 1) {
              await firstSend.future;
            }
          };

      final registerB = LiveActivityService.instance
          .registerPushToStartTokenForTesting(
            pushToStartToken: 'start-token-b',
            previousPushToStartToken: '',
          );
      await Future<void>.delayed(Duration.zero);
      final registerC = LiveActivityService.instance
          .registerPushToStartTokenForTesting(
            pushToStartToken: 'start-token-c',
            previousPushToStartToken: 'start-token-b',
          );
      await Future<void>.delayed(Duration.zero);

      expect(captured, hasLength(1));
      expect(captured.single['previousPushToStartToken'], 'start-token-a');

      firstSend.complete();
      await Future.wait([registerB, registerC]);

      expect(captured, hasLength(2));
      expect(captured.last['pushToStartToken'], 'start-token-c');
      expect(captured.last['previousPushToStartToken'], 'start-token-b');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('live_activity.push_to_start_token'),
        'start-token-c',
      );
    },
  );

  test(
    'failed unregister retry removes only the old owner and preserves new prefs',
    () async {
      const gameId = '20260520LGKT0';
      const tokenKey = 'live_activity.activity_push_token.$gameId';
      const activityIdKey = 'live_activity.activity_id.$gameId';
      const pendingKey = 'live_activity.pending_unregister_requests';
      SharedPreferences.setMockInitialValues({
        tokenKey: 'old-token',
        activityIdKey: 'old-activity',
        'push_notifications.installation_id': 'install-owner',
      });
      final prefs = await SharedPreferences.getInstance();
      final calls = <Map<String, dynamic>>[];
      var shouldFail = true;
      LiveActivityService.instance.unregisterRequestSenderForTesting =
          (request) async {
            calls.add(Map<String, dynamic>.from(request));
            if (shouldFail) {
              throw StateError('offline');
            }
          };

      await LiveActivityService.instance.unregisterLiveActivityForTesting(
        gameId,
      );

      expect(calls, hasLength(1));
      expect(calls.single, {
        'gameId': gameId,
        'activityPushToken': 'old-token',
        'activityId': 'old-activity',
        'installationId': 'install-owner',
      });
      expect(prefs.getStringList(pendingKey), hasLength(1));
      expect(prefs.getString(tokenKey), 'old-token');
      expect(prefs.getString(activityIdKey), 'old-activity');

      await prefs.setString(tokenKey, 'new-token');
      await prefs.setString(activityIdKey, 'new-activity');
      shouldFail = false;

      await LiveActivityService.instance
          .retryPendingLiveActivityUnregistersForTesting();

      expect(calls, hasLength(2));
      expect(calls.last, calls.first);
      expect(prefs.getStringList(pendingKey), isNull);
      expect(prefs.getString(tokenKey), 'new-token');
      expect(prefs.getString(activityIdKey), 'new-activity');
    },
  );

  test(
    'pending unregister dedupes an exact request and retains owner generations',
    () async {
      const gameId = '20260520LGKT1';
      const tokenKey = 'live_activity.activity_push_token.$gameId';
      const activityIdKey = 'live_activity.activity_id.$gameId';
      const pendingKey = 'live_activity.pending_unregister_requests';
      SharedPreferences.setMockInitialValues({
        tokenKey: 'first-token',
        activityIdKey: 'first-activity',
        'push_notifications.installation_id': 'install-owner',
      });
      final prefs = await SharedPreferences.getInstance();
      final calls = <Map<String, dynamic>>[];
      var shouldFail = true;
      LiveActivityService.instance.unregisterRequestSenderForTesting =
          (request) async {
            calls.add(Map<String, dynamic>.from(request));
            if (shouldFail) {
              throw StateError('offline');
            }
          };

      await LiveActivityService.instance.unregisterLiveActivityForTesting(
        gameId,
      );
      await LiveActivityService.instance.unregisterLiveActivityForTesting(
        gameId,
      );
      await prefs.setString(tokenKey, 'second-token');
      await prefs.setString(activityIdKey, 'second-activity');
      await LiveActivityService.instance.unregisterLiveActivityForTesting(
        gameId,
      );

      final pending = prefs
          .getStringList(pendingKey)!
          .map((item) => jsonDecode(item) as Map<String, dynamic>)
          .toList();
      expect(pending, hasLength(2));
      expect(pending.map((request) => request['activityPushToken']), [
        'first-token',
        'second-token',
      ]);
      expect(pending.map((request) => request['activityId']), [
        'first-activity',
        'second-activity',
      ]);
      expect(pending.map((request) => request['installationId']).toSet(), {
        'install-owner',
      });

      shouldFail = false;
      calls.clear();
      await LiveActivityService.instance
          .retryPendingLiveActivityUnregistersForTesting();

      expect(calls.map((request) => request['activityPushToken']), [
        'first-token',
        'second-token',
      ]);
      expect(prefs.getStringList(pendingKey), isNull);
      expect(prefs.getString(tokenKey), isNull);
      expect(prefs.getString(activityIdKey), isNull);
    },
  );

  test(
    'pending unregister storage drops malformed data and caps entries',
    () async {
      const pendingKey = 'live_activity.pending_unregister_requests';
      const legacyKey = 'live_activity.pending_unregister_game_ids';
      final encodedRequests = <String>[
        'not-json',
        jsonEncode({'gameId': 'missing-fields'}),
        jsonEncode({
          'gameId': '20260520LGKT2',
          'activityPushToken': List<String>.filled(513, 'x').join(),
          'activityId': 'activity-too-long-token',
          'installationId': 'install-owner',
        }),
        for (var index = 0; index < 40; index++)
          jsonEncode({
            'gameId': '20260520LGKT2',
            'activityPushToken': 'token-$index',
            'activityId': 'activity-$index',
            'installationId': 'install-owner',
          }),
      ];
      encodedRequests.add(encodedRequests.last);
      SharedPreferences.setMockInitialValues({
        pendingKey: encodedRequests,
        legacyKey: <String>['20260520LGKT2'],
      });
      final prefs = await SharedPreferences.getInstance();
      final calls = <Map<String, dynamic>>[];
      LiveActivityService.instance.unregisterRequestSenderForTesting =
          (request) async {
            calls.add(Map<String, dynamic>.from(request));
            throw StateError('offline');
          };

      await LiveActivityService.instance
          .retryPendingLiveActivityUnregistersForTesting();

      final cleaned = prefs
          .getStringList(pendingKey)!
          .map((item) => jsonDecode(item) as Map<String, dynamic>)
          .toList();
      expect(cleaned, hasLength(32));
      expect(calls, hasLength(32));
      expect(cleaned.first['activityPushToken'], 'token-8');
      expect(cleaned.last['activityPushToken'], 'token-39');
      expect(
        cleaned.map((request) => request['activityPushToken']).toSet(),
        hasLength(32),
      );
      expect(prefs.getStringList(legacyKey), isNull);
    },
  );

  test(
    'suspended game keeps follow state and updates its current surface',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      const gameId = '20260520LGKT0';
      await LiveActivityService.instance.followGame(gameId);

      MethodCall? capturedCall;
      const channel = MethodChannel('kbo_fans/live_activity');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            capturedCall = call;
            return <String, dynamic>{'supported': true};
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      await LiveActivityService.instance.syncFollowedGame(
        _game(
          gameId: gameId,
          awayTeamId: 'LG',
          homeTeamId: 'KT',
          status: GameStatus.suspended,
          inning: '5회말 경기 중단',
        ),
      );

      expect(await LiveActivityService.instance.followedGameId(), gameId);
      expect(capturedCall?.method, 'syncCurrentScore');
      final arguments = Map<String, dynamic>.from(
        capturedCall?.arguments as Map,
      );
      expect(arguments['scoreAvailable'], isTrue);
      expect(arguments['installationId'], startsWith('kbo-'));
    },
  );

  test(
    'suspended game with unavailable score keeps follow and sends dash contract',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      const gameId = '20260520LGKT2';
      await LiveActivityService.instance.followGame(gameId);

      MethodCall? capturedCall;
      const channel = MethodChannel('kbo_fans/live_activity');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            capturedCall = call;
            return <String, dynamic>{'supported': true};
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      await LiveActivityService.instance.syncFollowedGame(
        _game(
          gameId: gameId,
          awayTeamId: 'LG',
          homeTeamId: 'KT',
          status: GameStatus.suspended,
          inning: '5회말 경기 중단',
          scoreAvailable: false,
        ),
      );

      expect(await LiveActivityService.instance.followedGameId(), gameId);
      expect(capturedCall?.method, 'syncCurrentScore');
      expect(
        Map<String, dynamic>.from(
          capturedCall?.arguments as Map,
        )['scoreAvailable'],
        isFalse,
      );
    },
  );

  test(
    'unverified live score does not overwrite the last Live Activity score',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
      });
      const gameId = '20260520LGKT1';
      await LiveActivityService.instance.followGame(gameId);

      MethodCall? capturedCall;
      const channel = MethodChannel('kbo_fans/live_activity');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            capturedCall = call;
            return <String, dynamic>{'supported': true};
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      await LiveActivityService.instance.syncFollowedGame(
        _game(
          gameId: gameId,
          awayTeamId: 'LG',
          homeTeamId: 'KT',
          status: GameStatus.live,
          scoreAvailable: false,
        ),
      );

      expect(capturedCall, isNull);
      expect(await LiveActivityService.instance.followedGameId(), gameId);
    },
  );

  test('auto Live Activity target prefers a live my-team game', () {
    final games = [
      _game(
        gameId: '20260520LGKT0',
        awayTeamId: 'LG',
        homeTeamId: 'KT',
        status: GameStatus.scheduled,
      ),
      _game(
        gameId: '20260520SSOB0',
        awayTeamId: 'SS',
        homeTeamId: 'OB',
        status: GameStatus.live,
      ),
      _game(
        gameId: '20260520NCHH0',
        awayTeamId: 'NC',
        homeTeamId: 'HH',
        status: GameStatus.live,
      ),
    ];

    final selected = selectAutoLiveActivityGame(games: games, myTeamId: 'NC');

    expect(selected?.gameId, '20260520NCHH0');
  });

  test(
    'auto Live Activity target ignores scheduled games before lineup opens',
    () {
      final games = [
        _game(
          gameId: '20260520LGKT0',
          awayTeamId: 'LG',
          homeTeamId: 'KT',
          status: GameStatus.scheduled,
        ),
      ];

      final selected = selectAutoLiveActivityGame(games: games, myTeamId: 'LG');

      expect(selected, isNull);
    },
  );

  test(
    'auto Live Activity target includes scheduled my-team game after lineup opens',
    () {
      final games = [
        _game(
          gameId: '20260520SSOB0',
          awayTeamId: 'SS',
          homeTeamId: 'OB',
          status: GameStatus.scheduled,
          lineupOpened: true,
        ),
        _game(
          gameId: '20260520LGKT0',
          awayTeamId: 'LG',
          homeTeamId: 'KT',
          status: GameStatus.scheduled,
          lineupOpened: true,
        ),
      ];

      final selected = selectAutoLiveActivityGame(games: games, myTeamId: 'LG');

      expect(selected?.gameId, '20260520LGKT0');
    },
  );

  test(
    'auto Live Activity target includes scheduled my-team game within ten minutes',
    () {
      final games = [
        _game(
          gameId: '20260520LGKT0',
          awayTeamId: 'LG',
          homeTeamId: 'KT',
          status: GameStatus.scheduled,
        ),
      ];

      final selected = selectAutoLiveActivityGame(
        games: games,
        myTeamId: 'LG',
        now: DateTime.utc(2026, 5, 20, 9, 20),
      );

      expect(selected?.gameId, '20260520LGKT0');
    },
  );

  test(
    'auto Live Activity target keeps my-team lineup-open games above other live games',
    () {
      final games = [
        _game(
          gameId: '20260520LGKT0',
          awayTeamId: 'LG',
          homeTeamId: 'KT',
          status: GameStatus.scheduled,
          lineupOpened: true,
        ),
        _game(
          gameId: '20260520SSOB0',
          awayTeamId: 'SS',
          homeTeamId: 'OB',
          status: GameStatus.live,
        ),
      ];

      final selected = selectAutoLiveActivityGame(games: games, myTeamId: 'LG');

      expect(selected?.gameId, '20260520LGKT0');
    },
  );

  test(
    'Live Activity payload includes current at-bat stats and base state',
    () {
      final payload = buildLiveActivityScorePayloadForTesting(
        game: _game(
          gameId: '20260620SSHH0',
          awayTeamId: 'SS',
          homeTeamId: 'HH',
          status: GameStatus.live,
          inning: '1회초',
        ),
        currentAtBat: const CurrentAtBat(
          batterName: '페라자',
          batterNumber: 30,
          batterHand: '좌타',
          batterAverage: '0.312',
          pitcherName: '장찬희',
          pitcherNumber: 19,
          pitcherHand: '우투',
          pitcherEra: '3.21',
          pitchCount: 14,
          inningText: '1회말',
          baseState: '주자1,2루',
          balls: 1,
          strikes: 2,
          outs: 1,
        ),
      );

      expect(payload['inning'], '1회말');
      expect(payload['batter'], '페라자');
      expect(payload['batterAverage'], '0.312');
      expect(payload['pitcher'], '장찬희');
      expect(payload['pitcherEra'], '3.21');
      expect(payload['pitchCount'], 14);
      expect(payload['balls'], 1);
      expect(payload['strikes'], 2);
      expect(payload['outs'], 1);
      expect(payload['situationText'], '1사 1,2루');
      expect(payload['installationId'], 'install-test');
    },
  );

  test('Live Activity payload clears current at-bat for final games', () {
    final payload = buildLiveActivityScorePayloadForTesting(
      game: _game(
        gameId: '20260620SSHH0',
        awayTeamId: 'SS',
        homeTeamId: 'HH',
        status: GameStatus.final_,
        inning: '경기종료',
      ),
      currentAtBat: const CurrentAtBat(
        batterName: '디아즈',
        batterNumber: 4,
        batterHand: '좌타',
        batterAverage: '0.312',
        pitcherName: '손주영',
        pitcherNumber: 29,
        pitcherHand: '좌투',
        pitcherEra: '3.21',
        pitchCount: 37,
        inningText: '9회 초',
        baseState: '주자없음',
        balls: 1,
        strikes: 3,
        outs: 3,
      ),
    );

    expect(payload['inning'], '경기종료');
    expect(payload['batter'], '');
    expect(payload['pitcher'], '');
    expect(payload['pitchCount'], 0);
    expect(payload['balls'], 0);
    expect(payload['strikes'], 0);
    expect(payload['outs'], 0);
    expect(payload['situationText'], '');
  });

  test('Live Activity payload shows pregame rank text after lineup opens', () {
    final payload = buildLiveActivityScorePayloadForTesting(
      game: _game(
        gameId: '20260620LGKT0',
        awayTeamId: 'LG',
        homeTeamId: 'KT',
        status: GameStatus.scheduled,
        lineupOpened: true,
      ),
      standings: const [
        TeamStanding(
          rank: 2,
          teamId: 'LG',
          teamName: 'LG 트윈스',
          wins: 40,
          losses: 28,
          draws: 2,
          pct: '.588',
          gb: '1.5',
        ),
        TeamStanding(
          rank: 5,
          teamId: 'KT',
          teamName: 'KT 위즈',
          wins: 34,
          losses: 34,
          draws: 1,
          pct: '.500',
          gb: '7.0',
        ),
      ],
    );

    expect(payload['isPregame'], isTrue);
    expect(payload['inning'], '경기전');
    expect(payload['awayRankText'], '2위');
    expect(payload['homeRankText'], '5위');
  });

  test(
    'Live Activity payload treats scheduled game within ten minutes as pregame',
    () {
      final payload = buildLiveActivityScorePayloadForTesting(
        game: _game(
          gameId: '20260620LGKT0',
          awayTeamId: 'LG',
          homeTeamId: 'KT',
          status: GameStatus.scheduled,
        ),
        standings: const [
          TeamStanding(
            rank: 2,
            teamId: 'LG',
            teamName: 'LG 트윈스',
            wins: 40,
            losses: 28,
            draws: 2,
            pct: '.588',
            gb: '1.5',
          ),
          TeamStanding(
            rank: 5,
            teamId: 'KT',
            teamName: 'KT 위즈',
            wins: 34,
            losses: 34,
            draws: 1,
            pct: '.500',
            gb: '7.0',
          ),
        ],
        now: DateTime.utc(2026, 6, 20, 9, 20),
      );

      expect(payload['isPregame'], isTrue);
      expect(payload['inning'], '경기전');
      expect(payload['awayRankText'], '2위');
      expect(payload['homeRankText'], '5위');
    },
  );

  test('Live Activity payload normalizes KBO team IDs for display labels', () {
    final payload = buildLiveActivityScorePayloadForTesting(
      game: _game(
        gameId: '20260624SSSK0',
        awayTeamId: 'SS',
        homeTeamId: 'SK',
        status: GameStatus.live,
      ),
    );

    expect(payload['awayTeam'], '삼성');
    expect(payload['homeTeam'], 'SSG');
  });

  test('Live Activity payload keeps score availability separate from zero', () {
    final payload = buildLiveActivityScorePayloadForTesting(
      game: _game(
        gameId: '20260624LGKT1',
        awayTeamId: 'LG',
        homeTeamId: 'KT',
        status: GameStatus.suspended,
        scoreAvailable: false,
      ),
    );

    expect(payload['awayScore'], 0);
    expect(payload['homeScore'], 0);
    expect(payload['scoreAvailable'], isFalse);
  });

  test('Android follow notification title normalizes team IDs', () {
    final title = buildAndroidFollowNotificationTitleForTesting(
      game: _game(
        gameId: '20260624SSSK0',
        awayTeamId: 'SS',
        homeTeamId: 'SK',
        status: GameStatus.live,
      ),
    );

    expect(title, '삼성 0:0 SSG');
  });
}

Game _game({
  required String gameId,
  required String awayTeamId,
  required String homeTeamId,
  required GameStatus status,
  String? inning,
  bool lineupOpened = false,
  bool scoreAvailable = true,
}) {
  return Game(
    gameId: gameId,
    status: status,
    inning: inning ?? (status == GameStatus.live ? '1회초' : ''),
    away: TeamScore(
      teamId: awayTeamId,
      teamName: awayTeamId,
      shortName: awayTeamId,
      score: 0,
      scoreAvailable: scoreAvailable,
      innings: const [],
    ),
    home: TeamScore(
      teamId: homeTeamId,
      teamName: homeTeamId,
      shortName: homeTeamId,
      score: 0,
      scoreAvailable: scoreAvailable,
      innings: const [],
    ),
    stadium: '잠실',
    startTime: '18:30',
    lineupOpened: lineupOpened,
  );
}
