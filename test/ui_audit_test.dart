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

Future<GoRouter> _pumpInvite(WidgetTester t, CareRepository care) async {
  final router = _inviteRouter();
  addTearDown(router.dispose);
  await t.pumpWidget(
    ChangeNotifierProvider.value(
      value: care,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await t.pump();
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

    await t.ensureVisible(find.text('Pro'));
    await t.tap(find.text('Pro'));
    await t.pumpAndSettle();
    // The gate has no line of its own: billing.paywall.opened from=sitter_link.
    expect(find.text('paywall:invite'), findsOneWidget);
  });

  testWidgets('pro: opening the screen never creates a link', (t) async {
    final (care, adapter) = await _connected(t, pro: true);
    await _pumpInvite(t, care);
    expect(find.text('Create browser link'), findsOneWidget);
    expect(_sitterBodies(adapter), isEmpty);
  });

  Future<void> createWith(WidgetTester t, String? typed) async {
    final (care, adapter) = await _connected(
      t,
      pro: true,
      more: [_sitterReply],
    );
    await _pumpInvite(t, care);
    // Centred, so the pinned Share button below the list can't cover it.
    await t.runAsync(
      () => Scrollable.ensureVisible(
        t.element(find.text('Create browser link')),
        alignment: 0.5,
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Create browser link'));
    await t.pumpAndSettle();
    expect(find.text('Who is this link for?'), findsOneWidget);
    if (typed != null) await t.enterText(find.byType(TextField), typed);
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump();
    final body = _sitterBodies(adapter).single as Map;
    expect(body['label'], typed ?? care.defaultSitterLabel());
    expect(find.text(typed ?? care.defaultSitterLabel()), findsOneWidget);
    expect(find.text('Works until Oct 10'), findsOneWidget);
  }

  testWidgets('pro: default label is sent when kept', (t) async {
    await createWith(t, null);
  });

  testWidgets('pro: custom label is sent', (t) async {
    await createWith(t, 'Sara weekend');
  });
}
