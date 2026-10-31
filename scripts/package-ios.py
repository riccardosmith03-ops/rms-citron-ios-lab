"""Inspect a successful device build, strip signing on its copy, and produce an unsigned IPA.

No device access, account authentication, firmware, keys or game data are involved.
"""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import posixpath
import re
import shutil
import stat
import struct
import subprocess
import sys
import zipfile

COMMIT = "c3aa70f81e15ea97ee85b6a9a71cbf75d370851e"
MAXIMUM_DEVICE_OS = (17, 6, 1)
MH_EXECUTE = 2
MH_DYLIB = 6
DYLIB_LOAD_COMMANDS = {0xC, 0x80000018, 0x8000001F, 0x80000023, 0x20}


def version(value):
    return (value >> 16, (value >> 8) & 255, value & 255)


def parse_os_version(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise ValueError("Invalid MinimumOSVersion")
    parts = tuple(map(int, value.split(".")))
    return parts + (0,) * (3 - len(parts))


def inspect_macho(path, expected_type=None):
    data = path.read_bytes()
    if len(data) < 32 or struct.unpack_from("<I", data)[0] != 0xFEEDFACF:
        raise ValueError("Expected a thin 64-bit iPhoneOS Mach-O: " + path.name)
    _, cpu, _, file_type, count, command_bytes, _, _ = struct.unpack_from("<8I", data)
    if cpu != 0x0100000C:
        raise ValueError("Non-arm64 code in device package: " + path.name)
    if expected_type is not None and file_type != expected_type:
        raise ValueError("Unexpected Mach-O file type: " + path.name)
    offset = 32
    command_end = offset + command_bytes
    if command_end > len(data) or count > command_bytes // 8:
        raise ValueError("Mach-O load commands exceed file bounds: " + path.name)
    minimum = None
    loads = []
    install_name = None
    rpaths = []

    def command_string(size, minimum_offset):
        if size < minimum_offset:
            raise ValueError("Truncated Mach-O string command: " + path.name)
        name_offset = struct.unpack_from("<I", data, offset + 8)[0]
        if not minimum_offset <= name_offset < size:
            raise ValueError("Invalid Mach-O string offset: " + path.name)
        raw = data[offset + name_offset:offset + size]
        if b"\0" not in raw:
            raise ValueError("Unterminated Mach-O command string: " + path.name)
        try:
            name = raw.split(b"\0", 1)[0].decode("utf-8")
        except UnicodeDecodeError as error:
            raise ValueError("Invalid Mach-O path encoding: " + path.name) from error
        if not name:
            raise ValueError("Empty Mach-O path: " + path.name)
        return name

    for _ in range(count):
        if offset + 8 > command_end:
            raise ValueError("Truncated Mach-O command header: " + path.name)
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or size % 8 or offset + size > command_end:
            raise ValueError("Invalid Mach-O load command")
        if command == 0x32:
            if size < 24 or minimum is not None:
                raise ValueError("Invalid or duplicate LC_BUILD_VERSION: " + path.name)
            _, _, platform, min_os, sdk, tools = struct.unpack_from("<6I", data, offset)
            if 24 + tools * 8 > size:
                raise ValueError("Truncated LC_BUILD_VERSION tool list: " + path.name)
            minimum = version(min_os)
            if platform != 2 or minimum > MAXIMUM_DEVICE_OS:
                raise ValueError("Binary targets simulator or a newer OS: " + path.name)
        elif command in DYLIB_LOAD_COMMANDS:
            loads.append({"path": command_string(size, 24), "kind": hex(command)})
        elif command == 0xD:
            if install_name is not None:
                raise ValueError("Duplicate LC_ID_DYLIB: " + path.name)
            install_name = command_string(size, 24)
        elif command == 0x8000001C:
            rpaths.append(command_string(size, 12))
        offset += size
    if offset != command_end:
        raise ValueError("Inconsistent Mach-O command byte count: " + path.name)
    if minimum is None:
        raise ValueError("Missing iPhoneOS LC_BUILD_VERSION: " + path.name)
    if expected_type == MH_DYLIB and install_name is None:
        raise ValueError("Missing LC_ID_DYLIB: " + path.name)
    return {"architecture": "arm64", "file_type": file_type,
            "minimum_os": ".".join(map(str, minimum)), "loads": loads,
            "install_name": install_name, "rpaths": rpaths,
            "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}


def system_path(value):
    normalized = posixpath.normpath(value)
    return normalized.startswith("/System/Library/") or normalized.startswith("/usr/lib/")


def inside_app(path, app):
    resolved = path.resolve()
    if app.resolve() not in resolved.parents:
        raise ValueError("Embedded path escapes the app: " + path.name)
    return resolved


def expand_relative(value, loader, executable, app):
    for token, directory in (("@loader_path", loader.parent),
                             ("@executable_path", executable.parent)):
        if value == token or value.startswith(token + "/"):
            suffix = value[len(token):].lstrip("/")
            candidate = (directory / suffix).resolve()
            if candidate != app.resolve() and app.resolve() not in candidate.parents:
                raise ValueError("Runtime search path escapes the app: " + value)
            return candidate
    raise ValueError("Unsupported relative runtime path: " + value)


def validate_dependencies(app, executable, inspection):
    """Validate actual loader chains; an unrelated framework's rpath is not used."""
    app = app.resolve()
    executable = executable.resolve()
    main_rpaths = inspection[executable.relative_to(app).as_posix()]["rpaths"]

    def expand_rpaths(values, loader):
        expanded = []
        for value in values:
            if value.startswith("/"):
                if not system_path(value):
                    raise ValueError("Host absolute LC_RPATH is not distributable: " + value)
                expanded.append(posixpath.normpath(value))
            else:
                expanded.append(expand_relative(value, loader, executable, app))
        return expanded

    inherited_main = expand_rpaths(main_rpaths, executable)
    queue = [(app / key, inherited_main) for key in list(inspection)]
    visited = set()
    while queue:
        loader, inherited = queue.pop(0)
        loader = inside_app(loader, app)
        key = loader.relative_to(app).as_posix()
        if key not in inspection:
            inspection[key] = inspect_macho(loader, MH_DYLIB)
        metadata = inspection[key]
        own_rpaths = expand_rpaths(metadata["rpaths"], loader)
        search = list(dict.fromkeys(own_rpaths + inherited))
        marker = (key, tuple(map(str, search)))
        if marker in visited:
            continue
        visited.add(marker)
        identity = metadata["install_name"]
        if identity and identity.startswith("/") and not system_path(identity):
            raise ValueError("Host absolute LC_ID_DYLIB is not distributable: " + identity)
        for dependency in metadata["loads"]:
            name = dependency["path"]
            target = None
            resolution = None
            if name.startswith("/"):
                if not system_path(name):
                    raise ValueError("Host absolute dependency is not distributable: " + name)
                resolved = posixpath.normpath(name)
                resolution = "system"
            elif name.startswith("@rpath/"):
                relative = name[len("@rpath/"):]
                if ".." in Path(relative).parts or relative.startswith("/"):
                    raise ValueError("Invalid @rpath dependency: " + name)
                for directory in search:
                    if isinstance(directory, Path):
                        candidate = inside_app(directory / relative, app)
                        if candidate.is_file():
                            target = candidate
                            break
                if target is None:
                    if "/usr/lib/swift" in search and re.fullmatch(r"libswift[A-Za-z0-9_]*\.dylib", relative):
                        resolved = "/usr/lib/swift/" + relative
                        resolution = "swift-system"
                    else:
                        raise FileNotFoundError("Unresolved embedded dependency: " + name)
            elif name.startswith(("@loader_path/", "@executable_path/")):
                target = inside_app(expand_relative(name, loader, executable, app), app)
                if not target.is_file():
                    raise FileNotFoundError("Missing embedded dependency: " + name)
            else:
                raise ValueError("Non-relocatable dependency: " + name)
            if target is not None:
                resolved = target.relative_to(app).as_posix()
                resolution = "embedded"
                if resolved not in inspection:
                    inspection[resolved] = inspect_macho(target, MH_DYLIB)
                queue.append((target, search))
            dependency["resolved_path"] = resolved
            dependency["resolution"] = resolution
    return inspection


def remove_signing_metadata(app, staging):
    """Delete only named signing metadata in this newly copied Payload app."""
    app = app.resolve()
    staging = staging.resolve()
    if staging not in app.parents or app.name != "CitronIOS.app":
        raise ValueError("Signing cleanup must stay inside copied app staging")
    targets = [p for p in app.rglob("*")
               if p.name in ("_CodeSignature", "embedded.mobileprovision")]
    for item in sorted(targets, key=lambda p: len(p.parts), reverse=True):
        resolved = item.resolve()
        if app not in resolved.parents or staging not in resolved.parents:
            raise ValueError("Signing cleanup target escapes copied app")
        if item.is_symlink() or item.is_file():
            item.unlink()
        elif item.is_dir():
            shutil.rmtree(item)


def main():
    if len(sys.argv) != 4:
        raise SystemExit("usage: package-ios.py <build-dir> <dependency-licenses-dir> <artifact-dir>")
    build, license_dir, output = map(lambda s: Path(s).resolve(), sys.argv[1:])
    candidates = [p for p in build.rglob("CitronIOS.app") if p.is_dir()]
    if len(candidates) != 1:
        raise RuntimeError("Expected exactly one CitronIOS device app product")
    output.mkdir(parents=True, exist_ok=True)
    staging = output / "unsigned-package"
    if staging.exists():
        raise FileExistsError("Packaging staging directory already exists")
    payload = staging / "Payload"
    payload.mkdir(parents=True)
    app = payload / "CitronIOS.app"
    shutil.copytree(candidates[0], app, symlinks=True)
    for item in app.rglob("*"):
        if item.is_symlink() and app not in item.resolve().parents:
            raise RuntimeError("Bundle symlink points outside the app")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    for key in ("CFBundleIdentifier", "CFBundleExecutable", "MinimumOSVersion"):
        if not isinstance(info.get(key), str) or not info[key] or "$" in info[key]:
            raise ValueError("Unexpanded or missing Xcode plist field: " + key)
    executable_name = info["CFBundleExecutable"]
    if "/" in executable_name or "\\" in executable_name:
        raise ValueError("Invalid bundle executable name")
    main_binary = app / executable_name
    moltenvk = app / "Frameworks/MoltenVK.framework/MoltenVK"
    if not main_binary.is_file() or not moltenvk.is_file():
        raise FileNotFoundError("App executable or embedded MoltenVK framework missing")
    minimum_plist = parse_os_version(info["MinimumOSVersion"])
    if minimum_plist > MAXIMUM_DEVICE_OS:
        raise ValueError("MinimumOSVersion excludes the target iPhone")
    loose_dylibs = list((app / "Frameworks").glob("*.dylib"))
    if any(not re.fullmatch(r"libswift[A-Za-z0-9_]*\.dylib", p.name) for p in loose_dylibs):
        raise RuntimeError("Unexpected loose dylib; the native Citron core must be linked statically")
    initial = [main_binary, moltenvk] + loose_dylibs
    inspection = {p.relative_to(app).as_posix(): inspect_macho(
        p, MH_EXECUTE if p == main_binary else MH_DYLIB) for p in initial}
    if parse_os_version(inspection[executable_name]["minimum_os"]) != minimum_plist:
        raise ValueError("MinimumOSVersion differs from executable LC_BUILD_VERSION")
    validate_dependencies(app, main_binary, inspection)
    # Remove signatures only from the copied package, leaving build products untouched.
    for name in list(inspection):
        binary = app / name
        signature = subprocess.run(["/usr/bin/codesign", "-d", str(binary)],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if signature.returncode == 0:
            subprocess.run(["/usr/bin/codesign", "--remove-signature", str(binary)], check=True)
    remove_signing_metadata(app, staging)
    inspection = {name: inspect_macho(app / name,
        MH_EXECUTE if name == executable_name else MH_DYLIB) for name in inspection}
    validate_dependencies(app, main_binary, inspection)
    # Keep source attribution and third-party license texts with the artifact.
    destination_licenses = output / "licenses"
    shutil.copytree(license_dir, destination_licenses)
    project = Path(__file__).resolve().parents[1]
    shutil.copy2(project / "COPYING", destination_licenses / "Prototype-and-Citron-GPL-3.0.txt")
    shutil.copy2(project / "NOTICE.txt", destination_licenses / "NOTICE.txt")
    ipa = output / ("Citron-iOS-UNSIGNED-" + COMMIT[:9] + ".ipa")
    with zipfile.ZipFile(ipa, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for item in sorted(payload.rglob("*")):
            name = item.relative_to(staging).as_posix()
            if item.is_symlink():
                entry = zipfile.ZipInfo(name)
                entry.create_system = 3
                entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(entry, os.readlink(item))
            elif item.is_file():
                archive.write(item, name)
    record = {"created_utc": datetime.now(timezone.utc).isoformat(), "upstream_commit": COMMIT,
              "bundle_identifier": info["CFBundleIdentifier"],
              "minimum_os_plist": info["MinimumOSVersion"], "unsigned": True,
              "binaries": inspection, "ipa_name": ipa.name, "ipa_bytes": ipa.stat().st_size,
              "ipa_sha256": hashlib.sha256(ipa.read_bytes()).hexdigest(),
              "runtime_tested": False, "installed_on_device": False,
              "limitation": "Build/package inspection does not prove JIT, renderer or game operation"}
    with (output / "package-inspection.json").open("x", encoding="utf-8") as stream:
        json.dump(record, stream, indent=2)
    print(json.dumps({"ipa": ipa.name, "bytes": ipa.stat().st_size,
                      "sha256": record["ipa_sha256"], "runtime_tested": False}))


if __name__ == "__main__":
    main()
