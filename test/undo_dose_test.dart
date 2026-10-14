import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/sample_household.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLog.enableTestCapture();
  });
  tearDown(AppLog.disableTestCapture);

  // 14:00: the afternoon fluids are due and nothing is logged for them yet.
  CareRepository care() => sampleCare(clock: () => DateTime(2026, 10, 3, 14));

  test('undo takes back a dose logged by mistake on this phone', () async {
    final c = care();
    expect(c.isConnected, isFalse);
    expect(
      await c.logDose(
        doseId: 'fluids.afternoon',
        memberId: c.you.id,
        amount: '100 ml',
        timeLabel: '2:00 PM',
      ),
      isTrue,
    );
    expect(c.canUndoDose('fluids.afternoon'), isTrue);

    expect(c.undoDose('fluids.afternoon'), isTrue);
    expect(c.loggedDose('fluids.afternoon', dayKey(c.now)), isNull);
    expect(c.doseById('fluids.afternoon')?.status, DoseStatus.due);
    expect(AppLog.logged('dose.undo.completed'), isTrue);
    // Nothing left to take back.
    expect(c.canUndoDose('fluids.afternoon'), isFalse);
  });

  test('undo returns the counted supply', () async {
    final c = care()..debugStorePro = true;
    await c.addMedication(
      petId: 'miso',
      name: 'Gabapentin',
      amount: '50 mg',
      parts: [DayPart.afternoon],
      supplyTotal: 20,
    );
    final med = c.medications.firstWhere((m) => m.name == 'Gabapentin');
    final doseId = '${med.id}.afternoon';
    await c.logDose(
      doseId: doseId,
      memberId: c.you.id,
      amount: '50 mg',
      timeLabel: '2:00 PM',
    );
    expect(c.medicationById(med.id)?.dosesLeft, 19);
    expect(c.undoDose(doseId), isTrue);
    expect(c.medicationById(med.id)?.dosesLeft, 20);
  });

  test('nothing logged: undo is refused and logged', () {
    final c = care();
    expect(c.canUndoDose('fluids.afternoon'), isFalse);
    expect(c.undoDose('fluids.afternoon'), isFalse);
    expect(AppLog.logged('dose.undo.rejected'), isTrue);
  });

  test('a skipped or not-sure dose is not "undone" from the toast', () async {
    final c = care();
    await c.markDoseUncertain('fluids.afternoon');
    expect(c.canUndoDose('fluids.afternoon'), isFalse);
  });
}
