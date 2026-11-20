import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';

/// Opens an http(s) [url] in the external browser; shows a snack bar when
/// that is not possible. Other schemes are refused, the URL comes from
/// fetched third-party pages.
Future<void> openExternalLink(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  var ok = false;
  if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      ok = false;
    }
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).linkOpenFailed)),
    );
  }
}
