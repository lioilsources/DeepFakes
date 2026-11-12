import 'package:flutter/material.dart';

import 'api/client.dart';
import 'api/device_id.dart';
import 'api/share_source.dart';
import 'app.dart';

/// Override with `--dart-define=API_BASE=https://…`.
const apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://localhost:8096',
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
