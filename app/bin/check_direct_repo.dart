import 'package:flutter/foundation.dart' show debugPrint;
import 'package:kbo_fans/data/repositories/kbo_direct_repository.dart';

Future<void> main() async {
  final repo = KboDirectRepository();
  final game = await repo.getGame('20260331OBSS0');
  debugPrint('game=${game?.gameId} status=${game?.status} inning=${game?.inning}');
  debugPrint(
    'away score=${game?.away.score} hits=${game?.away.hits} errors=${game?.away.errors} walks=${game?.away.walks} innings=${game?.away.innings}',
  );
  debugPrint(
    'home score=${game?.home.score} hits=${game?.home.hits} errors=${game?.home.errors} walks=${game?.home.walks} innings=${game?.home.innings}',
  );
}
