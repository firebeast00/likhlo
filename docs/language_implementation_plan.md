# English and Roman Urdu implementation

The app language changes presentation only. Accounting, parsing, validation decisions, navigation identifiers, category keys, wallet names, transaction descriptions and notification action IDs stay unchanged.

## 1. Independent preference and migration
- Add `appLanguage` to the existing settings box, defaulting to `english` for old installations and invalid/missing values.
- Keep `smartEntryLanguage` independent and preserve its current default and stored value.
- Copy the new setting through `SettingsState.copyWith`; do not alter any ledger schema or Hive type ID.
- Use Flutter localization delegates with an explicit `ur-Latn` variant and left-to-right controls. Bundle complete catalogs into Dart so first-frame rendering and offline use need no asynchronous file reads or new package versions.

## 2. App-authored text
- Use named catalog entries and placeholder values for screens, dialogs, tooltips, validation, chart labels, onboarding, receipt/batch review, backups and PDF headings.
- Interpolate parameters once. Treat user-entered names/descriptions as opaque values, even when they equal an English built-in label.
- Translate canonical built-in categories/sections only at display boundaries; pass their original values to callbacks, queries and persistence.
- Keep currency values and report/file identifiers unchanged. Existing widgets keep their positions and state.

## 3. Notification and speech boundary
- Pass message keys and parameters through shared dashboard feedback. Render written and spoken templates from the same values.
- Retain a limited English-message adapter for existing service errors; use it only at app-response boundaries.
- Read the persisted app language in background quick entry. Refresh the pinned notification and recreate scheduled app reminders on language changes using the same IDs, times and payloads.
- Preserve opt-in, silent-mode checks, microphone cancellation and duplicate-speech suppression.
- Prefer an installed Urdu voice for authored Urdu-script speech. If the message or voice has no supported Urdu version, use its English template with an English voice. Explain this fallback beside a voice-preview control.
- Stop pending speech when switching language; reconfigure the engine by language and engine identity. TTS failures remain best effort and cannot roll back ledger operations.

## 4. Verification gates
- Catalog key parity and exact placeholder parity across English/Roman Urdu; Urdu speech placeholders must be a subset of the same event parameters.
- Compare accounting, NLP, query, transfer, title policy and backup codec files with the starting commit. Any change beyond explicit background language-storage initialization must be investigated.
- Preference migration/persistence tests, user-value preservation, notification-title/body parameters, English fallback, Urdu voice switching and cancellation races.
- Run the existing ledger/query/NLP/transfer/backup tests and new language tests on Flutter. If Flutter is unavailable, record that limitation explicitly; syntax/static checks cannot substitute for execution.
- Phone checks: restart, rapid language changes, open forms, offline voice availability, silent mode, background quick entry, reminder content and narrow screens.

Deliver changes as a separate draft branch based on the existing voice-feedback fixes. Do not merge automatically.
