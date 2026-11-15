#!/usr/bin/env python3
"""Exercise the public-source guard in disposable repositories."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('source_guard', Path(__file__).with_name('check_public_source.py'))
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)

class PublicSourceGuardTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.original_root = guard.ROOT
        guard.ROOT = self.root
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        self.keys = self.root / 'VoiceTranslation/Utils/BuiltInKeys.swift'
        self.keys.parent.mkdir(parents=True)
        self.keys.write_text('static let openAIKey = ""\nstatic let customAPIKey = ""\nstatic let hasOpenAIKey = false\nstatic let hasCustomAPIKey = false\n')
        workflow = self.root / '.github/workflows/build-macos.yml'
        workflow.parent.mkdir(parents=True)
        workflow.write_text('name: safe-public-build\n')
    def tearDown(self):
        guard.ROOT = self.original_root
        self.directory.cleanup()
    def test_empty_public_build_passes(self):
        self.assertEqual(guard.main(), 0)
    def test_credential_in_new_source_fails(self):
        (self.root / 'accident.swift').write_text('let key = "' + 'sk-' + 'z' * 32 + '"\n')
        self.assertEqual(guard.main(), 1)
    def test_encoded_builtin_key_fails_even_without_recognizable_prefix(self):
        self.keys.write_text(self.keys.read_text() + '\nlet value = Data(base64Encoded: "eA==")\n')
        self.assertEqual(guard.main(), 1)
    def test_local_backup_accidentally_staged_fails(self):
        local = self.root / 'build-local/private.txt'
        local.parent.mkdir()
        local.write_text('local acceptance data')
        (self.root / '.gitignore').write_text('/build-local/\n')
        subprocess.run(['git', 'add', '-f', 'build-local/private.txt'], cwd=self.root, check=True)
        self.assertEqual(guard.main(), 1)

if __name__ == '__main__':
    unittest.main()
