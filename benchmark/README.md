# Pakistani Smart Entry benchmark

Run with:

```bash
dart run tool/semantic_benchmark.dart
```

The checked-in JSONL file is a deterministic seed set for parser regression.
Production ASR selection still requires consented recordings from multiple
Pakistani speakers, devices, accents, networks, and noise conditions. Add
audio/provider results without storing names, account identifiers, or complete
transaction histories.

Primary acceptance metrics are exact amount, intent, wallet/direction, complete
semantic command accuracy, unsafe execution rate, cutoff rate, and latency.
