"""Convert reviewed NLP reports into a side-effect-free semantic benchmark.

Usage: python3 tool/diagnostics_to_corpus.py report.json corpus.jsonl
For a wrong result, a developer supplies review.expected_result as a JSON object
with intent/amount/title (and optional allow_auto_execute). Plain-language
reviews stay in the report for manual triage and are counted as skipped.
Correct reviews freeze only the fields explicitly supported by the benchmark.
Original exports should stay out of git unless they contain approved test data.
"""
import argparse
import json
from pathlib import Path


def convert(report):
    if report.get('schema_version') != 1:
        raise ValueError('Unsupported diagnostic schema')
    samples, skipped = [], 0
    for command in report.get('commands', []):
        review = command.get('review', {})
        if review.get('assessment') not in ('correct', 'wrong'):
            skipped += 1
            continue
        expected = None
        try:
            expected = json.loads(review.get('expected_result', ''))
        except (ValueError, TypeError):
            pass
        if not isinstance(expected, dict) and review.get('assessment') == 'correct':
            expected = command.get('parse')
            entries = command.get('execution_input', {}).get('entries', [])
            if isinstance(expected, dict) and len(entries) == 1:
                final = entries[0]
                if any(expected.get(key) != final.get(key) for key in ('amount', 'title')):
                    skipped += 1
                    continue  # Final save may be correct only because the tester edited it.
        if not isinstance(expected, dict) or not isinstance(expected.get('intent'), str):
            skipped += 1
            continue
        if expected['intent'] in ('batch', 'udhar_lent', 'udhar_borrowed'):
            skipped += 1  # Different parser paths need their own focused tests.
            continue
        text = command.get('submitted_transcript') or command.get('raw_transcript')
        if (not text or '[name_' in text or '[name_' in str(expected.get('title', ''))
                or command.get('text_truncated') or command.get('dropped_events', 0)):
            skipped += 1
            continue
        sample = {'id': command['id'], 'input': text, 'source': 'voice'}
        for key in ('intent', 'amount', 'title', 'allow_auto_execute'):
            if key in expected:
                sample[key] = expected[key]
        samples.append(sample)
    return samples, skipped


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument('report', type=Path)
    args.add_argument('output', type=Path)
    parsed = args.parse_args()
    samples, skipped = convert(json.loads(parsed.report.read_text()))
    parsed.output.write_text(''.join(json.dumps(s, ensure_ascii=False) + '\n' for s in samples))
    print(f'{len(samples)} replay samples; {skipped} skipped (unreviewed or needs developer labels).')


if __name__ == '__main__':
    main()
