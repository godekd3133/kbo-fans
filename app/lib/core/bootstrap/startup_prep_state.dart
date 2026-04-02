import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/game.dart';

class StartupPrepState {
  final String title;
  final String message;
  final int completedSteps;
  final int totalSteps;
  final bool blocking;

  const StartupPrepState({
    required this.title,
    required this.message,
    required this.completedSteps,
    required this.totalSteps,
    required this.blocking,
  });

  const StartupPrepState.initial()
    : title = 'KBO Fans',
      message = '앱을 시작하는 중입니다',
      completedSteps = 0,
      totalSteps = 1,
      blocking = true;

  double get progress {
    if (totalSteps <= 0) {
      return 0;
    }
    final value = completedSteps / totalSteps;
    return value.clamp(0, 1);
  }

  StartupPrepState copyWith({
    String? title,
    String? message,
    int? completedSteps,
    int? totalSteps,
    bool? blocking,
  }) {
    return StartupPrepState(
      title: title ?? this.title,
      message: message ?? this.message,
      completedSteps: completedSteps ?? this.completedSteps,
      totalSteps: totalSteps ?? this.totalSteps,
      blocking: blocking ?? this.blocking,
    );
  }
}

class StartupPrepNotifier extends Notifier<StartupPrepState> {
  @override
  StartupPrepState build() => const StartupPrepState.initial();

  void reset({
    required String message,
    required int totalSteps,
    bool blocking = true,
  }) {
    state = StartupPrepState(
      title: 'KBO Fans',
      message: message,
      completedSteps: 0,
      totalSteps: totalSteps,
      blocking: blocking,
    );
  }

  void advance(String message) {
    state = state.copyWith(
      message: message,
      completedSteps: state.completedSteps + 1,
    );
  }

  void configure({String? message, int? totalSteps, bool? blocking}) {
    state = state.copyWith(
      message: message,
      totalSteps: totalSteps,
      blocking: blocking,
    );
  }

  int get completedStepCount => state.completedSteps;

  void complete([String message = '준비가 완료되었습니다']) {
    state = state.copyWith(
      message: message,
      completedSteps: state.totalSteps,
      blocking: false,
    );
  }

  void idle([String message = '야구 정보를 준비하는 중입니다']) {
    state = const StartupPrepState.initial().copyWith(message: message);
  }
}

class StartupScoreboardNotifier extends Notifier<List<Game>?> {
  @override
  List<Game>? build() => null;

  void setGames(List<Game>? games) {
    state = games;
  }
}

final startupPrepProvider =
    NotifierProvider<StartupPrepNotifier, StartupPrepState>(
      StartupPrepNotifier.new,
    );

final startupScoreboardProvider =
    NotifierProvider<StartupScoreboardNotifier, List<Game>?>(
      StartupScoreboardNotifier.new,
    );
