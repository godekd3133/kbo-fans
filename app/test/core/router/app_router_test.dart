import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/router/app_router.dart';

void main() {
  test('onboarding 상태 변경은 GoRouter 인스턴스를 재생성하지 않는다', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = container.read(routerProvider);

    container.read(onboardingDoneProvider.notifier).setValue(true);

    expect(identical(container.read(routerProvider), router), isTrue);
  });
}
