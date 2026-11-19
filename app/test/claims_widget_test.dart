import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pravdomer/api/models.dart';
import 'package:pravdomer/l10n/app_localizations.dart';
import 'package:pravdomer/screens/result_screen.dart';
import 'package:pravdomer/widgets/claims_section.dart';

import 'fixtures.dart';

Map<String, dynamic> j(String s) => jsonDecode(s) as Map<String, dynamic>;

Widget wrap(Widget child, {Locale locale = const Locale('cs')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('claim card with evidence', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      wrap(
        ClaimCard(
          claim: Claim.fromJson(j(claimJson)),
          verdict: Verdict.fromJson(j(verdictJson)),
          onShowInText: (_) {},
          onOpenLink: (_, url) => opened.add(url),
        ),
      ),
    );
    expect(
      find.text('Vláda schválila rozpočet se schodkem 230 miliard korun.'),
      findsOneWidget,
    );
    expect(find.text('Fakt'), findsOneWidget);
    expect(find.text('Podloženo'), findsOneWidget);
    expect(find.text('Odhad jistoty: 62 %'), findsOneWidget);
    expect(find.text('Shrnutí modelu'), findsOneWidget);
    expect(find.text('Důkazy (1)'), findsOneWidget);
    expect(find.text('mfcr.gov.cz'), findsOneWidget);
    expect(find.text('Primární zdroj'), findsOneWidget);
    expect(find.text('podporuje'), findsOneWidget);
    expect(find.text('schodek ve výši 230 miliard Kč'), findsOneWidget);
    expect(find.text('Hodnocení Demagog.cz: Pravda'), findsOneWidget);
    expect(find.textContaining('zveřejněno'), findsOneWidget);
    expect(find.text('Ukázat v textu'), findsOneWidget);
    await tester.tap(find.byKey(const Key('evidence-link')));
    expect(opened, ['https://mfcr.gov.cz/rozpocet']);
  });

  testWidgets('unverifiable reads as a result, not an error', (tester) async {
    await tester.pumpWidget(
      wrap(
        ClaimCard(
          claim: Claim.fromJson(j(claimJson)),
          verdict: Verdict.fromJson({
            'claim_id': 'c1',
            'label': 'unverifiable',
            'reason': 'no_sources',
            'confidence': 0.1,
          }),
          finished: true,
        ),
      ),
    );
    expect(find.text('Nelze ověřit'), findsOneWidget);
    expect(
      find.text('Nenašli jsme žádné zdroje k tomuto tvrzení.'),
      findsOneWidget,
    );
    expect(find.textContaining('Odhad jistoty'), findsNothing);
    expect(find.textContaining('Důkazy'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('checking spinner, purged text, unknown label raw (en)', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        Column(
          children: [
            ClaimCard(claim: Claim.fromJson({'id': 'a', 'p': 1})),
            ClaimCard(
              claim: Claim.fromJson({'id': 'b', 'p': 1, 'kind': 'rumour'}),
              verdict: Verdict.fromJson({'label': 'half_true'}),
            ),
          ],
        ),
        locale: const Locale('en'),
      ),
    );
    expect(find.text('Checking…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('The claim text has been deleted.'), findsNWidgets(2));
    expect(find.text('half_true'), findsOneWidget);
    expect(find.text('rumour'), findsOneWidget);
  });

  testWidgets('result screen: claims section, summary, error, show in text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ctrl = StreamController<AnalysisEvent>();
    addTearDown(ctrl.close);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('cs'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ResultScreen(connect: () => ctrl.stream),
      ),
    );
    ctrl.add(DocumentEvent(AnalysisDocument.fromJson(j(documentJson))));
    await tester.pump();
    expect(find.text('Hledám tvrzení…'), findsOneWidget);

    ctrl
      ..add(ClaimEvent(Claim.fromJson(j(claimJson))))
      ..add(
        ClaimEvent(
          Claim.fromJson({
            'id': 'c2',
            'p': 2,
            'kind': 'opinion',
            'claim': 'Zemi čeká zkáza.',
          }),
        ),
      );
    await tester.pump();
    expect(find.text('Ověřuje se…'), findsNWidgets(2));

    ctrl
      ..add(
        VerdictEvent(
          Verdict.fromJson({
            'claim_id': 'c2',
            'label': 'not_checked',
            'reason': 'opinion',
          }),
        ),
      )
      ..add(VerdictEvent(Verdict.fromJson(j(verdictJson))))
      ..add(
        ClaimsSummaryEvent(
          ClaimsSummary.fromJson({
            'claims_found': 2,
            'checked': 1,
            'by_label': {'supported': 1, 'not_checked': 1},
            'error': 'internal',
          }),
        ),
      )
      ..add(const DoneEvent());
    await tester.pump();
    expect(
      find.text('1 z 1 tvrzení podloženo · 1 neověřováno'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('claims-error')), findsOneWidget);
    expect(find.text('Neověřovaná tvrzení (1)'), findsOneWidget);
    await tester.tap(find.text('Neověřovaná tvrzení (1)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Názor, ten neověřujeme.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('claim-show-c1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final rich = find.descendant(
      of: find.byKey(const Key('paragraph-1')),
      matching: find.descendant(
        of: find.byKey(const Key('highlighted-text')),
        matching: find.byType(RichText),
      ),
    );
    final spans = <TextSpan>[];
    (tester.widget<RichText>(rich.first).text as TextSpan).visitChildren((s) {
      if (s is TextSpan && s.text != null) spans.add(s);
      return true;
    });
    final marked = spans.where(
      (s) => s.style?.decorationStyle == TextDecorationStyle.solid,
    );
    expect(marked.map((s) => s.text).join(), 'odstavec je klidný');
  });
}
