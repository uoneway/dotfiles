#!/usr/bin/env python3
"""Install machine-selected apps using merged common and personal definitions."""
import argparse
import importlib.util
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
from urllib.parse import urlparse

_machine_spec = importlib.util.spec_from_file_location(
    "dotfiles_machine_config", Path(__file__).with_name("machine-config.py"))
machine_config = importlib.util.module_from_spec(_machine_spec)
_machine_spec.loader.exec_module(machine_config)
tomllib = machine_config.tomllib

ROOT = Path(__file__).resolve().parents[4]
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9]+(?:\.[A-Za-z0-9]+)*)?")
LABEL = "local.karabiner.shift-english"  # Preserve the existing app/launchd identity.


def validate_version(value):
    if not isinstance(value, str) or (value != "latest" and not VERSION.fullmatch(value)):
        raise ValueError(f"invalid version: {value!r}; use latest or x.y.z")
    return value


def validate_recipe(name, entry):
    if not isinstance(entry, dict):
        raise ValueError(f"{name}: use an object with method and version")
    method = entry.get("method")
    fields = {
        "official": {"adapter", "installer_url", "latest_urls", "latest_format", "tag_prefix"},
        "homebrew": {"package", "kind"},
        "script": {"path", "interpreter", "args"},
        "right-shift-app": {"package"},
    }
    common = {"method", "version", "enabled", "platforms", "description"}
    if not isinstance(method, str) or method not in fields or set(entry) - common - fields[method]:
        raise ValueError(f"{name}: unknown method or fields")
    validate_version(entry.get("version", "latest"))
    if not isinstance(entry.get("enabled", True), bool):
        raise ValueError(f"{name}: enabled must be boolean")
    for field, allowed in (("platforms", {"Darwin", "Linux"}),):
        values = entry.get(field, ["Darwin", "Linux"])
        if not isinstance(values, list) or not values or any(not isinstance(v, str) or v not in allowed for v in values):
            raise ValueError(f"{name}: invalid {field}")
    if "description" in entry and not isinstance(entry["description"], str):
        raise ValueError(f"{name}: description must be text")
    if method == "official":
        if entry.get("adapter") not in ("codex", "claude") or name != entry["adapter"]:
            raise ValueError(f"{name}: official adapter requires its matching command name")
        urls = entry.get("latest_urls")
        if not isinstance(urls, list) or not urls:
            raise ValueError(f"{name}: latest_urls must be a nonempty list")
        for url in [entry.get("installer_url")] + urls:
            if not isinstance(url, str) or urlparse(url).scheme != "https" or not urlparse(url).netloc:
                raise ValueError(f"{name}: installer and metadata URLs must use HTTPS")
        if entry.get("latest_format") not in ("text", "tag_name") or not isinstance(entry.get("tag_prefix", ""), str):
            raise ValueError(f"{name}: invalid latest metadata format")
    elif method == "homebrew":
        package = entry.get("package")
        if not isinstance(package, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_+@./-]*", package):
            raise ValueError(f"{name}: invalid Homebrew package")
        if entry.get("kind", "formula") not in ("formula", "cask"):
            raise ValueError(f"{name}: kind must be formula or cask")
    elif method == "script":
        path = entry.get("path")
        if not isinstance(path, str) or not path or Path(path).is_absolute() or ".." in Path(path).parts:
            raise ValueError(f"{name}: script path must be relative to config")
        if entry.get("interpreter", "bash") not in ("bash", "sh", "python3"):
            raise ValueError(f"{name}: invalid script interpreter")
        values = entry.get("args", ["{version}"])
        if not isinstance(values, list) or any(not isinstance(v, str) for v in values):
            raise ValueError(f"{name}: args must be an array of strings")
        if not any("{version}" in v for v in values):
            raise ValueError(f"{name}: args must pass {{version}} to the script")
    else:
        package = entry.get("package")
        if not isinstance(package, str) or not package or Path(package).is_absolute() or ".." in Path(package).parts:
            raise ValueError(f"{name}: package must be relative to dotfiles")
        if entry.get("platforms") != ["Darwin"]:
            raise ValueError(f"{name}: right-shift-app requires platforms=[Darwin]")
    return dict(entry, version=entry.get("version", "latest"))


def read_catalog(path):
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise ValueError(f"invalid app catalog: {path}")
    return data


def merge_entry(base, override):
    # Old shorthand versions remain accepted as personal overrides.
    if isinstance(override, str):
        override = {"version": override}
    elif override is False:
        override = {"enabled": False}
    if not isinstance(override, dict):
        raise ValueError("app overrides must be objects, version strings, or false")
    result = dict(base)
    if "method" in override and override["method"] != base.get("method"):
        # Installation-specific fields cannot carry over to another method.
        result = {key: value for key, value in base.items()
                  if key in {"version", "enabled", "platforms", "description"}}
    for key, value in override.items():
        result[key] = merge_entry(result[key], value) if isinstance(result.get(key), dict) and isinstance(value, dict) else value
    # components was used by an older installer. Placement now lives exclusively
    # in machines.toml; tolerate the field while migrating those personal files.
    result.pop("components", None)
    return result


def policy(root=ROOT):
    common = read_catalog(root / "apps.json")
    path = root / "config/apps.json"
    personal = read_catalog(path) if path.exists() else {}
    result = {}
    for name in dict.fromkeys(list(common) + list(personal)):
        if not isinstance(name, str) or not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", name):
            raise ValueError(f"invalid app name: {name}")
        base = common.get(name, {})
        if not isinstance(base, dict):
            raise ValueError(f"{name}: common definition must be an object")
        result[name] = validate_recipe(name, merge_entry(base, personal.get(name, {})))
    return result


def machine_name(explicit=None, home=None):
    if explicit is not None:
        return explicit
    value = os.environ.get("DOTFILES_MACHINE")
    if value:
        return value
    marker = (home or Path.home()) / ".local/state/dotfiles/machine"
    return marker.read_text().strip() if marker.exists() else None


def machine_apps(name, root=ROOT):
    return machine_config.settings(name, root).get("apps", [])


def plan(args, system=None, root=ROOT, data=None):
    system = system or platform.system()
    if system not in ("Darwin", "Linux"):
        raise ValueError(f"unsupported OS: {system}")
    data = policy(root) if data is None else data
    selected_machine = machine_name(getattr(args, "machine", None))
    if selected_machine is not None:
        selected = machine_apps(selected_machine, root)
    elif not args.tools:
        selected = machine_apps(None, root)
    else:
        selected = []
    names = args.tools.split(",") if args.tools else selected
    if len(set(names)) != len(names) or set(names) - set(data):
        raise ValueError("tools must be a unique list of names defined in apps.json")
    overrides = {}
    for item in args.version:
        if "=" not in item:
            raise ValueError("--version requires TOOL=VERSION")
        name, value = item.split("=", 1)
        if name not in names or name in overrides:
            raise ValueError(f"invalid or duplicate version override: {name}")
        overrides[name] = validate_version(value)
    if args.latest and overrides:
        raise ValueError("--latest and --version cannot be combined")
    result = []
    for name in names:
        entry = data[name]
        if not entry.get("enabled", True):
            continue
        value = overrides.get(name, "latest" if args.latest else entry["version"])
        if system not in entry.get("platforms", ["Darwin", "Linux"]):
            if args.tools:
                raise ValueError(f"{name} does not support {system}")
            continue
        if entry["method"] == "homebrew":
            if value != "latest":
                raise ValueError(f"{name}: Homebrew cannot install arbitrary x.y.z; use a versioned formula or script")
            if entry.get("kind", "formula") == "cask" and system != "Darwin":
                raise ValueError(f"{name}: Homebrew casks require macOS")
        result.append((name, value))
    return result


def default_recipe(tool):
    return validate_recipe(tool, read_catalog(ROOT / "apps.json")[tool])


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "dotfiles-app-installer"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def run(command, env=None, check=True):
    quiet = command[0] == "launchctl" and not check
    return subprocess.run(command, env=env, check=check,
                          stdout=subprocess.DEVNULL if quiet else None,
                          stderr=subprocess.DEVNULL if quiet else None)


def reported_version(binary):
    try:
        output = subprocess.check_output([str(binary), "--version"], text=True,
                                         stderr=subprocess.DEVNULL, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    match = re.search(VERSION.pattern, output)
    return match.group() if match else None


def publish_command(source, destination):
    """Publish on the destination filesystem; /tmp may be a separate mount."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".dotfiles-command-", dir=destination.parent)
    os.close(fd)
    temporary = Path(name)
    try:
        if source.is_symlink():
            temporary.unlink()
            temporary.symlink_to(os.readlink(source))
        else:
            shutil.copy2(source, temporary)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def latest_cli(tool, recipe=None):
    recipe = recipe or default_recipe(tool)
    last_error = None
    for url in recipe["latest_urls"]:
        try:
            payload = fetch(url).decode().strip()
            value = json.loads(payload)["tag_name"] if recipe["latest_format"] == "tag_name" else payload
            if not isinstance(value, str):
                raise ValueError(f"{tool}: latest metadata must contain a version string")
            prefix = recipe.get("tag_prefix", "")
            if prefix and value.startswith(prefix):
                value = value[len(prefix):]
            validate_version(value)
            if value == "latest":
                raise ValueError(f"unresolved latest version for {tool}")
            return value
        except (OSError, ValueError, KeyError, TypeError) as error:
            last_error = error
    raise ValueError(f"{tool}: cannot resolve latest metadata: {last_error}")


def install_cli(tool, requested, home, recipe=None):
    version = requested
    if requested == "latest":
        version = latest_cli(tool, recipe) if recipe is not None else latest_cli(tool)
    recipe = recipe or default_recipe(tool)
    binary = home / ".local/bin" / tool
    current = reported_version(binary)
    codex_home = Path(os.environ.get("CODEX_HOME", str(home / ".codex")))
    updater = codex_home / "packages/standalone/auto-update-version"
    if current != version or (tool == "codex" and updater.exists()):
        url = recipe["installer_url"]
        env = os.environ.copy()
        env["PATH"] = str(home / ".local/bin") + os.pathsep + env.get("PATH", "")
        env["CODEX_NON_INTERACTIVE"] = "1"
        with tempfile.TemporaryDirectory(prefix="dotfiles-installer-") as directory:
            script = Path(directory) / "install.sh"
            script.write_bytes(fetch(url))
            if tool == "codex":
                # Hide competing npm/Homebrew commands from the official
                # installer's conflict handling, which can otherwise append
                # to .zshrc even when the destination is already on PATH.
                staging_bin = Path(directory) / "bin"
                staging_bin.mkdir()
                env["CODEX_INSTALL_DIR"] = str(staging_bin)
                env["PATH"] = str(staging_bin) + os.pathsep + os.defpath
            command = ["sh", str(script), "--release", version] if tool == "codex" else ["bash", str(script), version]
            run(command, env=env)
            if tool == "codex":
                if reported_version(staging_bin / "codex") != version:
                    raise RuntimeError("Official Codex installer did not produce requested version")
                binary.parent.mkdir(parents=True, exist_ok=True)
                for name in ("codex", "codex-code-mode-host"):
                    installed = staging_bin / name
                    if installed.exists():
                        publish_command(installed, binary.parent / name)
        if tool == "codex" and reported_version(binary) != version:
            raise RuntimeError(f"{binary} did not report requested version {version}")
    # Claude's native updater must not silently replace an explicitly pinned
    # version. A launcher refers to the versioned vendor binary, not itself.
    if tool == "claude":
        target = home / ".local/share/claude/versions" / version
        if not target.is_file() or reported_version(target) != version:
            raise RuntimeError(f"Claude native binary missing: {target}")
        setting = "export DISABLE_AUTOUPDATER=1" if requested != "latest" else "unset DISABLE_AUTOUPDATER"
        launcher = f"#!/bin/sh\n{setting}\nexec {shlex.quote(str(target))} \"$@\"\n"
        temporary = binary.with_name(".claude-dotfiles-new")
        temporary.write_text(launcher)
        temporary.chmod(0o755)
        temporary.replace(binary)
    print(f"[ok] {tool} {version} ({requested})", flush=True)
    active = shutil.which(tool)
    if active and Path(active) != binary:
        print(f"[warn] PATH currently selects {active}; put {binary.parent} first", flush=True)
    return version


def app_source(requested, root=ROOT, recipe=None):
    recipe = recipe or default_recipe("right-shift-english")
    package = root / recipe["package"]
    version = (package / "latest").read_text().strip() if requested == "latest" else requested
    validate_version(version)
    source = package / version / "ShiftEnglish.swift"
    if not source.is_file():
        raise ValueError(f"Right Shift English {version} is not bundled in this dotfiles revision")
    return version, source


def app_plist(version):
    return {"CFBundleName": "Right Shift English", "CFBundleDisplayName": "Right Shift English",
            "CFBundleIdentifier": LABEL, "CFBundleExecutable": "shift-english",
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version,
            "CFBundleVersion": version, "LSMinimumSystemVersion": "13.0", "LSUIElement": True,
            "NSPrincipalClass": "NSApplication"}


def app_is_running(domain):
    result = subprocess.run(["launchctl", "print", f"{domain}/{LABEL}"],
                            capture_output=True, text=True)
    return result.returncode == 0 and bool(re.search(r"^\s*state = running$", result.stdout, re.MULTILINE))


def wait_for_app(domain, timeout=3):
    deadline = time.monotonic() + timeout
    while True:
        if app_is_running(domain):
            return
        if time.monotonic() >= deadline:
            raise RuntimeError("Right Shift English did not stay running; check "
                               "~/.local/share/karabiner-shift-english/daemon-error.log. "
                               "The terminal permission check alone does not confirm app access.")
        time.sleep(0.2)


def install_app(requested, home, root=ROOT, recipe=None):
    version, source = app_source(requested, root, recipe)
    app = home / "Applications/Right Shift English.app"
    binary = app / "Contents/MacOS/shift-english"
    stamp = app / "Contents/Resources/dotfiles-source.sha256"
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    matching = (stamp.exists() and stamp.read_text().strip() == digest
                and reported_version(binary) == version)
    backup = app.with_name(app.name + ".previous")
    if not matching and backup.exists():
        raise RuntimeError(f"Previous app backup already exists: {backup}")
    domain = f"gui/{os.getuid()}"
    agent = home / "Library/LaunchAgents" / f"{LABEL}.plist"
    runtime = home / ".local/share/karabiner-shift-english"
    if not matching:
        for command in ("swiftc", "codesign"):
            if not shutil.which(command):
                raise RuntimeError(f"{command} required; install Xcode Command Line Tools first")
        app.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix=".right-shift-build-", dir=app.parent) as directory:
            stage = Path(directory) / app.name
            (stage / "Contents/MacOS").mkdir(parents=True)
            (stage / "Contents/Resources").mkdir()
            run(["swiftc", "-O", str(source), "-o", str(stage / "Contents/MacOS/shift-english")])
            (stage / "Contents/Info.plist").write_bytes(plistlib.dumps(app_plist(version)))
            (stage / "Contents/Resources/dotfiles-source.sha256").write_text(digest + "\n")
            run(["codesign", "--force", "--sign", "-", "--identifier", LABEL, str(stage)])
            run(["codesign", "--verify", "--deep", "--strict", str(stage)])
            if reported_version(stage / "Contents/MacOS/shift-english") != version:
                raise RuntimeError("Built app version mismatch")
            # Complete compilation and verification before stopping a working app.
            run(["launchctl", "bootout", f"{domain}/{LABEL}"], check=False)
            if app.exists():
                app.rename(backup)
            try:
                stage.rename(app)
            except OSError:
                if backup.exists():
                    backup.rename(app)
                raise
            if backup.exists():
                shutil.rmtree(backup)
    runtime.mkdir(parents=True, exist_ok=True, mode=0o700)
    agent.parent.mkdir(parents=True, exist_ok=True)
    data = {"Label": LABEL, "ProgramArguments": [str(binary)], "RunAtLoad": True,
            "KeepAlive": {"Crashed": True}, "ThrottleInterval": 3,
            "LimitLoadToSessionType": "Aqua", "ProcessType": "Interactive",
            "StandardOutPath": str(runtime / "daemon.log"),
            "StandardErrorPath": str(runtime / "daemon-error.log")}
    changed = not agent.exists() or plistlib.loads(agent.read_bytes()) != data
    agent.write_bytes(plistlib.dumps(data))
    if changed:
        run(["launchctl", "bootout", f"{domain}/{LABEL}"], check=False)
    loaded = run(["launchctl", "print", f"{domain}/{LABEL}"], check=False).returncode == 0
    if not loaded:
        run(["launchctl", "bootstrap", domain, str(agent)])
    permission = app_is_running(domain) or run([str(binary), "--check-permission"], check=False).returncode == 0
    if permission:
        run(["launchctl", "kickstart", f"{domain}/{LABEL}"])
        try:
            wait_for_app(domain)
        except RuntimeError:
            if "--request-permission" in source.read_text():
                run(["open", "-n", str(app), "--args", "--request-permission"], check=False)
            raise
        print(f"[ok] right-shift-english {version} ({requested}); login startup registered", flush=True)
    else:
        # Older pinned releases do not implement the prompt helper.
        if "--request-permission" in source.read_text():
            run(["open", "-n", str(app), "--args", "--request-permission"], check=False)
        print(f"[action] right-shift-english {version} installed; Accessibility permission required before use. "
              "Enable Right Shift English in macOS System Settings, then run dotfiles install right-shift-english", flush=True)
    return version


def script_command(entry, version, root=ROOT):
    config = (root / "config").resolve()
    path = (config / entry["path"]).resolve()
    if config not in path.parents or not path.is_file():
        raise ValueError(f"script must exist inside config: {entry['path']}")
    arguments = [value.replace("{version}", version) for value in entry.get("args", ["{version}"])]
    return [entry.get("interpreter", "bash"), str(path)] + arguments


def install_brew(name, requested, entry):
    if requested != "latest":
        raise ValueError(f"{name}: Homebrew requires latest")
    brew = shutil.which("brew")
    if not brew:
        raise RuntimeError("Homebrew is required; install it before applying homebrew entries")
    kind = "--" + entry.get("kind", "formula")
    package = entry["package"]
    run([brew, "update"])
    installed = subprocess.check_output([brew, "list", kind], text=True).splitlines()
    present = package.rsplit("/", 1)[-1] in installed
    run([brew, "upgrade" if present else "install", kind, package])
    print(f"[ok] {name} via Homebrew ({package})", flush=True)


def install_job(name, version, entry, home, root=ROOT):
    method = entry["method"]
    if method == "official":
        return install_cli(entry["adapter"], version, home, entry)
    if method == "right-shift-app":
        return install_app(version, home, root, entry)
    if method == "homebrew":
        return install_brew(name, version, entry)
    command = script_command(entry, version, root)
    env = os.environ.copy()
    env.update(DOTFILES_APP_NAME=name, DOTFILES_APP_VERSION=version, DOTFILES_ROOT=str(root))
    run(command, env=env)
    print(f"[ok] {name}: personal installation script completed ({version})", flush=True)


def main(argv=None, root=ROOT):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tools", nargs="?", help="comma-separated app names; default: machines.toml apps")
    parser.add_argument("--latest", action="store_true", help="override configured versions with latest")
    parser.add_argument("--version", action="append", default=[], metavar="TOOL=VERSION")
    parser.add_argument("--dry-run", action="store_true", help="print policy without downloads or writes")
    parser.add_argument("--machine", help="use this machines.toml entry; install locally, not over SSH")
    parser.add_argument("--catalog", action="store_true", help="print merged app definitions without installation")
    args = parser.parse_args(argv)
    try:
        data = policy(root)
        if args.catalog:
            if args.tools or args.latest or args.version or args.machine or args.dry_run:
                raise ValueError("--catalog cannot be combined with install selection options")
            print(json.dumps(data, ensure_ascii=False, indent=2))
            return 0
        jobs = plan(args, root=root, data=data)
        # Check every local version before any installation starts.
        for tool, version in jobs:
            entry = data[tool]
            if entry["method"] == "right-shift-app":
                app_source(version, root=root, recipe=entry)
            elif entry["method"] == "script":
                script_command(entry, version, root)
        if args.dry_run:
            for tool, version in jobs:
                entry = data[tool]
                detail = entry.get("installer_url") or entry.get("package") or entry.get("path")
                print(f"{tool}={version} method={entry['method']} source={detail}")
            return 0
        home = Path.home()
        state = home / ".local/state/dotfiles"
        state.mkdir(parents=True, exist_ok=True)
        with (state / "apps.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            for tool, version in jobs:
                install_job(tool, version, data[tool], home, root)
        return 0
    except (ValueError, OSError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"[error] app installation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
