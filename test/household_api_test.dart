import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pawsitive_sync/data/household_api.dart';
import 'package:pawsitive_sync/domain/models.dart';

void main() {
  test('household json maps onto the models', () async {
    final api = HouseholdApi(
      Uri.parse('https://example.test'),
      client: MockClient((request) async {
        expect(request.url.path, '/v1/household');
        return http.Response('''
{
  "isPro": false,
  "plan": "yearly",
  "members": [
    {"id":"you","name":"You","initials":"You","role":"owner","avatarTone":"brand","isYou":true}
  ],
  "pets": [
    {"id":"miso","name":"Miso","species":"cat","ageYears":12,"breed":"Domestic shorthair","sex":"female","conditions":["Diabetes"],"weightKg":"4.6","onTimePercent":97,"dailyMeds":3}
  ],
  "doses": [
    {"id":"fluids-pm","petId":"miso","medicationId":"fluids","name":"Fluids","amount":"100 ml","part":"afternoon","status":"due","subtitle":"Miso · due 1:00 PM"}
  ],
  "medications": [],
  "activity": []
}
''', 200);
      }),
    );

    final house = await api.fetchHousehold();
    expect(house.pets.single.name, 'Miso');
    expect(house.pets.single.weightKg, 4.6);
    expect(house.doses.single.status, DoseStatus.due);
    expect(house.members.single.isYou, isTrue);
  });
}
