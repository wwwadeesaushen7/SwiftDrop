"""Publish only the installer which matches the checked Windows build metadata.

Runs in the main-branch GitHub Actions publisher, separately from build/test jobs.
It never changes application sources or substitutes an older successful build.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil


def publish(root, artifact, source_commit, build_result, run_url, repository):
    root = Path(root)
    match = re.search(r"(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", (root / "pubspec.yaml").read_text())
    if not match or not re.fullmatch(r"[0-9a-f]{40}", source_commit):
        raise ValueError("Invalid source version or commit")
    version, build = match.groups()
    downloads = root / "downloads"
    downloads.mkdir(exist_ok=True)
    status = {"version": version, "source_commit": source_commit, "status": build_result, "run_url": run_url}
    heading = f"# Windows download — SwiftDrop {version}\n\n"
    if build_result == "success":
        artifact = Path(artifact)
        info = json.loads((artifact / "BUILD-INFO.json").read_text())
        filename = f"SwiftDrop-{version}-windows-x64-setup.exe"
        expected_app = f"{version}.{build}"
        if (info.get("version") != version or info.get("source_commit") != source_commit
                or info.get("installer_filename") != filename
                or info.get("application_version") != expected_app
                or info.get("installer_version") != version or info.get("build_number") != int(build)):
            raise ValueError("Windows metadata does not match source; refusing to publish a different version")
        installer = artifact / filename
        if not 0 < installer.stat().st_size < 100 * 1024 * 1024:
            raise ValueError("Installer exceeds regular GitHub file limits; use the versioned Actions artifact")
        with installer.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        if digest != info.get("installer_sha256") or installer.stat().st_size != info.get("installer_bytes"):
            raise ValueError("Installer checksum or size mismatch")
        # Perform every check before replacing published data.
        shutil.copyfile(installer, downloads / filename)
        stem = f"SwiftDrop-{version}-windows-x64"
        (downloads / f"{stem}-BUILD-INFO.json").write_text(json.dumps(info, indent=2) + "\n")
        (downloads / f"{stem}-SHA256SUMS.txt").write_text(f"{digest}  {filename}\n")
        status.update(installer=filename, sha256=digest, bytes=installer.stat().st_size)
        url = f"https://github.com/{repository}/raw/refs/heads/main/downloads/{filename}"
        text = (heading + f"**[Download {filename}]({url})** — {installer.stat().st_size / 1_000_000:.1f} MB.\n\n"
                "This file was built on Windows. The compiled app version and installer version were checked against pubspec.yaml before publication.\n\n"
                f"Source commit: `{source_commit}`. [Build run]({run_url}).\n\n"
                f"SHA-256: `{digest}`.\n\n"
                "Close the older SwiftDrop app, then run this installer. No Flutter SDK or C++ development tools are needed to install it. "
                "The development installer is unsigned; its Windows build and version checks do not establish physical-device transfer testing.\n\n"
                "After installation, the menu should show **GitHub files**, with **Push files** and **Pull files**.\n")
    else:
        text = (heading + f"This run did not produce a verified installer (status: **{build_result}**). "
                f"[Open the build run]({run_url}) for its error. Do not substitute a 0.2.0 download.\n\n"
                f"Requested source commit: `{source_commit}`.\n")
    (downloads / "WINDOWS.md").write_text(text)
    (downloads / "windows-build.json").write_text(json.dumps(status, indent=2) + "\n")
    return status


if __name__ == "__main__":
    publish(Path.cwd(), os.environ["WINDOWS_ARTIFACT_DIR"], os.environ["SOURCE_COMMIT"],
            os.environ["BUILD_RESULT"], os.environ["WINDOWS_RUN_URL"], os.environ["GITHUB_REPOSITORY"])
