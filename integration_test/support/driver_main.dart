// Manual QA entrypoint: the real app plus the Flutter Driver extension so a
// tool can tap and type on the simulator. Never referenced from lib/.
//
//   flutter run -t integration_test/support/driver_main.dart -d <sim> \
//     --dart-define-from-file=config/dev.json
import 'package:flutter_driver/driver_extension.dart';
import 'package:pawsitive_sync/main.dart' as app;

void main() {
  enableFlutterDriverExtension();
  app.main();
}
