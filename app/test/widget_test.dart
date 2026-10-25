import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';

void main() {
  testWidgets('PharmaTraceApp initial screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PharmaTraceApp());
    await tester.pumpAndSettle();

    // Verify title and role selection elements exist
    expect(find.text('PharmaTrace'), findsWidgets);
    expect(find.text('Continue as'), findsOneWidget);
    expect(find.text('Consumer'), findsWidgets);
    expect(find.text('Manufacturer'), findsWidgets);
  });
}
