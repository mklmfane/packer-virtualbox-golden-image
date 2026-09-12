#!/usr/bin/env python3
"""Prepare a Windows Server 2022 Standard WSL-ready image.

Automatically selects the English x64 Standard Desktop Experience image.
Docker is installed inside WSL after deploying the generalized Windows image.
"""

import argparse
import getpass
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent


def sha256(path):
    digest = hashlib.sha256()

    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)

    return digest.hexdigest()


def normalize_checksum(value):
    value = value.strip()

    if value.lower().startswith("sha256:"):
        value = value[7:]

    if not re.fullmatch(r"[0-9a-fA-F]{64}", value):
        raise ValueError(
            "Expected 64 hexadecimal SHA256 characters, "
            "optionally prefixed with sha256:."
        )

    return value.lower()


def checked(args, **kwargs):
    result = subprocess.run(
        args,
        stderr=subprocess.PIPE,
        **kwargs,
    )

    if result.returncode:
        detail = result.stderr or ""

        if isinstance(detail, bytes):
            detail = detail.decode("utf-8", errors="replace")

        raise ValueError(
            f"{Path(args[0]).name} failed: {detail.strip()}"
        )

    return result


def select_image(xml_path):
    root = ET.parse(xml_path).getroot()
    images = []

    for image in root.findall("IMAGE"):
        def field(name):
            return (image.findtext(name) or "").strip()

        images.append({
            "index": image.get("INDEX"),
            "name": field("NAME"),
            "edition": field("WINDOWS/EDITIONID"),
            "installation": field("WINDOWS/INSTALLATIONTYPE"),
            "build": field("WINDOWS/VERSION/BUILD"),
            "arch": field("WINDOWS/ARCH"),
            "language": field("WINDOWS/LANGUAGES/DEFAULT"),
        })

    matches = [
        image
        for image in images
        if image["build"] == "20348"
        and image["arch"] == "9"
        and image["edition"].lower() in (
            "serverstandard",
            "serverstandardeval",
        )
        and image["installation"].lower() == "server"
        and image["language"].lower() == "en-us"
    ]

    if len(matches) != 1 or not matches[0]["name"]:
        available = "\n".join(
            f"  index={image['index']} "
            f"name={image['name']!r} "
            f"edition={image['edition']} "
            f"installation={image['installation']} "
            f"build={image['build']} "
            f"language={image['language']}"
            for image in images
        )

        raise ValueError(
            "Expected exactly one English x64 Windows Server 2022 "
            "Standard Desktop Experience image.\n"
            "Automatic selection will not guess.\n"
            f"Available images:\n{available}"
        )

    return matches[0]


def detect_image(iso, scratch_parent):
    sevenzip = shutil.which("7zz") or shutil.which("7z")
    wim = shutil.which("wimlib-imagex")

    if not sevenzip or not wim:
        raise ValueError(
            "Install ISO inspection tools:\n"
            "sudo apt-get install -y 7zip wimtools"
        )

    listing = checked(
        [sevenzip, "l", "-slt", str(iso)],
        stdout=subprocess.PIPE,
        text=True,
    ).stdout

    members = []

    for block in re.split(r"\r?\n\s*\r?\n", listing):
        fields = dict(
            line.split(" = ", 1)
            for line in block.splitlines()
            if " = " in line
        )

        name = fields.get("Path", "")

        if name.replace("\\", "/").lower() in (
            "sources/install.wim",
            "sources/install.esd",
        ):
            members.append((
                name,
                int(fields.get("Size", "0")),
            ))

    if len(members) != 1:
        raise ValueError(
            "Expected sources/install.wim or sources/install.esd "
            "in the ISO. Split SWM media is not supported."
        )

    member, size = members[0]

    if size <= 0:
        raise ValueError(
            "Could not determine installation image size."
        )

    required_space = size + 512 * 1024 * 1024

    if shutil.disk_usage(scratch_parent).free < required_space:
        raise ValueError(
            f"Need at least {required_space // (1024 * 1024)} MiB "
            f"free in {scratch_parent} for temporary ISO inspection."
        )

    print(
        "Inspecting the ISO installation image; "
        "temporary extraction may take several minutes.",
        flush=True,
    )

    with tempfile.TemporaryDirectory(
        prefix=".iso-inspect-",
        dir=scratch_parent,
    ) as temporary_directory:
        image_file = Path(temporary_directory) / "install.wim"

        with image_file.open("wb") as stream:
            checked(
                [sevenzip, "e", "-so", "-bd", str(iso), member],
                stdout=stream,
            )

        xml_path = Path(temporary_directory) / "images.xml"

        checked(
            [
                wim,
                "info",
                str(image_file),
                f"--extract-xml={xml_path}",
            ],
            stdout=subprocess.PIPE,
        )

        return select_image(xml_path)


def password_problems(password):
    """Return validation messages without exposing the password."""
    problems = []

    if not 16 <= len(password) <= 64:
        problems.append(
            "Password must contain 16–64 characters."
        )

    if not re.search(r"[A-Z]", password):
        problems.append(
            "Missing an uppercase ASCII letter."
        )

    if not re.search(r"[a-z]", password):
        problems.append(
            "Missing a lowercase ASCII letter."
        )

    if not re.search(r"[0-9]", password):
        problems.append(
            "Missing a digit."
        )

    # Hyphen is last in the character class, so it is literal.
    if not re.search(r"[!@#%_+-]", password):
        problems.append(
            "Missing an allowed symbol: !@#%_+-"
        )

    if re.search(r"[^A-Za-z0-9!@#%_+-]", password):
        problems.append(
            "Contains unsupported characters. "
            "Only ASCII letters, digits, and !@#%_+- are allowed. "
            "Spaces are not allowed."
        )

    return problems


def prompt_password():
    """Retry password entry without repeating ISO inspection."""
    print(
        "\nTemporary Packer password requirements:\n"
        "  - 16–64 characters\n"
        "  - Uppercase letter, lowercase letter, digit, and symbol\n"
        "  - Allowed symbols: !@#%_+-\n"
        "Input is hidden. Press Ctrl+C to cancel."
    )

    while True:
        password = getpass.getpass("Temporary Packer password: ")
        problems = password_problems(password)

        if problems:
            print("\nPassword rejected:")

            for problem in problems:
                print(f"  - {problem}")

            print("Please try again.\n")
            continue

        confirmation = getpass.getpass("Repeat password: ")

        if password != confirmation:
            print(
                "\nPasswords do not match. Please try again.\n"
            )
            continue

        return password


def main():
    parser = argparse.ArgumentParser(description=__doc__)

    parser.add_argument(
        "target",
        choices=["server2022"],
    )
    parser.add_argument(
        "--iso",
        required=True,
        type=Path,
        help="Local Windows Server 2022 ISO path",
    )
    parser.add_argument(
        "--iso-sha256",
        required=True,
        help="Expected SHA256, with or without sha256:",
    )

    args = parser.parse_args()
    os.umask(0o077)

    try:
        checksum = normalize_checksum(args.iso_sha256)
        iso = args.iso.expanduser().resolve()

        if not iso.is_file():
            raise ValueError(f"ISO not found: {iso}")

        target = ROOT / args.target

        if not (target / "windows.pkr.hcl").is_file():
            raise ValueError(
                "Place prepare.py in the project root "
                "above server2022/."
            )

        destination = target / "generated"

        if destination.exists():
            raise ValueError(
                f"{destination} already exists. "
                "Preserve or remove it deliberately "
                "before preparing again."
            )

        print(f"Checking SHA256: {iso}", flush=True)
        actual = sha256(iso)

        if actual != checksum:
            raise ValueError(
                "ISO checksum mismatch.\n"
                f"Expected: {checksum}\n"
                f"Actual:   {actual}"
            )

        print(
            "ISO matches the supplied SHA256. "
            "Publisher authenticity depends on where "
            "that expected hash came from.",
            flush=True,
        )

        image = detect_image(iso, target)

        print(
            f"Selected image {image['index']}: {image['name']}",
            flush=True,
        )

        password = prompt_password()

        # Create output only after validation and password confirmation.
        destination.mkdir(mode=0o700)

        values = {
            "iso_url": str(iso),
            "iso_checksum": "sha256:" + checksum,
            "image_name": image["name"],
            "admin_password": password,
        }

        values_path = destination / "values.pkrvars.hcl"

        with values_path.open("x", encoding="utf-8") as output:
            for key, value in values.items():
                output.write(
                    f"{key} = {json.dumps(value)}\n"
                )

        values_path.chmod(0o600)

        metadata_path = destination / "selected-image.json"
        metadata_path.write_text(
            json.dumps(image, indent=2) + "\n",
            encoding="utf-8",
        )

        print(f"\nCreated {values_path}")
        print(
            "Keep generated/ private and ignored by Git."
        )
        print("\nNext commands:")
        print("cd server2022")
        print("packer init .")
        print(
            "packer validate "
            "-var-file=generated/values.pkrvars.hcl ."
        )
        print(
            "packer build "
            "-var-file=generated/values.pkrvars.hcl ."
        )

    except (KeyboardInterrupt, EOFError):
        print("\nPreparation cancelled.")
        raise SystemExit(130)

    except (ValueError, OSError, ET.ParseError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()