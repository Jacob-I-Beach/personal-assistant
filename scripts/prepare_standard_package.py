"""Make a Health-disabled signing input from an already verified device archive.

Run on macOS. Apple's codesign replaces only the temporary ad-hoc signature;
the eventual installer must still sign with the user's matching identity.
"""
import argparse
import hashlib
import json
import plistlib
from pathlib import Path
import struct
import subprocess
import tempfile
from zipfile import ZipFile, ZIP_DEFLATED

from inspect_ipa import inspect


def sections(binary: bytes) -> dict:
    if struct.unpack_from('<II', binary) != (0xFEEDFACF, 0x0100000C):
        raise ValueError('Expected a thin ARM64 Mach-O input.')
    cursor = 32
    result = {}
    for _ in range(struct.unpack_from('<I', binary, 16)[0]):
        command, size = struct.unpack_from('<II', binary, cursor)
        if size < 8 or cursor + size > len(binary):
            raise ValueError('Invalid load command.')
        if command == 0x19:  # LC_SEGMENT_64
            count = struct.unpack_from('<I', binary, cursor + 64)[0]
            if 72 + count * 80 > size:
                raise ValueError('Invalid section table.')
            for index in range(count):
                section = cursor + 72 + index * 80
                name = binary[section:section + 16].rstrip(b'\0').decode()
                segment = binary[section + 16:section + 32].rstrip(b'\0').decode()
                length = struct.unpack_from('<Q', binary, section + 40)[0]
                offset = struct.unpack_from('<I', binary, section + 48)[0]
                kind = struct.unpack_from('<I', binary, section + 64)[0] & 0xFF
                if kind in (1, 0xC, 0x12) or not length:  # zero-fill sections
                    continue
                if offset + length > len(binary):
                    raise ValueError('Invalid file-backed section.')
                result[(segment, name)] = hashlib.sha256(binary[offset:offset + length]).hexdigest()
        cursor += size
    if ('__TEXT', '__text') not in result:
        raise ValueError('Missing compiled code section.')
    return result


def prepare(source: Path, checksums: Path, destination: Path, increased_memory: bool = False) -> dict:
    receipt = inspect(source, checksums)
    if destination.exists() or source.resolve() == destination.resolve():
        raise ValueError('Preserve the source and any existing output.')
    if receipt['health_enabled_in_app']:
        raise ValueError('Use the compiled Health-disabled input.')
    destination.parent.mkdir(parents=True, exist_ok=True)
    prefix = 'Payload/PersonalAssistant.app/'
    with tempfile.TemporaryDirectory(prefix='standard-signing-', dir=destination.parent) as temporary:
        staging = Path(temporary)
        with ZipFile(source) as archive:
            archive.extractall(staging)  # inspect() checked paths and CRC above.
            for entry in archive.infolist():
                mode = (entry.external_attr >> 16) & 0o7777
                if mode:
                    (staging / entry.filename).chmod(mode)
            original = {name: hashlib.sha256(archive.read(name)).hexdigest()
                        for name in archive.namelist() if not name.endswith('/')}
        app = staging / prefix
        info_path = app / 'Info.plist'
        info = plistlib.loads(info_path.read_bytes())
        info['AssistantHealthEnabled'] = False
        info.pop('NSHealthShareUsageDescription', None)
        info.pop('NSHealthUpdateUsageDescription', None)
        info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
        executable = app / info['CFBundleExecutable']
        original_sections = sections(executable.read_bytes())
        entitlements = staging / 'empty-entitlements.plist'
        requested = {'com.apple.developer.kernel.increased-memory-limit': True} if increased_memory else {}
        entitlements.write_bytes(plistlib.dumps(requested))
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--timestamp=none',
                        '--generate-entitlement-der', '--entitlements', str(entitlements), str(app)], check=True)
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        if sections(executable.read_bytes()) != original_sections:
            raise ValueError('Compiled sections changed during signing.')
        changed = []
        for name, digest in original.items():
            if hashlib.sha256((staging / name).read_bytes()).hexdigest() != digest:
                changed.append(name)
                if name not in (prefix + 'Info.plist', prefix + info['CFBundleExecutable']) and not name.startswith(prefix + '_CodeSignature/'):
                    raise ValueError('Unexpected changed file: ' + name)
        extensions = list((app / 'PlugIns').glob('*.appex'))
        if not any(plistlib.loads((extension / 'Info.plist').read_bytes()).get('NSExtension', {}).get('NSExtensionPointIdentifier') == 'com.apple.widgetkit-extension' for extension in extensions):
            raise ValueError('The Live Activity extension is missing.')
        with ZipFile(destination, 'w', compression=ZIP_DEFLATED) as output:
            for path in sorted((staging / 'Payload').rglob('*')):
                if path.is_file():
                    output.write(path, path.relative_to(staging).as_posix())
    output_checksums = destination.parent / 'SHA256SUMS.txt'
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    previous_checksums = output_checksums.read_text(encoding='utf-8') if output_checksums.exists() else ''
    output_checksums.write_text(previous_checksums.rstrip() + '\n' + digest + '  ' + destination.name + '\n', encoding='utf-8')
    result = inspect(destination, output_checksums)
    if result['requested_entitlements'] != requested or result['health_enabled_in_app']:
        raise ValueError('The signing input requests unexpected capabilities.')
    result.update(source_sha256=receipt['sha256'], health_deferred=True,
                  compiled_sections_unchanged=True, activity_extension_preserved=True,
                  apple_adhoc_signature_verified=True, changed_files=changed,
                  increased_memory_requested=increased_memory,
                  note='Unsigned installation input with a verified ad-hoc signature. Personal signing is still required. A memory request is not a granted profile entitlement or measured iOS allowance.')
    destination.with_suffix('.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('checksums', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--increased-memory', action='store_true', help='Request only the regular increased-memory entitlement; matching provisioning is still required.')
    args = parser.parse_args()
    print(json.dumps(prepare(args.source, args.checksums, args.destination, args.increased_memory), indent=2))
