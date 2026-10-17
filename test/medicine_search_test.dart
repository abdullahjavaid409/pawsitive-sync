import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/data/medicine_search.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/meds/medicine_forms.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MedicineSearch.forget();
  });

  test('phone list: prefix matches first, this species first', () {
    final dog = MedicineSearch.local(Species.dog, 'carp');
    expect(dog.first.name, 'Carprofen');
    final cat = MedicineSearch.local(Species.cat, 'meth');
    expect(cat.first.name, 'Methimazole');
    // A use matches too ("thyroid" → thyroid medicines).
    expect(
      MedicineSearch.local(Species.cat, 'thyroid').map((m) => m.name),
      contains('Felimazole'),
    );
  });

  test('a phone match never goes online', () {
    expect(MedicineSearch.shouldAskOnline(Species.dog, 'apoq'), isFalse);
    expect(MedicineSearch.shouldAskOnline(Species.dog, 'xy'), isFalse);
    expect(MedicineSearch.shouldAskOnline(Species.dog, 'zorbaflux'), isTrue);
  });

  test(
    'online answer is saved: same search is then answered offline',
    () async {
      var calls = 0;
      Future<List<Map<String, dynamic>>> ask(String q) async {
        calls++;
        return [
          {
            'name': 'zorbaflux',
            'form': 'tablet',
            'use': 'test',
            'species': ['dog', 'horse'],
          },
          {'name': '', 'form': 'tablet'},
        ];
      }

      final found = await MedicineSearch.online('zorba', ask);
      expect(found!.single.name, 'Zorbaflux');
      expect(found.single.species, {Species.dog});
      expect(found.single.form, MedicineForm.tablet);
      expect(MedicineSearch.shouldAskOnline(Species.dog, 'zorba'), isFalse);
      expect(
        MedicineSearch.local(Species.dog, 'zorba').single.name,
        'Zorbaflux',
      );
      expect(calls, 1);

      // Survives a restart (saved in preferences).
      MedicineSearch.forget();
      await MedicineSearch.load();
      expect(
        MedicineSearch.local(Species.dog, 'zorba').single.name,
        'Zorbaflux',
      );
    },
  );

  test('a search the server had nothing for is not asked again', () async {
    Future<List<Map<String, dynamic>>> ask(String q) async => [];
    final found = await MedicineSearch.online('qqqzz', ask);
    expect(found, isEmpty);
    expect(MedicineSearch.shouldAskOnline(Species.cat, 'qqqzz'), isFalse);
    // One answer serves every pet: a dog's search doesn't ask again.
    expect(MedicineSearch.shouldAskOnline(Species.dog, 'qqqzz'), isFalse);
  });

  test('offline: null, nothing remembered, asks again next time', () async {
    Future<List<Map<String, dynamic>>> ask(String q) =>
        Future.error(Exception('offline'));
    final found = await MedicineSearch.online('zorba', ask);
    expect(found, isNull);
    expect(MedicineSearch.shouldAskOnline(Species.dog, 'zorba'), isTrue);
  });
}
