#!/usr/bin/env python3
"""Linux-safe project/fixture checks. Deliberately does not claim Swift compilation."""
from pathlib import Path
import hashlib
import importlib.util
import io
import json
import plistlib
import re
import struct
import sys
import xml.etree.ElementTree as ET
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]


def check():
    spec = importlib.util.spec_from_file_location("folio_project", ROOT / "scripts/project.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    data = module.project_data()
    stored = (ROOT / "Folio.xcodeproj/project.pbxproj").read_text()
    assert stored == "// !$*UTF8*$!\n" + module.openstep(data) + "\n", "Xcode project is stale; run python3 scripts/project.py"
    objects = data["objects"]
    reference_fields = {"rootObject", "mainGroup", "productRefGroup", "buildConfigurationList", "fileRef", "productRef", "productReference", "target", "targetProxy", "containerPortal", "remoteGlobalIDString", "package"}
    array_references = {"children", "files", "buildPhases", "dependencies", "targets", "buildConfigurations", "packageReferences", "packageProductDependencies"}
    for obj in list(objects.values()) + [data]:
        for field, value in obj.items():
            if field in reference_fields:
                assert value in objects, (field, value)
            if field in array_references:
                assert all(item in objects for item in value), field
    for group, directory in [("app", "Folio"), ("tests", "FolioTests"), ("ui", "FolioUITests")]:
        files = list((ROOT / directory).glob("*.swift"))
        assert files, directory + " has no Swift sources"
        for source in files:
            ref = module.uid("file." + group + "." + source.name)
            assert ref in objects, source
            phase = objects[module.uid("phase." + group + ".sources")]
            assert any(objects[build].get("fileRef") == ref for build in phase["files"]), source
    scheme = ET.parse(ROOT / "Folio.xcodeproj/xcshareddata/xcschemes/Folio.xcscheme")
    for build in scheme.iter("BuildableReference"):
        assert build.attrib["BlueprintIdentifier"] in objects
    assert len(list(scheme.iter("TestableReference"))) == 2
    info = plistlib.loads((ROOT / "Folio/Info.plist").read_bytes())
    assert info["CFBundleDisplayName"] == "Folio"
    assert info["NSMicrophoneUsageDescription"]
    assert info["UIApplicationSceneManifest"]["UIApplicationSupportsMultipleScenes"] is False
    assert len(info["UISupportedInterfaceOrientations~ipad"]) == 4
    assert info["UTExportedTypeDeclarations"][0]["UTTypeTagSpecification"]["public.filename-extension"] == ["folio"]
    privacy = plistlib.loads((ROOT / "Folio/PrivacyInfo.xcprivacy").read_bytes())
    assert privacy["NSPrivacyTracking"] is False
    assert privacy["NSPrivacyCollectedDataTypes"] == []
    icon = (ROOT / "Folio/Assets.xcassets/AppIcon.appiconset/AppIcon.png").read_bytes()
    assert icon[:8] == b"\x89PNG\r\n\x1a\n"
    assert struct.unpack(">II", icon[16:24]) == (1024, 1024)
    assert icon[25] == 2, "App icon must be opaque RGB"
    at, image = 8, bytearray()
    while at < len(icon):
        size = struct.unpack(">I", icon[at:at + 4])[0]
        kind = icon[at + 4:at + 8]; payload = icon[at + 8:at + 8 + size]
        assert zlib.crc32(kind + payload) == struct.unpack(">I", icon[at + 8 + size:at + 12 + size])[0]
        if kind == b"IDAT":
            image.extend(payload)
        at += size + 12
    assert len(zlib.decompress(image)) == 1024 * (1 + 1024 * 3)
    for source in (ROOT / "Folio").glob("*.swift"):
        text = source.read_text()
        assert not re.search(r"import\s+(WebKit|JavaScriptCore)", text), source
        assert "WKWebView" not in text, source
    assert "PKCanvasView" in (ROOT / "Folio/NativeCanvas.swift").read_text()
    assert "@main" in (ROOT / "Folio/FolioApp.swift").read_text()
    fixtures = ROOT / "Tests/FolioCoreTests/Fixtures"
    for name in ["android-library.zip", "android-notebook.folio"]:
        raw = (fixtures / name).read_bytes()
        assert struct.unpack("<H", raw[6:8])[0] & 8, "Fixture must exercise Java-style streaming data descriptors"
        with zipfile.ZipFile(io.BytesIO(raw)) as archive:
            assert archive.testzip() is None
            if name.endswith(".zip"):
                manifest = json.loads(archive.read("folio-library.json"))
                assert manifest["format"] == "folio-library"
                assert len(manifest["notebooks"]) == 2
                assert len(manifest["files"]) == len(archive.namelist()) - 1
                for path, record in manifest["files"].items():
                    content = archive.read(path)
                    assert record["bytes"] == len(content)
                    assert record["sha256"] == hashlib.sha256(content).hexdigest()
                books = [json.loads(archive.read("notebooks/" + id + ".folio.json")) for id in manifest["notebooks"]]
                assert books[1]["trashed"] is True
                assert books[0]["pages"][0]["texts"][0]["link"].endswith(books[1]["pages"][0]["id"])
    print("PASS: Xcode source membership, object references, test scheme, metadata, opaque icon, native entry/canvas, and Android fixture CRC/SHA-256.")
    print("Not run: Swift compiler, Xcode build, XCTest, Simulator, signing, or physical iPad checks.")


if __name__ == "__main__":
    try:
        check()
    except (AssertionError, KeyError, OSError, ValueError) as error:
        sys.exit("FAIL: " + str(error))
