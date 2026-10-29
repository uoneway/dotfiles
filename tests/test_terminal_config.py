"""Exercise real terminal migration and merge scripts against existing state."""

import contextlib
import io
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / ".claude/skills/setup/scripts"
spec = importlib.util.spec_from_file_location("terminal_config", SCRIPTS / "terminal-config.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TerminalConfigTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="terminal migration ")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        state_env = patch.dict(os.environ, {"DOTFILES_STATE_DIR": str(self.root / "state")})
        state_env.start()
        self.addCleanup(state_env.stop)
        self.home = self.root / "home"
        self.xdg = self.home / ".config"
        self.home.mkdir()
        self.manager = module.TerminalConfig(self.root, self.home, self.xdg)
        self.manager.scripts = SCRIPTS
        self.ghostty = self.xdg / "ghostty"
        self.ghostty.mkdir(parents=True)
        self.source = self.root / "config/terminal/ghostty"
        self.source.mkdir(parents=True)
        (self.source / "common.conf").write_text("font-size = 12\n")

    def test_ghostty_keeps_machine_preferences_and_repeated_apply_is_stable(self):
        original = "font-size = 12\nfont-family = Machine Font\ntheme = dark\n"
        (self.ghostty / "config").write_text(original)
        (self.ghostty / "theme-private").write_text("machine theme")
        self.manager.ghostty(False)
        self.assertEqual((self.ghostty / "local.conf").read_text(),
                         "font-family = Machine Font\ntheme = dark\n")
        self.assertEqual((self.root / "backup/.config/ghostty/config").read_text(), original)
        before = self.snapshot(self.ghostty)
        self.manager.ghostty(False)
        self.manager.ghostty(True)
        self.assertEqual(before, self.snapshot(self.ghostty))

    def test_existing_local_file_and_legacy_profile_include_survive(self):
        (self.ghostty / "config.ghostty").write_text("font-size = 18\n")
        (self.ghostty / "local.conf").write_text("theme = local\n")
        profiles = self.source / "profiles"
        profiles.mkdir()
        ((profiles / "herdr.conf").resolve()).write_text("keybind = super+t=text:hello\n")
        (self.ghostty / "herdr.conf").symlink_to(self.root / "config/shell/ghostty-herdr.conf")
        self.manager.ghostty(False)
        self.assertEqual((self.ghostty / "local.conf").read_text(), "theme = local\n")
        self.assertEqual((self.ghostty / "local.pre-dotfiles.conf").read_text(), "font-size = 18\n")
        self.assertEqual((self.ghostty / "herdr.conf").resolve(), (profiles / "herdr.conf").resolve())
        self.assertNotIn("profiles/herdr.conf", (self.ghostty / "config.ghostty").read_text())

    def test_check_detects_missing_links_without_changing_files(self):
        (self.ghostty / "config").write_text("font-size = 18\n")
        before = self.snapshot(self.root)
        with self.assertRaises(RuntimeError):
            self.manager.ghostty(True)
        self.assertEqual(before, self.snapshot(self.root))

    def test_toml_merge_preserves_machine_keys_arrays_and_read_only_check(self):
        base = self.root / "base.toml"
        target = self.root / "herdr/config.toml"
        target.parent.mkdir()
        base.write_text('[terminal]\nshell_mode = "login"\n')
        state = ('onboarding = false\n[terminal]\nshell_mode = "non_login"\n'
                 'default_shell = "/bin/bash"\n[ui]\nstatus_indicators = "symbols"\n'
                 '[[machines]]\nlabel = "GPU"\nshell_mode = "machine-only"\n'
                 '[[machines]]\nlabel = "CPU"\n')
        target.write_text(state)
        before = self.snapshot(self.root)
        result = self.merge(base, target, check=True)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertEqual(before, self.snapshot(self.root))
        result = self.merge(base, target)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(target.read_text(), state.replace('shell_mode = "non_login"',
                                                         'shell_mode = "login"'))
        after = self.snapshot(self.root)
        self.assertEqual(self.merge(base, target).returncode, 0)
        self.assertEqual(self.merge(base, target, check=True).returncode, 0)
        self.assertEqual(after, self.snapshot(self.root))

    def test_herdr_ui_merge_check_and_restore_preserve_local_state(self):
        base = self.root / "config/terminal/herdr/config-gpui.base.toml"
        base.parent.mkdir(parents=True)
        base.write_text('theme = "Nord"\n[terminal]\nsize = 12.0\n')
        target = self.xdg / "herdr/config-gpui.local.toml"
        target.parent.mkdir(parents=True)
        original = 'theme = "Default"\nlayout = "compact"\n[terminal]\nsize = 16.0\nfamily = "Local Font"\n'
        target.write_text(original)
        defaults = target.with_name("config-gpui.toml")
        defaults.write_text('# Managed by the app\ntheme = "Default"\n')
        session = target.with_name("session.json")
        session.write_text('{"workspace": "machine-only"}')
        before = self.snapshot(self.root)
        with self.assertRaises(subprocess.CalledProcessError):
            self.manager.herdr_ui(True)
        self.assertEqual(before, self.snapshot(self.root))
        env = {"DOTFILES_BACKUP": str(self.root / "backup"), "HOME": str(self.home)}
        with patch.dict(os.environ, env):
            self.manager.herdr_ui(False)
        self.assertEqual(target.read_text(), original.replace('"Default"', '"Nord"').replace('16.0', '12.0'))
        after = self.snapshot(self.root)
        self.manager.herdr_ui(True)
        with patch.dict(os.environ, env):
            self.manager.herdr_ui(False)
        self.assertEqual(after, self.snapshot(self.root))
        self.manager.uninstall("--restore")
        self.assertEqual(target.read_text(), original)
        self.assertEqual(defaults.read_text(), '# Managed by the app\ntheme = "Default"\n')
        self.assertEqual(session.read_text(), '{"workspace": "machine-only"}')

    def test_toml_check_does_not_convert_symlinks_and_invalid_merge_is_not_written(self):
        base = self.root / "base.toml"
        source = self.root / "original.toml"
        target = self.root / "config.toml"
        base.write_text('[terminal]\nshell_mode = "login"\n')
        source.write_text('[terminal]\nshell_mode = "non_login"\n')
        target.symlink_to(source)
        before = self.snapshot(self.root)
        self.assertEqual(self.merge(base, target, check=True).returncode, 1)
        self.assertEqual(before, self.snapshot(self.root))
        target.unlink()
        target.write_text('[terminal]\nshell_mode = """\nnon_login\n"""\n')
        before_text = target.read_text()
        self.assertNotEqual(self.merge(base, target).returncode, 0)
        self.assertEqual(target.read_text(), before_text)

    def test_executable_links_preserve_existing_command_backup(self):
        binary = self.root / "config/bin/hdr"
        binary.parent.mkdir(parents=True)
        binary.write_text("#!/bin/zsh\nexit 0\n")
        binary.chmod(0o755)
        target = self.home / ".local/bin/hdr"
        target.parent.mkdir(parents=True)
        target.write_text("old machine command")
        self.manager.run(False)
        self.assertEqual(target.resolve(), binary.resolve())
        self.assertEqual((self.root / "backup/.local/bin/hdr").read_text(), "old machine command")
        self.manager.run(True)

    def test_uninstall_keep_retains_local_settings_and_standalone_config(self):
        (self.ghostty / "config").write_text("theme = machine\n")
        self.manager.ghostty(False)
        self.manager.uninstall("--keep")
        self.assertFalse((self.ghostty / "common.conf").is_symlink())
        self.assertEqual((self.ghostty / "common.conf").read_text(), "font-size = 12\n")
        self.assertEqual((self.ghostty / "local.conf").read_text(), "theme = machine\n")

    def test_real_apply_migrates_shell_links_and_preserves_local_files(self):
        scripts = self.root / ".claude/skills/setup/scripts"
        shutil.copytree(SCRIPTS, scripts)
        (scripts / "install-manifest-skills.sh").write_text("exit 0\n")
        cli = self.root / "bin/dotfiles"
        cli.parent.mkdir()
        shutil.copy2(ROOT / "bin/dotfiles", cli)
        config = self.root / "config"
        (config / "machines.toml").write_text('[local]\ncomponents = "terminal"\napps = []\n')
        zsh = config / "terminal/zsh"
        zsh.mkdir(parents=True)
        (zsh / "zshrc").write_text("# common shell\n")
        (config / "ai").mkdir()
        (config / "ai/AGENTS.md").write_text("test instructions\n")
        (self.home / ".zshrc").symlink_to(config / "shell/zshrc")
        local = self.home / ".zshrc.d/local.zsh"
        local.parent.mkdir()
        local.write_text("export MACHINE_ONLY=yes\n")
        obsolete = local.with_name("aliases.zsh")
        obsolete.symlink_to(zsh / "zshrc.d/aliases.zsh")
        secrets = local.with_name("secrets.zsh")
        secrets.write_text("# private machine settings\n")
        (self.ghostty / "config").write_text("theme = machine\n")
        binary = config / "bin/hdr"
        binary.parent.mkdir()
        binary.write_text("#!/bin/zsh\nexit 0\n")
        binary.chmod(0o755)
        env = os.environ.copy()
        env.update(HOME=str(self.home), XDG_CONFIG_HOME=str(self.xdg), SHELL="/bin/bash")
        bashrc = self.home / ".bashrc"
        bashrc.write_text("export MACHINE_BASH_SETTING=yes\n")
        result = subprocess.run(["bash", str(cli), "apply", "terminal", "--skip-install"],
                                env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.home / ".zshrc").resolve(), (zsh / "zshrc").resolve())
        self.assertEqual(local.read_text(), "export MACHINE_ONLY=yes\n")
        self.assertFalse(obsolete.is_symlink())
        self.assertEqual(secrets.read_text(), "# private machine settings\n")
        self.assertTrue((self.home / ".local/state/dotfiles/applied").is_file())
        self.assertFalse(bashrc.is_symlink())
        self.assertTrue(bashrc.read_text().startswith("export MACHINE_BASH_SETTING=yes\n"))
        first = bashrc.read_text()
        result = subprocess.run(["bash", str(scripts / "link-shell.sh"), "zsh"], env=env,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(first, bashrc.read_text())
        result = subprocess.run(["bash", "-c", 'source "$HOME/.bashrc"; '
                                 'test "$MACHINE_BASH_SETTING" = yes && test -z "$ZSH_VERSION"'],
                                env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode, 0, result.stdout)


    def test_override_warnings_are_read_only_and_hide_values(self):
        shared = self.root / "config/terminal/zsh"
        shared.mkdir(parents=True)
        (shared / "zshrc").write_text("export PATH=shared\nalias gc=shared\nhelper() { :; }\n")
        local = self.home / ".zshrc.d/local.zsh"
        local.parent.mkdir()
        sentinel = self.home / "must-not-execute"
        local.write_text(f"export PATH=private-value\nalias gc='private-command'\n"
                         f"helper() {{ :; }}\ntouch '{sentinel}'\nexport UNIQUE=secret-value\n")
        local.with_name("secrets.zsh").write_text("export PATH=secret-value\n")
        (self.source / "common.conf").write_text("font-size = 12\nkeybind = super+t=new_tab\n")
        (self.ghostty / "local.conf").write_text(
            "font-size = 18\nkeybind = super+t=text:private-command\n"
            "keybind = super+n=new_window\ntheme = private-value\n")
        before = self.snapshot(self.root)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.manager.warn_overrides()
        warning = output.getvalue()
        for name in ("PATH", "gc", "helper", "font-size", "keybind[super+t]"):
            self.assertIn(name, warning)
        for value in ("private-value", "private-command", "secret-value", "secrets.zsh",
                      "UNIQUE", "super+n", "theme"):
            self.assertNotIn(value, warning)
        self.assertEqual(before, self.snapshot(self.root))

    def merge(self, base, target, check=False):
        env = os.environ.copy()
        env["DOTFILES_BACKUP"] = str(self.root / "backup")
        args = ["bash", str(SCRIPTS / "merge-toml.sh"), str(base), str(target)]
        if check:
            args.append("--check")
        return subprocess.run(args, env=env, text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT)

    @staticmethod
    def snapshot(root):
        return {str(p.relative_to(root)): ("link", os.readlink(p)) if p.is_symlink()
                else ("file", p.read_bytes()) for p in root.rglob("*") if p.is_file() or p.is_symlink()}


if __name__ == "__main__":
    unittest.main()
