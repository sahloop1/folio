#!/usr/bin/env python3
"""Map Codemagic's increasing build count to Apple's three-part build format."""
from pathlib import Path
import re
import sys


def assign(project: Path, build_count: str) -> str:
    if not re.fullmatch(r"[0-9]{1,8}", build_count):
        raise ValueError("Expected Codemagic's numeric BUILD_NUMBER.")
    number = int(build_count) + 1
    major = number // 10_000 + 1
    if major > 9999:
        raise ValueError("This build count exceeds Apple's version component limit.")
    version = f"{major}.{number // 100 % 100}.{number % 100}"
    text = project.read_text()
    updated, count = re.subn(r'("CURRENT_PROJECT_VERSION"\s*=\s*")[^"]+(";)',
                             lambda match: match[1] + version + match[2], text)
    if count != 6:
        raise ValueError("Expected six Folio target version settings; the Xcode project layout changed.")
    project.write_text(updated)
    return version


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: python3 scripts/cloud-build-number.py BUILD_NUMBER")
    try:
        project = Path(__file__).resolve().parents[1] / "Folio.xcodeproj/project.pbxproj"
        print("Apple build number:", assign(project, sys.argv[1]))
    except (OSError, ValueError) as error:
        sys.exit(str(error))
