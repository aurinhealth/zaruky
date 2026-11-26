# Záruky

iOS 26 appka na účtenky a záruky. Naskenuješ účtenku, appka v telefonu přečte text (Vision), vytáhne údaje (Apple Foundation Models, na starších telefonech jednoduchá pravidla), uloží je (SwiftData) a 30 dní před koncem záruky pošle upozornění. Prvních 5 účtenek zdarma, pak jednorázové odemčení přes StoreKit 2.

## Build bez Macu

Každý push na `main` spustí workflow `.github/workflows/build.yml` na macOS runneru GitHubu: XcodeGen vygeneruje projekt a `xcodebuild` ho sestaví pro simulátor bez podepisování.

## Build na Macu

```sh
brew install xcodegen
xcodegen generate
open Zaruky.xcodeproj
```

Bundle ID `cz.zaruky.app` a produkt `cz.zaruky.app.lifetime` jsou zástupné. Testovací nákup je v `Config/Products.storekit`.

## TestFlight

Workflow `.github/workflows/testflight.yml` při každém pushi na `main` sestaví podepsaný build a nahraje ho do TestFlightu (číslo buildu = číslo běhu workflow). Podepisování řeší Xcode přes cloud signing s App Store Connect API klíčem, žádný Mac ani certifikáty v repu nejsou potřeba.

Potřebné secrets v GitHubu (Settings → Secrets and variables → Actions): `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (celý obsah souboru .p8). API klíč musí mít roli Admin. Dokud secrets chybí, workflow se jen přeskočí.
