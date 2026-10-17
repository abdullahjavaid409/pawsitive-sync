import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/app_router.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/theme/app_theme.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';

/// What an event says happened. Two events of the same kind from one tap
/// mean the screen and the repository both logged the same outcome.
enum _Kind { opened, succeeded, failed }

/// Background lines that aren’t about the tap itself (store, network,
/// billing SDK, reminders, analytics).
const _background = {
  'store',
  'api',
  'sync',
  'reminders',
  'push',
  'data',
  'app',
  'analytics',
  'widget',
};

_Kind? _kindOf(String name) {
  if (name == 'nav.push' || name == 'nav.tab' || name == 'nav.replace') {
    return _Kind.opened;
  }
  if (RegExp(r'[._](opened|tapped)$').hasMatch(name)) return _Kind.opened;
  if (RegExp(
    r'(\.completed|\.saved|[._]success|\.added|\.joined|\.connected|_ready'
    r'|\.created_from_onboarding|\.finished)$',
  ).hasMatch(name)) {
    return _Kind.succeeded;
  }
  if (RegExp(r'([._]failed|[._]rejected|\.blocked)$').hasMatch(name)) {
    return _Kind.failed;
  }
  return null;
}

/// Runs one user action and fails if it logged the same outcome twice
/// (or the same event twice). Returns the events for further checks.
Future<List<AppLogRecord>> _action(
  WidgetTester tester,
  String what,
  Future<void> Function() body,
) async {
  AppLog.testRecords.clear();
  await body();
  await tester.pumpAndSettle();
  final events = [
    for (final r in AppLog.testRecords)
      if (!_background.contains(r.name.split('.').first) &&
          !r.name.startsWith('billing.rc.'))
        r,
  ];
  final names = events.map((e) => e.name).toList();
  final byKind = <_Kind, List<String>>{};
  for (final name in names) {
    final kind = _kindOf(name);
    if (kind != null) (byKind[kind] ??= []).add(name);
  }
  for (final entry in byKind.entries) {
    expect(
      entry.value,
      hasLength(1),
      reason: '"$what" logged ${entry.key.name} ${entry.value.length}×: $names',
    );
  }
  expect(
    names.toSet(),
    hasLength(names.length),
    reason: '"$what" repeated an event: $names',
  );
  return events;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });
  tearDown(AppLog.disableTestCapture);

  testWidgets('main flows log one line per action', (tester) async {
    await loadAppFonts();
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final care = CareRepository(clock: () => DateTime(2026, 10, 3, 9));
    final onboarding = OnboardingViewModel();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: care),
          ChangeNotifierProvider.value(value: onboarding),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: createRouter(onboarding),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> tap(Finder finder) async {
      if (finder.evaluate().isEmpty) {
        final texts = find
            .byType(Text)
            .evaluate()
            .map((e) => (e.widget as Text).data);
        fail('Not on screen: $finder. Showing: ${texts.join(' | ')}');
      }
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
    }

    // --- Onboarding ---
    await _action(tester, 'get started', () => tap(find.text('Get started')));
    await tester.enterText(find.byType(TextFormField), 'Luna');
    await tap(find.text('Cat'));
    await tester.pump();
    await _action(tester, 'pet basics', () => tap(find.text('Continue')));
    // v14 setup: skip the first medicine (added below), no invites.
    await _action(tester, 'skip medicine', () => tap(find.text('Skip')));
    await _action(tester, 'household', () => tap(find.text('Continue')));
    await _action(tester, 'reminders', () => tap(find.text('Not now')));
    await _action(tester, 'ready', () => tap(find.text('Go to Today')));
    final finish = await _action(
      tester,
      'finish setup',
      () => tap(find.text('Continue free with 1 pet')),
    );
    expect(
      finish.map((e) => e.name),
      contains('household.created_from_onboarding'),
    );
    expect(care.pets.single.name, 'Luna');

    // Pro for the rest (supply alerts, a second pet).
    care.debugStorePro = true;

    // --- Add medicine ---
    await _action(
      tester,
      'open add medicine',
      () => tap(find.text('Add first medicine')),
    );
    // Five-step flow: name, form, amount, when (with supply), review.
    await tester.enterText(find.byType(TextField).first, 'Apoquel');
    for (var i = 0; i < 3; i++) {
      await tester.pumpAndSettle();
      await tap(find.text('Continue'));
    }
    await tester.pumpAndSettle();
    await tap(find.text('Track remaining doses'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '4');
    await tester.pumpAndSettle();
    await tap(find.text('Continue'));
    await tester.pumpAndSettle();
    final saved = await _action(
      tester,
      'save medicine',
      () => tap(find.text('Save medicine')),
    );
    expect(saved.map((e) => e.name), contains('medication.add.completed'));
    await tester.pump(const Duration(seconds: 6)); // SnackBar leaves

    // --- Log a dose ---
    await _action(tester, 'open dose', () => tap(find.text('Mark given')));
    final logged = await _action(tester, 'log dose', () async {
      await tap(find.text('Confirm given').last);
      await tester.pump(const Duration(seconds: 1)); // sheet closes itself
    });
    expect(logged.map((e) => e.name), contains('dose.log.completed'));

    // --- Refill (low-supply banner → medicine → refill) ---
    await _action(tester, 'open refill', () => tap(find.text('Refill')));
    final refilled = await _action(
      tester,
      'refill',
      () => tap(find.text('I refilled it')),
    );
    expect(
      refilled.map((e) => e.name),
      contains('medication.refill.completed'),
    );
    await tester.pump(const Duration(seconds: 6));
    Finder tab(String label) => find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          w.properties.button == true &&
          w.properties.label == label,
    );
    for (var i = 0; i < 3 && tab('Pets').evaluate().isEmpty; i++) {
      await tester.tap(find.byTooltip('Back').last);
      await tester.pumpAndSettle();
    }

    // --- Add a pet ---
    await _action(tester, 'pets tab', () => tap(tab('Pets')));
    await _action(tester, 'open add pet', () => tap(find.byTooltip('Add pet')));
    await tester.enterText(
      find.widgetWithText(TextField, 'Pet name'),
      'Pepper',
    );
    await tap(find.text('Dog'));
    final added = await _action(
      tester,
      'save pet',
      () => tap(find.text('Save pet')),
    );
    expect(added.map((e) => e.name), contains('pet.add.completed'));
    await tester.pump(const Duration(seconds: 6));

    // --- Open settings (v14: from Household's header) ---
    await _action(tester, 'household tab', () => tap(tab('Household')));
    final settings = await _action(
      tester,
      'open settings',
      () => tap(find.byTooltip('Settings')),
    );
    expect(settings.map((e) => e.name), ['nav.push']);
    expect(settings.single.fields['to'], '/settings');
  });

  test('paywall links carry the gate, so the gate needs no line', () {
    expect(AppRoutes.paywallWith(), '/paywall');
    expect(
      AppRoutes.paywallWith(reason: 'invite', from: 'sitter_link'),
      '/paywall?reason=invite&from=sitter_link',
    );
  });

  testWidgets('free tier: a blocked "add pet" is one paywall line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final care = CareRepository(clock: () => DateTime(2026, 10, 3, 9));
    await care.addPet(name: 'Luna', species: Species.cat);
    final onboarding = OnboardingViewModel()..isComplete = true;
    final router = createRouter(onboarding);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: care),
          ChangeNotifierProvider.value(value: onboarding),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );
    router.go(AppRoutes.pets);
    await tester.pumpAndSettle();
    final events = await _action(
      tester,
      'blocked add pet',
      () => tester.tap(find.byTooltip('Add pet')),
    );
    // No gate line of its own; the paywall’s opened line names the gate.
    // (`offer_unavailable` is the store answer: no RevenueCat in tests.)
    expect(events.first.name, 'billing.paywall.opened');
    expect(events.first.fields['from'], 'add_pet_pets_tab');
    expect(
      events.map((e) => e.name),
      everyElement(startsWith('billing.paywall.')),
    );
  });
}
