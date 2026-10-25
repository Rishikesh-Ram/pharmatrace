import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';
import 'package:app/models/user_role.dart';
import 'package:app/screens/continue_choice_screen.dart';
import 'package:app/screens/organization_registration_screen.dart';
import 'package:app/screens/role_dashboard_screen.dart';
import 'package:app/screens/role_login_screen.dart';
import 'package:app/screens/splash_screen.dart';
import 'package:app/screens/welcome_screen.dart';
import 'package:app/widgets/pharma_artwork.dart';

void main() {
  testWidgets(
    'Animated 3-second WelcomeScreen appears at startup, animates 3 dots sequentially, and transitions to ContinueChoiceScreen without replaying on back navigation',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const PharmaTraceApp());

      // 1. Verify WelcomeScreen appears at startup with branding, tagline, artwork, and 3 dots
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byType(SplashCapsuleArtwork), findsOneWidget);
      expect(find.text('PharmaTrace'), findsOneWidget);
      expect(find.text('Trust Every Dose. Trace Every Batch.'), findsOneWidget);
      expect(find.byKey(const Key('welcome_three_dots')), findsOneWidget);
      expect(find.byKey(const Key('welcome_dot_0')), findsOneWidget);
      expect(find.byKey(const Key('welcome_dot_1')), findsOneWidget);
      expect(find.byKey(const Key('welcome_dot_2')), findsOneWidget);

      // Consumer and Organization buttons must NOT be on the welcome screen itself
      expect(find.byType(ContinueChoiceScreen), findsNothing);
      expect(find.text('Verify a Medicine'), findsNothing);
      expect(find.text('Organization Access'), findsNothing);

      // 2. Verify the three dots animate sequentially one after another
      await tester.pump(const Duration(milliseconds: 167));
      Opacity dot0AtT1 = tester.widget(
        find.byKey(const Key('welcome_dot_opacity_0')),
      );
      Opacity dot1AtT1 = tester.widget(
        find.byKey(const Key('welcome_dot_opacity_1')),
      );
      Opacity dot2AtT1 = tester.widget(
        find.byKey(const Key('welcome_dot_opacity_2')),
      );
      expect(dot0AtT1.opacity, greaterThan(dot1AtT1.opacity));
      expect(dot0AtT1.opacity, greaterThan(dot2AtT1.opacity));

      // Advance to ~500ms: dot 1 now has the highest opacity/scale
      await tester.pump(const Duration(milliseconds: 333));
      Opacity dot0AtT2 = tester.widget(
        find.byKey(const Key('welcome_dot_opacity_0')),
      );
      Opacity dot1AtT2 = tester.widget(
        find.byKey(const Key('welcome_dot_opacity_1')),
      );
      Opacity dot2AtT2 = tester.widget(
        find.byKey(const Key('welcome_dot_opacity_2')),
      );
      expect(dot1AtT2.opacity, greaterThan(dot0AtT2.opacity));
      expect(dot1AtT2.opacity, greaterThan(dot2AtT2.opacity));

      // Advance to ~833ms: dot 2 now has the highest opacity/scale
      await tester.pump(const Duration(milliseconds: 333));
      Opacity dot0AtT3 = tester.widget(
        find.byKey(const Key('welcome_dot_opacity_0')),
      );
      Opacity dot1AtT3 = tester.widget(
        find.byKey(const Key('welcome_dot_opacity_1')),
      );
      Opacity dot2AtT3 = tester.widget(
        find.byKey(const Key('welcome_dot_opacity_2')),
      );
      expect(dot2AtT3.opacity, greaterThan(dot0AtT3.opacity));
      expect(dot2AtT3.opacity, greaterThan(dot1AtT3.opacity));

      // 3. Advance to complete the 3-second welcome duration -> automatic transition to ContinueChoiceScreen
      await tester.pump(const Duration(milliseconds: 2200));
      await tester.pumpAndSettle();

      // 4. Verify destination is the Consumer/Organization choice screen
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(ContinueChoiceScreen), findsOneWidget);
      expect(find.text('How would you like to continue?'), findsOneWidget);
      expect(find.text('Consumer'), findsOneWidget);
      expect(find.text('Verify a Medicine'), findsOneWidget);
      expect(find.text('Organization'), findsOneWidget);
      expect(find.text('Organization Access'), findsOneWidget);

      // 5. Verify Organization path works and separates supply-chain organizations from Platform Governance (Administrator)
      await tester.tap(find.text('Organization Access'));
      await tester.pumpAndSettle();
      expect(find.text('Select your role'), findsOneWidget);
      expect(find.text('Manufacturer'), findsOneWidget);
      expect(find.text('Distributor'), findsOneWidget);
      expect(find.text('Pharmacy'), findsOneWidget);
      expect(find.text('Platform Governance'), findsOneWidget);
      expect(find.text('Administrator'), findsOneWidget);
      expect(
        find.text('Authorized platform administrators only.'),
        findsOneWidget,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(ContinueChoiceScreen), findsOneWidget);

      // 6. Verify Consumer path works without login and back navigation does NOT replay the welcome screen
      await tester.tap(find.text('Verify a Medicine'));
      await tester.pumpAndSettle();
      expect(find.text('Verify Your Medicine'), findsOneWidget);
    },
  );

  testWidgets(
    'RoleLoginScreen presents Admin as a restricted-access portal without public-registration warnings, and keeps organization registration for Manufacturer, Distributor, and Pharmacy',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // 1. Test Admin view: Restricted portal message, no confusing warning, no public registration link
      await tester.pumpWidget(
        const MaterialApp(
          home: RoleLoginScreen(
            key: ValueKey('admin'),
            initialRole: UserRole.admin,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Restricted Access Portal'), findsOneWidget);
      expect(find.text('Sign in as Administrator'), findsOneWidget);
      expect(
        find.text('Authorized platform administrators only.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('admin_email_field')), findsOneWidget);
      expect(find.byKey(const Key('admin_username_field')), findsOneWidget);
      expect(find.text('Admin Email'), findsOneWidget);
      expect(find.text('Admin Username'), findsOneWidget);
      expect(find.byKey(const Key('org_identifier_field')), findsNothing);
      expect(
        find.textContaining('Public registration is disabled'),
        findsNothing,
      );
      expect(
        find.text('New to PharmaTrace? Register your organization.'),
        findsNothing,
      );
      expect(find.text('Autofill'), findsNothing);

      // 2. Test Manufacturer, Distributor, and Pharmacy views: show organization registration link
      for (final orgRole in [
        UserRole.manufacturer,
        UserRole.distributor,
        UserRole.pharmacy,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: RoleLoginScreen(
              key: ValueKey(orgRole.name),
              initialRole: orgRole,
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Sign in as ${orgRole.title}'), findsOneWidget);
        expect(
          find.text('Enter your organization credentials to continue.'),
          findsOneWidget,
        );
        expect(
          find.text('New to PharmaTrace? Register your organization.'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('org_identifier_field')), findsOneWidget);
        expect(find.byKey(const Key('admin_email_field')), findsNothing);
        expect(find.byKey(const Key('admin_username_field')), findsNothing);
        expect(find.text('Restricted Access Portal'), findsNothing);
      }

      // 3. Tap the registration link to navigate to OrganizationRegistrationScreen
      await tester.tap(
        find.text('New to PharmaTrace? Register your organization.'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OrganizationRegistrationScreen), findsOneWidget);
      expect(find.text('Organization Registration'), findsOneWidget);
      expect(find.text('Submit Registration'), findsOneWidget);
      expect(
        find.text('Already registered? Return to Sign In'),
        findsOneWidget,
      );

      // Verify that public Admin registration is NOT an option in the role dropdown
      expect(find.text('Administrator'), findsNothing);

      // Tap Return to Sign In to verify returning to RoleLoginScreen
      await tester.tap(find.text('Already registered? Return to Sign In'));
      await tester.pumpAndSettle();

      expect(find.byType(OrganizationRegistrationScreen), findsNothing);
      expect(find.byType(RoleLoginScreen), findsOneWidget);
    },
  );

  testWidgets(
    'RoleDashboardScreen renders ListTiles inside Material ancestors and clean empty states without assertions',
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
        expect(find.text('No medicines registered yet.'), findsOneWidget);
        if (role == UserRole.admin) {
          expect(find.text('Restricted Admin Portal'), findsOneWidget);
          expect(find.text('Platform Administrator'), findsOneWidget);
        }
      }
    },
  );
}
