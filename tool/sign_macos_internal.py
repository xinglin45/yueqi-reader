#!/usr/bin/env python3
"""Finalize this workspace's ad-hoc checkpoint seal, preserving entitlements.

The pinned SDK emits individually valid frameworks but an invalid outer seal
with this native-assets build. This is not Developer ID signing/notarization.
"""
import plistlib
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / '小说/client/build/macos/Build/Products/Release/阅栖.app'
if sys.platform != 'darwin':
    raise SystemExit('This checkpoint verifier requires macOS.')
info = plistlib.loads((APP / 'Contents/Info.plist').read_bytes())
if info['CFBundleIdentifier'] != 'local.yueqi.novel':
    raise SystemExit('Unexpected bundle identifier; refusing to sign.')
metadata = subprocess.run(['codesign', '-dv', str(APP)], capture_output=True, check=True)
if b'Signature=adhoc' not in metadata.stderr:
    raise SystemExit('Only the existing ad-hoc internal checkpoint may be finalized.')

def entitlements():
    data = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(APP)], capture_output=True, check=True)
    return plistlib.loads(data.stdout)

before = entitlements()
for framework in (APP / 'Contents/Frameworks').glob('*.framework'):
    subprocess.run(['codesign', '--verify', '--strict', str(framework)], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', '--preserve-metadata=entitlements', str(APP)], check=True)
if entitlements() != before:
    raise SystemExit('Entitlements changed unexpectedly.')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(APP)], check=True)
print('Internal ad-hoc seal verified; entitlements preserved; no notarization.')
