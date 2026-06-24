import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OnboardingDoneNotifier extends Notifier<bool?> {
  @override
  bool? build() => null;

  void setValue(bool value) {
    state = value;
  }
}

/// 앱 초기 부트스트랩 중에는 null
final onboardingDoneProvider = NotifierProvider<OnboardingDoneNotifier, bool?>(
  OnboardingDoneNotifier.new,
);

final onboardingDoneRefreshProvider = Provider<ValueNotifier<bool?>>((ref) {
  final notifier = ValueNotifier<bool?>(ref.read(onboardingDoneProvider));
  ref.listen<bool?>(onboardingDoneProvider, (_, next) {
    notifier.value = next;
  });
  ref.onDispose(notifier.dispose);
  return notifier;
});
