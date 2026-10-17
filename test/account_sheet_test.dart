import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/data/account_service.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/ui/account/account_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/sample_household.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });
  tearDown(AppLog.disableTestCapture);

  group('email fields are checked on the phone first', () {
    test('a bad email or short password never reaches the network', () {
      expect(
        AccountService.checkEmailFields(email: 'sam', password: 'longenough'),
        isA<AccountFailed>().having((f) => f.code, 'code', 'invalid_email'),
      );
      expect(
        AccountService.checkEmailFields(
          email: 'sam@parkhome.com',
          password: 'short',
        ),
        isA<AccountFailed>().having((f) => f.code, 'code', 'weak_password'),
      );
      expect(
        AccountService.checkEmailFields(
          email: '  sam@parkhome.com ',
          password: 'longenough',
        ),
        isNull,
      );
    });
  });

  Future<bool?> openSheet(
    WidgetTester tester,
    CareRepository care, {
    AccountSheetMode mode = AccountSheetMode.save,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bool? result;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: care,
        child: MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async =>
                      result = await showAccountSheet(context, mode: mode),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('save sheet: why, the three ways in, and Not now', (
    tester,
  ) async {
    final care = sampleCare(clock: () => DateTime(2026, 10, 3, 14));
    await openSheet(tester, care);
    expect(find.text('Keep your household safe'), findsOneWidget);
    expect(
      find.textContaining('Free stays on this phone only'),
      findsOneWidget,
    );
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with email'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Keep your household safe'), findsNothing);
    expect(AppLog.logged('account.sheet_skipped'), isTrue);
  });

  testWidgets('email step shows field problems instantly, offline', (
    tester,
  ) async {
    final care = sampleCare(clock: () => DateTime(2026, 10, 3, 14));
    await openSheet(tester, care);
    await tester.tap(find.text('Continue with email'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'not-an-email');
    await tester.enterText(find.byType(TextField).last, 'secret123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    // Back returns to the choices with the error cleared.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsNothing);
    expect(find.text('Continue with email'), findsOneWidget);
  });

  testWidgets('create-account toggle and password helper', (tester) async {
    final care = sampleCare(clock: () => DateTime(2026, 10, 3, 14));
    await openSheet(tester, care);
    await tester.tap(find.text('Continue with email'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('At least 8 characters.'), findsOneWidget);
    expect(find.text('Forgot password?'), findsNothing);
  });

  testWidgets('restore sheet fits a small phone at 2x text', (tester) async {
    final care = sampleCare(clock: () => DateTime(2026, 10, 3, 14));
    await openSheet(
      tester,
      care,
      mode: AccountSheetMode.restore,
      size: const Size(320, 568),
      scale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Welcome back'), findsOneWidget);
  });
}
