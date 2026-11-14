#!/usr/bin/env python3
"""Synthetic Android-compatible ZIPs; never reads the user's real notebooks."""
from pathlib import Path
import hashlib
import io
import json
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "Tests/FolioCoreTests/Fixtures"


def identity(number):
    return f"00000000-0000-4000-8000-{number:012d}"


def metadata(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def pdf():
    output = bytearray(b"%PDF-1.4\n")
    objects = [b"<< /Type /Catalog /Pages 2 0 R >>", b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>", b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Resources << >> /Contents 4 0 R >>", b"<< /Length 0 >>\nstream\n\nendstream"]
    offsets = [0]
    for i, content in enumerate(objects, 1):
        offsets.append(len(output))
        output.extend(f"{i} 0 obj\n".encode() + content + b"\nendobj\n")
    xref = len(output)
    output.extend(b"xref\n0 5\n0000000000 65535 f \n")
    for offset in offsets[1:]:
        output.extend(f"{offset:010d} 00000 n \n".encode())
    output.extend(f"trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode())
    return bytes(output)


class StreamingBytes(io.BytesIO):
    def seekable(self):
        return False

    def seek(self, *args):
        raise io.UnsupportedOperation("data-descriptor fixture")


def archive(entries, stream=False):
    out = StreamingBytes() if stream else io.BytesIO()
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as target:
        for name, content in entries.items():
            info = zipfile.ZipInfo(name, (2026, 11, 14, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            target.writestr(info, content)
    return out.getvalue()


def create():
    DEST.mkdir(parents=True, exist_ok=True)
    audio = DEST / "voice.m4a"
    if not audio.exists():
        with tempfile.TemporaryDirectory(prefix="folio-fixture-") as folder:
            target = Path(folder) / "voice.m4a"
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.25", "-ac", "1", "-c:a", "aac", "-b:a", "32k", str(target)], check=True)
            audio.write_bytes(target.read_bytes())
    (DEST / "background.pdf").write_bytes(pdf())
    page = {"id": identity(11), "title": "Android page", "paper": "Ruled", "paperColor": -329745, "width": 1000, "height": 1414,
            "lineCount": 0, "rulingHeight": 0, "baseHeight": 0, "pdf": identity(101) + ".pdf", "pdfPage": 0,
            "strokes": [{"tool": "pen", "color": -14340028, "width": 3, "points": [100, 100, 0.5, 130, 125, 1.0]}],
            "documentText": {"text": "Café research · ملاحظات", "x": 100, "y": 100, "width": 750, "size": 24, "color": -14340028},
            "texts": [{"text": "Linked notebook", "x": 100, "y": 300, "size": 24, "link": "folio://notebook/" + identity(2) + "?page=" + identity(12)}],
            "audio": [{"id": identity(201), "file": identity(201) + ".m4a", "title": "Voice fixture", "durationMs": 250, "x": 110, "y": 400, "scale": 1}], "futurePageSetting": {"kept": True}}
    book = {"id": identity(1), "title": "Android research", "profile": "Study", "folder": "Research", "tags": ["science"], "color": -8413747,
            "trashed": False, "favorite": True, "created": 1, "updated": 2, "firstPageNumber": 1, "lastPageId": page["id"],
            "sections": [{"id": identity(31), "title": "Introduction", "pageId": page["id"], "parentId": ""}], "pages": [page], "futureNotebookSetting": 42}
    trash_page = dict(page, id=identity(12), pdf="", pdfPage=-1, audio=[], texts=[])
    trashed = dict(book, id=identity(2), title="Kept in Trash", trashed=True, pages=[trash_page], sections=[])
    assets = {"pdfs/" + identity(101) + ".pdf": pdf(), "audio/" + identity(201) + ".m4a": audio.read_bytes()}
    (DEST / "android-notebook.folio").write_bytes(archive(dict(assets, **{"notebook.json": metadata(book)}), stream=True))
    entries = dict(assets)
    entries.update({"notebooks/" + book["id"] + ".folio.json": metadata(book), "notebooks/" + trashed["id"] + ".folio.json": metadata(trashed),
                    "Folio.apk": b"Synthetic APK inventory fixture, never executed", "READ-ME.txt": b"Synthetic Android transfer"})
    manifest = {"format": "folio-library", "version": 1, "notebooks": [book["id"], trashed["id"]], "files": {name: {"bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()} for name, content in entries.items()},
                "preferences": {"activeProfile": "Study", "libraryProfiles": ["Personal", "Study"], "profileFolders.Study": ["Research"], "fingerDrawing": False, "assistantToken": "synthetic-value-must-be-dropped"}}
    entries["folio-library.json"] = metadata(manifest)
    (DEST / "android-library.zip").write_bytes(archive(entries, stream=True))
    (DEST / "README.md").write_text("Synthetic compatibility fixtures generated by scripts/make_fixtures.py.\nThe ZIPs use DEFLATE and streaming data descriptors, like Java ZipOutputStream.\nThe PDF is a valid blank page; voice.m4a is a generated quarter-second tone.\nFolio.apk is deliberately a dummy inventory entry and is never executed.\nNo personal notebook data or credentials are included.\n")
    print("Created synthetic Android transfer, notebook, PDF, and M4A fixtures.")


if __name__ == "__main__":
    create()
