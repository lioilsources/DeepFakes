// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Czech (`cs`).
class AppLocalizationsCs extends AppLocalizations {
  AppLocalizationsCs([String locale = 'cs']) : super(locale);

  @override
  String get appTitle => 'Pravdoměr';

  @override
  String get homeHeadline => 'Změřte teplotu textu';

  @override
  String get homeIntro =>
      'Vložte odkaz na článek nebo samotný text. Měříme emoce a rétorické techniky, ne to, zda je text pravdivý.';

  @override
  String get inputHint => 'https://… nebo vložte text';

  @override
  String get inputDetectedUrl => 'Rozpoznán odkaz';

  @override
  String inputDetectedText(int count) {
    return 'Text ($count znaků)';
  }

  @override
  String get analyseButton => 'Analyzovat';

  @override
  String get pasteButton => 'Vložit';

  @override
  String get clearButton => 'Vymazat';

  @override
  String get errorEmptyInput => 'Nejdřív vložte odkaz nebo text.';

  @override
  String errorRateLimited(int seconds) {
    return 'Příliš mnoho požadavků. Zkuste to znovu za $seconds s.';
  }

  @override
  String get errorBadRequest => 'Vstup není platný. Zkontrolujte odkaz.';

  @override
  String get errorTooLarge => 'Text je příliš dlouhý.';

  @override
  String get errorFetchFailed => 'Stránku se nepodařilo stáhnout.';

  @override
  String get errorExtractFailed =>
      'Na stránce se nepodařilo najít text článku.';

  @override
  String get errorLlmUnavailable =>
      'Analytická služba je dočasně nedostupná. Zkuste to později.';

  @override
  String get errorInternal => 'Na serveru se něco pokazilo.';

  @override
  String get errorNetwork => 'Server není dostupný. Zkontrolujte připojení.';

  @override
  String get errorNotFound => 'Analýza už neexistuje.';

  @override
  String get errorConnectionLost =>
      'Spojení se přerušilo. Zobrazují se dílčí výsledky.';

  @override
  String errorUnknown(String code) {
    return 'Neočekávaná chyba: $code';
  }

  @override
  String get retryButton => 'Zkusit znovu';

  @override
  String get resultTitle => 'Teplota textu';

  @override
  String get statusQueued => 'Čeká ve frontě…';

  @override
  String get statusFetching => 'Stahuji stránku…';

  @override
  String get statusAnalyzing => 'Analyzuji odstavce…';

  @override
  String get statusDone => 'Analýza dokončena';

  @override
  String get statusConnecting => 'Připojuji se…';

  @override
  String paragraphsProgress(int done, int total) {
    return 'Analyzováno $done z $total odstavců';
  }

  @override
  String paragraphsFailed(int count) {
    return 'Nepodařilo se analyzovat odstavců: $count';
  }

  @override
  String get gaugeLabel => 'naměřená teplota';

  @override
  String get gaugePending => 'měřím…';

  @override
  String get gaugeProvisional => 'průběžně, z analyzovaných odstavců';

  @override
  String get temperatureDisclaimer =>
      'Teplota ≠ pravdivost. Měří emoce a rétorické techniky v textu, ne to, zda je text pravdivý. Emotivní text může být pravdivý a klidný text mylný.';

  @override
  String get temperatureCalm => 'klidný';

  @override
  String get temperatureHeated => 'vyhrocený';

  @override
  String get emotionsTitle => 'Emoce';

  @override
  String get techniquesTitle => 'Rétorické techniky';

  @override
  String get techniquesNone => 'Zatím žádné nalezené techniky.';

  @override
  String get paragraphsTitle => 'Odstavce';

  @override
  String paragraphPending(int p) {
    return 'Odstavec $p se analyzuje…';
  }

  @override
  String paragraphScore(int score) {
    return 'teplota $score';
  }

  @override
  String headlineClickbait(int percent) {
    return 'Clickbait titulku: $percent %';
  }

  @override
  String get headlineMismatch => 'Titulek neodpovídá obsahu textu.';

  @override
  String languageLabel(String code) {
    return 'Jazyk: $code';
  }

  @override
  String techniqueConfidence(int percent) {
    return 'Jistota modelu: $percent %';
  }

  @override
  String get techniqueUnknownInfo => 'K této technice zatím nemáme popis.';

  @override
  String get sheetQuoteLabel => 'Citovaná pasáž';

  @override
  String get sheetNote => 'Jde o signál v textu, ne o hodnocení autora.';

  @override
  String methodInfo(String model, String method) {
    return 'Model $model, metoda $method';
  }

  @override
  String get techniqueNameCalling => 'Nálepkování';

  @override
  String get techniqueNameCallingInfo =>
      'Označení osoby nebo skupiny hanlivou nálepkou místo argumentu.';

  @override
  String get techniqueLoadedLanguage => 'Citově zabarvený jazyk';

  @override
  String get techniqueLoadedLanguageInfo =>
      'Slova se silným emočním nábojem, která mají vyvolat reakci.';

  @override
  String get techniqueFearAppeal => 'Strašení';

  @override
  String get techniqueFearAppealInfo =>
      'Vyvolávání strachu nebo obav, aby čtenář přijal závěr.';

  @override
  String get techniqueFalseDilemma => 'Falešné dilema';

  @override
  String get techniqueFalseDilemmaInfo =>
      'Nabízí jen dvě možnosti, ačkoli jich existuje víc.';

  @override
  String get techniqueWhataboutism => 'Whataboutism („a co oni?“)';

  @override
  String get techniqueWhataboutismInfo =>
      'Odvedení pozornosti poukazem na jiné, údajně horší jednání.';

  @override
  String get techniqueAppealToAuthority => 'Odvolání na autoritu';

  @override
  String get techniqueAppealToAuthorityInfo =>
      'Tvrzení se opírá o něčí autoritu místo o doložené důkazy.';

  @override
  String get techniqueStrawMan => 'Slaměný panák';

  @override
  String get techniqueStrawManInfo =>
      'Zkreslení cizího názoru, aby se dal snáz vyvrátit.';

  @override
  String get techniqueExaggeration => 'Zveličování nebo zlehčování';

  @override
  String get techniqueExaggerationInfo =>
      'Přehánění nebo zlehčování nad rámec toho, co dokládají fakta.';

  @override
  String get techniqueRepetition => 'Opakování';

  @override
  String get techniqueRepetitionInfo =>
      'Opakování stejného sdělení, aby působilo přesvědčivěji.';

  @override
  String get techniqueDoubt => 'Zpochybňování';

  @override
  String get techniqueDoubtInfo =>
      'Zpochybnění důvěryhodnosti osoby nebo instituce bez doložení.';

  @override
  String get techniqueFlagWaving => 'Mávání vlajkou';

  @override
  String get techniqueFlagWavingInfo =>
      'Odvolání na národní nebo skupinovou identitu místo argumentu.';

  @override
  String get techniqueSlogans => 'Hesla';

  @override
  String get techniqueSlogansInfo => 'Krátká úderná fráze místo vysvětlení.';

  @override
  String get techniqueCausalOversimplification => 'Zjednodušení příčin';

  @override
  String get techniqueCausalOversimplificationInfo =>
      'Složitý jev vysvětlený jedinou příčinou.';

  @override
  String get techniqueBandwagon => 'Efekt stáda';

  @override
  String get techniqueBandwagonInfo =>
      'Argument, že něco platí, protože to dělají nebo si myslí všichni.';

  @override
  String get techniqueRedHerring => 'Odvádění pozornosti';

  @override
  String get techniqueRedHerringInfo =>
      'Vložení nesouvisejícího tématu, které odvádí od podstaty.';

  @override
  String get emotionAnger => 'Hněv';

  @override
  String get emotionFear => 'Strach';

  @override
  String get emotionDisgust => 'Znechucení';

  @override
  String get emotionSadness => 'Smutek';

  @override
  String get emotionJoy => 'Radost';

  @override
  String get emotionSurprise => 'Překvapení';

  @override
  String get emotionNeutral => 'Neutrální';
}
