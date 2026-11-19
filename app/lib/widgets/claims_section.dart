import 'package:flutter/material.dart';

import '../api/analysis_state.dart';
import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../l10n/labels.dart';
import 'open_link.dart';

typedef LinkOpener = void Function(BuildContext context, String url);

/// Colour of a verdict label. Neutral grey for anything that is not a
/// conclusion (unverifiable, not checked, unknown).
Color verdictColor(String label, ColorScheme scheme) => switch (label) {
  'supported' => const Color(0xFF2E7D32),
  'mostly_supported' => const Color(0xFF689F38),
  'disputed' => const Color(0xFFB26A00),
  'refuted' => const Color(0xFFC62828),
  _ => scheme.outline,
};

IconData _verdictIcon(String label) => switch (label) {
  'supported' => Icons.check_circle,
  'mostly_supported' => Icons.check_circle_outline,
  'disputed' => Icons.compare_arrows,
  'refuted' => Icons.cancel_outlined,
  'not_checked' => Icons.remove_circle_outline,
  _ => Icons.help_outline,
};

/// "3 z 6 tvrzení podloženo · 1 vyvráceno · 2 nelze ověřit", or null when no
/// verdict is known yet.
String? claimsSummaryText(AppLocalizations l, AnalysisState s) {
  final counts = s.claimLabelCounts;
  if (counts.isEmpty) return null;
  final total = s.claimsChecked;
  int n(String k) => counts[k] ?? 0;
  return [
    if (total > 0) l.claimsSummaryLead(n('supported'), total),
    if (n('mostly_supported') > 0)
      l.claimsCountMostlySupported(n('mostly_supported')),
    if (n('disputed') > 0) l.claimsCountDisputed(n('disputed')),
    if (n('refuted') > 0) l.claimsCountRefuted(n('refuted')),
    if (n('unverifiable') > 0) l.claimsCountUnverifiable(n('unverifiable')),
    if (n('not_checked') > 0) l.claimsCountNotChecked(n('not_checked')),
  ].join(' · ');
}

/// Claims (fact-check) part of the result screen. Deliberately framed apart
/// from the temperature sections: the two are independent axes.
class ClaimsSection extends StatelessWidget {
  const ClaimsSection({
    super.key,
    required this.state,
    this.selectedClaimId,
    this.onShowInText,
    this.onOpenLink = openExternalLink,
  });

  final AnalysisState state;
  final String? selectedClaimId;
  final ValueChanged<Claim>? onShowInText;
  final LinkOpener onOpenLink;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = state;
    final checked = s.checkedClaims;
    final notChecked = s.notCheckedClaims;
    final summary = claimsSummaryText(l, s);
    final failed = s.claimsSummary?.error;

    Widget card(Claim c, {bool dimmed = false}) => ClaimCard(
      claim: c,
      verdict: s.verdictOf(c.id),
      finished: s.finished || s.claimsSummary != null,
      selected: c.id == selectedClaimId,
      dimmed: dimmed,
      onShowInText: onShowInText,
      onOpenLink: onOpenLink,
    );

    // Material (not a decorated box) so the expansion tile's ink shows.
    return Padding(
      key: const Key('claims-section'),
      padding: const EdgeInsets.only(bottom: 20),
      child: Material(
        color: scheme.secondaryContainer.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.secondary.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.fact_check_outlined, color: scheme.secondary),
                  const SizedBox(width: 8),
                  Text(l.claimsTitle, style: theme.textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 6),
              Text(l.claimsIntro, style: theme.textTheme.bodySmall),
              if (failed != null)
                Container(
                  key: const Key('claims-error'),
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: scheme.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.claimsFailed,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              if (summary != null) ...[
                const SizedBox(height: 10),
                Text(
                  summary,
                  key: const Key('claims-summary'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (s.claims.isEmpty)
                s.finished || s.claimsSummary != null
                    ? Text(l.claimsNone, style: theme.textTheme.bodyMedium)
                    : Row(
                        children: [
                          const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l.claimsSearching,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
              for (final c in checked) card(c),
              if (notChecked.isNotEmpty)
                Theme(
                  data: theme.copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    key: const Key('claims-not-checked'),
                    tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                    childrenPadding: EdgeInsets.zero,
                    title: Text(
                      l.claimsNotCheckedTitle(notChecked.length),
                      style: theme.textTheme.titleSmall,
                    ),
                    children: [
                      for (final c in notChecked) card(c, dimmed: true),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ClaimCard extends StatelessWidget {
  const ClaimCard({
    super.key,
    required this.claim,
    this.verdict,
    this.finished = false,
    this.selected = false,
    this.dimmed = false,
    this.onShowInText,
    this.onOpenLink = openExternalLink,
  });

  final Claim claim;
  final Verdict? verdict;

  /// No more verdicts will come; a missing one is shown as "no result".
  final bool finished;
  final bool selected;
  final bool dimmed;
  final ValueChanged<Claim>? onShowInText;
  final LinkOpener onOpenLink;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final v = verdict;
    final text = claim.claim.isNotEmpty
        ? claim.claim
        : claim.quote.isNotEmpty
        ? claim.quote
        : null;
    final reason = v?.reason;
    final reasonText = reason != null
        ? verdictReason(l, reason)
        : v?.label == 'unverifiable'
        ? l.verdictUnverifiableInfo
        : null;
    final concluded = v != null && confidenceLabels.contains(v.label);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _KindChip(kind: claim.kind),
            const SizedBox(width: 6),
            if (claim.p > 0)
              Text(
                l.claimParagraph(claim.p),
                style: theme.textTheme.labelMedium,
              ),
            const Spacer(),
            VerdictBadge(verdict: v, finished: finished),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          text ?? l.claimPurged,
          style: text == null
              ? theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: scheme.outline,
                )
              : theme.textTheme.bodyLarge,
        ),
        if (reasonText != null) ...[
          const SizedBox(height: 6),
          Text(
            reasonText,
            key: const Key('claim-reason'),
            style: theme.textTheme.bodyMedium,
          ),
        ],
        if (v != null && v.showsConfidence) ...[
          const SizedBox(height: 6),
          Tooltip(
            message: l.verdictConfidenceNote,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.verdictConfidence((v.confidence! * 100).round()),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(width: 4),
                Icon(Icons.info_outline, size: 14, color: scheme.outline),
              ],
            ),
          ),
        ],
        if (concluded &&
            v.independentSources != null &&
            v.sourcesConsidered != null)
          Text(
            l.verdictSources(v.independentSources!, v.sourcesConsidered!),
            style: theme.textTheme.bodySmall,
          ),
        if (v?.explanation != null && v!.label != 'unverifiable') ...[
          const SizedBox(height: 10),
          Text(l.modelSummaryLabel, style: theme.textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(v.explanation!, style: theme.textTheme.bodyMedium),
        ],
        if (v != null && v.evidence.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            l.evidenceTitle(v.evidence.length),
            style: theme.textTheme.labelMedium,
          ),
          for (final e in v.evidence)
            EvidenceTile(evidence: e, onOpenLink: onOpenLink),
        ],
        if (onShowInText != null && claim.p > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: Key('claim-show-${claim.id}'),
              onPressed: () => onShowInText!(claim),
              icon: const Icon(Icons.format_quote, size: 18),
              label: Text(l.claimShowInText),
            ),
          ),
      ],
    );

    return Opacity(
      opacity: dimmed ? 0.7 : 1,
      child: Card(
        key: Key('claim-${claim.id}'),
        margin: const EdgeInsets.symmetric(vertical: 6),
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: body,
        ),
      ),
    );
  }
}

class VerdictBadge extends StatelessWidget {
  const VerdictBadge({super.key, this.verdict, this.finished = false});

  final Verdict? verdict;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final v = verdict;
    final label = v?.label;
    final color = label == null
        ? theme.colorScheme.outline
        : verdictColor(label, theme.colorScheme);
    final Widget leading;
    final String text;
    if (v == null && !finished) {
      leading = SizedBox.square(
        dimension: 12,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
      );
      text = l.verdictChecking;
    } else if (v == null) {
      leading = Icon(Icons.more_horiz, size: 14, color: color);
      text = l.verdictMissing;
    } else {
      leading = Icon(_verdictIcon(v.label), size: 14, color: color);
      text = verdictLabel(l, v.label);
    }
    return Container(
      key: const Key('verdict-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 4),
          Text(text, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        claimKindName(AppLocalizations.of(context), kind),
        style: theme.textTheme.labelSmall,
      ),
    );
  }
}

class EvidenceTile extends StatelessWidget {
  const EvidenceTile({
    super.key,
    required this.evidence,
    this.onOpenLink = openExternalLink,
  });

  final Evidence evidence;
  final LinkOpener onOpenLink;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final e = evidence;
    final stanceColor = switch (e.stance) {
      'supports' => verdictColor('supported', scheme),
      'refutes' => verdictColor('refuted', scheme),
      _ => scheme.outline,
    };
    final fc = e.factcheck;
    final url = e.url;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (e.site != null)
                Text(
                  e.site!,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Text(
                sourceTypeName(l, e.sourceType),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.outline,
                ),
              ),
              if (e.stance.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: stanceColor),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    stanceName(l, e.stance),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: stanceColor,
                    ),
                  ),
                ),
            ],
          ),
          if (e.title != null) ...[
            const SizedBox(height: 4),
            Text(e.title!, style: theme.textTheme.bodyMedium),
          ],
          if (e.quote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: stanceColor, width: 3)),
              ),
              child: Text(
                e.quote,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          if (fc != null) ...[
            const SizedBox(height: 6),
            Text(
              l.factcheckRating(fc.publisher ?? e.site ?? '', fc.rating ?? ''),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (e.publishedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              l.evidencePublished(
                MaterialLocalizations.of(
                  context,
                ).formatMediumDate(e.publishedAt!.toLocal()),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (url != null)
            InkWell(
              key: const Key('evidence-link'),
              onTap: () => onOpenLink(context, url),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.open_in_new, size: 14, color: scheme.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
