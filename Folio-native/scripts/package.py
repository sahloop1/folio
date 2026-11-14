#!/usr/bin/env python3
"""Package native source only; never label a source ZIP as an installable IPA."""
from pathlib import Path
import hashlib
import importlib.util
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def package():
    spec = importlib.util.spec_from_file_location("folio_check", ROOT / "scripts/check.py")
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); module.check()
    target = ROOT.parent / "dist/Folio-iPad-Native-3.0.0-source.zip"
    target.parent.mkdir(parents=True, exist_ok=True)
    files = []
    for directory in ["Folio", "Folio.xcodeproj", "FolioTests", "FolioUITests", "Sources", "Tests", "scripts"]:
        files.extend(path for path in (ROOT / directory).rglob("*") if path.is_file() and not any(part in {"__pycache__", "xcuserdata", ".DS_Store"} for part in path.parts) and path.suffix != ".pyc")
    files.extend(ROOT / name for name in ["Package.swift", "README.md", "INSTALL.md", "LINUX-TESTFLIGHT.md", "VERIFICATION.md", ".gitignore"])
    inventory = {}
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for source in sorted(files):
            path = "Folio-native/" + str(source.relative_to(ROOT))
            raw = source.read_bytes(); inventory[path] = hashlib.sha256(raw).hexdigest()
            archive.writestr(path, raw)
        path = ".github/workflows/folio-native.yml"
        raw = (ROOT.parent / path).read_bytes()
        # The packaged repository puts ipad-native at the root path expected by the workflow.
        # Keep a ready-to-copy workflow next to the project with its actual root adjusted.
        raw = raw.replace(b"ipad-native/", b"Folio-native/")
        archive.writestr(path, raw); inventory[path] = hashlib.sha256(raw).hexdigest()
        path = "codemagic.yaml"
        raw = (ROOT.parent / path).read_bytes().replace(b"ipad-native/", b"Folio-native/")
        archive.writestr(path, raw); inventory[path] = hashlib.sha256(raw).hexdigest()
        archive.writestr("SOURCE-MANIFEST.json", json.dumps({"kind": "native-ios-source", "installable": False, "version": "3.0.0", "sha256": inventory}, indent=2, sort_keys=True) + "\n")
    with zipfile.ZipFile(target) as archive:
        assert archive.testzip() is None
        manifest = json.loads(archive.read("SOURCE-MANIFEST.json"))
        for name, digest in manifest["sha256"].items():
            assert hashlib.sha256(archive.read(name)).hexdigest() == digest
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    target.with_suffix(target.suffix + ".sha256").write_text(digest + "  " + target.name + "\n")
    print(f"Packaged {len(inventory)} files: {target}")
    print("Native source project; no compiled or signed IPA has been produced.")


if __name__ == "__main__":
    package()
