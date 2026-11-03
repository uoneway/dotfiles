import importlib.util
from pathlib import Path
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / '.claude/skills/setup/scripts/remove-orca-integrations.py'
SPEC = importlib.util.spec_from_file_location('remove_orca', SCRIPT)
cleanup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cleanup)


class RemoveOrcaTests(unittest.TestCase):
    def test_preserves_other_hooks_in_same_group_and_other_settings(self):
        herdr = {'type': 'command', 'command': 'bash ~/.codex/herdr-agent-state.sh session'}
        data = {
            'hooks': {
                'SessionStart': [{'matcher': '*', 'hooks': [
                    {'type': 'command', 'command': ': orca-agent-hook-form=1; exit 0'}, herdr,
                ]}],
                'Stop': [{'hooks': [{'command': 'sh "$HOME/.orca/agent-hooks/claude-hook.sh"'}]}],
            },
            'env': {'KEEP': 'yes'},
            'permissions': {'allow': ['Read']},
        }
        expected = {
            'hooks': {'SessionStart': [{'matcher': '*', 'hooks': [herdr]}]},
            'env': {'KEEP': 'yes'}, 'permissions': {'allow': ['Read']},
        }
        self.assertEqual(cleanup.clean_json(data), expected)
        self.assertEqual(cleanup.clean_json(data), expected)

    def test_removes_only_orca_tui_plugin(self):
        data = {'plugin': ['other', 'file:///home/me/.config/opencode/plugins/orca-opencode-status-tui/tui.js']}
        self.assertEqual(cleanup.clean_json(data), {'plugin': ['other']})

    def test_removes_only_known_trust_grant(self):
        home = Path('/home/me')
        section = '[projects."/home/me/Library/Application Support/orca/rate-limit-pty-cwd"]\n'
        rest = '[projects."/home/me/work"]\ntrust_level = "trusted"\n'
        self.assertEqual(cleanup.clean_toml(section + 'trust_level = "trusted"\n\n' + rest, home), rest)
        changed = section + 'trust_level = "untrusted"\n' + rest
        self.assertEqual(cleanup.clean_toml(changed, home), changed)


if __name__ == '__main__':
    unittest.main()
