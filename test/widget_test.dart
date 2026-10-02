import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/app.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/ui/onboarding/onboarding_view_model.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('welcome leads into pet basics', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => CareRepository()),
          ChangeNotifierProvider(create: (_) => OnboardingViewModel()),
        ],
        child: const PawsitiveApp(),
      ),
    );
    await tester.pump();

    expect(
      find.text('Every dose, seen by everyone who cares for them.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('Who are we caring for?'), findsOneWidget);
  });

  test('logging a due dose marks it given', () {
    final care = CareRepository();
    expect(care.givenCount, 3);

    care.logDose(
      doseId: 'fluids-pm',
      memberId: 'you',
      amount: '100 ml',
      timeLabel: '1:06 PM',
    );

    final dose = care.doseById('fluids-pm');
    expect(dose?.status.name, 'given');
    expect(care.givenCount, 4);
    expect(care.activity.first.actor, 'You');
  });
}
