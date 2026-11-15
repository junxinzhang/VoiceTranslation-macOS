#!/usr/bin/env python3
"""Export reviewable source without Git history, local builds or private backups."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    target = (args.output or ROOT / 'build-local/public-source' / ('VoiceTranslation-source-' + stamp)).resolve()
    if target.exists():
        parser.error('output already exists; choose a new directory')
    subprocess.run([sys.executable, str(ROOT / 'scripts/check_public_source.py')], cwd=ROOT, check=True)
    result = subprocess.run(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
                            cwd=ROOT, capture_output=True, check=True)
    paths = sorted(set(result.stdout.decode().split('\0')) - {''})
    target.mkdir(parents=True)
    manifest = []
    for name in paths:
        relative = Path(name)
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('unsafe source path')
        # Workstation instructions are not part of the app source distribution.
        if name == 'AGENTS.md':
            continue
        source = ROOT / relative
        if not source.is_file():
            continue
        if source.is_symlink():
            raise ValueError('source symlinks require manual review')
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        manifest.append({'path': name, 'sha256': hashlib.sha256(source.read_bytes()).hexdigest()})
    (target / 'SOURCE_MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n')
    subprocess.run([sys.executable, str(target / 'scripts/check_public_source.py')], cwd=target, check=True)
    archive = shutil.make_archive(str(target), 'zip', root_dir=target.parent, base_dir=target.name)
    digest = hashlib.sha256(Path(archive).read_bytes()).hexdigest()
    Path(archive + '.sha256').write_text(digest + '  ' + Path(archive).name + '\n')
    print(f'Exported {len(manifest)} files to {target}')
    print(f'Archive: {archive}')
    return 0

if __name__ == '__main__':
    sys.exit(main())
