"""Exercise provenance and publication with disposable real filesystem inputs."""
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[2]


class NativeDistributionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.package = self.root / 'Vendor' / 'NessaNative'
        (self.package / 'Sources').mkdir(parents=True)
        source = self.package / 'Sources' / 'Recorded.swift'
        source.write_text('// recorded\n')
        (self.package / 'SOURCE.json').write_text(json.dumps({
            'commit': 'fixture-revision',
            'files': {'Sources/Recorded.swift': hashlib.sha256(source.read_bytes()).hexdigest()},
            'symlinks': {},
        }))
        verification = self.root / 'verification' / 'sync'
        verification.mkdir(parents=True)
        self.checker = verification / 'check-native-package.py'
        shutil.copyfile(REPO / 'verification/sync/check-native-package.py', self.checker)

    def check(self):
        return subprocess.run([sys.executable, str(self.checker), 'fixture-revision'],
                              capture_output=True, text=True)

    def test_recorded_inventory_passes(self):
        self.assertEqual(self.check().returncode, 0)

    def test_unrecorded_swift_input_is_rejected(self):
        (self.package / 'Sources/Extra.swift').write_text('// unexpected\n')
        self.assertNotEqual(self.check().returncode, 0)

    def test_external_package_root_is_rejected(self):
        external = self.root / 'external-package'
        self.package.rename(external)
        self.package.symlink_to(external, target_is_directory=True)
        self.assertNotEqual(self.check().returncode, 0)

    def test_unrecorded_symlink_is_rejected(self):
        (self.package / 'Extra.swift').symlink_to('Sources/Recorded.swift')
        self.assertNotEqual(self.check().returncode, 0)

    def test_recorded_external_symlink_is_rejected(self):
        outside = self.root / 'outside.swift'
        outside.write_text('// outside\n')
        (self.package / 'External.swift').symlink_to(outside)
        path = self.package / 'SOURCE.json'
        manifest = json.loads(path.read_text())
        manifest['symlinks']['External.swift'] = str(outside)
        path.write_text(json.dumps(manifest))
        self.assertNotEqual(self.check().returncode, 0)

    def publish(self, destination):
        return subprocess.run([sys.executable, str(REPO / 'scripts/publish-native-package.py'),
                               str(self.package), str(destination)], capture_output=True, text=True)

    def test_fresh_destination_contains_package_at_root(self):
        destination = self.root / 'published'
        self.assertEqual(self.publish(destination).returncode, 0)
        self.assertTrue((destination / 'SOURCE.json').is_file())
        self.assertTrue((destination / 'Sources/Recorded.swift').is_file())

    def test_destination_created_during_build_is_preserved(self):
        destination = self.root / 'published'
        # The build's initial absence check has already happened.
        self.assertFalse(destination.exists())
        destination.mkdir()
        (destination / 'sentinel').write_text('competitor')
        self.assertNotEqual(self.publish(destination).returncode, 0)
        self.assertEqual(list(destination.iterdir()), [destination / 'sentinel'])
        self.assertTrue((self.package / 'SOURCE.json').is_file())


if __name__ == '__main__':
    unittest.main()
