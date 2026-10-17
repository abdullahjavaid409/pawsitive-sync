// Manual QA entrypoint: the real app plus the Flutter Driver extension so a
// tool can tap and type on the simulator. Never referenced from lib/.
//
//   flutter run -t integration_test/support/driver_main.dart -d <sim> \
//     --dart-define-from-file=config/dev.json
//
// For demo recordings of Pro screens, point it at the local QA backend
// (never production) and send `request_data` with message `pro`:
//
//   flutter run -t integration_test/support/driver_main.dart -d <sim> \
//     --dart-define=API_BASE_URL=http://127.0.0.1:3100
import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/main.dart' as app;
import 'package:provider/provider.dart';

void main() {
  enableFlutterDriverExtension(handler: _request);
  app.main();
}

/// `pro`: stands in for RevenueCat's entitlement listener, the same way the
/// integration tests do — this file only ships in driver runs, never in lib/.
Future<String> _request(String? message) async {
  if (message != 'pro') return 'unknown request: $message';
  CareRepository? care;
  void visit(Element element) {
    if (care != null) return;
    if (element.widget is Scaffold) {
      care = Provider.of<CareRepository>(element, listen: false);
      return;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  final repo = care;
  if (repo == null) return 'no app screen yet';
  repo.applyStoreEntitlement(true, BillingPlan.yearly);
  return 'pro=${repo.isPro}';
}
