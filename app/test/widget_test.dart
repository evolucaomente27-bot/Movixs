import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/main.dart';

void main() {
  testWidgets('MovixsApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MovixsApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('MOVIXS'), findsOneWidget);
  });
}
