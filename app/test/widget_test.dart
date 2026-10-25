import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';
import 'package:app/models/user_role.dart';
import 'package:app/screens/role_dashboard_screen.dart';
import 'package:app/screens/role_login_screen.dart';
import 'package:app/screens/splash_screen.dart';
import 'package:app/screens/welcome_screen.dart';

void main() {
  testWidgets(
    'Animated 5-second SplashScreen automatically transitions to WelcomeScreen -> ContinueChoice -> RoleSelect',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const PharmaTraceApp());
      await tester.pump(const Duration(milliseconds: 500));

      // 1. Verify SplashScreen is active with wordmark & tagline
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.text('PharmaTrace'), findsOneWidget);
      expect(find.text('Trust Every Dose. Trace Every Batch.'), findsOneWidget);

      // 2. Advance past the 5-second splash duration without clicking
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Verify automatic transition to WelcomeScreen
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(
        find.text("Every medicine has a story.\nMake sure it's genuine."),
        findsOneWidget,
      );
      expect(
        find.text(
          'Verify authenticity and follow every batch with confidence.',
        ),
        findsOneWidget,
      );
      expect(find.text('Get Started'), findsOneWidget);

      // 3. Tap Get Started -> ContinueChoiceScreen
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      expect(find.text('Consumer'), findsOneWidget);
      expect(
        find.text('Check whether your medicine can be verified.'),
        findsOneWidget,
      );
      expect(find.text('Verify a Medicine'), findsOneWidget);

      expect(find.text('Organization'), findsOneWidget);
      expect(
        find.text('Manage medicines and supply-chain records.'),
        findsOneWidget,
      );
      expect(find.text('Organization Login'), findsOneWidget);

      // 4. Tap Organization Login -> RoleSelectScreen
      await tester.tap(find.text('Organization Login'));
      await tester.pumpAndSettle();

      expect(find.text('Select your role'), findsOneWidget);
      expect(find.text('Manufacturer'), findsOneWidget);
      expect(find.text('Distributor'), findsOneWidget);
      expect(find.text('Pharmacy'), findsOneWidget);
      expect(find.text('Administrator'), findsOneWidget);

      // 5. Navigate back and verify SplashScreen does NOT restart
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.text('Verify a Medicine'), findsOneWidget);
    },
  );

  testWidgets(
    'RoleLoginScreen shows registration link for Manufacturer/Distributor/Pharmacy but NOT for Admin',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: RoleLoginScreen(
            key: ValueKey('mfr'),
            initialRole: UserRole.manufacturer,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('New to PharmaTrace? Register your organization.'),
        findsOneWidget,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: RoleLoginScreen(
            key: ValueKey('admin'),
            initialRole: UserRole.admin,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('New to PharmaTrace? Register your organization.'),
        findsNothing,
      );
      expect(
        find.textContaining('Public registration is disabled for Admin'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'RoleDashboardScreen renders ListTiles inside Material ancestors without assertions',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final role in UserRole.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: RoleDashboardScreen(key: ValueKey(role.name), role: role),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    },
  );
}
