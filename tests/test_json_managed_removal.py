"""JSON ownership, local overrides and Claude path expansion regressions."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / '.claude/skills/setup/scripts'


class JsonManagedRemovalTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='json merge ')
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.base = self.root / 'base.json'
        self.target = self.root / 'home/.claude/settings.json'
        self.env = dict(os.environ, HOME=str(self.root / 'home'),
                        DOTFILES_STATE_DIR=str(self.root / 'state'),
                        DOTFILES_BACKUP=str(self.root / 'backup'))

    def write(self, path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value))

    def run_merge(self, *args, code=0):
        result = subprocess.run(['python3', str(SCRIPTS / 'merge-settings.py'), str(self.base),
                                 str(self.target), '--format', 'json', *args],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result.stdout

    def snapshot(self):
        return {str(p.relative_to(self.root)): p.read_bytes()
                for p in self.root.rglob('*') if p.is_file()}

    def test_removed_permissions_preserve_local_siblings_and_current_base_wins(self):
        self.write(self.base, {'permissions': {'allow': ['Read'], 'deny': ['Write']}, 'model': 'a'})
        self.write(self.target, {'permissions': {'additionalDirectories': ['/local']}, 'hooks': {'local': True}})
        self.run_merge()
        live = json.loads(self.target.read_text())
        live['model'] = 'local'
        self.write(self.target, live)
        self.write(self.base, {'permissions': {'deny': ['Edit']}, 'model': 'b'})
        before = self.snapshot()
        self.run_merge('--check', code=1)
        self.assertEqual(self.snapshot(), before)
        self.run_merge()
        self.assertEqual(json.loads(self.target.read_text()), {
            'permissions': {'additionalDirectories': ['/local'], 'deny': ['Edit']},
            'hooks': {'local': True}, 'model': 'b'})
        before = self.snapshot()
        self.run_merge()
        self.run_merge('--check')
        self.assertEqual(self.snapshot(), before)

    def test_modified_array_is_preserved_and_conflict_remains_until_resolved(self):
        self.write(self.base, {'permissions': {'allow': ['Read']}})
        self.run_merge()
        self.write(self.target, {'permissions': {'allow': ['Read', 'Local']}})
        self.write(self.base, {})
        self.assertIn('[conflict]', self.run_merge())
        self.assertIn('[conflict]', self.run_merge('--check', code=1))
        self.write(self.target, {'permissions': {'allow': ['Read']}})
        self.run_merge()
        self.assertEqual(json.loads(self.target.read_text()), {})

    def test_first_run_preserves_unknown_values_and_boolean_is_not_integer(self):
        self.write(self.base, {'number': 1})
        self.write(self.target, {'unknown': None})
        self.run_merge()
        self.write(self.target, {'unknown': None, 'number': True})
        self.write(self.base, {})
        self.assertIn('[conflict]', self.run_merge())
        self.assertEqual(json.loads(self.target.read_text()), {'unknown': None, 'number': True})

    def test_path_expansion_snapshot_uses_effective_applied_value(self):
        self.write(self.base, {'extraKnownMarketplaces': {
            'mine': {'source': {'path': '~/dotfiles/marketplace', 'source': 'directory'}}}})
        self.run_merge('--claude-marketplace-root', str(self.root / 'custom clone'))
        self.assertEqual(json.loads(self.target.read_text())['extraKnownMarketplaces']['mine']['source']['path'],
                         str(self.root / 'custom clone/marketplace'))
        self.write(self.base, {})
        self.run_merge('--claude-marketplace-root', str(self.root / 'new clone'))
        self.assertEqual(json.loads(self.target.read_text()), {})

    def test_check_missing_target_creates_nothing(self):
        self.write(self.base, {'model': 'a'})
        before = self.snapshot()
        self.run_merge('--check', code=1)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(self.target.parent.exists())

    def test_check_symlink_read_only_then_apply_preserves_source_and_backs_up(self):
        self.write(self.base, {'model': 'a'})
        source = self.root / 'original.json'
        self.write(source, {'model': 'b', 'local': 1})
        self.target.parent.mkdir(parents=True)
        self.target.symlink_to(source)
        before = self.snapshot()
        self.run_merge('--check', code=1)
        self.assertEqual(self.snapshot(), before)
        self.assertTrue(self.target.is_symlink())
        self.run_merge()
        self.assertFalse(self.target.is_symlink())
        self.assertEqual(json.loads(source.read_text()), {'model': 'b', 'local': 1})
        self.assertEqual(Path(str(self.target) + '.pre-merge.bak').read_text(), source.read_text())

    def test_invalid_json_does_not_modify_target_backup_or_snapshot(self):
        self.write(self.base, {'active': 1})
        self.run_merge()
        for invalid in ['{', '{"x": 1, "x": 2}', '[]', '{"x": NaN}']:
            self.base.write_text(invalid)
            before = self.snapshot()
            self.run_merge(code=1)
            self.assertEqual(self.snapshot(), before)

    def test_current_base_replaces_scalar_with_object_as_before(self):
        self.write(self.base, {'permissions': {'allow': ['Read']}})
        self.write(self.target, {'permissions': None, 'local': {}})
        self.run_merge()
        self.assertEqual(json.loads(self.target.read_text()),
                         {'permissions': {'allow': ['Read']}, 'local': {}})

    def test_claude_wrapper_uses_shared_merger_and_expands_first_install(self):
        clone = self.root / 'dotfiles'
        scripts = clone / '.claude/skills/setup/scripts'
        shutil.copytree(SCRIPTS, scripts)
        self.write(clone / 'config/ai/claude/settings.base.json', {
            'extraKnownMarketplaces': {'mine': {'source': {'path': '~/dotfiles/local'}}}})
        result = subprocess.run(['bash', str(scripts / 'merge-claude-settings.sh')],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(self.target.read_text())['extraKnownMarketplaces']['mine']['source']['path'],
                         str(clone / 'local'))


if __name__ == '__main__':
    unittest.main()
