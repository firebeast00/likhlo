# Voice diagnostics testing

Enable **Settings → Voice diagnostics → Record voice commands** on a test
device. This is separate from the existing anonymous timing/error switch.
Use the regular Home, notification, quick-action or Udhaar microphone. Open a
record, mark **Correct**, **Misunderstood / wrong**, or **Unsure**, and add the
actual phrase and intended action/fields. Recording does not change parsing,
confidence thresholds, wallet selection, confirmation rules or ledger writes.

Select records or filter by outcome/review and the last 1/7/30 days. Export,
inspect the JSON preview, then Save JSON or Share JSON using the device share
sheet. Exclude a record by returning to the selection list. Known wallet,
person and detected title names are masked by default; inspect the entire
preview because names, spelling variants, amounts and other details may remain.
Use synthetic names/accounts when exact text is needed for parser replay.
Nothing is automatically uploaded. No audio or contacts are captured.

## Evidence and limits

Each schema-v1 command stores recognizer words unchanged up to the documented
text limit, partial/final flags, provider confidence when available, requested
locale and on-device mode, recognizer cycles/retries/errors, assembled submitted
input, normalization rules, intent/fields/confidence, confirmations, action
inputs after tester edits, results and affected IDs, app responses and independent TTS status. Query
records include the actual reference time, calendar range/month, wallet filter
and aggregate results. Tester assessment is independent of action completion.

Platform ASR may replace Roman Urdu words before NLP sees them. Compare
**What I actually said** with **Original recognizer words** to identify this.
Compare original/submitted input with normalization output to identify app
substitutions. Compare intent/fields and action result to isolate later errors.
The report contains text, not recordings, so it cannot independently prove what
was spoken or evaluate the recognizer against the original waveform.

Retention: 30 days, 2,000 records, 10 MB, whichever is reached first. A record
keeps at most 120 events, up to 2,048 characters per text field and 40 items per
event collection; truncation/drop counts are exposed. Oldest records are
evicted first. Deleted records cannot be restored by late callbacks. A process
exit leaves an interrupted record with action outcome unknown; recorded
execution evidence should be checked before repeating a financial command.
Diagnostics use a separate Hive box and are excluded from ledger backups.
Storage errors are visible on the diagnostics screen and never block actions.
Disabling capture retains history; Clear diagnostics deletes it without
changing the ledger or other settings.

TTS invocation is not proof that sound played. Completion is recorded only
when an unambiguous platform callback is observed. FlutterTts callbacks lack
utterance IDs, so overlapping/interrupted speech reports unknown callback
correlation instead of claiming a new utterance completed. Financial outcome
is never changed by a TTS failure.

## Fast team loop

1. Each teammate spends 10 minutes testing English, Roman Urdu, Urdu script,
   mixed speech, amounts (sau/hazar/lakh), names, wallets, dates, long pauses,
   noise and no-network conditions. Include failed and successful commands.
2. Review every failure immediately and a sample of successes. Record the
   intended amount/title/wallet/date; a saved wrong command is still wrong.
   If you had to correct detected fields before saving, review the original
   interpretation as wrong and name the stage that needed correction.
3. Collect JSON files manually. Group repeated failures by recognition,
   normalization, intent/field parsing, action validation and spoken feedback.
4. Fix the largest repeated group. Keep speakers/devices aside as a holdout;
   do not evaluate only phrases used to write new rules. The report's reviewed
   accuracy denominator excludes unsure/unreviewed commands and shows coverage.
5. Replay annotated parser examples before distributing the next build.

```bash
python3 tool/diagnostics_to_corpus.py report.json corpus.jsonl
dart run tool/semantic_benchmark.dart corpus.jsonl
flutter test test/voice_diagnostics_service_test.dart test/voice_diagnostics_observer_test.dart test/voice_diagnostics_screen_test.dart
```

For wrong examples, developers can turn the tester's explanation into a JSON
object in `review.expected_result`, e.g.
`{"intent":"add_expense","amount":100,"title":"Chai"}`. The conversion
tool never imports or executes ledger commands. It skips unreviewed, unsure,
masked, truncated, batch and Udhaar examples, and saves whose amount/title were edited
without explicit developer labels; add separate focused tests for those
paths. Masked examples are suitable for privacy review, but use an approved
synthetic unmasked export when exact names/spellings matter.

Build with `--dart-define=BUILD_COMMIT=<sha>` and optionally
`--dart-define=APP_VERSION=<version+build>` to attach reproducible metadata.
Without these flags the commit is reported as unknown. The NLP version tag
refers to the unchanged parser baseline; bump it when parser behavior changes.

## Validation and device checks

The diagnostics CI compares the full Flutter suite to the exact current-app
baseline `3ba06f0`, runs focused diagnostics tests and builds an Android debug
APK. Existing baseline failures are reported separately. The debug APK is for
teammate feature testing. Use a profile/release build on physical devices for
performance measurements.

Before release, verify microphone permissions denied/allowed, all four voice
entry paths, an incomplete phrase, offline recognition fallback, confirmation
save/cancel/retry, Udhaar save/cancel, actual share/save destinations, process
termination/relaunch, clear/opt-out and masked preview. Check that diagnostics
off/on do not change ledger results and compare frame timings on the same
device. Native recognizer/TTS/share behavior requires a real device check.
