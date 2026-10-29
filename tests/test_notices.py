"""Check that persistent notices survive the real install/apply/push output order."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / ".claude/skills/setup/scripts"


class NoticeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="dotfiles-notices-")
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.workspace = self.directory / "workspace"
        self.home_dir = self.directory / "user"
        self.state = self.home_dir / ".local/state"
        scripts = self.workspace / ".claude/skills/setup/scripts"
        shutil.copytree(SCRIPTS, scripts)
        (self.workspace / "bin").mkdir()
        shutil.copy2(ROOT / "bin/dotfiles", self.workspace / "bin/dotfiles")
        shutil.copytree(ROOT / "templates", self.workspace / "templates")
        shutil.copy2(ROOT / "apps.json", self.workspace / "apps.json")
        (self.workspace / "config").mkdir()
        (self.workspace / "config/apps.json").write_text("{}")
        (self.workspace / "config/machines.toml").write_text(
            '[local]\napps = []\ncomponents = "terminal"\n'
            '[defaults]\napps = []\ncomponents = "terminal"\n'
            '[machines.gpu]\nhost = "fixture-gpu"\npath = "/fixture/dotfiles"\n')
        for name in ("link-shell.sh", "install-manifest-skills.sh", "verify.sh"):
            (scripts / name).write_text("echo 'later shell/verification log'\n")
        for name in ("terminal-config.py", "karabiner-config.py", "macos-keyboard.py"):
            (scripts / name).write_text("print('later configuration log')\n")
        tools = self.directory / "tools"
        tools.mkdir()
        (tools / "git").write_text("#!/bin/sh\nexit 0\n")
        (tools / "ssh").write_text('''#!/usr/bin/env python3
import json, os, sys
command = sys.argv[-1]
if "notices.py --json" in command:
    print(json.dumps([dict(schema=1, id="fixed", message="[NOTICE] remote source passes")]))
elif " apply " in command:
    assert command.startswith("DOTFILES_DEFER_NOTICES=1 "), command
    print("later remote apply/verification log")
    sys.exit(int(os.environ.get("FIXTURE_APPLY_FAILURE", "0")))
''')
        for path in tools.iterdir():
            path.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home_dir), XDG_STATE_HOME=str(self.state),
                        PATH=str(tools) + os.pathsep + os.environ["PATH"],
                        DOTFILES_MACHINE="", DOTFILES_DEFER_NOTICES="")

    def run_cli(self, *args, **env):
        return subprocess.run(["bash", str(self.workspace / "bin/dotfiles")] + list(args),
                              env=dict(self.env, **env), text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def write_notice(self):
        path = self.state / "dotfiles/notices/fixed.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(dict(schema=1, id="fixed", message="[NOTICE] local source passes")))
        return path

    def test_real_apply_and_install_emit_notice_after_all_other_logs(self):
        path = self.write_notice()
        original = path.read_bytes()
        for args in (("apply", "terminal"), ("install",)):
            with self.subTest(args=args):
                result = self.run_cli(*args)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertTrue(result.stdout.rstrip().endswith("[NOTICE] local source passes"), result.stdout)
                self.assertEqual(path.read_bytes(), original)
        result = self.run_cli("apply", "terminal", DOTFILES_DEFER_NOTICES="1")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("[NOTICE]", result.stdout)

    def test_push_collects_remote_notice_after_its_final_summary_even_on_apply_failure(self):
        for failed in ("0", "7"):
            with self.subTest(failed=failed):
                result = self.run_cli("push", "--all", FIXTURE_APPLY_FAILURE=failed)
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertIn("gpu: OK" if failed == "0" else "gpu: APPLY/VERIFY FAILED", result.stdout)
                self.assertLess(result.stdout.index("=== push summary ==="),
                                result.stdout.index("=== 확인이 필요한 알림 ==="))
                self.assertIn("[gpu]", result.stdout)
                self.assertTrue(result.stdout.rstrip().endswith("[NOTICE] remote source passes"), result.stdout)

    def test_read_only_json_has_no_state_writes_and_ignores_bad_record(self):
        command = ["python3", str(SCRIPTS / "notices.py"), "--json"]
        result = subprocess.run(command, env=self.env, text=True, capture_output=True)
        self.assertEqual(json.loads(result.stdout), [])
        self.assertFalse(self.state.exists())
        path = self.write_notice()
        (path.parent / "bad.json").write_text('{"schema":1,"id":"bad","message":null}')
        before = {p.name: p.read_bytes() for p in path.parent.iterdir()}
        result = subprocess.run(command, env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(len(json.loads(result.stdout)), 1)
        self.assertIn("[warn]", result.stderr)
        self.assertEqual(before, {p.name: p.read_bytes() for p in path.parent.iterdir()})


if __name__ == "__main__":
    unittest.main()
