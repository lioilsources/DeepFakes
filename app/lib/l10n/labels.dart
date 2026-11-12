// Maps API enum values to localized strings. Unknown values fall back to the raw key.
import 'app_localizations.dart';

String techniqueName(AppLocalizations l, String key) {
  switch (key) {
    case 'name_calling':
      return l.techniqueNameCalling;
    case 'loaded_language':
      return l.techniqueLoadedLanguage;
    case 'fear_appeal':
      return l.techniqueFearAppeal;
    case 'false_dilemma':
      return l.techniqueFalseDilemma;
    case 'whataboutism':
      return l.techniqueWhataboutism;
    case 'appeal_to_authority':
      return l.techniqueAppealToAuthority;
    case 'straw_man':
      return l.techniqueStrawMan;
    case 'exaggeration':
      return l.techniqueExaggeration;
    case 'repetition':
      return l.techniqueRepetition;
    case 'doubt':
      return l.techniqueDoubt;
    case 'flag_waving':
      return l.techniqueFlagWaving;
    case 'slogans':
      return l.techniqueSlogans;
    case 'causal_oversimplification':
      return l.techniqueCausalOversimplification;
    case 'bandwagon':
      return l.techniqueBandwagon;
    case 'red_herring':
      return l.techniqueRedHerring;
    default:
      return key;
  }
}

String techniqueInfo(AppLocalizations l, String key) {
  switch (key) {
    case 'name_calling':
      return l.techniqueNameCallingInfo;
    case 'loaded_language':
      return l.techniqueLoadedLanguageInfo;
    case 'fear_appeal':
      return l.techniqueFearAppealInfo;
    case 'false_dilemma':
      return l.techniqueFalseDilemmaInfo;
    case 'whataboutism':
      return l.techniqueWhataboutismInfo;
    case 'appeal_to_authority':
      return l.techniqueAppealToAuthorityInfo;
    case 'straw_man':
      return l.techniqueStrawManInfo;
    case 'exaggeration':
      return l.techniqueExaggerationInfo;
    case 'repetition':
      return l.techniqueRepetitionInfo;
    case 'doubt':
      return l.techniqueDoubtInfo;
    case 'flag_waving':
      return l.techniqueFlagWavingInfo;
    case 'slogans':
      return l.techniqueSlogansInfo;
    case 'causal_oversimplification':
      return l.techniqueCausalOversimplificationInfo;
    case 'bandwagon':
      return l.techniqueBandwagonInfo;
    case 'red_herring':
      return l.techniqueRedHerringInfo;
    default:
      return l.techniqueUnknownInfo;
  }
}

String emotionName(AppLocalizations l, String key) {
  switch (key) {
    case 'anger':
      return l.emotionAnger;
    case 'fear':
      return l.emotionFear;
    case 'disgust':
      return l.emotionDisgust;
    case 'sadness':
      return l.emotionSadness;
    case 'joy':
      return l.emotionJoy;
    case 'surprise':
      return l.emotionSurprise;
    case 'neutral':
      return l.emotionNeutral;
    default:
      return key;
  }
}

/// Emotion keys in display order.
const emotionKeys = <String>[
  'anger',
  'fear',
  'disgust',
  'sadness',
  'joy',
  'surprise',
  'neutral',
];
