// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Pravdoměr';

  @override
  String get homeHeadline => 'Measure the temperature of a text';

  @override
  String get homeIntro =>
      'Paste a link to an article or the text itself. We measure emotions and rhetorical techniques — not whether the text is true.';

  @override
  String get inputHint => 'https://… or paste text';

  @override
  String get inputDetectedUrl => 'Link detected';

  @override
  String inputDetectedText(int count) {
    return 'Text ($count characters)';
  }

  @override
  String get analyseButton => 'Analyse';

  @override
  String get pasteButton => 'Paste';

  @override
  String get clearButton => 'Clear';

  @override
  String get errorEmptyInput => 'Paste a link or text first.';

  @override
  String errorRateLimited(int seconds) {
    return 'Too many requests. Try again in $seconds s.';
  }

  @override
  String get errorBadRequest => 'The input is not valid. Check the link.';

  @override
  String get errorTooLarge => 'The text is too long.';

  @override
  String get errorFetchFailed => 'The page could not be downloaded.';

  @override
  String get errorExtractFailed => 'No article text was found on the page.';

  @override
  String get errorLlmUnavailable =>
      'The analysis service is temporarily unavailable. Try again later.';

  @override
  String get errorInternal => 'Something went wrong on the server.';

  @override
  String get errorNetwork => 'Cannot reach the server. Check your connection.';

  @override
  String get errorNotFound => 'The analysis no longer exists.';

  @override
  String get errorConnectionLost =>
      'The connection was lost. Partial results are shown.';

  @override
  String errorUnknown(String code) {
    return 'Unexpected error: $code';
  }

  @override
  String get retryButton => 'Try again';

  @override
  String get resultTitle => 'Text temperature';

  @override
  String get statusQueued => 'Waiting in queue…';

  @override
  String get statusFetching => 'Downloading the page…';

  @override
  String get statusAnalyzing => 'Analysing paragraphs…';

  @override
  String get statusDone => 'Analysis finished';

  @override
  String get statusConnecting => 'Connecting…';

  @override
  String paragraphsProgress(int done, int total) {
    return '$done of $total paragraphs analysed';
  }

  @override
  String paragraphsFailed(int count) {
    return '$count paragraphs could not be analysed';
  }

  @override
  String get gaugeLabel => 'measured temperature';

  @override
  String get gaugePending => 'measuring…';

  @override
  String get gaugeProvisional => 'provisional, from analysed paragraphs';

  @override
  String get temperatureDisclaimer =>
      'Temperature ≠ truthfulness. It measures emotions and rhetorical techniques in the text, not whether the text is true. An emotional text can be accurate and a calm one can be wrong.';

  @override
  String get temperatureCalm => 'calm';

  @override
  String get temperatureHeated => 'heated';

  @override
  String get emotionsTitle => 'Emotions';

  @override
  String get techniquesTitle => 'Rhetorical techniques';

  @override
  String get techniquesNone => 'No techniques found so far.';

  @override
  String get paragraphsTitle => 'Paragraphs';

  @override
  String paragraphPending(int p) {
    return 'Paragraph $p is being analysed…';
  }

  @override
  String paragraphScore(int score) {
    return 'temperature $score';
  }

  @override
  String headlineClickbait(int percent) {
    return 'Headline clickbait: $percent %';
  }

  @override
  String get headlineMismatch => 'The headline does not match the body.';

  @override
  String languageLabel(String code) {
    return 'Language: $code';
  }

  @override
  String techniqueConfidence(int percent) {
    return 'Model confidence: $percent %';
  }

  @override
  String get techniqueUnknownInfo =>
      'No description available for this technique.';

  @override
  String get sheetQuoteLabel => 'Quoted passage';

  @override
  String get sheetNote =>
      'This is a signal in the text, not a judgement of its author.';

  @override
  String methodInfo(String model, String method) {
    return 'Model $model, method $method';
  }

  @override
  String get techniqueNameCalling => 'Name calling';

  @override
  String get techniqueNameCallingInfo =>
      'Labelling a person or group with a derogatory tag instead of an argument.';

  @override
  String get techniqueLoadedLanguage => 'Loaded language';

  @override
  String get techniqueLoadedLanguageInfo =>
      'Words with a strong emotional charge meant to provoke a reaction.';

  @override
  String get techniqueFearAppeal => 'Appeal to fear';

  @override
  String get techniqueFearAppealInfo =>
      'Raising fear or anxiety so the reader accepts a conclusion.';

  @override
  String get techniqueFalseDilemma => 'False dilemma';

  @override
  String get techniqueFalseDilemmaInfo =>
      'Presenting only two options when more exist.';

  @override
  String get techniqueWhataboutism => 'Whataboutism';

  @override
  String get techniqueWhataboutismInfo =>
      'Deflecting by pointing to other, allegedly worse behaviour.';

  @override
  String get techniqueAppealToAuthority => 'Appeal to authority';

  @override
  String get techniqueAppealToAuthorityInfo =>
      'The claim rests on someone\'s authority rather than on evidence.';

  @override
  String get techniqueStrawMan => 'Straw man';

  @override
  String get techniqueStrawManInfo =>
      'Distorting an opposing view so it is easier to refute.';

  @override
  String get techniqueExaggeration => 'Exaggeration or minimisation';

  @override
  String get techniqueExaggerationInfo =>
      'Overstating or downplaying something beyond what the facts support.';

  @override
  String get techniqueRepetition => 'Repetition';

  @override
  String get techniqueRepetitionInfo =>
      'Repeating the same message to make it seem more convincing.';

  @override
  String get techniqueDoubt => 'Casting doubt';

  @override
  String get techniqueDoubtInfo =>
      'Questioning the credibility of a person or institution without support.';

  @override
  String get techniqueFlagWaving => 'Flag waving';

  @override
  String get techniqueFlagWavingInfo =>
      'Using national or group identity as the argument.';

  @override
  String get techniqueSlogans => 'Slogans';

  @override
  String get techniqueSlogansInfo =>
      'A short catchy phrase in place of an explanation.';

  @override
  String get techniqueCausalOversimplification => 'Causal oversimplification';

  @override
  String get techniqueCausalOversimplificationInfo =>
      'Explaining a complex issue by a single cause.';

  @override
  String get techniqueBandwagon => 'Bandwagon';

  @override
  String get techniqueBandwagonInfo =>
      'Claiming something is right because everyone does or believes it.';

  @override
  String get techniqueRedHerring => 'Red herring';

  @override
  String get techniqueRedHerringInfo =>
      'Introducing an unrelated topic that distracts from the point.';

  @override
  String get emotionAnger => 'Anger';

  @override
  String get emotionFear => 'Fear';

  @override
  String get emotionDisgust => 'Disgust';

  @override
  String get emotionSadness => 'Sadness';

  @override
  String get emotionJoy => 'Joy';

  @override
  String get emotionSurprise => 'Surprise';

  @override
  String get emotionNeutral => 'Neutral';

  @override
  String get claimsTitle => 'Claims';

  @override
  String get claimsIntro =>
      'We check individual claims against sources we find, not the author or the outlet. Claim checks and text temperature are two independent things.';

  @override
  String get claimsSearching => 'Looking for claims…';

  @override
  String get claimsNone => 'No claims to check were found in the text.';

  @override
  String get claimsFailed =>
      'Claim checking could not be completed. The text temperature is not affected.';

  @override
  String claimsSummaryLead(int count, int total) {
    return '$count of $total claims supported';
  }

  @override
  String claimsCountMostlySupported(int count) {
    return '$count mostly supported';
  }

  @override
  String claimsCountDisputed(int count) {
    return '$count disputed';
  }

  @override
  String claimsCountRefuted(int count) {
    return '$count refuted';
  }

  @override
  String claimsCountUnverifiable(int count) {
    return '$count cannot be verified';
  }

  @override
  String claimsCountNotChecked(int count) {
    return '$count not checked';
  }

  @override
  String claimsNotCheckedTitle(int count) {
    return 'Not checked ($count)';
  }

  @override
  String get claimPurged => 'The claim text has been deleted.';

  @override
  String get claimShowInText => 'Show in text';

  @override
  String claimParagraph(int p) {
    return '§ $p';
  }

  @override
  String get verdictChecking => 'Checking…';

  @override
  String get verdictMissing => 'No result';

  @override
  String get verdictSupported => 'Supported';

  @override
  String get verdictMostlySupported => 'Mostly supported';

  @override
  String get verdictDisputed => 'Disputed';

  @override
  String get verdictRefuted => 'Refuted';

  @override
  String get verdictUnverifiable => 'Cannot verify';

  @override
  String get verdictNotChecked => 'Not checked';

  @override
  String get verdictUnverifiableInfo =>
      'The sources found are not enough for a conclusion. This does not mean the claim is false.';

  @override
  String verdictConfidence(int percent) {
    return 'Estimated confidence: $percent %';
  }

  @override
  String get verdictConfidenceNote =>
      'An estimate, not yet a calibrated probability.';

  @override
  String verdictSources(int independent, int considered) {
    return 'Independent sources: $independent of $considered';
  }

  @override
  String get modelSummaryLabel => 'Model summary';

  @override
  String evidenceTitle(int count) {
    return 'Evidence ($count)';
  }

  @override
  String evidencePublished(String date) {
    return 'published $date';
  }

  @override
  String factcheckRating(String publisher, String rating) {
    return 'Rating by $publisher: $rating';
  }

  @override
  String get linkOpenFailed => 'The link could not be opened.';

  @override
  String get stanceSupports => 'supports';

  @override
  String get stanceRefutes => 'refutes';

  @override
  String get reasonOpinion => 'An opinion; we do not check those.';

  @override
  String get reasonPrediction => 'A prediction; it cannot be checked yet.';

  @override
  String get reasonLowPriority =>
      'A less important claim; we did not check it.';

  @override
  String get reasonLimit => 'Over the limit of checked claims per article.';

  @override
  String get reasonNoSources => 'We found no sources for this claim.';

  @override
  String get reasonNoRelevantEvidence =>
      'The sources found do not address the claim directly.';

  @override
  String get reasonWeakEvidence =>
      'The evidence found is too weak for a conclusion.';

  @override
  String get reasonCheckFailed => 'Checking this claim could not be completed.';

  @override
  String get sourceFactChecker => 'Fact-checker';

  @override
  String get sourcePrimary => 'Primary source';

  @override
  String get sourceEncyclopedia => 'Encyclopedia';

  @override
  String get sourceNews => 'News';

  @override
  String get sourceUnknown => 'Unknown source';

  @override
  String get kindFact => 'Fact';

  @override
  String get kindOpinion => 'Opinion';

  @override
  String get kindPrediction => 'Prediction';
}
