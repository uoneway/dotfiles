"""Exercise deletion ownership through the actual shell entry point."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / '.claude/skills/setup/scripts'


class ManagedRemovalTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.base = self.root / 'base.toml'
        self.target = self.root / 'live.toml'
        self.env = dict(os.environ, DOTFILES_STATE_DIR=str(self.root / 'state'),
                        DOTFILES_BACKUP=str(self.root / 'backup'))

    def run_merge(self, *args, code=0):
        result = subprocess.run(['bash', str(SCRIPTS / 'merge-toml.sh'), str(self.base),
                                 str(self.target), *args], env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result.stdout

    def snapshot(self):
        return {str(p.relative_to(self.root)): p.read_bytes()
                for p in self.root.rglob('*') if p.is_file()}

    def test_unchanged_removed_local_keys_preserved_and_check_read_only(self):
        self.base.write_text('old = "shared"\n[ui]\nretired = true\nactive = 1\n')
        self.target.write_text('old = "shared"\nlocal = "private"\n[ui]\nretired = true\nactive = 1\nlocal = 3\n')
        self.run_merge()
        self.base.write_text('[ui]\nactive = 2\n')
        before = self.snapshot()
        self.run_merge('--check', code=1)
        self.assertEqual(before, self.snapshot())
        self.run_merge()
        self.assertEqual(self.target.read_text(), 'local = "private"\n[ui]\nactive = 2\nlocal = 3\n')
        before = self.snapshot()
        self.run_merge()
        self.run_merge('--check')
        self.assertEqual(before, self.snapshot())

    def test_local_conflict_survives_snapshot_advance_and_can_be_resolved(self):
        self.base.write_text('old = 1\nactive = 1\n')
        self.run_merge()
        self.target.write_text('old = 2\nactive = 7\n')
        self.base.write_text('active = 3\n')
        self.assertIn('[conflict]', self.run_merge())
        self.assertEqual(self.target.read_text(), 'old = 2\nactive = 3\n')
        self.assertIn('[conflict]', self.run_merge('--check', code=1))
        self.target.write_text('old = 1\nactive = 3\n')
        self.run_merge()
        self.assertEqual(self.target.read_text(), 'active = 3\n')

    def test_first_run_does_not_claim_unknown_keys_and_migration_is_scoped(self):
        self.base.write_text('active = 1\n')
        self.target.write_text('commit_attribution = "Codex (AI-generated)"\nactive = 1\n')
        self.run_merge()
        self.assertIn('commit_attribution', self.target.read_text())
        migration = ['--migrations', str(SCRIPTS / 'codex-toml-migrations.json')]
        self.run_merge(*migration)
        self.assertNotIn('commit_attribution', self.target.read_text())
        self.target.write_text('commit_attribution = "Codex (AI-generated)"\nactive = 1\n')
        self.run_merge(*migration)
        self.assertIn('commit_attribution', self.target.read_text())  # one-time only

    def test_custom_legacy_value_is_preserved(self):
        self.base.write_text('active = 1\n')
        self.target.write_text('commit_attribution = "custom"\nactive = 1\n')
        self.assertIn('[conflict]', self.run_merge('--migrations', str(SCRIPTS / 'codex-toml-migrations.json')))
        self.assertIn('"custom"', self.target.read_text())

    def test_type_changes_are_local_changes_and_empty_base_works(self):
        self.base.write_text('old = 1\n')
        self.run_merge()
        self.target.write_text('old = true\n')
        self.base.write_text('')
        self.assertIn('[conflict]', self.run_merge())
        self.assertEqual(self.target.read_text(), 'old = true\n')
        self.target.write_text('old = 1\n')
        self.run_merge()
        self.assertEqual(self.target.read_text(), '')

    def test_failed_render_preserves_config_snapshot_and_backups(self):
        self.base.write_text('active = 1\n')
        self.run_merge()
        self.base.write_text('active = "new"\n')
        self.target.write_text('active = """\nold\n"""\n')
        before = self.snapshot()
        self.run_merge(code=1)
        self.assertEqual(before, self.snapshot())
        self.base.write_text('invalid = [')
        before = self.snapshot()
        self.run_merge(code=1)
        self.assertEqual(before, self.snapshot())

    def test_symlink_is_converted_without_modifying_source(self):
        self.base.write_text('active = 1\n')
        source = self.root / 'source.toml'
        source.write_text('active = 2\nlocal = true\n')
        self.target.symlink_to(source.name)
        before = self.snapshot()
        self.run_merge('--check', code=1)
        self.assertTrue(self.target.is_symlink())
        self.assertEqual(before, self.snapshot())
        self.run_merge()
        self.assertFalse(self.target.is_symlink())
        self.assertEqual(source.read_text(), 'active = 2\nlocal = true\n')

    def test_multiline_retired_value_and_quoted_key(self):
        self.base.write_text('[ui]\n"old.key" = [1, 2]\n')
        self.run_merge()
        self.target.write_text('[ui]\n"old.key" = [\n1,\n2,\n]\nlocal = true\n')
        self.base.write_text('')
        self.run_merge()
        self.assertEqual(self.target.read_text(), '[ui]\nlocal = true\n')

    def test_dotted_key_removal_and_reintroduced_key(self):
        self.base.write_text('ui.old = 1\n')
        self.run_merge()
        self.base.write_text('')
        self.run_merge()
        self.assertEqual(self.target.read_text(), '')
        self.base.write_text('ui.old = 2\n')
        self.run_merge()
        self.target.write_text('ui.old = 3\n')
        self.base.write_text('')
        self.assertIn('[conflict]', self.run_merge())
        self.base.write_text('ui.old = 4\n')
        self.run_merge()
        self.run_merge('--check')
        self.assertEqual(self.target.read_text(), 'ui.old = 4\n')


if __name__ == '__main__':
    unittest.main()
