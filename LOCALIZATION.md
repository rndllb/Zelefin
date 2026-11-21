# App UI localization

Zelefin’s chrome (menus, tabs, settings, empty states) is localized. Server/media titles, genre names from Jellyfin/Emby, and debug logs stay in their original language.

## Preference

- Key: `zelefin.appLanguage`
- Empty / `system` = follow the device language
- iOS: `@AppStorage` + root `.appLanguage(_:)` (locale + layout direction)
- Android: `InterfacePreferences` SharedPreferences + `AppCompatDelegate.setApplicationLocales`

Settings → **Interface** → **App Language**. Playback audio/subtitle language pickers stay under Playback and do not change UI chrome.

## Catalogs

| Platform | Source of truth |
|----------|-----------------|
| iOS | `IOS/Zelefin/Localizable.xcstrings` |
| Android | `Android/app/src/main/res/values/strings.xml` + `values-*/strings.xml` |

Keys stay parallel: dotted on iOS (`settings.language.app`), underscores on Android (`settings_language_app`).

### v1 locales

`en` (source), `zh-Hans` / `zh-rCN`, `hi`, `es`, `ar` (RTL), `fr`, `pt-BR` / `pt-rBR`, `ru`, `de`, `ja`, `id` / `in` (Android Indonesian folder).

## Adding a language

1. **English key** — add the string to `Localizable.xcstrings` (`en`) and `values/strings.xml` with the same semantic key.
2. **Translate** — fill the new locale in the string catalog and add `values-<tag>/strings.xml` (Android resource qualifiers: `zh-rCN`, `pt-rBR`, `in` for Indonesian).
3. **Picker** — add a case to `AppLanguage` on both platforms (`IOS/.../AppLanguage.swift`, `Android/.../AppLanguage.kt`) with `nativeName` in that language’s script and the correct BCP-47 / Android tag.
4. **Xcode** — ensure the locale is listed under the project’s `knownRegions` (String Catalog localizations are enough for runtime once the case exists).
5. **RTL** — if the language is right-to-left, confirm `AppLanguage.isRightToLeft` / Android `supportsRtl` and spot-check dock, sheets, and player chrome using start/end (not left/right).

No other call-site rewrites are required when keys already use catalogs/`stringResource`.

## RTL (Arabic)

- iOS: `.appLanguage` sets `layoutDirection` from `AppLanguage.isRightToLeft`; prefer `chevron.forward` / `chevron.backward` and leading/trailing padding.
- Android: `android:supportsRtl="true"`; use `start`/`end` padding and `Icons.AutoMirrored.*` for nav chevrons. Keep absolute left/right only for media seek direction indicators.

## QA checklist

- Switch App Language in Interface without reinstalling; chrome updates (Android may recreate the activity).
- Cold start restores the chosen language.
- **System** follows the device language again.
- Spot-check Home, Library, Search, Settings, and player chrome in System, one LTR locale, and Arabic.
