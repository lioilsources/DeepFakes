import 'dart:async';

import 'package:share_handler/share_handler.dart';

/// Text or URLs shared to the app from the OS share sheet.
abstract class ShareSource {
  /// Content that launched the app, if any.
  Future<String?> initial();

  /// Content shared while the app is running.
  Stream<String> get stream;
}

/// [ShareSource] backed by the `share_handler` plugin. Failures (e.g. the
/// iOS Share Extension not being set up yet) are swallowed.
class PlatformShareSource implements ShareSource {
  ShareHandlerPlatform get _h => ShareHandlerPlatform.instance;

  static String? _content(SharedMedia? m) {
    final c = m?.content?.trim();
    return (c == null || c.isEmpty) ? null : c;
  }

  @override
  Future<String?> initial() async {
    try {
      return _content(await _h.getInitialSharedMedia());
    } on Exception {
      return null;
    }
  }

  @override
  Stream<String> get stream => _h.sharedMediaStream
      .map(_content)
      .where((c) => c != null)
      .cast<String>()
      .handleError((Object _) {});
}
