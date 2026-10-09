"""Validate a downloaded, unsigned device package without extracting or executing it."""
import argparse
import hashlib
import json
import plistlib
import struct
from pathlib import Path, PurePosixPath
from zipfile import ZipFile


def inspect(ipa: Path, checksum_file: Path) -> dict:
    checksums = {}
    for line in checksum_file.read_text().splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) == 2:
            checksums[parts[1].lstrip(" *")] = parts[0].lower()
    expected = checksums.get(ipa.name)
    if expected is None:
        raise ValueError("No checksum was recorded for this package filename.")
    with ipa.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    if digest != expected:
        raise ValueError("The package does not match the build's SHA-256 checksum.")

    prefix = "Payload/PersonalAssistant.app/"
    with ZipFile(ipa) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("The package contains duplicate archive paths.")
        if any(PurePosixPath(name).is_absolute() or ".." in PurePosixPath(name).parts for name in names):
            raise ValueError("An archive path escapes the package directory.")
        if archive.testzip() is not None:
            raise ValueError("The package has a corrupt ZIP entry.")
        info = plistlib.loads(archive.read(prefix + "Info.plist"))
        if info["CFBundleIdentifier"] != "dev.jacob.personalassistant":
            raise ValueError("Unexpected app identifier.")
        executable = info["CFBundleExecutable"]
        binary = archive.read(prefix + executable)
        if len(binary) < 32 or struct.unpack_from("<I", binary)[0] != 0xFEEDFACF:
            raise ValueError("Expected a 64-bit Mach-O executable.")
        if struct.unpack_from("<I", binary, 4)[0] != 0x0100000C:
            raise ValueError("Expected an ARM64 iPhone executable.")
        command_count = struct.unpack_from("<I", binary, 16)[0]
        offset = 32
        platform = None
        signature = None
        for _ in range(command_count):
            command, size = struct.unpack_from("<II", binary, offset)
            if size < 8 or offset + size > len(binary):
                raise ValueError("Invalid Mach-O load command.")
            if command == 0x32:  # LC_BUILD_VERSION
                platform = struct.unpack_from("<I", binary, offset + 8)[0]
            if command == 0x1D:  # LC_CODE_SIGNATURE
                start, length = struct.unpack_from("<II", binary, offset + 8)
                if start + length > len(binary):
                    raise ValueError("The code-signature range is invalid.")
                signature = binary[start:start + length]
            offset += size
        if platform != 2:  # PLATFORM_IOS; PLATFORM_IOSSIMULATOR is 7.
            raise ValueError("This executable is not built for a physical iOS device.")
        metal_libraries = [name for name in names if name.endswith(".metallib")]
        if not metal_libraries:
            raise ValueError("The bundled Metal model kernels are missing.")
        if any(name.endswith((".safetensors", ".gguf")) for name in names):
            raise ValueError("Model weights unexpectedly appear in the installation package.")
        entitlements = {}
        if signature:
            magic, length, count = struct.unpack_from(">III", signature)
            if magic != 0xFADE0CC0 or length > len(signature) or 12 + count * 8 > length:
                raise ValueError("The embedded signature container is malformed.")
            for index in range(count):
                slot, start = struct.unpack_from(">II", signature, 12 + index * 8)
                if slot == 5:  # CSSLOT_ENTITLEMENTS (XML)
                    if start + 8 > length:
                        raise ValueError("Invalid entitlement range.")
                    blob_magic, size = struct.unpack_from(">II", signature, start)
                    if blob_magic != 0xFADE7171 or size < 8 or start + size > length:
                        raise ValueError("Invalid entitlement blob.")
                    entitlements = plistlib.loads(signature[start + 8:start + size])
        watch_bundles = []
        for name in names:
            if name.startswith(prefix + "Watch/") and name.endswith(".app/Info.plist"):
                watch_info = plistlib.loads(archive.read(name))
                if watch_info.get("WKCompanionAppBundleIdentifier") != info["CFBundleIdentifier"]:
                    raise ValueError("The Watch companion points to a different iPhone app.")
                watch_bundles.append({
                    "bundle_identifier": watch_info["CFBundleIdentifier"],
                    "version": watch_info["CFBundleShortVersionString"],
                    "build": watch_info["CFBundleVersion"],
                })
        return {
            "file": ipa.name,
            "sha256": digest,
            "bytes": ipa.stat().st_size,
            "bundle_identifier": info["CFBundleIdentifier"],
            "version": info["CFBundleShortVersionString"],
            "build": info["CFBundleVersion"],
            "minimum_ios": info.get("MinimumOSVersion"),
            "executable_architecture": "arm64",
            "executable_platform": "iOS device",
            "metal_library_count": len(metal_libraries),
            "watch_bundles": watch_bundles,
            "requested_entitlements": entitlements,
            "health_enabled_in_app": info.get("AssistantHealthEnabled") is True,
            "has_embedded_provisioning_profile": prefix + "embedded.mobileprovision" in names,
            "installation_status": "Requires personal signing and physical-device testing",
        }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("checksums", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = inspect(args.ipa, args.checksums)
    serialized = json.dumps(result, indent=2) + "\n"
    if args.report:
        args.report.write_text(serialized, encoding="utf-8")
    print(serialized, end="")
