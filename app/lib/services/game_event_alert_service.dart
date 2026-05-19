import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/widgets/dev_console.dart';
import '../data/models/boxscore.dart';
import '../data/models/game.dart';
import '../data/models/relay.dart';
import '../data/repositories/game_repository.dart';
import 'push_notification_service.dart';

class GameEventAlertService {
  GameEventAlertService._();

  static final GameEventAlertService instance = GameEventAlertService._();
  static const _snapshotKey = 'game_event_alert.snapshots';
  static const _channelId = 'game_event_alerts';
  static const _channelName = '경기 이벤트 알림';
  static const _channelDescription = '경기 이벤트 로컬 알림';
  static const _scheduledLineupCheckInterval = Duration(minutes: 5);
  static const _liveLineupCheckInterval = Duration(minutes: 20);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _notificationsAllowed = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      return;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );

    await _plugin.initialize(settings);
    final androidAllowed = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.areNotificationsEnabled();
    final iosAllowed = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.checkPermissions();
    _notificationsAllowed = androidAllowed ?? iosAllowed?.isEnabled ?? false;
    _initialized = true;
  }

  Future<bool> requestPermissions() async {
    if (kIsWeb) {
      return false;
    }

    await initialize();
    final androidAllowed = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    final iosAllowed = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _notificationsAllowed =
        androidAllowed ?? iosAllowed ?? _notificationsAllowed;
    return _notificationsAllowed;
  }

  Future<void> processGames({
    required List<Game> games,
    required String? myTeamId,
    required GameRepository repository,
  }) async {
    if (kIsWeb) {
      return;
    }

    await initialize();
    if (!_notificationsAllowed) {
      return;
    }
    final settings = await PushNotificationService.instance.loadSettings();
    final prefs = await SharedPreferences.getInstance();
    final snapshots = _readSnapshots(prefs);
    final trackedGames = _trackedGames(
      games: games,
      myTeamId: myTeamId,
      trackAllGames: settings.allGames,
    );
    final trackedGameIds = trackedGames.map((game) => game.gameId).toSet();
    snapshots.removeWhere((gameId, _) => !trackedGameIds.contains(gameId));
    if (trackedGames.isEmpty) {
      await _writeSnapshots(prefs, snapshots);
      return;
    }

    for (final game in trackedGames) {
      final previous = snapshots[game.gameId];
      final previousRelaySeq = previous?.lastRelaySeq ?? 0;
      final nextRelaySeq = await _processRelayEvents(
        repository: repository,
        game: game,
        previous: previous,
        settings: settings,
        myTeamId: myTeamId,
      );
      final lineupResult = await _processLineupEvents(
        repository: repository,
        game: game,
        previous: previous,
        settings: settings,
      );

      final current = _GameAlertSnapshot.fromGame(
        game,
        lastRelaySeq: nextRelaySeq ?? previousRelaySeq,
        lineupSignature:
            lineupResult.signature ?? previous?.lineupSignature ?? '',
        lastLineupCheckedAtMs:
            lineupResult.checkedAtMs ?? previous?.lastLineupCheckedAtMs ?? 0,
      );

      if (previous != null) {
        await _maybeNotifyScoreboardEvents(
          previous: previous,
          current: current,
          settings: settings,
          game: game,
          myTeamId: myTeamId,
        );
      }

      snapshots[game.gameId] = current;
    }

    await _writeSnapshots(prefs, snapshots);
  }

  List<Game> _trackedGames({
    required List<Game> games,
    required String? myTeamId,
    required bool trackAllGames,
  }) {
    final filtered = games.where((game) {
      if (game.status == GameStatus.cancelled ||
          game.status == GameStatus.suspended) {
        return false;
      }
      if (trackAllGames) {
        return true;
      }
      if (myTeamId == null || myTeamId.isEmpty) {
        return false;
      }
      return game.away.teamId == myTeamId || game.home.teamId == myTeamId;
    }).toList();

    filtered.sort((a, b) => a.gameId.compareTo(b.gameId));
    return filtered;
  }

  Future<int?> _processRelayEvents({
    required GameRepository repository,
    required Game game,
    required _GameAlertSnapshot? previous,
    required PushNotificationSettings settings,
    required String? myTeamId,
  }) async {
    final notifyHomerun = settings.sendsImmediately(
      PushNotificationMoment.homerun,
    );
    final notifyInningChange = settings.sendsImmediately(
      PushNotificationMoment.inningChange,
    );
    if (!(notifyHomerun || notifyInningChange)) {
      return previous?.lastRelaySeq;
    }
    if (game.status != GameStatus.live) {
      return previous?.lastRelaySeq;
    }

    try {
      final relayData = await repository.getRelayData(
        game.gameId,
        afterSeqNo: previous?.lastRelaySeq == 0 ? null : previous?.lastRelaySeq,
      );
      final relayItems = [...relayData.relayItems]
        ..sort((a, b) => a.seqNo.compareTo(b.seqNo));

      var maxSeq = previous?.lastRelaySeq ?? 0;
      final shouldNotify = previous != null && maxSeq > 0;
      for (final item in relayItems) {
        if (item.seqNo > maxSeq) {
          maxSeq = item.seqNo;
        }
        if (!shouldNotify) {
          continue;
        }

        if (notifyHomerun && _isHomerunEvent(item)) {
          await _showNow(
            title: '${game.away.shortName} vs ${game.home.shortName} 홈런',
            body: item.text,
            tag: '${game.gameId}:homerun:${item.seqNo}',
          );
        }

        if (notifyInningChange && item.event == 'INNING_CHANGE') {
          await _showNow(
            title: '${game.away.shortName} vs ${game.home.shortName} 이닝 교대',
            body: item.text,
            tag: '${game.gameId}:inning:${item.seqNo}',
          );
        }
      }

      return maxSeq;
    } catch (error) {
      DevConsole.instance.warn('Relay alert processing failed: $error');
      return previous?.lastRelaySeq;
    }
  }

  Future<_LineupCheckResult> _processLineupEvents({
    required GameRepository repository,
    required Game game,
    required _GameAlertSnapshot? previous,
    required PushNotificationSettings settings,
  }) async {
    if (!settings.sendsImmediately(PushNotificationMoment.lineupOpened)) {
      return _LineupCheckResult(
        signature: previous?.lineupSignature,
        checkedAtMs: previous?.lastLineupCheckedAtMs,
      );
    }
    if (game.status == GameStatus.final_ ||
        game.status == GameStatus.cancelled ||
        game.status == GameStatus.suspended) {
      return _LineupCheckResult(
        signature: previous?.lineupSignature,
        checkedAtMs: previous?.lastLineupCheckedAtMs,
      );
    }
    if (!_shouldCheckLineupNow(game: game, previous: previous)) {
      return _LineupCheckResult(
        signature: previous?.lineupSignature,
        checkedAtMs: previous?.lastLineupCheckedAtMs,
      );
    }

    final checkedAtMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final lineup = await repository.getLineupData(game.gameId);
      final signature = _lineupSignature(lineup);
      if (signature.isEmpty) {
        return _LineupCheckResult(
          signature: previous?.lineupSignature ?? '',
          checkedAtMs: checkedAtMs,
        );
      }

      if (previous != null && previous.lineupSignature != signature) {
        final title = previous.lineupSignature.isEmpty
            ? '선발 라인업 공개'
            : '선발 라인업 변경';
        await _showNow(
          title: title,
          body:
              '${game.away.shortName} vs ${game.home.shortName} 라인업이 업데이트됐습니다.',
          tag: '${game.gameId}:lineup:${signature.hashCode}',
        );
      }

      return _LineupCheckResult(signature: signature, checkedAtMs: checkedAtMs);
    } catch (error) {
      final lastChecked = previous?.lastLineupCheckedAtMs ?? 0;
      final shouldLog =
          checkedAtMs - lastChecked >=
          const Duration(minutes: 1).inMilliseconds;
      if (shouldLog) {
        DevConsole.instance.warn('Lineup alert processing failed: $error');
      }
      return _LineupCheckResult(
        signature: previous?.lineupSignature,
        checkedAtMs: checkedAtMs,
      );
    }
  }

  bool _shouldCheckLineupNow({
    required Game game,
    required _GameAlertSnapshot? previous,
  }) {
    if (game.status == GameStatus.scheduled) {
      return _isLineupCheckDue(
        previous?.lastLineupCheckedAtMs ?? 0,
        _scheduledLineupCheckInterval,
      );
    }

    if (game.status == GameStatus.live) {
      if ((previous?.lineupSignature ?? '').isEmpty) {
        return _isLineupCheckDue(
          previous?.lastLineupCheckedAtMs ?? 0,
          _scheduledLineupCheckInterval,
        );
      }

      return _isLineupCheckDue(
        previous?.lastLineupCheckedAtMs ?? 0,
        _liveLineupCheckInterval,
      );
    }

    return false;
  }

  bool _isLineupCheckDue(int lastCheckedAtMs, Duration interval) {
    if (lastCheckedAtMs <= 0) {
      return true;
    }
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - lastCheckedAtMs;
    return elapsedMs >= interval.inMilliseconds;
  }

  Future<void> _maybeNotifyScoreboardEvents({
    required _GameAlertSnapshot previous,
    required _GameAlertSnapshot current,
    required PushNotificationSettings settings,
    required Game game,
    required String? myTeamId,
  }) async {
    final isMyTeamGame =
        myTeamId != null &&
        myTeamId.isNotEmpty &&
        (game.away.teamId == myTeamId || game.home.teamId == myTeamId);
    final myTeam = isMyTeamGame
        ? (game.away.teamId == myTeamId ? game.away : game.home)
        : null;
    final opponent = isMyTeamGame
        ? (game.away.teamId == myTeamId ? game.home : game.away)
        : null;

    if (settings.sendsImmediately(PushNotificationMoment.gameStart) &&
        previous.status == GameStatus.scheduled &&
        current.status == GameStatus.live) {
      await _showNow(
        title: isMyTeamGame && myTeam != null
            ? '${myTeam.shortName} 경기 시작'
            : '${game.away.shortName} vs ${game.home.shortName} 경기 시작',
        body: isMyTeamGame && opponent != null
            ? '${opponent.shortName}전이 시작됐습니다. ${game.stadium}'
            : '${game.stadium} 경기 시작',
        tag: '${game.gameId}:start:${current.inning}',
      );
    }

    final awayDelta = current.awayScore - previous.awayScore;
    final homeDelta = current.homeScore - previous.homeScore;
    if (settings.sendsImmediately(PushNotificationMoment.scoring) &&
        (awayDelta > 0 || homeDelta > 0)) {
      if (isMyTeamGame && myTeam != null && opponent != null) {
        final myScoreDelta =
            current.scoreForTeam(myTeam.teamId) -
            previous.scoreForTeam(myTeam.teamId);
        if (myScoreDelta > 0) {
          await _showNow(
            title: '${myTeam.shortName} $myScoreDelta점 득점',
            body:
                '현재 ${myTeam.shortName} ${current.scoreForTeam(myTeam.teamId)} : ${current.scoreForTeam(opponent.teamId)} ${opponent.shortName}',
            tag:
                '${game.gameId}:score:${current.scoreForTeam(myTeam.teamId)}:${current.scoreForTeam(opponent.teamId)}',
          );
        }
      } else {
        final scorer = awayDelta > 0 ? game.away : game.home;
        final delta = awayDelta > 0 ? awayDelta : homeDelta;
        await _showNow(
          title: '${scorer.shortName} $delta점 득점',
          body:
              '현재 ${game.away.shortName} ${current.awayScore} : ${current.homeScore} ${game.home.shortName}',
          tag: '${game.gameId}:score:${current.awayScore}:${current.homeScore}',
        );
      }
    }

    if (settings.sendsImmediately(PushNotificationMoment.reversal)) {
      final previousLeader = previous.leadingTeamId;
      final currentLeader = current.leadingTeamId;
      if (previousLeader != currentLeader && currentLeader != null) {
        if (isMyTeamGame && myTeam != null && opponent != null) {
          final myLeading = currentLeader == myTeam.teamId;
          await _showNow(
            title: myLeading
                ? '${myTeam.shortName} 역전'
                : '${myTeam.shortName} 역전 허용',
            body:
                '${opponent.shortName}전 스코어 ${current.scoreForTeam(myTeam.teamId)}:${current.scoreForTeam(opponent.teamId)}',
            tag:
                '${game.gameId}:reversal:${current.awayScore}:${current.homeScore}',
          );
        } else {
          final leader = currentLeader == game.away.teamId
              ? game.away
              : game.home;
          await _showNow(
            title: '${leader.shortName} 역전',
            body:
                '현재 ${game.away.shortName} ${current.awayScore} : ${current.homeScore} ${game.home.shortName}',
            tag:
                '${game.gameId}:reversal:${current.awayScore}:${current.homeScore}',
          );
        }
      }
    }

    if (settings.sendsImmediately(PushNotificationMoment.gameEnd) &&
        previous.status != GameStatus.final_ &&
        current.status == GameStatus.final_) {
      if (isMyTeamGame && myTeam != null && opponent != null) {
        final myScore = current.scoreForTeam(myTeam.teamId);
        final opponentScore = current.scoreForTeam(opponent.teamId);
        final result = myScore > opponentScore
            ? '승리'
            : myScore < opponentScore
            ? '패배'
            : '무승부';
        await _showNow(
          title: '${myTeam.shortName} 경기 종료',
          body: '$result · $myScore : $opponentScore ${opponent.shortName}',
          tag: '${game.gameId}:end:$myScore:$opponentScore',
        );
      } else {
        await _showNow(
          title: '${game.away.shortName} vs ${game.home.shortName} 경기 종료',
          body:
              '최종 ${current.awayScore} : ${current.homeScore} ${game.home.shortName}',
          tag: '${game.gameId}:end:${current.awayScore}:${current.homeScore}',
        );
      }
    }
  }

  Future<void> _showNow({
    required String title,
    required String body,
    required String tag,
  }) async {
    try {
      await _plugin.show(
        tag.hashCode & 0x7fffffff,
        title,
        body,
        NotificationDetails(
          android: const AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (error) {
      DevConsole.instance.warn('Game event alert failed: $error');
    }
  }

  bool _isHomerunEvent(RelayItem item) {
    final event = item.event.toUpperCase();
    if (event.contains('HOMERUN')) {
      return true;
    }
    return item.text.contains('홈런');
  }

  String _lineupSignature(GameLineupData lineup) {
    final away = _teamLineupSignature(lineup.away);
    final home = _teamLineupSignature(lineup.home);
    if (away.isEmpty || home.isEmpty) {
      return '';
    }
    return '$away||$home';
  }

  String _teamLineupSignature(TeamLineupData data) {
    if (data.lineup.isEmpty) {
      return '';
    }
    final starter = data.starterName ?? '';
    final players = data.lineup
        .map((entry) => '${entry.order}:${entry.position}:${entry.name}')
        .join('|');
    return '${data.teamId}#$starter#$players';
  }

  Map<String, _GameAlertSnapshot> _readSnapshots(SharedPreferences prefs) {
    final raw = prefs.getString(_snapshotKey);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (key, value) => MapEntry(
          key,
          _GameAlertSnapshot.fromJson(value as Map<String, dynamic>),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeSnapshots(
    SharedPreferences prefs,
    Map<String, _GameAlertSnapshot> snapshots,
  ) async {
    if (snapshots.isEmpty) {
      await prefs.remove(_snapshotKey);
      return;
    }
    await prefs.setString(
      _snapshotKey,
      jsonEncode({
        for (final entry in snapshots.entries) entry.key: entry.value.toJson(),
      }),
    );
  }
}

class _GameAlertSnapshot {
  final GameStatus status;
  final String inning;
  final String awayTeamId;
  final String homeTeamId;
  final int awayScore;
  final int homeScore;
  final int lastRelaySeq;
  final String lineupSignature;
  final int lastLineupCheckedAtMs;

  const _GameAlertSnapshot({
    required this.status,
    required this.inning,
    required this.awayTeamId,
    required this.homeTeamId,
    required this.awayScore,
    required this.homeScore,
    required this.lastRelaySeq,
    required this.lineupSignature,
    required this.lastLineupCheckedAtMs,
  });

  factory _GameAlertSnapshot.fromGame(
    Game game, {
    required int lastRelaySeq,
    required String lineupSignature,
    required int lastLineupCheckedAtMs,
  }) {
    return _GameAlertSnapshot(
      status: game.status,
      inning: game.inning,
      awayTeamId: game.away.teamId,
      homeTeamId: game.home.teamId,
      awayScore: game.away.score,
      homeScore: game.home.score,
      lastRelaySeq: lastRelaySeq,
      lineupSignature: lineupSignature,
      lastLineupCheckedAtMs: lastLineupCheckedAtMs,
    );
  }

  factory _GameAlertSnapshot.fromJson(Map<String, dynamic> json) {
    return _GameAlertSnapshot(
      status: GameStatus.values.firstWhere(
        (value) => value.name == (json['status'] as String? ?? ''),
        orElse: () => GameStatus.scheduled,
      ),
      inning: json['inning'] as String? ?? '',
      awayTeamId: json['awayTeamId'] as String? ?? '',
      homeTeamId: json['homeTeamId'] as String? ?? '',
      awayScore: json['awayScore'] as int? ?? 0,
      homeScore: json['homeScore'] as int? ?? 0,
      lastRelaySeq: json['lastRelaySeq'] as int? ?? 0,
      lineupSignature: json['lineupSignature'] as String? ?? '',
      lastLineupCheckedAtMs: json['lastLineupCheckedAtMs'] as int? ?? 0,
    );
  }

  int scoreForTeam(String teamId) {
    if (teamId == awayTeamId) {
      return awayScore;
    }
    if (teamId == homeTeamId) {
      return homeScore;
    }
    return 0;
  }

  String? get leadingTeamId {
    if (awayScore == homeScore) {
      return null;
    }
    return awayScore > homeScore ? awayTeamId : homeTeamId;
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'inning': inning,
      'awayTeamId': awayTeamId,
      'homeTeamId': homeTeamId,
      'awayScore': awayScore,
      'homeScore': homeScore,
      'lastRelaySeq': lastRelaySeq,
      'lineupSignature': lineupSignature,
      'lastLineupCheckedAtMs': lastLineupCheckedAtMs,
    };
  }
}

class _LineupCheckResult {
  final String? signature;
  final int? checkedAtMs;

  const _LineupCheckResult({this.signature, this.checkedAtMs});
}
