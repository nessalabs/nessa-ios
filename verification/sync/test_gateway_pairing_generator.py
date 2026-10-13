"""Contract generation refuses unsupported grammar, dirty sources, and owner drift."""
import os
import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = pathlib.Path(__file__).resolve().parents[2] / 'scripts/generate-gateway-pairing.py'
spec = importlib.util.spec_from_file_location('pairing_generator', SCRIPT)
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)
SOURCE = os.environ.get('NESSA_GATEWAY_SCHEMA_SOURCE')

class GeneratorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not SOURCE:
            raise unittest.SkipTest('Set NESSA_GATEWAY_SCHEMA_SOURCE to the explicit pinned gateway checkout; no implicit task path is used')
        cls.source = pathlib.Path(SOURCE)
        for name in generator.SOURCES:
            if not (cls.source/name).is_file():
                raise RuntimeError('Missing explicit schema prerequisite: ' + str(cls.source/name))
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        for name in generator.SOURCES:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((self.source/name).read_bytes())
    def generate(self):
        with patch.object(generator.subprocess, 'check_output', side_effect=[generator.PIN+'\n', '']):
            return generator.generate(self.root)
    def mutate(self, name, change):
        path = self.root / name
        data = json.loads(path.read_text())
        change(data)
        path.write_text(json.dumps(data))
    def test_published_output_is_exact(self):
        output = self.generate()
        for path, text in output.items():
            self.assertEqual((generator.ROOT/path).read_text(), text)
    def test_unknown_constraint_is_rejected(self):
        self.mutate(generator.SOURCES[0], lambda d: d['$defs']['PairingOwnerStatus']['properties']['generation'].update(multipleOf=2))
        with self.assertRaises(AssertionError): self.generate()
    def test_unknown_schema_type_is_rejected(self):
        self.mutate(generator.SOURCES[0], lambda d: d['$defs']['PairingOwnerStatus']['properties']['generation'].update(type='number'))
        with self.assertRaises(ValueError): self.generate()
    def test_pairing_byte_owner_drift_is_rejected(self):
        self.mutate(generator.SOURCES[1], lambda d: d['$defs']['DeviceKey'].update(minItems=64,maxItems=64))
        with self.assertRaises(AssertionError): self.generate()
    def test_response_union_drift_is_rejected(self):
        self.mutate(generator.SOURCES[2], lambda d: d['$defs']['ResFrame']['oneOf'][0].update(required=[]))
        with self.assertRaises(AssertionError): self.generate()
    def test_other_object_unions_are_rejected(self):
        self.mutate(generator.SOURCES[0], lambda d: d['$defs']['PairingOwnerStatus'].update(oneOf=[{'required':['credentialId']}]))
        with self.assertRaises(AssertionError): self.generate()
    def test_wrong_revision_is_rejected(self):
        with patch.object(generator.subprocess, 'check_output', return_value='different\n'):
            with self.assertRaises(AssertionError): generator.generate(self.root)
    def test_dirty_source_is_rejected(self):
        with patch.object(generator.subprocess, 'check_output', side_effect=[generator.PIN+'\n',' M protocol/product/v1.json\n']):
            with self.assertRaises(AssertionError): generator.generate(self.root)

if __name__ == '__main__': unittest.main()
