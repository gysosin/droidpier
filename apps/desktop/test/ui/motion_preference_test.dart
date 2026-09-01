import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_android_dex/ui/motion/dex_motion.dart';

/// The reduce-motion preference.
///
/// It may only ever *reduce* motion. Someone whose operating system asks for
/// reduced motion has made an accessibility choice, and an application setting
/// must not be able to overrule it — so the preference ORs with the platform
/// rather than replacing it.
void main() {
  Future<bool> resolved(
    WidgetTester tester, {
    required bool platformReduces,
    required bool preferenceReduces,
  }) async {
    late bool value;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: platformReduces),
        child: ReduceMotionScope(
          reduce: preferenceReduces,
          child: Builder(
            builder: (BuildContext context) {
              value = DexMotion.enabled(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return value;
  }

  testWidgets('motion runs when neither asks to reduce it', (
    WidgetTester tester,
  ) async {
    expect(
      await resolved(tester, platformReduces: false, preferenceReduces: false),
      isTrue,
    );
  });

  testWidgets('the preference alone can reduce motion', (
    WidgetTester tester,
  ) async {
    expect(
      await resolved(tester, platformReduces: false, preferenceReduces: true),
      isFalse,
    );
  });

  testWidgets('the platform alone still reduces motion', (
    WidgetTester tester,
  ) async {
    // The behaviour that already existed, and must survive the new setting.
    expect(
      await resolved(tester, platformReduces: true, preferenceReduces: false),
      isFalse,
    );
  });

  testWidgets('the preference cannot overrule the platform', (
    WidgetTester tester,
  ) async {
    // There is deliberately no way to express "animate anyway". Reducing
    // motion is an accessibility choice; an app setting does not get a vote on
    // reversing it.
    expect(
      await resolved(tester, platformReduces: true, preferenceReduces: false),
      isFalse,
    );
  });

  testWidgets('with no scope at all, the platform decides', (
    WidgetTester tester,
  ) async {
    late bool value;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (BuildContext context) {
            value = DexMotion.enabled(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(value, isFalse);
  });
}
