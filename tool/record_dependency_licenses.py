#!/usr/bin/env python3
"""Record resolved dependency license hashes without retaining machine paths."""
import argparse
from datetime import date
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from urllib.parse import unquote, urljoin, urlparse

ROOT = Path(__file__).resolve().parent.parent
CLIENT = ROOT / '小说/client'
parser = argparse.ArgumentParser()
parser.add_argument('--checkpoint', required=True, choices=['mac-01', 'mac-02', 'mac-06', 'mac-03'])
checkpoint = parser.parse_args().checkpoint
OUT = ROOT / 'docs/licenses'
config_path = CLIENT / '.dart_tool/package_config.json'
config = json.loads(config_path.read_text())
packages = {
    p['name']: p for p in json.loads(subprocess.check_output(
        [str(ROOT / 'tool/flutterw'), 'pub', 'deps', '--json'], cwd=CLIENT, text=True,
    ))['packages']
}
roots = {
    p['name']: Path(unquote(urlparse(urljoin(config_path.as_uri(), p['rootUri'])).path))
    for p in config['packages']
}
runtime = set()


def visit(name):
    if name in runtime:
        return
    runtime.add(name)
    for dependency in packages[name].get('directDependencies', []):
        visit(dependency)


visit('novel_app')
production_runtime = set(runtime)
if checkpoint in ('mac-06', 'mac-03'):
    visit('epub_view')
    visit('html')
experiment = runtime - production_runtime
runtime = production_runtime
records = []
for name, package in sorted(packages.items()):
    source = package['source']
    record = {
        'name': name, 'version': package['version'], 'source': source,
        'scope': 'runtime' if name in runtime else 'mac06_experiment' if name in experiment else 'development',
    }
    if name in ('novel_app', 'reader_core', 'platform_services', 'reader_storage'):
        record['license_status'] = 'project_license_not_selected'
    else:
        folder = roots[name]
        license_file = folder / 'LICENSE'
        if not license_file.exists() and source == 'sdk':
            license_file = roots['flutter'].parent.parent / 'LICENSE'
        if not license_file.exists():
            raise RuntimeError('Missing license: ' + name)
        record['license_sha256'] = hashlib.sha256(license_file.read_bytes()).hexdigest()
        record['license_status'] = 'text_inspected'
        if name in runtime or name in experiment:
            prior = next((p for p in sorted(OUT.glob('mac-*/' + name + '-LICENSE.txt')) if hashlib.sha256(p.read_bytes()).hexdigest() == record['license_sha256']), OUT / 'mac-01' / (name + '-LICENSE.txt'))
            if checkpoint != 'mac-01' and prior.exists() and hashlib.sha256(prior.read_bytes()).hexdigest() == record['license_sha256']:
                target = prior
            else:
                target = OUT / checkpoint / (name + '-LICENSE.txt')
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(license_file, target)
            record['retained_license'] = target.relative_to(OUT).as_posix()
        if source == 'hosted':
            record['upstream'] = 'https://pub.dev/packages/' + name + '/versions/' + package['version']
    records.append(record)
(OUT / (checkpoint + '-dependencies.json')).write_text(json.dumps({
    'verified_date': date.today().isoformat(),
    'sdk_pin': '../../tool/flutter-sdk.json',
    'application_lockfile': '../../小说/client/pubspec.lock',
    'packages': records,
}, ensure_ascii=False, indent=2) + '\n')
print(f'Recorded {len(records)} packages; {len(runtime)} in the runtime closure.')
