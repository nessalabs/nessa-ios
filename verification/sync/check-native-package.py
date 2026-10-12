#!/usr/bin/env python3
"""Check recorded distribution bytes and symlinks; this is not a signature trust policy."""
import hashlib
import json
import os
import pathlib
import sys

package = pathlib.Path(__file__).resolve().parents[2] / 'Vendor' / 'NessaNative'
if package.is_symlink():
    raise SystemExit('The vendored package root must not be a symlink')
manifest = json.loads((package / 'SOURCE.json').read_text())
if len(sys.argv) != 2 or manifest['commit'] != sys.argv[1]:
    raise SystemExit('Expected the exact gateway source revision as the argument')
actual_files = set()
actual_symlinks = set()
for directory, folders, files in os.walk(package, followlinks=False):
    for name in folders + files:
        path = pathlib.Path(directory) / name
        relative = path.relative_to(package).as_posix()
        if not path.resolve().is_relative_to(package.resolve()):
            raise SystemExit('Package entry escapes its root: ' + relative)
        if path.is_symlink():
            actual_symlinks.add(relative)
        elif path.is_file():
            if relative != 'SOURCE.json':
                actual_files.add(relative)
        elif not path.is_dir():
            raise SystemExit('Unsupported package entry: ' + relative)
if actual_files != set(manifest['files']) or actual_symlinks != set(manifest['symlinks']):
    raise SystemExit('Package inventory differs from its manifest')
for relative, expected in manifest['files'].items():
    path = package / relative
    if pathlib.PurePosixPath(relative).is_absolute() or '..' in path.relative_to(package).parts:
        raise SystemExit('Manifest path escapes the package')
    if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        raise SystemExit('Package bytes changed: ' + relative)
for relative, target in manifest['symlinks'].items():
    path = package / relative
    if pathlib.PurePosixPath(relative).is_absolute() or '..' in path.relative_to(package).parts:
        raise SystemExit('Manifest symlink path escapes the package')
    if not path.is_symlink() or os.readlink(path) != target:
        raise SystemExit('Package symlink changed: ' + relative)
print('PASS: complete native distribution inventory, bytes and symlinks match ' + manifest['commit'])
