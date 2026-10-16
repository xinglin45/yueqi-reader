#!/usr/bin/env python3
"""Project-scoped Flutter install and exact-revision command runner (no PATH edits)."""
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
PIN = json.loads((ROOT / 'tool/flutter-sdk.json').read_text(encoding='utf-8'))


def sdk_path():
    override = os.environ.get('YUEQI_FLUTTER_SDK')
    if override:
        return Path(override).expanduser().resolve()
    if sys.platform == 'darwin':
        base = Path.home() / 'Library/Developer/yueqi'
    elif sys.platform == 'win32':
        base = Path(os.environ.get('LOCALAPPDATA', Path.home())) / 'Yueqi'
    else:
        base = Path.home() / '.local/share/yueqi'
    return base / 'flutter' / PIN['version'] / 'flutter'


def validate(sdk):
    if not sdk.is_dir():
        raise RuntimeError('Flutter尚未安装；先运行 python3 tool/sdk.py install')
    revision = subprocess.check_output(
        ['git', '-C', str(sdk), 'rev-parse', 'HEAD'], text=True,
    ).strip()
    if revision != PIN['framework_revision']:
        raise RuntimeError('Flutter版本不符；需要固定的 ' + PIN['version'] +
                           ' / ' + PIN['framework_revision'])
    engine = (sdk / 'bin/internal/engine.version').read_text().strip()
    if engine != PIN['engine_revision']:
        raise RuntimeError('Flutter engine修订不符；不会自动覆盖现有SDK')
    dart_version = sdk / 'bin/cache/dart-sdk/version'
    if dart_version.exists() and dart_version.read_text().strip() != PIN['dart_version']:
        raise RuntimeError('Dart版本不符；需要 ' + PIN['dart_version'])


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ('install', 'flutter', 'dart'):
        raise RuntimeError('用法：python3 tool/sdk.py install|flutter|dart [参数…]')
    command = sys.argv[1]
    sdk = sdk_path()
    if command == 'install' and not sdk.exists():
        sdk.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([
            'git', 'clone', '--depth', '1', '--branch', PIN['version'],
            PIN['repository'], str(sdk),
        ], check=True)
        subprocess.run(['git', '-C', str(sdk), 'switch', '-c', 'stable'], check=True)
    validate(sdk)
    env = dict(os.environ)
    env['PATH'] = str(sdk / 'bin') + os.pathsep + env.get('PATH', '')
    env['FLUTTER_SUPPRESS_ANALYTICS'] = 'true'
    env['DART_SUPPRESS_ANALYTICS'] = 'true'
    if command == 'dart':
        binary = sdk / 'bin/cache/dart-sdk/bin' / ('dart.exe' if os.name == 'nt' else 'dart')
        if not binary.exists():
            raise RuntimeError('Dart缓存尚未就绪；先运行 python3 tool/sdk.py install')
        args = [str(binary), *sys.argv[2:]]
    else:
        binary = sdk / 'bin' / ('flutter.bat' if os.name == 'nt' else 'flutter')
        args = [str(binary), '--suppress-analytics', *(
            ['--version', '--machine'] if command == 'install' else sys.argv[2:]
        )]
    return subprocess.call(args, env=env)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.CalledProcessError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
