import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/widgets/care_tab_builder.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/household/invite_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_household_api.dart';
import 'support/sample_household.dart';

GoRouter _inviteRouter() => GoRouter(
  initialLocation: AppRoutes.invite,
  routes: [
    GoRoute(
      path: AppRoutes.invite,
      builder: (context, state) => const InviteScreen(),
    ),
    GoRoute(
      path: AppRoutes.paywall,
      builder: (context, state) =>
          Text('paywall:${state.uri.queryParameters['reason']}'),
    ),
  ],
);

/// Connected household (real async: Dio needs real timers).
Future<(CareRepository, FakeHouseholdAdapter)> _connected(
  WidgetTester t, {
  required bool pro,
  List<FakeReply> more = const [],
}) async {
  final adapter = FakeHouseholdAdapter([
    (201, connectHouseholdBody(isPro: pro)),
    (200, {'ok': true}), // push device register
    ...more,
  ]);
  final care = CareRepository(
    api: fakeHouseholdApi(adapter),
    clock: () => DateTime(2026, 10, 3, 14),
  );
  await t.runAsync(() async {
    await care.addPet(name: 'Milo', species: Species.cat);
    await care.connect();
  });
  return (care, adapter);
}

Future<GoRouter> _pumpInvite(
  WidgetTester t,
  CareRepository care, {
  String name = 'Sara weekend',
}) async {
  final router = _inviteRouter();
  addTearDown(router.dispose);
  await t.pumpWidget(
    ChangeNotifierProvider.value(
      value: care,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await t.pump();
  // Step 1: who. Share sheet, so no Mail/Messages plugin is needed.
  await t.enterText(find.byType(TextField).first, name);
  await t.tap(find.text('Share'));
  await t.pump();
  await t.tap(find.text('Continue'));
  await t.pumpAndSettle();
  return router;
}

Iterable<Object?> _sitterBodies(FakeHouseholdAdapter adapter) => [
  for (final r in adapter.requests)
    if (r.path.contains('sitter-links')) r.data,
];

const _sitterReply = (
  201,
  {'token': 'sitter-tok', 'expiresAt': '2026-10-10T00:00:00.000Z'},
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });
  tearDown(AppLog.disableTestCapture);

  testWidgets('hidden tab skips rebuilds and catches up when shown', (t) async {
    final care = CareRepository(clock: () => DateTime(2026, 10, 3, 14));
    var builds = 0;
    var visible = true;
    late StateSetter setVisible;
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: care,
        child: StatefulBuilder(
          builder: (context, setState) {
            setVisible = setState;
            return TickerMode(
              enabled: visible,
              child: CareTabBuilder(
                builder: (context, care) {
                  builds++;
                  return Text(
                    '${care.pets.length}',
                    textDirection: TextDirection.ltr,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
    expect(builds, 1);

    loadSampleHousehold(care);
    await t.pump();
    expect(builds, 2, reason: 'visible: rebuilds on change');

    setVisible(() => visible = false);
    await t.pump();
    final hiddenBuilds = builds;
    loadSampleHousehold(care);
    loadSampleHousehold(care);
    await t.pump();
    expect(builds, hiddenBuilds, reason: 'hidden: no rebuild storm');

    setVisible(() => visible = true);
    await t.pump();
    expect(builds, hiddenBuilds + 1, reason: 'shown: one catch-up build');
  });

  testWidgets('free household: sitter link is locked and never requested', (
    t,
  ) async {
    final (care, adapter) = await _connected(t, pro: false);
    expect(care.canInviteHousehold, isFalse);
    await _pumpInvite(t, care);

    expect(find.text('Pro'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_sitterBodies(adapter), isEmpty);

    await t.tap(find.text('Pet sitter'));
    await t.pumpAndSettle();
    // The gate has no line of its own: billing.paywall.opened from=sitter_link.
    expect(find.text('paywall:invite'), findsOneWidget);
  });

  testWidgets('step 1 needs a name and a valid address', (t) async {
    final (care, _) = await _connected(t, pro: true);
    final router = _inviteRouter();
    addTearDown(router.dispose);
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: care,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await t.pump();
    FilledButton continueButton() =>
        t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'));
    expect(continueButton().onPressed, isNull, reason: 'no name yet');
    await t.enterText(find.byType(TextField).first, 'Sara');
    await t.pump();
    expect(continueButton().onPressed, isNotNull);

    await t.enterText(find.byType(TextField).last, '12');
    await t.pump();
    expect(find.text('Check the phone number'), findsOneWidget);
    expect(continueButton().onPressed, isNull);
    await t.enterText(find.byType(TextField).last, '+1 (415) 555-0100');
    await t.pump();
    expect(continueButton().onPressed, isNotNull);

    await t.tap(find.text('Email'));
    await t.pump();
    await t.enterText(find.byType(TextField).last, 'sara@');
    await t.pump();
    expect(
      find.text('Enter a full email, like sara@example.com'),
      findsOneWidget,
    );
    await t.enterText(find.byType(TextField).last, 'sara@example.com');
    await t.pump();
    expect(continueButton().onPressed, isNotNull);
  });

  testWidgets('pro: walking to review never creates a link', (t) async {
    final (care, adapter) = await _connected(t, pro: true);
    await _pumpInvite(t, care);
    await t.tap(find.text('Pet sitter'));
    await t.pump();
    await t.tap(find.text('2 weeks'));
    await t.pump();
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text('Look it over'), findsOneWidget);
    expect(find.text('Pet sitter · 2 weeks'), findsOneWidget);
    expect(_sitterBodies(adapter), isEmpty);
  });

  testWidgets('family: review shows the code message, back steps', (t) async {
    final (care, _) = await _connected(t, pro: true);
    await _pumpInvite(t, care, name: 'Sara Lee');
    await t.tap(find.text('Family or partner'));
    await t.pump();
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Fridge door');
    await t.pump();
    expect(
      find.textContaining('Hi Sara! Fridge door', findRichText: true),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(care.inviteCode)), findsOneWidget);
    await t.tap(find.byTooltip('Back'));
    await t.pumpAndSettle();
    expect(find.text('What can Sara do?'), findsOneWidget);
  });

  testWidgets('pro: send creates the named link for the chosen days', (
    t,
  ) async {
    final (care, adapter) = await _connected(
      t,
      pro: true,
      more: [_sitterReply, _sitterReply],
    );
    await _pumpInvite(t, care);
    await t.tap(find.text('Pet sitter'));
    await t.pump();
    await t.tap(find.text('2 weeks'));
    await t.pump();
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    await t.tap(find.text('Share invite'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pumpAndSettle();
    final body = _sitterBodies(adapter).single as Map;
    expect(body['label'], 'Sara weekend');
    expect(body['days'], 14);
    // The share sheet call fails fast in tests (no plugin) and is caught.
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pumpAndSettle();
    expect(find.text('Invite ready for Sara'), findsOneWidget);
    expect(find.text('Sara weekend'), findsOneWidget);
    expect(find.text('Works until Oct 10'), findsOneWidget);
    // Last step closes rather than going back to send twice.
    expect(find.byTooltip('Close'), findsOneWidget);

    // Another sitter: the sheet still offers the default label.
    await t.tap(find.text('Create another link'));
    await t.pumpAndSettle();
    expect(find.text('Who is this link for?'), findsOneWidget);
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump();
    expect(
      (_sitterBodies(adapter).last as Map)['label'],
      care.defaultSitterLabel(),
    );
  });
}
