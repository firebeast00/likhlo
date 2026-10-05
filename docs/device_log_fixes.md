# TECNO LE7 device log review

Reviewed the 5 October 2026 debug run supplied after the language update.

| Log finding | App change | Verification limit |
| --- | --- | --- |
| Stats category header overflows by 39 pixels with 312 pixels of content width | Wrap the title and exact rupee total onto separate lines when needed; retain the side-by-side layout when it fits | Widget tests render the actual Stats screen at 320, 360 and 800 pixels, in both languages, with normal and enlarged text |
| Android accessibility bridge reports a child with zero bounds and no transform under the dimmer slider | Export one bounded slider semantics node with localized label, value, focus and increase/decrease actions; retain native touch and keyboard behavior and the 0–0.75 dimmer range | Semantics/action and touch tests; Android bridge output still needs device confirmation |
| Device STT reports `error_network` with an empty transcript | Request one offline retry in the same locale using the existing retry budget; do not retry cloud recognition, a nonempty draft or rate limiting. Ignore old result/finalization callbacks after a new attempt starts | Tests cover retry bounds and native `onDevice`/locale arguments. Offline support and installed language packs are device-dependent |
| Startup skips 122/107 frames while connecting TTS | Create TTS only when opted-in speech needs it; defer optional warm-up until after the first frame settles. A user request can still configure speech immediately | Factory test proves disabled speech and cancellation never instantiate TTS. A debug log cannot establish release-mode frame performance |
| `E/ion` graphics-driver message and final `Lost connection to device` | No unrelated renderer or accounting changes | No Dart crash stack or fatal Android process exception is present. The supplied output does not establish why the debugger disconnected |

Accounting, parsing, ledger validation, query selection and financial calculations remain unchanged. Changes to speech transport affect only the empty-transcript failure path; existing recognized commands still pass through the same parser and executor.

CI reruns catalog validation, Flutter analysis, the full test suite and its pre-language baseline comparison. The baseline comparison retains and reports existing failures rather than claiming the entire original suite passes.
