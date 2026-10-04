import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/data/revenue_cat_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show PurchasesErrorCode;

import 'test_log_helpers.dart';

PurchaseResult map(Object code, [String? message]) =>
    RevenueCatService.mapPlatformErrorForTest(
      PlatformException(code: '$code', message: message),
    );

String codeOf(PurchasesErrorCode c) =>
    '${PurchasesErrorCode.values.indexOf(c)}';

void main() {
  setUp(AppLog.enableTestCapture);
  tearDown(AppLog.disableTestCapture);

  test('cancel is silent', () {
    final r = map(codeOf(PurchasesErrorCode.purchaseCancelledError));
    expect(r.kind, PurchaseErrorKind.cancelled);
    expect(r.message, isNull);
    expectLogged(
      'billing.rc.purchase_error',
      fields: {'code': 'purchaseCancelledError'},
    );
  });

  test('every store failure maps to friendly copy', () {
    final cases = {
      PurchasesErrorCode.paymentPendingError: PurchaseErrorKind.pending,
      PurchasesErrorCode.productAlreadyPurchasedError:
          PurchaseErrorKind.alreadyOwned,
      PurchasesErrorCode.receiptAlreadyInUseError:
          PurchaseErrorKind.alreadyOwned,
      PurchasesErrorCode.purchaseNotAllowedError: PurchaseErrorKind.notAllowed,
      PurchasesErrorCode.networkError: PurchaseErrorKind.network,
      PurchasesErrorCode.offlineConnectionError: PurchaseErrorKind.network,
      PurchasesErrorCode.productNotAvailableForPurchaseError:
          PurchaseErrorKind.unavailable,
      PurchasesErrorCode.configurationError: PurchaseErrorKind.unavailable,
      PurchasesErrorCode.storeProblemError: PurchaseErrorKind.unknown,
    };
    for (final entry in cases.entries) {
      final r = map(codeOf(entry.key), 'raw SDK text');
      expect(r.kind, entry.value, reason: entry.key.name);
      expect(r.message, isNotEmpty, reason: entry.key.name);
      expect(
        r.message,
        isNot(contains('raw SDK text')),
        reason: 'never show SDK internals: ${entry.key.name}',
      );
    }
  });

  test('every SDK code yields a result, never throws', () {
    for (final code in PurchasesErrorCode.values) {
      final r = map(codeOf(code), 'x');
      expect(r.success, isFalse);
      if (r.kind != PurchaseErrorKind.cancelled) {
        expect(r.message, isNotEmpty, reason: code.name);
      }
    }
  });

  test('non-numeric or out-of-range codes do not throw (no stuck spinner)', () {
    for (final code in ['abc', '', '-1', '9999', '1.5']) {
      final r = map(code, 'weird');
      expect(r.success, isFalse, reason: code);
      expect(r.message, isNotEmpty, reason: code);
    }
  });
}
