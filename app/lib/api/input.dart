/// What the user wants analysed: a link or a pasted text.
class AnalysisInput {
  const AnalysisInput.url(String this.url) : text = null;
  const AnalysisInput.text(String this.text) : url = null;

  final String? url;
  final String? text;

  bool get isUrl => url != null;
}

final _urlPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

/// Shared content often looks like "Article title https://…". When the input
/// is a single link with at most a short caption around it, treat it as a
/// URL; otherwise it is text. Returns null for blank input.
AnalysisInput? classifyInput(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final matches = _urlPattern.allMatches(s).toList();
  if (matches.length == 1) {
    final m = matches.single;
    final rest = (s.substring(0, m.start) + s.substring(m.end)).trim();
    if (rest.length <= 200) {
      final url = m.group(0)!.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');
      final uri = Uri.tryParse(url);
      if (uri != null && uri.host.isNotEmpty) return AnalysisInput.url(url);
    }
  }
  return AnalysisInput.text(s);
}
