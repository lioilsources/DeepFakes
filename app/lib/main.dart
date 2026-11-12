import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

import 'api/client.dart';
import 'api/device_id.dart';
import 'api/share_source.dart';
import 'app.dart';

/// Override with `--dart-define=API_BASE=https://…`. Release builds (CI)
/// default to the public API, everything else to a local server.
const apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: kReleaseMode
      ? 'https://pravdomer.ol1n.com'
      : 'http://localhost:8096',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final deviceId = await loadDeviceId();
  runApp(
    PravdomerApp(
      client: PravdomerClient(baseUrl: Uri.parse(apiBase), deviceId: deviceId),
      shareSource: PlatformShareSource(),
    ),
  );
}
