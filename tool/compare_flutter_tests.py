"""Report the full suite, failing CI only for failures absent from the baseline.

Both reports must finish; infrastructure failures must never pass this check.
Run: python3 tool/compare_flutter_tests.py baseline.json head.json
"""
import json
import pathlib
import sys


def read_report(path):
    suites, tests, failures = {}, {}, set()
    completed = False
    successful = False
    for line in pathlib.Path(path).read_text().splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue  # Flutter may emit dependency/engine diagnostics before JSON.
        kind = event.get('type')
        if kind == 'suite':
            suites[event['suite']['id']] = event['suite']['path']
        elif kind == 'testStart':
            test = event['test']
            tests[test['id']] = test
        elif kind == 'testDone':
            test = tests[event['testID']]
            test['result'] = event['result']
            test['skipped'] = event['skipped']
            test['hidden'] = event.get('hidden', False)
            if event['result'] != 'success':
                suite = suites[test['suiteID']]
                # Reports come from different checkout directories.
                relative = suite.split('/test/', 1)[-1]
                failures.add((relative, test['name']))
        elif kind == 'done':
            completed = True
            successful = event['success']
    if not completed or not tests or any('result' not in test for test in tests.values()):
        raise SystemExit(f'Incomplete test report: {path}')
    if not successful and not failures:
        raise SystemExit(f'Unreported runner failure: {path}')
    passed = sum(test['result'] == 'success' and not test['skipped']
                 and not test.get('hidden', False) for test in tests.values())
    print(f'{path}: {passed} passed, {len(failures)} failed')
    return failures


if __name__ == '__main__':
    baseline = read_report(sys.argv[1])
    head = read_report(sys.argv[2])
    for suite, name in sorted(head & baseline):
        print(f'Existing failure: {suite}: {name}')
    for suite, name in sorted(baseline - head):
        print(f'Resolved failure: {suite}: {name}')
    new = head - baseline
    for suite, name in sorted(new):
        print(f'NEW failure: {suite}: {name}')
    if new:
        raise SystemExit(1)
    print('No new failing tests compared with the pre-language commit.')
