import 'package:pawsitive_sync/domain/models.dart';

/// Short subtitle for household headers when there are many pets.
String householdPetSubtitle(List<Pet> pets) {
  if (pets.isEmpty) return 'Good care is a team effort.';
  if (pets.length == 1) {
    return 'The people looking after ${pets.first.name}.';
  }
  if (pets.length == 2) {
    return 'The people looking after ${pets[0].name} and ${pets[1].name}.';
  }
  return 'The people looking after ${pets.length} pets.';
}
