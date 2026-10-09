"""Produce an iPhone-only signing input for official iLoader 2.3.6.

The complete compiled iPhone/Watch archive is retained separately. This copies
the iPhone files byte-for-byte and omits only the unsupported Watch bundle.
The resulting archive requires a complete re-sign before installation.
"""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import zipfile


def prepare(source: Path, destination: Path) -> dict:
    if source.resolve() == destination.resolve():
        raise ValueError("The original package must be retained.")
    root = "Payload/PersonalAssistant.app/"
    watch = root + "Watch/"
    omitted = []
    with zipfile.ZipFile(source) as original:
        if original.testzip() is not None:
            raise ValueError("The source archive failed its CRC check.")
        info = plistlib.loads(original.read(root + "Info.plist"))
        if info["CFBundleIdentifier"] != "dev.jacob.personalassistant":
            raise ValueError("Unexpected app identity.")
        if info.get("AssistantHealthEnabled") is True:
            raise ValueError("This iLoader route cannot provision HealthKit.")
        executable_path = root + info["CFBundleExecutable"]
        main_digest = hashlib.sha256(original.read(executable_path)).hexdigest()
        with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as output:
            for entry in original.infolist():
                if entry.filename.startswith(watch):
                    omitted.append(entry.filename)
                else:
                    output.writestr(entry, original.read(entry.filename))
    with zipfile.ZipFile(destination) as candidate:
        if candidate.testzip() is not None:
            raise ValueError("The resulting archive failed its CRC check.")
        if hashlib.sha256(candidate.read(executable_path)).hexdigest() != main_digest:
            raise ValueError("The iPhone executable changed during packaging.")
        if any(name.startswith(watch) for name in candidate.namelist()):
            raise ValueError("The resulting archive still contains Watch files.")
    return {
        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "output_sha256": hashlib.sha256(destination.read_bytes()).hexdigest(),
        "iphone_executable_sha256": main_digest,
        "version": info["CFBundleShortVersionString"],
        "build": info["CFBundleVersion"],
        "bundle_identifier": info["CFBundleIdentifier"],
        "omitted_watch_entries": len(omitted),
        "requires_personal_resigning": True,
        "health_enabled": False,
        "reason": "Official iLoader 2.3.6 does not provision Watch bundles or request HealthKit.",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    receipt = prepare(args.source, args.destination)
    args.destination.with_suffix(".json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, indent=2))
