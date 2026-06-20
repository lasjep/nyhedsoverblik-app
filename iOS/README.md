# Nyhedsoverblik til iPad — kom i gang

Appen deler ~90 % af koden med macOS-versionen (`../Sources/Nyhedsoverblik`).
Mac-specifikke dele (flydende panel, menukommandoer) er `#if os(macOS)`-afskærmet.

## Engangsopsætning (når Xcode er færdiginstalleret)

1. **Åbn Xcode én gang** og acceptér licensen. Kør evt.:
   `sudo xcode-select -s /Applications/Xcode.app`

2. **Tilføj dit Apple ID**: Xcode → Settings → Accounts → "+" → log ind.
   Det opretter et gratis "Personal Team".

3. **Vælg team**: Åbn `Nyhedsoverblik.xcodeproj`, vælg target
   *NyhedsoverblikIOS* → Signing & Capabilities → sæt **Team** til dit
   personal team. (Skriv evt. team-id'et ind i `project.yml` under
   `DEVELOPMENT_TEAM:` så det overlever regenerering.)

4. **Tilslut iPad'en med kabel**, lås den op, og tryk "Tillad" når den
   spørger om at stole på Mac'en.

5. **Første installation**: nemmest direkte i Xcode — vælg din iPad som
   destination øverst og tryk ▶. Første gang skal du på iPad'en slå
   **Udviklertilstand** til (Indstillinger → Anonymitet & sikkerhed →
   Udviklertilstand) og bagefter godkende udvikleren under
   Indstillinger → Generelt → VPN & enhedsadministration.

## Daglig brug / fornyelse

Efter engangsopsætningen klarer scriptet alt:

```sh
./deploy.sh
```

Med gratis Apple ID udløber appen efter **7 dage** — kør bare `deploy.sh`
igen med iPad'en tilsluttet.

## Filstruktur

- `project.yml` — projektdefinition (XcodeGen). Kør `xcodegen generate`
  efter du har tilføjet/fjernet filer.
- `NyhedsoverblikIOS/` — iOS-specifik kode (app-entry + ikon).
- `../Sources/Nyhedsoverblik/` — den delte kodebase.

## Kendte forskelle fra macOS-versionen

- Intet flydende panel (giver ikke mening på iPad)
- Artikler åbner i indbygget webview i tredje kolonne (samme som Mac)
- Læst-status synkroniseres IKKE mellem Mac og iPad endnu
  (kræver Apple Developer Program → iCloud)
