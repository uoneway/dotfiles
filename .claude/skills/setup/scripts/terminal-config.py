#!/usr/bin/env python3
"""Apply/check terminal preferences without replacing machine-local state."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[4]


class TerminalConfig:
    def __init__(self, root=ROOT, home=None, xdg=None):
        self.root = Path(root)
        self.config = self.root / "config"
        self.home = Path(home or Path.home())
        self.xdg = Path(xdg or os.environ.get("XDG_CONFIG_HOME") or self.home / ".config")
        self.backup = self.root / "backup"
        self.scripts = self.root / ".claude/skills/setup/scripts"

    def save_backup(self, path):
        if not path.exists() and not path.is_symlink():
            return
        try:
            rel = path.relative_to(self.home)
        except ValueError:
            rel = Path("external") / str(path).lstrip("/")
        dest = self.backup / rel
        if not dest.exists() and not dest.is_symlink():
            dest.parent.mkdir(parents=True, exist_ok=True)
            if path.exists():
                shutil.copy2(path, dest)
            else:
                dest.symlink_to(os.readlink(path))

    def link(self, source, target, check):
        if target.is_symlink() and os.readlink(target) == str(source):
            return
        if check:
            raise RuntimeError(f"missing or incorrect link: {target}")
        self.save_backup(target)
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists() or target.is_symlink():
            target.unlink()
        target.symlink_to(source)
        print(f"  [ok] {target} -> {source}")

    def ghostty(self, check):
        source = self.config / "terminal/ghostty"
        target = self.xdg / "ghostty"
        installed = shutil.which("ghostty") or Path("/Applications/Ghostty.app").exists()
        if not source.is_dir() or not (installed or target.is_dir()):
            return
        common = source / "common.conf"
        if common.is_file():
            self.link(common, target / "common.conf", check)
            # Keep the existing filename, including the newer config.ghostty name.
            live = target / ("config.ghostty" if (target / "config.ghostty").exists() else "config")
            local = target / "local.conf"
            original = target / "local.pre-dotfiles.conf"
            wrapper = (
                "# dotfiles: Ghostty common + local\n"
                'config-file = "common.conf"\n'
                'config-file = "?local.pre-dotfiles.conf"\n'
                'config-file = "?local.conf"\n'
            )
            text = live.read_text() if live.exists() else ""
            if text != wrapper:
                if check:
                    raise RuntimeError(f"Ghostty config needs migration: {live}")
                if "# dotfiles: Ghostty common + local" in text:
                    raise RuntimeError(f"move manual additions from {live} to {local}")
                self.save_backup(live)
                shared_lines = {line.strip() for line in common.read_text().splitlines()
                                if line.strip() and not line.lstrip().startswith("#")}
                text = "\n".join(line for line in text.splitlines()
                                 if line.strip() not in shared_lines)
                if text:
                    text += "\n"
                if text.strip():
                    dest = original if local.exists() else local
                    if dest.exists():
                        raise RuntimeError(f"refusing to overwrite existing local settings: {dest}")
                    dest.write_text(text)
                if live.is_symlink():
                    live.unlink()
                live.write_text(wrapper)
                print(f"  [ok] Ghostty common config; original preferences kept locally in {target}")
        profiles = source / "profiles"
        if profiles.is_dir():
            for profile in sorted(profiles.glob("*.conf")):
                self.link(profile, target / "profiles" / profile.name, check)
        # Preserve old explicit includes without loading the Herdr profile globally.
        legacy = target / "herdr.conf"
        if legacy.is_symlink() and os.readlink(legacy) in (
            str(self.config / "shell/ghostty-herdr.conf"),
            str(source / "profiles/herdr.conf"),
        ):
            self.link(source / "profiles/herdr.conf", legacy, check)
        print("  [ok] Ghostty preferences and local override layout")

    def herdr(self, check):
        base = self.config / "terminal/herdr/config.base.toml"
        target = self.xdg / "herdr/config.toml"
        binary = shutil.which("herdr")
        if not binary and (self.home / ".local/bin/herdr").is_file():
            binary = str(self.home / ".local/bin/herdr")
        if not base.is_file() or not (binary or target.parent.is_dir()):
            return
        command = ["bash", str(self.scripts / "merge-toml.sh"), str(base), str(target)]
        if check:
            command.append("--check")
        subprocess.run(command, check=True)
        if not check and binary:
            status = subprocess.run([binary, "status", "server"], capture_output=True, text=True, timeout=15)
            if status.returncode == 0 and "status: running" in status.stdout:
                subprocess.run([binary, "server", "reload-config"], check=True, timeout=15)
        print("  [ok] Herdr base keys; machine settings and sessions preserved")

    def herdr_ui(self, check):
        base = self.config / "terminal/herdr/config-gpui.base.toml"
        target = self.xdg / "herdr/config-gpui.local.toml"
        installed = shutil.which("herdr-gpui") or Path("/Applications/Herdr.app").exists()
        if not base.is_file() or not (installed or target.is_file()):
            return
        command = ["bash", str(self.scripts / "merge-toml.sh"), str(base), str(target)]
        if check:
            command.append("--check")
        subprocess.run(command, check=True)
        # The app watches the local overrides; its managed defaults stay untouched.
        print("  [ok] Herdr UI base keys; other local preferences preserved")

    def run(self, check=False):
        bins = self.config / "bin"
        if bins.is_dir():
            for source in sorted(bins.iterdir()):
                if source.is_file() and os.access(source, os.X_OK):
                    self.link(source, self.home / ".local/bin" / source.name, check)
        self.ghostty(check)
        self.herdr(check)
        self.herdr_ui(check)
        self.warn_overrides()

    def warn_overrides(self):
        """Report overlapping declarations without executing local code or printing values."""
        def shell_names(path):
            if not path.is_file():
                return []
            found = []
            for number, line in enumerate(path.read_text().splitlines(), 1):
                if line.lstrip().startswith("#"):
                    continue
                alias = re.search(r"(?:^|&&|;)\s*alias\s+([A-Za-z0-9_.-]+)=", line)
                function = re.match(r"\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_-]*)\s*\(\)\s*\{", line)
                variable = re.search(r"(?:^|&&|;)\s*(?:export\s+|typeset\s+-g\s+)?([A-Za-z_][A-Za-z0-9_]*)=", line)
                for kind, match in (("alias", alias), ("function", function), ("variable", variable)):
                    if match:
                        found.append((kind, match.group(1), number))
            return found

        shared = self.config / "terminal/zsh"
        os_file = "macos.zsh" if sys.platform == "darwin" else "linux.zsh"
        sources = (shared / "zshrc", shared / "zshrc.d" / os_file,
                   self.home / ".zshrc.d/machine-addition.zsh")
        names = {(kind, name) for source in sources for kind, name, _ in shell_names(source)}
        local = self.home / ".zshrc.d/local.zsh"
        for kind, name, number in shell_names(local):
            if (kind, name) in names:
                print(f"  [warn] local zsh {kind} overlaps shared settings: {name} ({local}:{number})")

        def ghostty_names(path):
            if not path.is_file():
                return []
            found = []
            for number, line in enumerate(path.read_text().splitlines(), 1):
                if not line.strip() or line.lstrip().startswith("#") or "=" not in line:
                    continue
                name, value = (part.strip() for part in line.split("=", 1))
                if name == "keybind":
                    name += "[" + value.split("=", 1)[0] + "]"
                if name != "config-file":
                    found.append((name, number))
            return found

        common = self.config / "terminal/ghostty/common.conf"
        names = {name for name, _ in ghostty_names(common)}
        for filename in ("local.pre-dotfiles.conf", "local.conf"):
            local = self.xdg / "ghostty" / filename
            for name, number in ghostty_names(local):
                if name in names:
                    print(f"  [warn] local Ghostty setting overlaps shared settings: {name} ({local}:{number})")

    def uninstall(self, mode):
        def unlink(target):
            if not target.is_symlink():
                return
            source = Path(os.readlink(target))
            try:
                source.relative_to(self.config)
            except ValueError:
                return
            target.unlink()
            if mode == "--keep" and source.is_file():
                shutil.copy2(source, target)
            elif mode == "--restore":
                backup = self.backup / target.relative_to(self.home)
                if backup.is_file():
                    shutil.copy2(backup, target)

        ghostty = self.xdg / "ghostty"
        for target in (ghostty / "common.conf", ghostty / "herdr.conf"):
            unlink(target)
        if (ghostty / "profiles").is_dir():
            for target in (ghostty / "profiles").glob("*.conf"):
                unlink(target)
        if (self.config / "bin").is_dir():
            for source in (self.config / "bin").iterdir():
                unlink(self.home / ".local/bin" / source.name)
        for name in ("config", "config.ghostty"):
            live = ghostty / name
            if not live.is_file() or "# dotfiles: Ghostty common + local" not in live.read_text():
                continue
            if mode == "--keep":
                continue
            backup = self.backup / live.relative_to(self.home)
            if mode == "--restore" and backup.is_file():
                shutil.copy2(backup, live)
            else:
                live.write_text('config-file = "?local.pre-dotfiles.conf"\n'
                                'config-file = "?local.conf"\n')
        for name in ("config.toml", "config-gpui.local.toml"):
            herdr = self.xdg / "herdr" / name
            backup = self.backup / herdr.relative_to(self.home)
            if mode == "--restore" and backup.is_file():
                shutil.copy2(backup, herdr)
        print("  [ok] terminal app links removed; local files and sessions preserved")


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3) or sys.argv[1] not in ("apply", "check", "uninstall"):
        raise SystemExit("Usage: terminal-config.py apply|check|uninstall [--restore|--keep|--remove-only]")
    try:
        manager = TerminalConfig()
        if sys.argv[1] == "uninstall":
            mode = sys.argv[2] if len(sys.argv) == 3 else "--restore"
            if mode not in ("--restore", "--keep", "--remove-only"):
                raise RuntimeError("invalid uninstall mode")
            manager.uninstall(mode)
        else:
            manager.run(check=sys.argv[1] == "check")
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"  [fail] terminal: {error}", file=sys.stderr)
        raise SystemExit(1)
