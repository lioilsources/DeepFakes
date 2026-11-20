import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_cs.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('cs'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Pravdoměr'**
  String get appTitle;

  /// No description provided for @homeHeadline.
  ///
  /// In en, this message translates to:
  /// **'Measure the temperature of a text'**
  String get homeHeadline;

  /// No description provided for @homeIntro.
  ///
  /// In en, this message translates to:
  /// **'Paste a link to an article or the text itself. We measure emotions and rhetorical techniques — not whether the text is true.'**
  String get homeIntro;

  /// No description provided for @inputHint.
  ///
  /// In en, this message translates to:
  /// **'https://… or paste text'**
  String get inputHint;

  /// No description provided for @inputDetectedUrl.
  ///
  /// In en, this message translates to:
  /// **'Link detected'**
  String get inputDetectedUrl;

  /// No description provided for @inputDetectedText.
  ///
  /// In en, this message translates to:
  /// **'Text ({count} characters)'**
  String inputDetectedText(int count);

  /// No description provided for @analyseButton.
  ///
  /// In en, this message translates to:
  /// **'Analyse'**
  String get analyseButton;

  /// No description provided for @pasteButton.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get pasteButton;

  /// No description provided for @clearButton.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearButton;

  /// No description provided for @errorEmptyInput.
  ///
  /// In en, this message translates to:
  /// **'Paste a link or text first.'**
  String get errorEmptyInput;

  /// No description provided for @errorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Try again in {seconds} s.'**
  String errorRateLimited(int seconds);

  /// No description provided for @errorBadRequest.
  ///
  /// In en, this message translates to:
  /// **'The input is not valid. Check the link.'**
  String get errorBadRequest;

  /// No description provided for @errorTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The text is too long.'**
  String get errorTooLarge;

  /// No description provided for @errorFetchFailed.
  ///
  /// In en, this message translates to:
  /// **'The page could not be downloaded.'**
  String get errorFetchFailed;

  /// No description provided for @errorExtractFailed.
  ///
  /// In en, this message translates to:
  /// **'No article text was found on the page.'**
  String get errorExtractFailed;

  /// No description provided for @errorLlmUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The analysis service is temporarily unavailable. Try again later.'**
  String get errorLlmUnavailable;

  /// No description provided for @errorInternal.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong on the server.'**
  String get errorInternal;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the server. Check your connection.'**
  String get errorNetwork;

  /// No description provided for @errorNotFound.
  ///
  /// In en, this message translates to:
  /// **'The analysis no longer exists.'**
  String get errorNotFound;

  /// No description provided for @errorConnectionLost.
  ///
  /// In en, this message translates to:
  /// **'The connection was lost. Partial results are shown.'**
  String get errorConnectionLost;

  /// No description provided for @errorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error: {code}'**
  String errorUnknown(String code);

  /// No description provided for @retryButton.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retryButton;

  /// No description provided for @resultTitle.
  ///
  /// In en, this message translates to:
  /// **'Text temperature'**
  String get resultTitle;

  /// No description provided for @statusQueued.
  ///
  /// In en, this message translates to:
  /// **'Waiting in queue…'**
  String get statusQueued;

  /// No description provided for @statusFetching.
  ///
  /// In en, this message translates to:
  /// **'Downloading the page…'**
  String get statusFetching;

  /// No description provided for @statusAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analysing paragraphs…'**
  String get statusAnalyzing;

  /// No description provided for @statusDone.
  ///
  /// In en, this message translates to:
  /// **'Analysis finished'**
  String get statusDone;

  /// No description provided for @statusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get statusConnecting;

  /// No description provided for @paragraphsProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} paragraphs analysed'**
  String paragraphsProgress(int done, int total);

  /// No description provided for @paragraphsFailed.
  ///
  /// In en, this message translates to:
  /// **'{count} paragraphs could not be analysed'**
  String paragraphsFailed(int count);

  /// No description provided for @gaugeLabel.
  ///
  /// In en, this message translates to:
  /// **'measured temperature'**
  String get gaugeLabel;

  /// No description provided for @gaugePending.
  ///
  /// In en, this message translates to:
  /// **'measuring…'**
  String get gaugePending;

  /// No description provided for @gaugeProvisional.
  ///
  /// In en, this message translates to:
  /// **'provisional, from analysed paragraphs'**
  String get gaugeProvisional;

  /// No description provided for @temperatureDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Temperature ≠ truthfulness. It measures emotions and rhetorical techniques in the text, not whether the text is true. An emotional text can be accurate and a calm one can be wrong.'**
  String get temperatureDisclaimer;

  /// No description provided for @temperatureCalm.
  ///
  /// In en, this message translates to:
  /// **'calm'**
  String get temperatureCalm;

  /// No description provided for @temperatureHeated.
  ///
  /// In en, this message translates to:
  /// **'heated'**
  String get temperatureHeated;

  /// No description provided for @emotionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Emotions'**
  String get emotionsTitle;

  /// No description provided for @techniquesTitle.
  ///
  /// In en, this message translates to:
  /// **'Rhetorical techniques'**
  String get techniquesTitle;

  /// No description provided for @techniquesNone.
  ///
  /// In en, this message translates to:
  /// **'No techniques found so far.'**
  String get techniquesNone;

  /// No description provided for @paragraphsTitle.
  ///
  /// In en, this message translates to:
  /// **'Paragraphs'**
  String get paragraphsTitle;

  /// No description provided for @paragraphPending.
  ///
  /// In en, this message translates to:
  /// **'Paragraph {p} is being analysed…'**
  String paragraphPending(int p);

  /// No description provided for @paragraphScore.
  ///
  /// In en, this message translates to:
  /// **'temperature {score}'**
  String paragraphScore(int score);

  /// No description provided for @headlineClickbait.
  ///
  /// In en, this message translates to:
  /// **'Headline clickbait: {percent} %'**
  String headlineClickbait(int percent);

  /// No description provided for @headlineMismatch.
  ///
  /// In en, this message translates to:
  /// **'The headline does not match the body.'**
  String get headlineMismatch;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language: {code}'**
  String languageLabel(String code);

  /// No description provided for @techniqueConfidence.
  ///
  /// In en, this message translates to:
  /// **'Model confidence: {percent} %'**
  String techniqueConfidence(int percent);

  /// No description provided for @techniqueUnknownInfo.
  ///
  /// In en, this message translates to:
  /// **'No description available for this technique.'**
  String get techniqueUnknownInfo;

  /// No description provided for @sheetQuoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Quoted passage'**
  String get sheetQuoteLabel;

  /// No description provided for @sheetNote.
  ///
  /// In en, this message translates to:
  /// **'This is a signal in the text, not a judgement of its author.'**
  String get sheetNote;

  /// No description provided for @methodInfo.
  ///
  /// In en, this message translates to:
  /// **'Model {model}, method {method}'**
  String methodInfo(String model, String method);

  /// No description provided for @techniqueNameCalling.
  ///
  /// In en, this message translates to:
  /// **'Name calling'**
  String get techniqueNameCalling;

  /// No description provided for @techniqueNameCallingInfo.
  ///
  /// In en, this message translates to:
  /// **'Labelling a person or group with a derogatory tag instead of an argument.'**
  String get techniqueNameCallingInfo;

  /// No description provided for @techniqueLoadedLanguage.
  ///
  /// In en, this message translates to:
  /// **'Loaded language'**
  String get techniqueLoadedLanguage;

  /// No description provided for @techniqueLoadedLanguageInfo.
  ///
  /// In en, this message translates to:
  /// **'Words with a strong emotional charge meant to provoke a reaction.'**
  String get techniqueLoadedLanguageInfo;

  /// No description provided for @techniqueFearAppeal.
  ///
  /// In en, this message translates to:
  /// **'Appeal to fear'**
  String get techniqueFearAppeal;

  /// No description provided for @techniqueFearAppealInfo.
  ///
  /// In en, this message translates to:
  /// **'Raising fear or anxiety so the reader accepts a conclusion.'**
  String get techniqueFearAppealInfo;

  /// No description provided for @techniqueFalseDilemma.
  ///
  /// In en, this message translates to:
  /// **'False dilemma'**
  String get techniqueFalseDilemma;

  /// No description provided for @techniqueFalseDilemmaInfo.
  ///
  /// In en, this message translates to:
  /// **'Presenting only two options when more exist.'**
  String get techniqueFalseDilemmaInfo;

  /// No description provided for @techniqueWhataboutism.
  ///
  /// In en, this message translates to:
  /// **'Whataboutism'**
  String get techniqueWhataboutism;

  /// No description provided for @techniqueWhataboutismInfo.
  ///
  /// In en, this message translates to:
  /// **'Deflecting by pointing to other, allegedly worse behaviour.'**
  String get techniqueWhataboutismInfo;

  /// No description provided for @techniqueAppealToAuthority.
  ///
  /// In en, this message translates to:
  /// **'Appeal to authority'**
  String get techniqueAppealToAuthority;

  /// No description provided for @techniqueAppealToAuthorityInfo.
  ///
  /// In en, this message translates to:
  /// **'The claim rests on someone\'s authority rather than on evidence.'**
  String get techniqueAppealToAuthorityInfo;

  /// No description provided for @techniqueStrawMan.
  ///
  /// In en, this message translates to:
  /// **'Straw man'**
  String get techniqueStrawMan;

  /// No description provided for @techniqueStrawManInfo.
  ///
  /// In en, this message translates to:
  /// **'Distorting an opposing view so it is easier to refute.'**
  String get techniqueStrawManInfo;

  /// No description provided for @techniqueExaggeration.
  ///
  /// In en, this message translates to:
  /// **'Exaggeration or minimisation'**
  String get techniqueExaggeration;

  /// No description provided for @techniqueExaggerationInfo.
  ///
  /// In en, this message translates to:
  /// **'Overstating or downplaying something beyond what the facts support.'**
  String get techniqueExaggerationInfo;

  /// No description provided for @techniqueRepetition.
  ///
  /// In en, this message translates to:
  /// **'Repetition'**
  String get techniqueRepetition;

  /// No description provided for @techniqueRepetitionInfo.
  ///
  /// In en, this message translates to:
  /// **'Repeating the same message to make it seem more convincing.'**
  String get techniqueRepetitionInfo;

  /// No description provided for @techniqueDoubt.
  ///
  /// In en, this message translates to:
  /// **'Casting doubt'**
  String get techniqueDoubt;

  /// No description provided for @techniqueDoubtInfo.
  ///
  /// In en, this message translates to:
  /// **'Questioning the credibility of a person or institution without support.'**
  String get techniqueDoubtInfo;

  /// No description provided for @techniqueFlagWaving.
  ///
  /// In en, this message translates to:
  /// **'Flag waving'**
  String get techniqueFlagWaving;

  /// No description provided for @techniqueFlagWavingInfo.
  ///
  /// In en, this message translates to:
  /// **'Using national or group identity as the argument.'**
  String get techniqueFlagWavingInfo;

  /// No description provided for @techniqueSlogans.
  ///
  /// In en, this message translates to:
  /// **'Slogans'**
  String get techniqueSlogans;

  /// No description provided for @techniqueSlogansInfo.
  ///
  /// In en, this message translates to:
  /// **'A short catchy phrase in place of an explanation.'**
  String get techniqueSlogansInfo;

  /// No description provided for @techniqueCausalOversimplification.
  ///
  /// In en, this message translates to:
  /// **'Causal oversimplification'**
  String get techniqueCausalOversimplification;

  /// No description provided for @techniqueCausalOversimplificationInfo.
  ///
  /// In en, this message translates to:
  /// **'Explaining a complex issue by a single cause.'**
  String get techniqueCausalOversimplificationInfo;

  /// No description provided for @techniqueBandwagon.
  ///
  /// In en, this message translates to:
  /// **'Bandwagon'**
  String get techniqueBandwagon;

  /// No description provided for @techniqueBandwagonInfo.
  ///
  /// In en, this message translates to:
  /// **'Claiming something is right because everyone does or believes it.'**
  String get techniqueBandwagonInfo;

  /// No description provided for @techniqueRedHerring.
  ///
  /// In en, this message translates to:
  /// **'Red herring'**
  String get techniqueRedHerring;

  /// No description provided for @techniqueRedHerringInfo.
  ///
  /// In en, this message translates to:
  /// **'Introducing an unrelated topic that distracts from the point.'**
  String get techniqueRedHerringInfo;

  /// No description provided for @emotionAnger.
  ///
  /// In en, this message translates to:
  /// **'Anger'**
  String get emotionAnger;

  /// No description provided for @emotionFear.
  ///
  /// In en, this message translates to:
  /// **'Fear'**
  String get emotionFear;

  /// No description provided for @emotionDisgust.
  ///
  /// In en, this message translates to:
  /// **'Disgust'**
  String get emotionDisgust;

  /// No description provided for @emotionSadness.
  ///
  /// In en, this message translates to:
  /// **'Sadness'**
  String get emotionSadness;

  /// No description provided for @emotionJoy.
  ///
  /// In en, this message translates to:
  /// **'Joy'**
  String get emotionJoy;

  /// No description provided for @emotionSurprise.
  ///
  /// In en, this message translates to:
  /// **'Surprise'**
  String get emotionSurprise;

  /// No description provided for @emotionNeutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get emotionNeutral;

  /// No description provided for @claimsTitle.
  ///
  /// In en, this message translates to:
  /// **'Claims'**
  String get claimsTitle;

  /// No description provided for @claimsIntro.
  ///
  /// In en, this message translates to:
  /// **'We check individual claims against sources we find, not the author or the outlet. Claim checks and text temperature are two independent things.'**
  String get claimsIntro;

  /// No description provided for @claimsSearching.
  ///
  /// In en, this message translates to:
  /// **'Looking for claims…'**
  String get claimsSearching;

  /// No description provided for @claimsNone.
  ///
  /// In en, this message translates to:
  /// **'No claims to check were found in the text.'**
  String get claimsNone;

  /// No description provided for @claimsFailed.
  ///
  /// In en, this message translates to:
  /// **'Claim checking could not be completed. The text temperature is not affected.'**
  String get claimsFailed;

  /// No description provided for @claimsSummaryLead.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} claims supported'**
  String claimsSummaryLead(int count, int total);

  /// No description provided for @claimsCountMostlySupported.
  ///
  /// In en, this message translates to:
  /// **'{count} mostly supported'**
  String claimsCountMostlySupported(int count);

  /// No description provided for @claimsCountDisputed.
  ///
  /// In en, this message translates to:
  /// **'{count} disputed'**
  String claimsCountDisputed(int count);

  /// No description provided for @claimsCountRefuted.
  ///
  /// In en, this message translates to:
  /// **'{count} refuted'**
  String claimsCountRefuted(int count);

  /// No description provided for @claimsCountUnverifiable.
  ///
  /// In en, this message translates to:
  /// **'{count} cannot be verified'**
  String claimsCountUnverifiable(int count);

  /// No description provided for @claimsCountNotChecked.
  ///
  /// In en, this message translates to:
  /// **'{count} not checked'**
  String claimsCountNotChecked(int count);

  /// No description provided for @claimsNotCheckedTitle.
  ///
  /// In en, this message translates to:
  /// **'Not checked ({count})'**
  String claimsNotCheckedTitle(int count);

  /// No description provided for @claimPurged.
  ///
  /// In en, this message translates to:
  /// **'The claim text has been deleted.'**
  String get claimPurged;

  /// No description provided for @claimShowInText.
  ///
  /// In en, this message translates to:
  /// **'Show in text'**
  String get claimShowInText;

  /// No description provided for @claimParagraph.
  ///
  /// In en, this message translates to:
  /// **'§ {p}'**
  String claimParagraph(int p);

  /// No description provided for @verdictChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get verdictChecking;

  /// No description provided for @verdictMissing.
  ///
  /// In en, this message translates to:
  /// **'No result'**
  String get verdictMissing;

  /// No description provided for @verdictSupported.
  ///
  /// In en, this message translates to:
  /// **'Supported'**
  String get verdictSupported;

  /// No description provided for @verdictMostlySupported.
  ///
  /// In en, this message translates to:
  /// **'Mostly supported'**
  String get verdictMostlySupported;

  /// No description provided for @verdictDisputed.
  ///
  /// In en, this message translates to:
  /// **'Disputed'**
  String get verdictDisputed;

  /// No description provided for @verdictRefuted.
  ///
  /// In en, this message translates to:
  /// **'Refuted'**
  String get verdictRefuted;

  /// No description provided for @verdictUnverifiable.
  ///
  /// In en, this message translates to:
  /// **'Cannot verify'**
  String get verdictUnverifiable;

  /// No description provided for @verdictNotChecked.
  ///
  /// In en, this message translates to:
  /// **'Not checked'**
  String get verdictNotChecked;

  /// No description provided for @verdictUnverifiableInfo.
  ///
  /// In en, this message translates to:
  /// **'The sources found are not enough for a conclusion. This does not mean the claim is false.'**
  String get verdictUnverifiableInfo;

  /// No description provided for @verdictConfidence.
  ///
  /// In en, this message translates to:
  /// **'Estimated confidence: {percent} %'**
  String verdictConfidence(int percent);

  /// No description provided for @verdictConfidenceNote.
  ///
  /// In en, this message translates to:
  /// **'An estimate, not yet a calibrated probability.'**
  String get verdictConfidenceNote;

  /// No description provided for @verdictSources.
  ///
  /// In en, this message translates to:
  /// **'Independent sources: {independent} of {considered}'**
  String verdictSources(int independent, int considered);

  /// No description provided for @modelSummaryLabel.
  ///
  /// In en, this message translates to:
  /// **'Model summary'**
  String get modelSummaryLabel;

  /// No description provided for @evidenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Evidence ({count})'**
  String evidenceTitle(int count);

  /// No description provided for @evidencePublished.
  ///
  /// In en, this message translates to:
  /// **'published {date}'**
  String evidencePublished(String date);

  /// No description provided for @factcheckRating.
  ///
  /// In en, this message translates to:
  /// **'Rating by {publisher}: {rating}'**
  String factcheckRating(String publisher, String rating);

  /// No description provided for @linkOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'The link could not be opened.'**
  String get linkOpenFailed;

  /// No description provided for @stanceSupports.
  ///
  /// In en, this message translates to:
  /// **'supports'**
  String get stanceSupports;

  /// No description provided for @stanceRefutes.
  ///
  /// In en, this message translates to:
  /// **'refutes'**
  String get stanceRefutes;

  /// No description provided for @reasonOpinion.
  ///
  /// In en, this message translates to:
  /// **'An opinion; we do not check those.'**
  String get reasonOpinion;

  /// No description provided for @reasonPrediction.
  ///
  /// In en, this message translates to:
  /// **'A prediction; it cannot be checked yet.'**
  String get reasonPrediction;

  /// No description provided for @reasonLowPriority.
  ///
  /// In en, this message translates to:
  /// **'A less important claim; we did not check it.'**
  String get reasonLowPriority;

  /// No description provided for @reasonLimit.
  ///
  /// In en, this message translates to:
  /// **'Over the limit of checked claims per article.'**
  String get reasonLimit;

  /// No description provided for @reasonNoSources.
  ///
  /// In en, this message translates to:
  /// **'We found no sources for this claim.'**
  String get reasonNoSources;

  /// No description provided for @reasonNoRelevantEvidence.
  ///
  /// In en, this message translates to:
  /// **'The sources found do not address the claim directly.'**
  String get reasonNoRelevantEvidence;

  /// No description provided for @reasonWeakEvidence.
  ///
  /// In en, this message translates to:
  /// **'The evidence found is too weak for a conclusion.'**
  String get reasonWeakEvidence;

  /// No description provided for @reasonCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Checking this claim could not be completed.'**
  String get reasonCheckFailed;

  /// No description provided for @sourceFactChecker.
  ///
  /// In en, this message translates to:
  /// **'Fact-checker'**
  String get sourceFactChecker;

  /// No description provided for @sourcePrimary.
  ///
  /// In en, this message translates to:
  /// **'Primary source'**
  String get sourcePrimary;

  /// No description provided for @sourceEncyclopedia.
  ///
  /// In en, this message translates to:
  /// **'Encyclopedia'**
  String get sourceEncyclopedia;

  /// No description provided for @sourceNews.
  ///
  /// In en, this message translates to:
  /// **'News'**
  String get sourceNews;

  /// No description provided for @sourceUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown source'**
  String get sourceUnknown;

  /// No description provided for @kindFact.
  ///
  /// In en, this message translates to:
  /// **'Fact'**
  String get kindFact;

  /// No description provided for @kindOpinion.
  ///
  /// In en, this message translates to:
  /// **'Opinion'**
  String get kindOpinion;

  /// No description provided for @kindPrediction.
  ///
  /// In en, this message translates to:
  /// **'Prediction'**
  String get kindPrediction;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['cs', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'cs':
      return AppLocalizationsCs();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
