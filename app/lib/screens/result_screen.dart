import 'dart:async';

import 'package:flutter/material.dart';

import '../api/analysis_state.dart';
import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../widgets/emotion_bars.dart';
import '../widgets/error_messages.dart';
import '../widgets/paragraph_tile.dart';
import '../widgets/shimmer.dart';
import '../widgets/technique_counts.dart';
import '../widgets/temperature_gauge.dart';

/// Live result of one analysis, built from the SSE event stream.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.connect, this.sourceUrl});

  /// Opens the event stream; called again on "try again".
  final Stream<AnalysisEvent> Function() connect;

  /// URL the user submitted, shown until the document arrives.
  final String? sourceUrl;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  AnalysisState _state = const AnalysisState();
  StreamSubscription<AnalysisEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = widget.connect().listen(
      (e) => setState(() => _state = _state.apply(e)),
      onError: (Object _) => setState(
        () => _state = _state.apply(const ErrorEvent('connection_lost')),
      ),
    );
  }

  void _retry() {
    setState(() {
      _state = AnalysisState(
        document: _state.document,
        results: _state.results,
        summary: _state.summary,
      );
    });
    _subscribe();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _statusText(AppLocalizations l) => switch (_state.status) {
    'queued' => l.statusQueued,
    'fetching' => l.statusFetching,
    'analyzing' => l.statusAnalyzing,
    'done' => l.statusDone,
    _ => l.statusConnecting,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = _state;
    final doc = s.document;
    final summary = s.summary;
    final error = s.error;
    final total = s.totalParagraphs;
    final analysed = doc == null
        ? 0
        : doc.paragraphs.where((p) => s.results.containsKey(p.p)).length;

    final header = <Widget>[
      Text(
        doc?.title ?? widget.sourceUrl ?? l.resultTitle,
        key: const Key('doc-title'),
        style: theme.textTheme.titleLarge,
      ),
      if (doc != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            [
              if (doc.site != null) doc.site!,
              if (doc.author != null) doc.author!,
              if (doc.publishedAt != null)
                MaterialLocalizations.of(
                  context,
                ).formatMediumDate(doc.publishedAt!.toLocal()),
              if (doc.language != null) l.languageLabel(doc.language!),
            ].join(' · '),
            key: const Key('doc-meta'),
            style: theme.textTheme.bodySmall,
          ),
        ),
      const SizedBox(height: 12),
      if (!s.finished)
        Row(
          children: [
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                total > 0
                    ? '${_statusText(l)} ${l.paragraphsProgress(analysed, total)}'
                    : _statusText(l),
                key: const Key('status'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        )
      else if (error == null)
        Text(
          _statusText(l),
          key: const Key('status'),
          style: theme.textTheme.bodySmall,
        ),
      if (error != null) _ErrorBanner(error: error, onRetry: _retry),
      const SizedBox(height: 16),
      Center(
        child: TemperatureGauge(
          score: s.score,
          provisional: s.scoreIsProvisional,
        ),
      ),
      if (summary?.headlineClickbait != null) ...[
        const SizedBox(height: 12),
        Text(
          l.headlineClickbait((summary!.headlineClickbait! * 100).round()),
          style: theme.textTheme.bodyMedium,
        ),
      ],
      if (summary?.headlineMatchesBody == false)
        Text(l.headlineMismatch, style: theme.textTheme.bodyMedium),
      if ((summary?.paragraphsFailed ?? 0) > 0)
        Text(
          l.paragraphsFailed(summary!.paragraphsFailed!),
          style: theme.textTheme.bodySmall,
        ),
      const SizedBox(height: 20),
      _Section(
        title: l.emotionsTitle,
        child: s.emotions.isEmpty
            ? const ShimmerLines(lines: 4)
            : EmotionBars(emotions: s.emotions),
      ),
      _Section(
        title: l.techniquesTitle,
        child: TechniqueCounts(counts: s.techniqueCounts),
      ),
      if (doc != null || !s.finished)
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(l.paragraphsTitle, style: theme.textTheme.titleMedium),
        ),
    ];

    final paragraphs = doc?.paragraphs ?? const <ParagraphText>[];
    return Scaffold(
      appBar: AppBar(title: Text(l.resultTitle)),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverList.list(children: header),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: doc == null
                  ? SliverList.list(
                      children: [if (!s.finished) const ShimmerLines(lines: 6)],
                    )
                  : SliverList.builder(
                      itemCount: paragraphs.length,
                      itemBuilder: (context, i) => ParagraphTile(
                        paragraph: paragraphs[i],
                        result: s.results[paragraphs[i].p],
                        finished: s.finished,
                      ),
                    ),
            ),
            if (summary?.model != null && summary?.method != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    l.methodInfo(summary!.model!, summary.method!),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error, required this.onRetry});

  final ErrorEvent error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final retryable = error.code != 'not_found' && error.code != 'bad_request';
    return Container(
      key: const Key('error-banner'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorMessage(l, error.code),
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          if (retryable)
            TextButton(onPressed: onRetry, child: Text(l.retryButton)),
        ],
      ),
    );
  }
}
