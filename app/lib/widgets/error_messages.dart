import '../l10n/app_localizations.dart';

/// User-facing message for an API or SSE error code.
String errorMessage(AppLocalizations l, String code, {Duration? retryAfter}) {
  switch (code) {
    case 'rate_limited':
      return l.errorRateLimited(retryAfter?.inSeconds ?? 60);
    case 'bad_request':
      return l.errorBadRequest;
    case 'too_large':
      return l.errorTooLarge;
    case 'fetch_failed':
      return l.errorFetchFailed;
    case 'extract_failed':
      return l.errorExtractFailed;
    case 'llm_unavailable':
      return l.errorLlmUnavailable;
    case 'internal':
      return l.errorInternal;
    case 'network':
      return l.errorNetwork;
    case 'not_found':
      return l.errorNotFound;
    case 'connection_lost':
      return l.errorConnectionLost;
    default:
      return l.errorUnknown(code);
  }
}
