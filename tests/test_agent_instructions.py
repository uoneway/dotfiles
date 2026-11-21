"""Exercise machine instruction generation and drift checks in a temporary home."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1] / ".claude/skills/setup/scripts"


class AgentInstructionsTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="dotfiles-agents-")
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.scripts = root / ".claude/skills/setup/scripts"
        shutil.copytree(SCRIPTS, self.scripts)
        for name in ("terminal-config.py", "karabiner-config.py", "macos-keyboard.py"):
            (self.scripts / name).write_text("# unrelated platform check\n")

        ai = root / "config/ai"
        additions = ai / "agents-additions"
        additions.mkdir(parents=True)
        (root / "config/terminal").mkdir()
        self.base = ai / "AGENTS.md"
        self.base.write_text(
            "# Instructions\n\n## Models\n\nBase model.\n\n"
            "## Commands\n\n```sh\n## Models\n```\n"
        )
        self.addition = additions / "shared.md"
        self.addition.write_text("## Extra\n\nExtra rule.\n\n## Models\n\nMachine model.\n")
        (root / "config/machines.toml").write_text('[local]\nagents_addition = "shared.md"\n')
        home = root / "home"
        self.instructions = home / ".gemini/GEMINI.md"
        self.env = dict(os.environ, HOME=str(home), DOTFILES_MACHINE="")

    def run_script(self, name, *args):
        return subprocess.run(
            ["bash", str(self.scripts / name), *args], env=self.env,
            text=True, capture_output=True, timeout=15,
        )

    def test_matching_section_replaces_base_and_verify_detects_old_output(self):
        result = self.run_script("link-tool.sh", "gemini")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            self.instructions.read_text(),
            "# Instructions\n\n## Models\n\nMachine model.\n\n"
            "## Commands\n\n```sh\n## Models\n```\n\n## Extra\n\nExtra rule.\n",
        )
        result = self.run_script("verify.sh", "--tools", "gemini")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

        self.instructions.write_text(self.base.read_text() + "\n" + self.addition.read_text())
        result = self.run_script("verify.sh", "--tools", "gemini")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("generated instructions differ", result.stdout)

    def test_unmatched_addition_is_appended(self):
        self.addition.write_text("## Extra\n\nExtra rule.\n")
        result = self.run_script("link-tool.sh", "gemini")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.instructions.read_text(), self.base.read_text() + "\n" + self.addition.read_text())
