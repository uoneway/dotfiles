"""Exercise shell apply/verify without touching the real home or config."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / ".claude/skills/setup/scripts"


class ShellLocalSettingsTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="dotfiles-shell-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "workspace"
        self.home = Path(self.tmp.name) / "home"
        self.scripts = self.root / ".claude/skills/setup/scripts"
        shutil.copytree(SCRIPTS, self.scripts)
        self.shared = self.root / "config/terminal/zsh/zshrc.d"
        self.shared.mkdir(parents=True)
        (self.shared.parent / "zshrc").write_text("# shared shell\n")
        (self.shared / "linux.zsh").write_text("# shared Linux\n")
        (self.root / "config/machines.toml").write_text("[local]\n")
        ai = self.root / "config/ai"
        ai.mkdir()
        (ai / "AGENTS.md").write_text("fixture\n")
        self.local = self.home / ".zshrc.d"
        self.local.mkdir(parents=True)
        for name in ("local.zsh", "secrets.zsh"):
            (self.local / name).write_text("# private fixture: " + name + "\n")
        (self.home / ".zshrc").write_text("# original shell\n")
        backup = self.root / "backup/.zshrc.d"
        backup.mkdir(parents=True)
        (backup / "local.zsh").write_text("# earlier local backup\n")
        for name in ("terminal-config.py", "karabiner-config.py", "macos-keyboard.py"):
            (self.scripts / name).write_text("# unrelated platform checks\n")
        self.env = dict(os.environ, HOME=str(self.home), SHELL="/bin/zsh",
                        DOTFILES_MACHINE="", SCRIPTS=str(self.scripts))

    def run_script(self, name):
        return subprocess.run(["bash", str(self.scripts / name)], env=self.env,
                              text=True, capture_output=True, timeout=15)

    def snapshot(self):
        result = {}
        for base in (self.home, self.root / "backup"):
            for path in base.rglob("*"):
                if path.is_symlink():
                    result[str(path)] = ("link", os.readlink(path))
                elif path.is_file():
                    result[str(path)] = ("file", path.read_bytes())
        return result

    def test_repeated_apply_preserves_local_files_and_backups(self):
        before = {name: (self.local / name).read_bytes()
                  for name in ("local.zsh", "secrets.zsh")}
        backup = self.root / "backup/.zshrc.d/local.zsh"
        original_backup = backup.read_bytes()
        for _ in range(2):
            result = self.run_script("link-shell.sh")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            for name, content in before.items():
                self.assertFalse((self.local / name).is_symlink())
                self.assertEqual((self.local / name).read_bytes(), content)
            self.assertEqual(backup.read_bytes(), original_backup)
        self.assertEqual((self.home / ".zshrc").resolve(), self.shared.parent / "zshrc")
        self.assertEqual((self.local / "linux.zsh").resolve(), self.shared / "linux.zsh")
        result = self.run_script("verify.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_shared_reserved_names_abort_before_any_shell_changes(self):
        for name in ("local.zsh", "secrets.zsh"):
            for kind in ("file", "broken-link", "directory"):
                with self.subTest(name=name, kind=kind):
                    path = self.shared / name
                    if kind == "file":
                        path.write_text("# must never be deployed\n")
                    elif kind == "broken-link":
                        path.symlink_to(self.shared / "missing")
                    else:
                        path.mkdir()
                    before = self.snapshot()
                    result = self.run_script("link-shell.sh")
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertIn(name, result.stdout + result.stderr)
                    self.assertEqual(self.snapshot(), before)
                    result = self.run_script("verify.sh")
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertIn(name, result.stdout + result.stderr)
                    self.assertEqual(self.snapshot(), before)
                    path.rmdir() if kind == "directory" else path.unlink()

    def test_local_symlinks_are_reported_and_never_replaced(self):
        for name in ("local.zsh", "secrets.zsh"):
            for broken in (False, True):
                with self.subTest(name=name, broken=broken):
                    path = self.local / name
                    original = path.read_bytes()
                    path.unlink()
                    path.symlink_to(self.shared / ("missing" if broken else "linux.zsh"))
                    before = self.snapshot()
                    for script in ("link-shell.sh", "verify.sh"):
                        result = self.run_script(script)
                        self.assertNotEqual(result.returncode, 0, result.stdout)
                        self.assertIn(name, result.stdout + result.stderr)
                        self.assertEqual(self.snapshot(), before)
                    path.unlink()
                    path.write_bytes(original)

    def test_missing_optional_local_files_are_allowed(self):
        for path in self.local.iterdir():
            path.unlink()
        for script in ("link-shell.sh", "verify.sh"):
            result = self.run_script(script)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
