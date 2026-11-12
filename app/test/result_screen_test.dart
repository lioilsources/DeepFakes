import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pravdomer/api/models.dart';
import 'package:pravdomer/l10n/app_localizations.dart';
import 'package:pravdomer/screens/result_screen.dart';

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
  home: child,
);

String? gaugeText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('gauge-score'))).data;

void tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('renders incremental, out-of-order events', (tester) async {
    tallView(tester);
    final ctrl = StreamController<AnalysisEvent>();
    addTearDown(ctrl.close);
    await tester.pumpWidget(wrap(ResultScreen(connect: () => ctrl.stream)));

    expect(find.byKey(const Key('temperature-disclaimer')), findsOneWidget);
    expect(find.textContaining('Teplota ≠ pravdivost'), findsOneWidget);

    ctrl
      ..add(const StatusEvent('fetching'))
      ..add(DocumentEvent(AnalysisDocument.fromJson(j(documentJson))));
    await tester.pump();
    expect(find.text('Titulek článku'), findsOneWidget);
    expect(find.textContaining('example.com'), findsOneWidget);
    expect(find.textContaining('Jazyk: cs'), findsOneWidget);
    // Both paragraphs still pending.
    expect(find.textContaining('se analyzuje'), findsNWidgets(2));

    // Paragraph 2 arrives before paragraph 1.
    const text2 = 'Tihle zrádci zničí naši zemi!';
    ctrl.add(
      ParagraphEvent(
        ParagraphResult.fromJson({
          'p': 2,
          'score': 70,
          'emotions': {'anger': 0.7, 'fear': 0.4},
          'techniques': [
            {
              'technique': 'name_calling',
              'quote': 'zrádci',
              'start': text2.indexOf('zrádci'),
              'end': text2.indexOf('zrádci') + 6,
              'confidence': 0.8,
            },
          ],
        }),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Odstavec 1 se analyzuje'), findsOneWidget);
    expect(find.textContaining('Odstavec 2 se analyzuje'), findsNothing);
    expect(find.text('teplota 70'), findsOneWidget);
    // Provisional overall score from the single analysed paragraph.
    expect(gaugeText(tester), '70');
    expect(find.text('Hněv'), findsOneWidget);
    expect(find.text('Nálepkování'), findsOneWidget); // technique chip

    // Tap the highlighted quote inside paragraph 2.
    final rich = find.descendant(
      of: find.byKey(const Key('paragraph-2')),
      matching: find.byKey(const Key('highlighted-text')),
    );
    await tester.ensureVisible(rich);
    await tester.pump();
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: rich, matching: find.byType(RichText)),
    );
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 7, extentOffset: 9),
    );
    final topLeft = paragraph.localToGlobal(Offset.zero);
    await tester.tapAt(topLeft + boxes.first.toRect().center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Citovaná pasáž'), findsOneWidget);
    expect(find.text('zrádci'), findsOneWidget);
    expect(find.textContaining('hanlivou nálepkou'), findsOneWidget);
    expect(find.text('Jistota modelu: 80 %'), findsOneWidget);
    Navigator.of(tester.element(find.text('Citovaná pasáž'))).pop();
    await tester.pump(const Duration(milliseconds: 500));

    ctrl
      ..add(ParagraphEvent(ParagraphResult.fromJson({'p': 1, 'score': 10})))
      ..add(SummaryEvent(AnalysisSummary.fromJson(j(summaryJson))))
      ..add(const DoneEvent());
    await tester.pump();
    expect(find.textContaining('se analyzuje'), findsNothing);
    expect(gaugeText(tester), '48');
    expect(find.text('Analýza dokončena'), findsOneWidget);
    expect(find.text('Clickbait titulku: 40 %'), findsOneWidget);
    expect(find.text('Strašení'), findsOneWidget);
  });

  testWidgets('error event shows a banner and keeps partial results', (
    tester,
  ) async {
    tallView(tester);
    final ctrl = StreamController<AnalysisEvent>();
    addTearDown(ctrl.close);
    await tester.pumpWidget(
      wrap(
        ResultScreen(connect: () => ctrl.stream),
        locale: const Locale('en'),
      ),
    );
    ctrl
      ..add(DocumentEvent(AnalysisDocument.fromJson(j(documentJson))))
      ..add(ParagraphEvent(ParagraphResult.fromJson({'p': 1, 'score': 5})))
      ..add(const ErrorEvent('llm_unavailable'));
    await tester.pump();
    expect(find.byKey(const Key('error-banner')), findsOneWidget);
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('temperature 5'), findsOneWidget);
    // Unanalysed paragraph shows its plain text instead of a shimmer.
    expect(find.text('Tihle zrádci zničí naši zemi!'), findsOneWidget);
  });
}
