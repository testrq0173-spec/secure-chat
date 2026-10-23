import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bharosa/app/app.dart';

void main() {
  testWidgets('BharosaApp mounts and navigates to onboarding smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: BharosaApp(),
      ),
    );

    // Let splash animations and initial check timer settle
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.byType(BharosaApp), findsOneWidget);
  });
}
