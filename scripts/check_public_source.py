#!/usr/bin/env python3
"""Fail closed on embedded credentials and accidentally staged local artifacts.

This is a lightweight guard, not a replacement for a dedicated secret scanner
or a review of repository history. Only paths and rule names are printed.
"""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def main():
    top = subprocess.run(['git', 'rev-parse', '--show-toplevel'], cwd=ROOT, capture_output=True, text=True)
    if top.returncode == 0 and Path(top.stdout.strip()).resolve() == ROOT.resolve():
        result = subprocess.run(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
                                cwd=ROOT, capture_output=True, check=True)
        paths = set(result.stdout.decode().split('\0')) - {''}
    else:
        # Downloaded source archives have no Git metadata. Ignore only local caches.
        ignored = {'.git', 'build-local', 'build', 'DerivedData', '__pycache__', '.swiftpm'}
        paths = {str(path.relative_to(ROOT)) for path in ROOT.rglob('*')
                 if path.is_file() and not ignored.intersection(path.relative_to(ROOT).parts)}
    violations = []
    secret = re.compile(rb'(?:sk-(?!test)[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)')
    for name in sorted(paths):
        path = ROOT / name
        if path.is_symlink():
            violations.append((name, 'unexpected source symlink'))
            continue
        if not path.is_file():
            continue
        if name.startswith(('build-local/', 'DerivedData/', 'build/', '.env')) or '.xcresult/' in name:
            violations.append((name, 'local artifact'))
        if path.stat().st_size > 5 * 1024 * 1024:
            continue
        data = path.read_bytes()
        if secret.search(data):
            violations.append((name, 'possible credential'))
        if name.startswith('VoiceTranslationTests/') and b'UserDefaults.standard' in data:
            violations.append((name, 'tests must isolate user preferences'))
    keys = ROOT / 'VoiceTranslation/Utils/BuiltInKeys.swift'
    expected = ['static let openAIKey = ""', 'static let customAPIKey = ""',
                'static let hasOpenAIKey = false', 'static let hasCustomAPIKey = false']
    if not keys.exists() or not all(value in keys.read_text() for value in expected) or 'base64Encoded' in keys.read_text():
        violations.append(('VoiceTranslation/Utils/BuiltInKeys.swift', 'public builds must contain no built-in credentials'))
    workflow = (ROOT / '.github/workflows/build-macos.yml').read_text()
    if 'secrets.OPENAI_API_KEY' in workflow or 'secrets.CUSTOM_API_KEY' in workflow:
        violations.append(('.github/workflows/build-macos.yml', 'service credentials must not enter packaged apps'))
    for name, rule in violations:
        print(f'{name}: {rule}', file=sys.stderr)
    if violations:
        return 1
    print(f'Public source checks passed ({len(paths)} paths); no credential values printed.')
    return 0

if __name__ == '__main__':
    sys.exit(main())
