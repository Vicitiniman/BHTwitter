#!/usr/bin/env python3
"""Exercise built-in Twitter name/icon branding on a synthetic IPA."""

import os
import plistlib
import struct
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
REBRAND = ROOT / "rebrand.sh"
ICON = ROOT / "branding" / "TwitterAppIcon.png"


def run(*args, cwd=None):
    subprocess.run(args, cwd=cwd, check=True)


def png_size(path):
    raw = path.read_bytes()
    if raw[:8] != b"\x89PNG\r\n\x1a\n" or raw[12:16] != b"IHDR":
        raise AssertionError(f"{path.name} is not a PNG")
    return struct.unpack(">II", raw[16:24])


def main():
    with tempfile.TemporaryDirectory(prefix="nfb-branding-") as temporary:
        root = Path(temporary)
        source = root / "source"
        app = source / "Payload" / "Twitter.app"
        localized = app / "en.lproj"
        localized.mkdir(parents=True)

        stock_icons = {
            "CFBundlePrimaryIcon": {"CFBundleIconName": "XAppIcon"},
            "CFBundleAlternateIcons": {
                "StockIcon": {
                    "CFBundleIconName": "StockIcon",
                    "CFBundleIconFiles": ["StockIcon60x60"],
                }
            },
        }
        info = {
            "CFBundleDisplayName": "X",
            "CFBundleIdentifier": "com.atebits.Tweetie2",
            "CFBundleIcons": stock_icons,
            "CFBundleIcons~ipad": {
                "CFBundleAlternateIcons": dict(
                    stock_icons["CFBundleAlternateIcons"]
                )
            },
        }
        with (app / "Info.plist").open("wb") as output:
            plistlib.dump(info, output, fmt=plistlib.FMT_BINARY)
        with (localized / "InfoPlist.strings").open("wb") as output:
            plistlib.dump(
                {"CFBundleDisplayName": "X"},
                output,
                fmt=plistlib.FMT_BINARY,
            )
        (source / "iTunesArtwork").write_bytes(b"artwork")
        os.symlink("Info.plist", app / "InfoLink.plist")

        ipa = root / "Twitter.ipa"
        run("zip", "-qry", str(ipa), ".", cwd=source)
        run(
            "bash",
            str(REBRAND),
            "--twitter-branding",
            "--twitter-icon",
            str(ICON),
            str(ipa),
        )

        expanded = root / "expanded"
        run("unzip", "-q", str(ipa), "-d", str(expanded))
        branded_app = expanded / "Payload" / "Twitter.app"
        with (branded_app / "Info.plist").open("rb") as source_plist:
            branded = plistlib.load(source_plist)
        with (
            branded_app / "en.lproj" / "InfoPlist.strings"
        ).open("rb") as localized_plist:
            localized_name = plistlib.load(localized_plist)

        assert branded["CFBundleDisplayName"] == "Twitter"
        assert localized_name["CFBundleDisplayName"] == "Twitter"
        assert (expanded / "iTunesArtwork").read_bytes() == b"artwork"
        assert (branded_app / "InfoLink.plist").is_symlink()
        for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
            alternates = branded[key]["CFBundleAlternateIcons"]
            assert "StockIcon" in alternates
            assert "BHTTwitterBird" in alternates

        expected = {
            "BHTTwitterAppIcon20x20.png": 20,
            "BHTTwitterAppIcon20x20@2x.png": 40,
            "BHTTwitterAppIcon20x20@3x.png": 60,
            "BHTTwitterAppIcon29x29.png": 29,
            "BHTTwitterAppIcon29x29@2x.png": 58,
            "BHTTwitterAppIcon29x29@3x.png": 87,
            "BHTTwitterAppIcon40x40.png": 40,
            "BHTTwitterAppIcon40x40@2x.png": 80,
            "BHTTwitterAppIcon40x40@3x.png": 120,
            "BHTTwitterAppIcon60x60@2x.png": 120,
            "BHTTwitterAppIcon60x60@3x.png": 180,
            "BHTTwitterAppIcon76x76.png": 76,
            "BHTTwitterAppIcon76x76@2x.png": 152,
            "BHTTwitterAppIcon83_5x83_5@2x.png": 167,
        }
        for filename, size in expected.items():
            assert png_size(branded_app / filename) == (size, size)

    print("Branding smoke test passed.")


if __name__ == "__main__":
    main()
