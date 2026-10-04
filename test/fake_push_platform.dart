import 'package:pawsitive_sync/data/push_service.dart';

/// A real-looking APNs token (64 hex chars), as an iPhone would report it.
const fakeApnsHex =
    '7f3a9c21d4e5b6a7980f1e2d3c4b5a69788796a5b4c3d2e1f0a9b8c7d6e5f401';

/// Stands in for the iOS `pawsitive_sync/push` channel in tests.
class FakePushPlatform implements PushPlatform {
  FakePushPlatform({this.hex = fakeApnsHex});

  /// Null = no token (simulator without APNs, Android without Firebase).
  String? hex;
  int tokenCalls = 0;
  Future<void> Function(Map<String, Object?> payload)? handler;
  void Function(PushToken token)? onToken;

  /// Never answers [token] in time (like a simulator without APNs).
  bool hang = false;

  @override
  Future<PushToken?> token() async {
    tokenCalls++;
    if (hang) return Future<PushToken?>.delayed(const Duration(days: 1));
    final value = hex;
    if (value == null) return null;
    return PushToken(
      platform: 'ios',
      token: 'apns:$value',
      environment: 'sandbox',
    );
  }

  @override
  void listen(
    Future<void> Function(Map<String, Object?> payload) onMessage, {
    void Function(PushToken token)? onToken,
  }) {
    handler = onMessage;
    this.onToken = onToken;
  }

  /// Simulates APNs handing over a token after connect.
  void deliverToken(String value) {
    hex = value;
    onToken?.call(
      PushToken(platform: 'ios', token: 'apns:$value', environment: 'sandbox'),
    );
  }
}
