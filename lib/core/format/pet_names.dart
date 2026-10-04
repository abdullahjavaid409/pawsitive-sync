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

/// Every pet named, for copy that must be exact (e.g. what a delete
/// removes): "Miso", "Miso and Juniper", "Miso, Juniper and Pip".
/// Falls back to "your pets" when there are none.
String petNameList(List<Pet> pets) {
  final names = [for (final pet in pets) pet.name];
  return switch (names.length) {
    0 => 'your pets',
    1 => names.first,
    _ => '${names.take(names.length - 1).join(', ')} and ${names.last}',
  };
}
