# Release appky — TestFlight + Firebase App Tester + olin.now

Pipeline je z Distribution (`align-project.sh`, golden `Distribution/workflows/`): `ci.yml`, `release-ios.yml`, `release-android.yml`. Appka leží v `app/`, workflowy pracují s `working-directory: app`. Release spouští tag `v*` (`git tag v0.1.0 && git push origin v0.1.0`), verze se bere z tagu. Postup releasu: skill `release-flutter`.

| | |
|---|---|
| iOS bundle | `com.ol1n.pravdomer` |
| Share extension (zatím není) | `com.ol1n.pravdomer.ShareExtension` |
| App Group (pro share extension) | `group.com.ol1n.pravdomer` |
| Android | `com.ol1n.pravdomer` |
| API v release buildu | `https://pravdomer.ol1n.com` (výchozí `API_BASE` při `kReleaseMode`) |

## Odchylka od golden šablony

`ci.yml` má navíc job `api` (Go vet + test pro `api/`). Při dalším `align-project.sh` ho zkontroluj, skript ho přepíše.

## Jednou ručně (účty)

Postup a pasti: `Distribution/SKILL.md`. Pro Pravdoměr:

1. **Apple Developer → Identifiers:** App ID `com.ol1n.pravdomer`. App Group `group.com.ol1n.pravdomer` založ rovnou, bude potřeba pro share extension.
2. **Profiles** (Distribution → App Store): `Pravdomer AppStore` → `Distribution/Apple/Pravdomer/Pravdomer_AppStore.mobileprovision`. Až přibude share extension: druhý profil do `Distribution/Apple/Pravdomer/extensions/` a krok s `IOS_EXT_PROVISION_PROFILE_BASE64` podle vzoru `lioilsources/ThePill`.
3. **App Store Connect** → New App: iOS, bundle `com.ol1n.pravdomer`, SKU `ol1npravdomer`. Jméno v listingu je otevřené (Pravdoměr je pracovní název).
   - Privacy Policy URL: `https://lioilsources.github.io/DeepFakes/privacy.html`
   - Support URL: `https://lioilsources.github.io/DeepFakes/support.html`
   - Marketing URL: `https://olin.now/pravdomer`
4. **Firebase** → Android app `com.ol1n.pravdomer` → `google-services.json` do `Distribution/Android/Pravdomer/` (`Distribution/SKILL.md` krok 3).
5. **Secrets:** `cd Distribution && ./scripts/setup-gh-secrets.sh --repo lioilsources/DeepFakes` + ruční opravy z `Distribution/CLAUDE.md`.

## Server pro release buildy

Release build mluví jen s `https://pravdomer.ol1n.com`, HTTP povoluje jen debug/profile build. Dokud API není nasazené (`api/docker-compose.yml` na NAS + Cloudflare Tunnel, nasazuje Olin), testuj debug/profile build s `--dart-define=API_BASE=…`. Bez běžícího LLM API vrátí `llm_unavailable` a appka to ukáže.

## Privacy / support

GitHub Pages z `main /docs`: `index.html`, `privacy.html`, `support.html`. Markdown v `docs/` Pages ignorují (`.nojekyll`).
