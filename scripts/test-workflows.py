#!/usr/bin/env python3
"""Application workflows using private preferences/files in a logged-in Mac session."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('native_qa', root / 'scripts/test-native-ui.py')
qa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', default='.build/debug/Twister')
parser.add_argument('--output', default='build/workflows')
args = parser.parse_args()
output = Path(args.output).resolve()
output.mkdir(parents=True, exist_ok=True)
app = qa.bundle_for_audit(Path(args.app).resolve(), output)
result = subprocess.run([str(app), '--workflow-smoke', str(output / 'checks')],
                        capture_output=True, text=True, timeout=180)
report = output / 'checks/workflow.json'
if result.returncode or not report.exists():
    raise AssertionError(result.stdout[-2000:] + result.stderr[-5000:])
report = json.loads(report.read_text())
assert report['passed'] and len(report['checks']) >= 50, report
print(f"PASS: {len(report['checks'])} application export, recovery and editor lifecycle checks")
