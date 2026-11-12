import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _key = 'device_id';

/// Random per-install UUID sent as `X-Device-Id`. Used only for rate limiting.
Future<String> loadDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_key);
  if (existing != null && existing.isNotEmpty) return existing;
  final id = const Uuid().v4();
  await prefs.setString(_key, id);
  return id;
}
