import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/team_data.dart';
import '../data/models/boxscore.dart';
import '../data/models/game.dart';
import '../data/models/player.dart';
import '../data/models/relay.dart';
import '../data/providers.dart';

const _kboImageHeaders = {
  'Referer': 'https://www.koreabaseball.com/',
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
};
const _kboPersonImageBase =
    'https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/person/middle';

class GameDetailPreloadService {
  GameDetailPreloadService._();

  static final GameDetailPreloadService instance = GameDetailPreloadService._();

  static const _warmTtl = Duration(minutes: 3);
  static const _dataTimeout = Duration(seconds: 10);
  static const _imageTimeout = Duration(seconds: 4);
  static const _maxPlayerImagesPerGame = 28;

  final Set<String> _inFlight = <String>{};
  final Map<String, DateTime> _warmedAt = <String, DateTime>{};

  void preloadScoreboardGames(
    WidgetRef ref,
    BuildContext context,
    List<Game> games, {
    String? myTeamId,
    int maxGames = 3,
  }) {
    if (games.isEmpty) {
      return;
    }

    final candidates = [...games]
      ..sort((a, b) {
        final aScore = _preloadPriority(a, myTeamId);
        final bScore = _preloadPriority(b, myTeamId);
        return bScore.compareTo(aScore);
      });

    for (final game in candidates.take(maxGames)) {
      preloadGame(ref, context, gameId: game.gameId, game: game);
    }
  }

  void preloadGame(
    WidgetRef ref,
    BuildContext context, {
    required String gameId,
    Game? game,
  }) {
    final now = DateTime.now();
    final warmed = _warmedAt[gameId];
    if (_inFlight.contains(gameId) ||
        (warmed != null && now.difference(warmed) < _warmTtl)) {
      return;
    }

    _inFlight.add(gameId);
    unawaited(
      _preloadGame(ref, context, gameId: gameId, seedGame: game).whenComplete(
        () {
          _inFlight.remove(gameId);
          _warmedAt[gameId] = DateTime.now();
        },
      ),
    );
  }

  int _preloadPriority(Game game, String? myTeamId) {
    var priority = 0;
    if (game.status == GameStatus.live) {
      priority += 100;
    }
    if (myTeamId != null &&
        (game.away.teamId == myTeamId || game.home.teamId == myTeamId)) {
      priority += 50;
    }
    if (game.status == GameStatus.final_) {
      priority += 20;
    }
    return priority;
  }

  Future<void> _preloadGame(
    WidgetRef ref,
    BuildContext context, {
    required String gameId,
    required Game? seedGame,
  }) async {
    final gameFuture = seedGame == null
        ? _read(ref, ref.read(gameProvider(gameId).future))
        : Future<Game?>.value(seedGame);

    final resolvedGame = await gameFuture.timeout(
      _dataTimeout,
      onTimeout: () => seedGame,
    );
    final game = resolvedGame ?? seedGame;
    final shouldWarmDetail = _shouldWarmDetail(game);
    final boxscoreFuture = shouldWarmDetail
        ? _read(ref, ref.read(gameBoxscoreProvider(gameId).future))
        : Future<GameBoxscoreData?>.value(null);
    final lineupFuture = shouldWarmDetail
        ? _read(ref, ref.read(gameLineupProvider(gameId).future))
        : Future<GameLineupData?>.value(null);
    final relayFuture = _shouldWarmRelay(game)
        ? _read(ref, ref.read(relayDataProvider(gameId).future))
        : Future<RelayData?>.value(null);
    final lineup = await lineupFuture.timeout(
      _dataTimeout,
      onTimeout: () => null,
    );
    final relay = await relayFuture.timeout(
      _dataTimeout,
      onTimeout: () => null,
    );
    final boxscore = await boxscoreFuture.timeout(
      _dataTimeout,
      onTimeout: () => null,
    );

    if (!context.mounted) {
      return;
    }

    _precacheTeamLogos(context, game);
    await _precachePlayerImages(
      ref,
      context,
      game: game,
      lineup: lineup,
      relay: relay,
      boxscore: boxscore,
    );
  }

  bool _shouldWarmDetail(Game? game) {
    if (game == null) {
      return false;
    }
    return game.status == GameStatus.live || game.status == GameStatus.final_;
  }

  bool _shouldWarmRelay(Game? game) {
    if (game == null) {
      return false;
    }
    return game.status == GameStatus.live || game.status == GameStatus.final_;
  }

  Future<T?> _read<T>(WidgetRef ref, Future<T> future) async {
    try {
      return await future;
    } catch (_) {
      return null;
    }
  }

  void _precacheTeamLogos(BuildContext context, Game? game) {
    if (game == null) {
      return;
    }
    for (final teamId in [game.away.teamId, game.home.teamId]) {
      final imageUrl = KboTeams.byId(teamId)?.logoUrl ?? '';
      if (imageUrl.isEmpty) {
        continue;
      }
      unawaited(_precacheUrl(context, imageUrl));
    }
  }

  Future<void> _precachePlayerImages(
    WidgetRef ref,
    BuildContext context, {
    required Game? game,
    required GameLineupData? lineup,
    required RelayData? relay,
    required GameBoxscoreData? boxscore,
  }) async {
    if (game == null) {
      return;
    }

    final season = DateTime.now().year;
    final playerFutures = <Future<List<PlayerProfile>?>>[
      if (game.away.teamId.isNotEmpty)
        _read(
          ref,
          ref.read(teamPlayersProvider('${game.away.teamId}|$season').future),
        ),
      if (game.home.teamId.isNotEmpty)
        _read(
          ref,
          ref.read(teamPlayersProvider('${game.home.teamId}|$season').future),
        ),
    ];
    final players = await Future.wait(playerFutures);
    if (!context.mounted) {
      return;
    }

    final imageByName = <String, String>{};
    for (final teamPlayers in players) {
      for (final player in teamPlayers ?? const <PlayerProfile>[]) {
        final imageUrl = _playerImageUrlFromProfile(player, season);
        if (player.name.isNotEmpty && imageUrl != null && imageUrl.isNotEmpty) {
          imageByName[player.name] = imageUrl;
        }
      }
    }

    final names = <String>{
      ..._lineupNames(lineup),
      ..._relayNames(relay),
      ..._boxscoreNames(boxscore),
    };
    final urls = <String>{
      for (final name in names)
        if ((imageByName[name] ?? '').isNotEmpty) imageByName[name]!,
      ..._lineupStarterImageUrls(lineup, season),
      if ((relay?.currentAtBat?.batterImageUrl ?? '').isNotEmpty)
        relay!.currentAtBat!.batterImageUrl,
      if ((relay?.currentAtBat?.pitcherImageUrl ?? '').isNotEmpty)
        relay!.currentAtBat!.pitcherImageUrl,
    };

    for (final url in urls.take(_maxPlayerImagesPerGame)) {
      unawaited(_precacheUrl(context, url));
    }
  }

  Iterable<String> _lineupStarterImageUrls(
    GameLineupData? lineup,
    int season,
  ) sync* {
    if (lineup == null) {
      return;
    }
    for (final team in [lineup.away, lineup.home]) {
      if ((team.starterImageUrl ?? '').isNotEmpty) {
        yield team.starterImageUrl!;
        continue;
      }
      final imageUrl = _playerImageUrl(
        season: season,
        playerId: team.starterId,
      );
      if (imageUrl != null && imageUrl.isNotEmpty) {
        yield imageUrl;
      }
    }
  }

  String? _playerImageUrlFromProfile(PlayerProfile player, int season) {
    if (player.imageUrl != null && player.imageUrl!.isNotEmpty) {
      return player.imageUrl;
    }
    return _playerImageUrl(season: season, playerId: player.id);
  }

  String? _playerImageUrl({required int season, required String? playerId}) {
    final cleaned = playerId?.trim() ?? '';
    if (cleaned.isEmpty) {
      return null;
    }
    return '$_kboPersonImageBase/$season/$cleaned.jpg';
  }

  Iterable<String> _lineupNames(GameLineupData? lineup) sync* {
    if (lineup == null) {
      return;
    }
    if ((lineup.away.starterName ?? '').isNotEmpty) {
      yield lineup.away.starterName!;
    }
    if ((lineup.home.starterName ?? '').isNotEmpty) {
      yield lineup.home.starterName!;
    }
    for (final entry in [...lineup.away.lineup, ...lineup.home.lineup]) {
      if (entry.name.isNotEmpty) {
        yield entry.name;
      }
    }
  }

  Iterable<String> _relayNames(RelayData? relay) sync* {
    final atBat = relay?.currentAtBat;
    if (atBat == null) {
      return;
    }
    if (atBat.batterName.isNotEmpty) {
      yield atBat.batterName;
    }
    if (atBat.pitcherName.isNotEmpty) {
      yield atBat.pitcherName;
    }
  }

  Iterable<String> _boxscoreNames(GameBoxscoreData? boxscore) sync* {
    if (boxscore == null) {
      return;
    }
    for (final batter in [...boxscore.away.batters, ...boxscore.home.batters]) {
      if (batter.name.isNotEmpty) {
        yield batter.name;
      }
    }
    for (final pitcher in [
      ...boxscore.away.pitchers,
      ...boxscore.home.pitchers,
    ]) {
      if (pitcher.name.isNotEmpty) {
        yield pitcher.name;
      }
    }
  }

  Future<void> _precacheUrl(BuildContext context, String url) async {
    try {
      await precacheImage(
        CachedNetworkImageProvider(url, headers: _kboImageHeaders),
        context,
      ).timeout(_imageTimeout);
    } catch (_) {}
  }
}
