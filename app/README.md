# Pravdoměr — Flutter appka (M1)

Mobilní klient pro iOS a Android. M1 umí jen **teplotu textu**: emoce, rétorické techniky a naměřenou teplotu 0–100 po odstavcích. Teplota ≠ pravdivost — appka to říká přímo u ukazatele.

Kontrakt API: [`../docs/API.md`](../docs/API.md).

## Spuštění

```sh
cd app
flutter pub get
flutter run --profile --dart-define=API_BASE=http://<adresa-api>:8096
```

Bez `API_BASE` appka volá `http://localhost:8096` (Android emulátor potřebuje `http://10.0.2.2:8096`). Nešifrované HTTP je povolené jen v debug/profile buildech na Androidu (`src/debug`, `src/profile`) a na iOS přes `NSAllowsLocalNetworking`; produkce poběží přes HTTPS. <!-- devconv:allow-ip -->

Gate:

```sh
flutter analyze
flutter test
```

## Struktura

| | |
|---|---|
| `lib/api/` | klient (`client.dart`), SSE parser (`sse.dart`), modely, stav analýzy, ID zařízení, rozpoznání URL/textu, share sheet |
| `lib/screens/` | `home_screen.dart` (vstup), `result_screen.dart` (živý výsledek) |
| `lib/widgets/` | ukazatel teploty, emoce, techniky, odstavce se zvýrazněním, bottom sheet |
| `lib/l10n/` | ARB (`app_cs.arb`, `app_en.arb`), generované `app_localizations*.dart`, mapování technik a emocí (`labels.dart`) |
| `test/` | SSE parser, modely z příkladů v API.md, zvýraznění (překryvy, emoji, diakritika), klient s mock HTTP, widget test výsledku |

Překlady se generují `flutter gen-l10n` (spouští se i samo při `flutter pub get`).

## Co je hotové

- Domovská obrazovka: vložení URL nebo textu, tlačítko Vložit ze schránky, rozpoznání odkazu i ve sdíleném „titulek + URL“.
- Sdílení z jiných appek na Androidu (`text/plain`, balíček `share_handler`); sdílený obsah rovnou spustí analýzu.
- Výsledek přes SSE `GET /v1/analyses/{id}/events`: titulek, web, autor, datum, jazyk; ukazatel naměřené teploty s upozorněním „Teplota ≠ pravdivost“; emoce; počty technik; odstavce v pořadí dokumentu, i když výsledky chodí napřeskáčku. Neanalyzované odstavce mají shimmer.
- Zvýraznění citací technik podle `start`/`end` (UTF-16), překrývající se citace jsou rozdělené na přesné úseky a tmavší. Klepnutí otevře bottom sheet s názvem techniky, vysvětlením, citací a jistotou modelu.
- Než dorazí `summary`, ukazuje se průběžná teplota, emoce a techniky z hotových odstavců (označené „průběžně“).
- Výpadek spojení: appka se znovu připojí (server pošle replay, stav je idempotentní); po opakovaných chybách ukáže dílčí výsledky a tlačítko „Zkusit znovu“.
- `429` na `POST`: hláška s odpočtem podle `Retry-After`, tlačítko je do té doby neaktivní. Chybové události `error` mají lokalizované hlášky.
- `X-Device-Id`: náhodné UUID uložené v `shared_preferences`.
- Čeština a angličtina přes ARB, včetně názvů a krátkých vysvětlení všech 15 technik.

## Co zbývá

- **iOS Share Extension.** Dart strana a `Info.plist` (URL schéma `ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)`) jsou připravené, ale target se musí přidat v Xcode:
  1. `open ios/Runner.xcworkspace` → File → New → Target → *Share Extension*, název `ShareExtension`, bundle id `com.ol1n.pravdomer.ShareExtension`.
  2. V `ios/ShareExtension/Info.plist` nastavit `NSExtensionActivationRule` na text a URL (vzor v README balíčku `share_handler`), `CFBundleVersion` = `$(FLUTTER_BUILD_NUMBER)`.
  3. Runner i ShareExtension: Signing & Capabilities → App Groups → `group.com.ol1n.pravdomer`.
  4. Do `ios/Podfile` uvnitř `target 'Runner'` přidat:
     ```ruby
     target 'ShareExtension' do
       inherit! :search_paths
       pod "share_handler_ios_models", :path => ".symlinks/plugins/share_handler_ios/ios/Models"
     end
     ```
     a spustit `pod install`.
  5. `ShareViewController.swift` nahradit: `import share_handler_ios_models` + `class ShareViewController: ShareHandlerIosViewController {}`.
  6. Ověřit, že Share Extension má stejný deployment target jako Runner a že se Runner buildí před extension (Build Phases → Embed Foundation Extensions nad Run Script).
- Ikona appky, release pipeline a stránky ve store (mimo M1).
- Obnovení výsledku po restartu appky (`GET /v1/analyses/{id}`) a historie analýz.
- Měření latence z pohledu appky (čas do prvního odstavce, do `summary`) pro `PRAVDOMER_EVAL.md`.
- Test na zařízení proti běžícímu Go API.
