import argparse
import importlib.util
import json
from pathlib import Path
import platform
import plistlib
import shlex
import subprocess
import os
import sys
import tempfile
import unittest
from unittest.mock import patch

TOOLS = ("codex", "claude", "right-shift-english")
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("install_apps", ROOT / ".claude/skills/setup/scripts/install-apps.py")
apps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(apps)


def args(tools=None, latest=False, version=None, components=None, machine=None):
    return argparse.Namespace(tools=tools, latest=latest, version=version or [], components=components, machine=machine)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dotfiles-tests-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "templates").mkdir()
        (self.root / "templates/apps.json").write_text((ROOT / "templates/apps.json").read_text())
        (self.root / "apps.json").write_text((ROOT / "apps.json").read_text())
        (self.root / "templates/machines.toml").write_text((ROOT / "templates/machines.toml").read_text())
        self.addCleanup(patch.stopall)
        patch.object(apps, "machine_name", side_effect=lambda explicit=None, home=None: explicit).start()

    def config(self, data):
        (self.root / "config").mkdir(exist_ok=True)
        (self.root / "config/apps.json").write_text(json.dumps(data))
        if isinstance(data, dict):
            (self.root / "config/machines.toml").write_text("[local]\napps = " + json.dumps(list(data)) + "\n")

    def binary(self, path, version):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"#!/bin/sh\nprintf '%s\\n' '{version}'\n")
        path.chmod(0o755)

    def test_default_latest_on_mac(self):
        self.assertEqual(apps.plan(args(), "Darwin", self.root), [(t, "latest") for t in TOOLS])

    def test_default_skips_app_on_linux(self):
        self.assertEqual(apps.plan(args(), "Linux", self.root), [(t, "latest") for t in TOOLS[:2]])

    def test_explicit_app_fails_on_linux(self):
        with self.assertRaises(ValueError): apps.plan(args("right-shift-english"), "Linux", self.root)

    def test_configured_pins_and_disabled_tools(self):
        self.config({"codex": "0.159.2", "claude": False})
        self.assertEqual(apps.plan(args(), "Darwin", self.root), [("codex", "0.159.2")])
        self.assertEqual(apps.plan(args(latest=True), "Darwin", self.root), [("codex", "latest")])

    def test_latest_overrides_pins(self):
        self.config({"codex": "0.159.2"})
        self.assertEqual(apps.plan(args(latest=True), "Linux", self.root), [("codex", "latest")])

    def test_multiple_version_overrides(self):
        result = apps.plan(args("codex,claude", version=["codex=0.159.2", "claude=2.1.277"]), "Linux", self.root)
        self.assertEqual(result, [("codex", "0.159.2"), ("claude", "2.1.277")])

    def test_app_placement_is_independent_of_settings_components(self):
        self.assertEqual(apps.plan(args(components="codex"), "Darwin", self.root), [(tool, "latest") for tool in TOOLS])

    def test_invalid_requests_are_rejected(self):
        requests = [args("bad"), args("codex,codex"), args(version=["bad=1.2.3"]),
                    args(version=["1.2.3"]), args(version=["codex=../x"]),
                    args(latest=True, version=["codex=1.2.3"]),
                    args(version=["codex=1.2.3", "codex=1.2.4"])]
        for request in requests:
            with self.subTest(request=request), self.assertRaises(ValueError):
                apps.plan(request, "Darwin", self.root)

    def test_invalid_manifests_fail(self):
        for data in [{"unknown": "latest"}, {"codex": True}, {"claude": None}, [], {"codex": "$(id)"}]:
            self.config(data)
            with self.subTest(data=data), self.assertRaises(ValueError): apps.policy(self.root)

    def test_official_latest_endpoints(self):
        with patch.object(apps, "fetch", return_value=b'{"tag_name":"rust-v0.159.3"}') as fetch:
            self.assertEqual(apps.latest_cli("codex"), "0.159.3")
            fetch.assert_called_once_with("https://releases.openai.com/codex/channels/latest")
        with patch.object(apps, "fetch", return_value=b"2.1.280\n"):
            self.assertEqual(apps.latest_cli("claude"), "2.1.280")

    def test_codex_metadata_fallback(self):
        with patch.object(apps, "fetch", side_effect=[OSError("offline"), b'{"tag_name":"rust-v0.159.3"}']):
            self.assertEqual(apps.latest_cli("codex"), "0.159.3")

    def test_codex_installer_receives_exact_version_and_path(self):
        home = self.root / "user space"
        calls = []
        def run(command, env=None, check=True):
            calls.append((command, env))
            self.binary(Path(env["CODEX_INSTALL_DIR"]) / "codex", "codex-cli 0.159.2")
            return subprocess.CompletedProcess(command, 0)
        with patch.object(apps, "fetch", return_value=b"# official installer fixture"), patch.object(apps, "run", side_effect=run):
            apps.install_cli("codex", "0.159.2", home)
        command, env = calls[0]
        self.assertEqual(command[-2:], ["--release", "0.159.2"])
        self.assertEqual(env["CODEX_NON_INTERACTIVE"], "1")
        self.assertTrue(env["PATH"].startswith(env["CODEX_INSTALL_DIR"] + ":"))
        self.assertNotIn("homebrew", env["PATH"])
        self.assertEqual(apps.reported_version(home / ".local/bin/codex"), "0.159.2")

    def test_matching_codex_version_skips_download(self):
        self.binary(self.root / ".local/bin/codex", "codex-cli 0.159.2")
        with patch.object(apps, "fetch") as fetch:
            apps.install_cli("codex", "0.159.2", self.root)
            fetch.assert_not_called()

    def test_latest_checks_remote_and_skips_equal_version(self):
        self.binary(self.root / ".local/bin/codex", "codex-cli 0.159.3")
        with patch.object(apps, "latest_cli", return_value="0.159.3") as latest, patch.object(apps, "fetch") as fetch:
            apps.install_cli("codex", "latest", self.root)
            latest.assert_called_once_with("codex")
            fetch.assert_not_called()

    def test_codex_pin_disables_existing_vendor_updater_even_at_same_version(self):
        self.binary(self.root / ".local/bin/codex", "codex-cli 0.159.2")
        updater = self.root / ".codex/packages/standalone/auto-update-version"
        updater.parent.mkdir(parents=True)
        updater.write_text("0.159.2-aarch64-apple-darwin")
        def run(command, env=None, check=True):
            self.binary(Path(env["CODEX_INSTALL_DIR"]) / "codex", "codex-cli 0.159.2")
            updater.unlink()
        with patch.object(apps, "fetch", return_value=b"fixture") as fetch, patch.object(apps, "run", side_effect=run):
            apps.install_cli("codex", "0.159.2", self.root)
            fetch.assert_called_once()
        self.assertFalse(updater.exists())

    def test_failed_install_does_not_report_success(self):
        with patch.object(apps, "fetch", side_effect=OSError("network down")):
            with self.assertRaises(OSError): apps.install_cli("codex", "0.159.2", self.root)
        self.assertFalse((self.root / ".local/bin/codex").exists())

    def test_wrong_installed_version_fails(self):
        with patch.object(apps, "fetch", return_value=b"fixture"), patch.object(apps, "run"):
            with self.assertRaises(RuntimeError): apps.install_cli("codex", "0.159.2", self.root)

    def test_publish_keeps_vendor_symlink_target(self):
        source = self.root / "staging/codex"
        self.binary(self.root / "vendor/codex", "0.159.2")
        source.parent.mkdir()
        source.symlink_to(self.root / "vendor/codex")
        destination = self.root / "bin/codex"
        apps.publish_command(source, destination)
        self.assertTrue(destination.is_symlink())
        self.assertEqual(destination.resolve(), source.resolve())
        self.assertEqual(apps.reported_version(destination), "0.159.2")

    def test_claude_pin_and_return_to_latest(self):
        binary = self.root / ".local/bin/claude"
        self.binary(binary, "2.1.277 (Claude Code)")
        native = self.root / ".local/share/claude/versions/2.1.277"
        self.binary(native, "2.1.277 (Claude Code)")
        apps.install_cli("claude", "2.1.277", self.root)
        self.assertIn("DISABLE_AUTOUPDATER=1", binary.read_text())
        self.assertEqual(apps.reported_version(binary), "2.1.277")
        with patch.object(apps, "latest_cli", return_value="2.1.277"):
            apps.install_cli("claude", "latest", self.root)
        self.assertIn("unset DISABLE_AUTOUPDATER", binary.read_text())

    def test_claude_upgrade_when_official_installer_preserves_custom_launcher(self):
        binary = self.root / ".local/bin/claude"
        self.binary(binary, "2.1.277 (Claude Code)")
        def install(command, env=None, check=True):
            self.assertEqual(command[-1], "2.1.280")
            self.binary(self.root / ".local/share/claude/versions/2.1.280", "2.1.280 (Claude Code)")
        with patch.object(apps, "fetch", return_value=b"fixture"), patch.object(apps, "run", side_effect=install):
            apps.install_cli("claude", "2.1.280", self.root)
        self.assertEqual(apps.reported_version(binary), "2.1.280")

    def test_unknown_app_release_fails_before_install(self):
        with self.assertRaises(ValueError): apps.app_source("9.9.9")
        version, source = apps.app_source("latest")
        self.assertEqual(version, "1.0.4")
        self.assertTrue(source.exists())

    def test_missing_app_release_stops_entire_plan_before_cli_install(self):
        with patch.object(apps.platform, "system", return_value="Darwin"), patch.object(apps, "install_cli") as install:
            self.assertEqual(apps.main(["codex,right-shift-english", "--version", "right-shift-english=9.9.9"]), 1)
            install.assert_not_called()

    def test_main_dispatches_selected_policy(self):
        with patch.object(apps.Path, "home", return_value=self.root), patch.object(apps, "install_cli") as install:
            self.assertEqual(apps.main(["codex", "--version", "codex=0.159.2"], root=self.root), 0)
            install.assert_called_once_with("codex", "0.159.2", self.root, apps.policy(self.root)["codex"])

    def test_concurrent_install_is_rejected_before_mutations(self):
        state = self.root / ".local/state/dotfiles"
        state.mkdir(parents=True)
        with (state / "apps.lock").open("a") as lock:
            apps.fcntl.flock(lock, apps.fcntl.LOCK_EX | apps.fcntl.LOCK_NB)
            with patch.object(apps.Path, "home", return_value=self.root), patch.object(apps, "install_cli") as install:
                self.assertEqual(apps.main(["codex", "--version", "codex=0.159.2"], root=self.root), 1)
                install.assert_not_called()

    def test_cli_dry_run_and_invalid_version(self):
        cli = ROOT / "bin/dotfiles"
        result = subprocess.run(["bash", str(cli), "install", "codex", "--version", "codex=0.159.2", "--dry-run"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("codex=0.159.2 method=official source=https://chatgpt.com/codex/install.sh", result.stdout)
        result = subprocess.run(["bash", str(cli), "install", "codex", "--version", "codex=bad", "--dry-run"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        result = subprocess.run(["bash", str(ROOT / "install.sh"), "--apps", "codex", "--latest", "--dry-run"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("codex=latest method=official", result.stdout)

    def test_apply_install_failure_prevents_linking_and_success_stamp(self):
        cli = self.root / "bin/dotfiles"
        cli.parent.mkdir()
        cli.write_text((ROOT / "bin/dotfiles").read_text())
        scripts = self.root / ".claude/skills/setup/scripts"
        scripts.mkdir(parents=True)
        (scripts / "machine-config.sh").write_text("dotfiles_machine_name() { :; }\ndotfiles_machine_extra() { :; }\n")
        (scripts / "install-apps.py").write_text("import sys; sys.exit(17)\n")
        applied = Path.home() / ".local/state/dotfiles/applied"
        before = applied.read_bytes() if applied.exists() else None
        result = subprocess.run(["bash", str(cli), "apply", "codex"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("dotfiles apply (", result.stdout)
        self.assertEqual(applied.read_bytes() if applied.exists() else None, before)

    def recipe(self, method="script", **values):
        return dict({"method": method, "version": "latest"}, **values)

    def test_new_app_does_not_require_framework_changes(self):
        self.config({"my-tool": self.recipe(path="installers/my-tool.sh")})
        self.assertEqual(apps.plan(args(), "Linux", self.root), [("my-tool", "latest")])
        self.assertEqual(apps.plan(args("my-tool", version=["my-tool=1.2.3"]), "Linux", self.root), [("my-tool", "1.2.3")])
        self.assertEqual(apps.plan(args("codex"), "Linux", self.root), [("codex", "latest")])

    def test_disabled_entries_remain_disabled_even_when_explicit(self):
        self.config({"my-tool": self.recipe(path="missing.sh", enabled=False)})
        self.assertEqual(apps.plan(args("my-tool", latest=True), "Linux", self.root), [])

    def test_recipe_platforms_and_machine_selection(self):
        self.config({"my-tool": self.recipe(path="install.sh", platforms=["Linux"])})
        self.assertEqual(apps.plan(args(), "Linux", self.root), [("my-tool", "latest")])
        self.assertEqual(apps.plan(args(), "Darwin", self.root), [])
        with self.assertRaises(ValueError): apps.plan(args("my-tool"), "Darwin", self.root)

    def test_invalid_recipe_fields_and_types(self):
        entries = [self.recipe(path="x.sh", typo=True), self.recipe(path="x.sh", enabled="false"),
                   self.recipe(path="x.sh", platforms="Linux"), self.recipe(path="../x.sh"),
                   self.recipe(path="/tmp/x.sh"), self.recipe(path="x.sh", args="{version}"),
                   self.recipe(path="x.sh", args=[]), self.recipe(path="x.sh", interpreter="zsh"),
                   self.recipe("unknown"), self.recipe("homebrew", package="--help"),
                   self.recipe("homebrew", package="ripgrep", kind="bad"),
                   self.recipe("right-shift-app", package="../other", platforms=["Darwin"]),
                   self.recipe("right-shift-app", package="packages/app"),
                   dict(apps.default_recipe("codex"), installer_url="http://example.com/install.sh"),
                   dict(apps.default_recipe("codex"), latest_urls=[])]
        for entry in entries:
            self.config({"codex" if entry["method"] == "official" else "my-tool": entry})
            with self.subTest(entry=entry), self.assertRaises(ValueError): apps.policy(self.root)

    def test_script_runs_real_arguments_without_shell_interpolation(self):
        installer = self.root / "config/installers/my tool.sh"
        installer.parent.mkdir(parents=True)
        installer.write_text('printf "%s\\n" "$1" "$2" "$DOTFILES_APP_NAME" "$DOTFILES_APP_VERSION" > "$3"\n')
        output = self.root / "output"
        entry = self.recipe(path="installers/my tool.sh", args=["{version}", "$(touch should-not-exist)", str(output)])
        apps.install_job("my-tool", "1.2.3", entry, self.root, self.root)
        self.assertEqual(output.read_text().splitlines(), ["1.2.3", "$(touch should-not-exist)", "my-tool", "1.2.3"])
        self.assertFalse((ROOT / "should-not-exist").exists())

    def test_script_missing_or_escaping_symlink_is_rejected(self):
        config = self.root / "config"
        config.mkdir()
        entry = self.recipe(path="installer.sh")
        with self.assertRaises(ValueError): apps.script_command(entry, "latest", self.root)
        outside = self.root / "outside.sh"
        outside.write_text("exit 0")
        (config / "installer.sh").symlink_to(outside)
        with self.assertRaises(ValueError): apps.script_command(entry, "latest", self.root)

    def test_script_failure_propagates(self):
        config = self.root / "config"
        config.mkdir()
        (config / "fail.sh").write_text("exit 17")
        with self.assertRaises(subprocess.CalledProcessError):
            apps.install_job("custom", "latest", self.recipe(path="fail.sh"), self.root, self.root)

    def test_custom_official_urls_are_used(self):
        entry = dict(apps.default_recipe("codex"), installer_url="https://example.com/installer", latest_urls=["https://example.com/latest"], tag_prefix="v")
        with patch.object(apps, "fetch", return_value=b'{"tag_name":"v1.2.3"}') as fetch:
            self.assertEqual(apps.latest_cli("codex", entry), "1.2.3")
            fetch.assert_called_once_with("https://example.com/latest")
        def install(command, env=None, check=True):
            self.binary(Path(env["CODEX_INSTALL_DIR"]) / "codex", "1.2.3")
        with patch.object(apps, "fetch", return_value=b"fixture") as fetch, patch.object(apps, "run", side_effect=install):
            apps.install_job("codex", "1.2.3", entry, self.root)
            fetch.assert_called_once_with("https://example.com/installer")

    def test_custom_app_package_path(self):
        package = self.root / "custom/app/1.2.3"
        package.mkdir(parents=True)
        (package.parent / "latest").write_text("1.2.3")
        (package / "ShiftEnglish.swift").write_text("fixture")
        entry = self.recipe("right-shift-app", package="custom/app", platforms=["Darwin"])
        self.assertEqual(apps.app_source("latest", self.root, entry), ("1.2.3", package / "ShiftEnglish.swift"))

    def test_brew_install_upgrade_and_missing_dependency(self):
        for kind in ("formula", "cask"):
            entry = self.recipe("homebrew", package="user/tap/my-tool", kind=kind)
            for installed, operation in (("", "install"), ("my-tool\n", "upgrade")):
                with patch.object(apps.shutil, "which", return_value="/opt/homebrew/bin/brew"), patch.object(apps.subprocess, "check_output", return_value=installed), patch.object(apps, "run") as run:
                    apps.install_job("my-tool", "latest", entry, self.root)
                    self.assertEqual(run.call_args_list[-1].args[0], ["/opt/homebrew/bin/brew", operation, "--" + kind, "user/tap/my-tool"])
        with patch.object(apps.shutil, "which", return_value=None), self.assertRaises(RuntimeError):
            apps.install_brew("my-tool", "latest", entry)

    def test_brew_pins_and_linux_casks_are_rejected(self):
        self.config({"my-tool": self.recipe("homebrew", package="my-tool", version="1.2.3")})
        with self.assertRaises(ValueError): apps.plan(args(), "Darwin", self.root)
        self.config({"my-tool": self.recipe("homebrew", package="my-tool", kind="cask")})
        with self.assertRaises(ValueError): apps.plan(args(), "Linux", self.root)

    def test_template_personal_examples_merge_without_auto_installing_catalog(self):
        self.config(json.loads((ROOT / "templates/apps.json").read_text()))
        data = apps.policy(self.root)
        self.assertFalse(data["my-tool"]["enabled"])
        self.assertIn("ripgrep", data)
        self.assertEqual(apps.plan(args(), "Darwin", self.root), [(tool, "latest") for tool in TOOLS])

    def test_bad_metadata_uses_fallback(self):
        entry = apps.default_recipe("codex")
        for payload in (b'{"tag_name":123}', b'{"wrong_key":"1.2.3"}', b'not-json', b'{"tag_name":"latest"}'):
            with self.subTest(payload=payload), patch.object(apps, "fetch", side_effect=[payload, b'{"tag_name":"rust-v1.2.3"}']):
                self.assertEqual(apps.latest_cli("codex", entry), "1.2.3")

    def test_missing_script_stops_before_any_installation(self):
        self.config({"codex": apps.default_recipe("codex"), "my-tool": self.recipe(path="missing.sh")})
        with patch.object(apps, "install_job") as install:
            self.assertEqual(apps.main([], root=self.root), 1)
            install.assert_not_called()

    def test_custom_brew_dry_run_has_no_commands_or_state_writes(self):
        self.config({"my-tool": self.recipe("homebrew", package="ripgrep")})
        with patch.object(apps, "run") as run, patch.object(apps.Path, "home", return_value=self.root):
            self.assertEqual(apps.main(["--dry-run"], root=self.root), 0)
            run.assert_not_called()
        self.assertFalse((self.root / ".local").exists())

    def test_template_script_fails_until_implemented(self):
        result = subprocess.run(["bash", str(ROOT / "templates/installers/example.sh"), "1.2.3"],
                                env={"DOTFILES_APP_NAME": "my-tool"}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 64)

    def machines(self, content):
        (self.root / "config").mkdir(exist_ok=True)
        (self.root / "config/machines.toml").write_text(content)

    def test_partial_override_retains_common_installation_details(self):
        self.config({"codex": {"version": "0.159.2"}})
        data = apps.policy(self.root)
        self.assertEqual(data["codex"]["version"], "0.159.2")
        self.assertEqual(data["codex"]["installer_url"], apps.default_recipe("codex")["installer_url"])
        self.assertIn("claude", data)
        self.assertIn("ripgrep", data)

    def test_personal_app_appends_and_arrays_replace(self):
        self.config({"new-tool": self.recipe(path="new.sh"), "codex": {"latest_urls": ["https://example.com/latest"]}})
        data = apps.policy(self.root)
        self.assertIn("new-tool", data)
        self.assertIn("claude", data)
        self.assertEqual(data["codex"]["latest_urls"], ["https://example.com/latest"])

    def test_method_override_discards_incompatible_fields(self):
        self.config({"codex": {"method": "homebrew", "package": "codex", "kind": "cask", "platforms": ["Darwin"]}})
        entry = apps.policy(self.root)["codex"]
        self.assertNotIn("installer_url", entry)
        self.assertNotIn("adapter", entry)
        self.assertEqual(entry["method"], "homebrew")
        self.config({"codex": {"method": "homebrew"}})
        with self.assertRaises(ValueError): apps.policy(self.root)

    def test_empty_personal_catalog_keeps_common_catalog(self):
        self.config({})
        self.assertIn("codex", apps.policy(self.root))
        self.assertEqual(apps.plan(args(), "Darwin", self.root), [])

    def test_machine_selection_overrides_defaults_and_empty_stops_install(self):
        self.machines('[local]\napps = ["right-shift-english"]\n[defaults]\napps = ["codex", "claude"]\n[machines.server]\napps = ["codex", "ripgrep"]\n[machines.empty]\napps = []\n[machines.inherit]\nhost = "example"\n')
        self.assertEqual(apps.plan(args(machine="server"), "Linux", self.root), [("codex", "latest"), ("ripgrep", "latest")])
        self.assertEqual(apps.plan(args(machine="empty"), "Darwin", self.root), [])
        self.assertEqual(apps.plan(args(machine="inherit"), "Linux", self.root), [("codex", "latest"), ("claude", "latest")])
        self.assertEqual(apps.plan(args("jq", machine="empty"), "Linux", self.root), [("jq", "latest")])

    def test_invalid_machine_policies_fail(self):
        cases = ['[local]\napps = "codex"', '[local]\napps = [1]', '[local]\napps = ["codex", "codex"]',
                 '[local]\napps = ["unknown"]', '[local]\napps = ["codex"', '[local]\napps = ["codex"]\napps = []']
        for content in cases:
            self.machines(content)
            with self.subTest(content=content), self.assertRaises(ValueError): apps.plan(args(), "Darwin", self.root)
        self.machines('[local]\napps = []')
        with self.assertRaises(ValueError): apps.plan(args(machine="unknown"), "Darwin", self.root)
        with self.assertRaises(ValueError): apps.plan(args("codex", machine="unknown"), "Darwin", self.root)

    def test_multiline_machine_apps_with_comments(self):
        self.machines('[local]\napps = [\n "codex", # CLI\n "jq",\n]\n')
        self.assertEqual(apps.plan(args(), "Linux", self.root), [("codex", "latest"), ("jq", "latest")])

    def test_local_and_registered_defaults_are_independent(self):
        self.machines('[local]\napps = ["right-shift-english"]\n[defaults]\napps = ["codex", "claude"]\n[machines.inherit]\nhost = "example"\n')
        self.assertEqual(apps.plan(args(), "Darwin", self.root), [("right-shift-english", "latest")])
        self.assertEqual(apps.plan(args(machine="inherit"), "Linux", self.root), [("codex", "latest"), ("claude", "latest")])
        self.machines('[defaults]\napps = ["codex"]\n[machines.inherit]\nhost = "example"\n')
        self.assertEqual(apps.plan(args(), "Darwin", self.root), [])
        self.assertEqual(apps.plan(args(machine="inherit"), "Darwin", self.root), [("codex", "latest")])
        self.machines('[local]\napps = ["codex"]\n[machines.inherit]\nhost = "example"\n')
        self.assertEqual(apps.plan(args(machine="inherit"), "Darwin", self.root), [])

    def test_invalid_local_or_defaults_tables_are_rejected(self):
        for content in ('local = []', 'defaults = []', '[defaults]\napps = "codex"', '[defaults]\napps = ["codex", "codex"]'):
            self.machines(content)
            with self.subTest(content=content), self.assertRaises(ValueError): apps.plan(args(), "Darwin", self.root)

    def test_machine_precedence_explicit_environment_marker(self):
        # Stop the fixture's deterministic machine-name replacement here.
        patch.stopall()
        home = self.root / "home"
        marker = home / ".local/state/dotfiles/machine"
        marker.parent.mkdir(parents=True)
        marker.write_text("saved-machine\n")
        with patch.dict(os.environ, {"DOTFILES_MACHINE": "env-machine"}):
            self.assertEqual(apps.machine_name("explicit", home), "explicit")
            self.assertEqual(apps.machine_name(home=home), "env-machine")
        with patch.dict(os.environ, {"DOTFILES_MACHINE": ""}):
            self.assertEqual(apps.machine_name(home=home), "saved-machine")
            marker.unlink()
            self.assertIsNone(apps.machine_name(home=home))

    def test_vendored_toml_parser_fallback(self):
        with patch.dict(sys.modules, {"tomllib": None}), patch.object(sys, "path", list(sys.path)):
            fallback_spec = importlib.util.spec_from_file_location("install_apps_fallback", ROOT / ".claude/skills/setup/scripts/install-apps.py")
            fallback = importlib.util.module_from_spec(fallback_spec)
            fallback_spec.loader.exec_module(fallback)
            self.assertEqual(fallback.tomllib.__name__, "tomli")
            self.assertEqual(fallback.machine_apps(None, self.root), list(TOOLS))

    def test_catalog_option_has_no_machine_requirement_or_install_calls(self):
        self.machines('invalid toml')
        with patch.object(apps, "install_job") as install, patch.object(apps, "machine_apps") as selection, patch("builtins.print"):
            self.assertEqual(apps.main(["--catalog"], root=self.root), 0)
            install.assert_not_called()
            selection.assert_not_called()
            self.assertEqual(apps.main(["codex", "--catalog"], root=self.root), 1)

    def test_init_config_creates_personal_catalog_and_real_installers_directory(self):
        scripts = self.root / ".claude/skills/setup/scripts"
        scripts.mkdir(parents=True)
        initializer = scripts / "init-config.sh"
        initializer.write_bytes((ROOT / ".claude/skills/setup/scripts/init-config.sh").read_bytes())
        for folder in ("ai", "shell", "installers"):
            (self.root / "templates" / folder).mkdir(exist_ok=True)
        (self.root / "templates/installers/example.sh").write_bytes((ROOT / "templates/installers/example.sh").read_bytes())
        subprocess.run(["bash", str(initializer)], check=True, capture_output=True)
        self.assertTrue((self.root / "config/installers/example.sh").is_file())
        self.assertTrue((self.root / "config/apps.json").is_file())
        self.assertTrue((self.root / "config/machines.toml").is_file())
        (self.root / "config/apps.json").write_text('{"codex":{"version":"1.2.3"}}')
        subprocess.run(["bash", str(initializer)], check=True, capture_output=True)
        self.assertEqual(json.loads((self.root / "config/apps.json").read_text())["codex"]["version"], "1.2.3")

    def test_apply_passes_machine_policy_and_version_without_components(self):
        cli = self.root / "bin/dotfiles"
        cli.parent.mkdir()
        cli.write_bytes((ROOT / "bin/dotfiles").read_bytes())
        scripts = self.root / ".claude/skills/setup/scripts"
        scripts.mkdir(parents=True)
        (scripts / "machine-config.sh").write_bytes((ROOT / ".claude/skills/setup/scripts/machine-config.sh").read_bytes())
        self.copy_machine_parser(scripts)
        self.machines('[local]\napps = []\n[machines.work]\nhost = "work"\napps = ["codex"]\n')
        output = self.root / "install-call.json"
        (scripts / "install-apps.py").write_text(
            'import json, os, sys\nfrom pathlib import Path\n'
            + f'Path({str(output)!r}).write_text(json.dumps({{"machine": os.environ.get("DOTFILES_MACHINE"), "args": sys.argv[1:]}}))\n'
            + 'sys.exit(17)\n')
        result = subprocess.run(["bash", str(cli), "apply", "codex", "--machine", "work", "--version", "codex=1.2.3"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(output.read_text()), {"machine": "work", "args": ["--version", "codex=1.2.3"]})
        self.assertNotIn("dotfiles apply (", result.stdout)

    def test_cli_uses_real_machine_file_and_merged_personal_catalog(self):
        cli = self.root / "bin/dotfiles"
        cli.parent.mkdir()
        cli.write_bytes((ROOT / "bin/dotfiles").read_bytes())
        scripts = self.root / ".claude/skills/setup/scripts"
        scripts.mkdir(parents=True)
        for name in ("machine-config.sh", "machine-config.py", "install-apps.py"):
            (scripts / name).write_bytes((ROOT / ".claude/skills/setup/scripts" / name).read_bytes())
        # Include the parser fallback so this subprocess test works on 3.8–3.10.
        import shutil
        shutil.copytree(ROOT / ".claude/skills/setup/scripts/vendor", scripts / "vendor")
        self.config({"codex": {"version": "0.159.2"}, "my-tool": self.recipe(path="installers/my-tool.sh")})
        installer = self.root / "config/installers/my-tool.sh"
        installer.parent.mkdir()
        installer.write_text('exit 0\n')
        self.machines('[local]\napps = ["my-tool"]\n[machines.work]\napps = ["codex", "jq"]\n')
        result = subprocess.run(["bash", str(cli), "install", "--machine", "work", "--dry-run"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [
            "codex=0.159.2 method=official source=https://chatgpt.com/codex/install.sh",
            "jq=latest method=homebrew source=jq"])
        result = subprocess.run(["bash", str(cli), "install", "--catalog"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertIn("my-tool", data)
        self.assertIn("claude", data)
        self.assertEqual(data["codex"]["version"], "0.159.2")

    def test_document_json_examples_parse(self):
        import re
        text = (ROOT / "docs/INSTALL_APPS.md").read_text()
        for block in re.findall(r"```json\n(.*?)\n```", text, flags=re.S):
            with self.subTest(block=block): json.loads(block)

    def test_document_toml_example_matches_local_and_remote_policy(self):
        import re
        text = (ROOT / "docs/INSTALL_APPS.md").read_text()
        blocks = re.findall(r"```toml\n(.*?)\n```", text, flags=re.S)
        self.assertTrue(blocks)
        for block in blocks:
            with self.subTest(block=block):
                self.machines(block)
                self.assertEqual(apps.plan(args(), "Darwin", self.root), [(tool, "latest") for tool in TOOLS])
                self.assertEqual(apps.plan(args(machine="work-server"), "Linux", self.root),
                                 [(tool, "latest") for tool in ("codex", "claude", "ripgrep", "jq")])
                self.assertEqual(apps.plan(args(machine="shell-only"), "Linux", self.root), [])

    def copy_machine_parser(self, scripts):
        import shutil
        (scripts / "machine-config.py").write_bytes((ROOT / ".claude/skills/setup/scripts/machine-config.py").read_bytes())
        shutil.copytree(ROOT / ".claude/skills/setup/scripts/vendor", scripts / "vendor", dirs_exist_ok=True)

    def test_general_machine_defaults_and_explicit_overrides(self):
        self.machines('[defaults]\ncomponents = "shell,claude,codex"\napps = ["codex"]\ntransport = "direct"\npath = "~/custom-dotfiles"\nagents_addition = "shared.md"\nzsh_addition = "shared.zsh"\n[local]\ncomponents = "shell"\napps = []\n[machines.inherit]\nhost = "server"\n[machines.override]\nhost = "other"\ncomponents = "shell"\napps = []\ntransport = "hub"\nagents_addition = ""\n')
        config = apps.machine_config
        inherited = config.settings("inherit", self.root)
        self.assertEqual(inherited["components"], "shell,claude,codex")
        self.assertEqual(inherited["transport"], "direct")
        self.assertEqual(inherited["path"], "~/custom-dotfiles")
        self.assertEqual(inherited["agents_addition"], "shared.md")
        self.assertEqual(inherited["zsh_addition"], "shared.zsh")
        overridden = config.settings("override", self.root)
        self.assertEqual(overridden["components"], "shell")
        self.assertEqual(overridden["apps"], [])
        self.assertEqual(overridden["transport"], "hub")
        self.assertEqual(overridden["agents_addition"], "")
        self.assertEqual(config.settings(None, self.root), {"components": "shell", "apps": []})

    def test_cli_machine_listing_applies_defaults_regardless_of_table_order(self):
        cli = self.root / "bin/dotfiles"
        cli.parent.mkdir()
        cli.write_bytes((ROOT / "bin/dotfiles").read_bytes())
        scripts = self.root / ".claude/skills/setup/scripts"
        scripts.mkdir(parents=True)
        self.copy_machine_parser(scripts)
        (scripts / "machine-config.sh").write_bytes((ROOT / ".claude/skills/setup/scripts/machine-config.sh").read_bytes())
        self.machines('[machines.work]\nhost = "work"\n[defaults]\ncomponents = "shell,claude,codex"\ntransport = "direct"\npath = "~/custom-dotfiles"\nagents_addition = "shared.md"\n[local]\ncomponents = "shell"\n')
        result = subprocess.run(["bash", str(cli), "machines"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("components=shell,claude,codex", result.stdout)
        self.assertIn("transport=direct", result.stdout)
        self.assertIn("path=~/custom-dotfiles", result.stdout)
        self.assertIn("agents_addition=shared.md", result.stdout)
        self.assertEqual(len(result.stdout.splitlines()), 1)

    def test_apply_uses_inherited_components_and_cli_override(self):
        cli = self.root / "bin/dotfiles"
        cli.parent.mkdir()
        cli.write_bytes((ROOT / "bin/dotfiles").read_bytes())
        scripts = self.root / ".claude/skills/setup/scripts"
        scripts.mkdir(parents=True)
        self.copy_machine_parser(scripts)
        (scripts / "machine-config.sh").write_bytes((ROOT / ".claude/skills/setup/scripts/machine-config.sh").read_bytes())
        (scripts / "install-apps.py").write_text("# no installation in this fixture\n")
        for name in ("link-shell.sh", "link-tool.sh", "verify.sh"):
            (scripts / name).write_text("exit 1\n")
        (scripts / "install-manifest-skills.sh").write_text("exit 0\n")
        self.machines('[defaults]\ncomponents = "shell,claude,codex"\napps = []\n[machines.work]\nhost = "work"\n')
        for arguments, expected in (([], "shell,claude,codex"), (["codex"], "codex")):
            result = subprocess.run(["bash", str(cli), "apply", *arguments, "--machine", "work"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)  # Prevent writing an applied stamp.
            self.assertIn("components: " + expected, result.stdout, result.stderr)

    def test_invalid_default_components_and_extra_files_fail(self):
        for content in ('[defaults]\ncomponents = "shell,bad"', '[defaults]\ncomponents = []',
                        '[defaults]\nagents_addition = "../outside.md"', '[defaults]\ntransport = "bad"'):
            self.machines(content)
            with self.subTest(content=content), self.assertRaises(ValueError): apps.machine_config.load(self.root)

    @unittest.skipUnless(platform.system() == "Darwin", "macOS app build")
    def test_real_app_build_install_and_repeat_without_rebuilding(self):
        real_run = apps.run
        commands = []
        def run(command, env=None, check=True):
            commands.append(command)
            if command[0] == "launchctl":
                return subprocess.CompletedProcess(command, 1 if command[1] == "print" else 0)
            return real_run(command, env=env, check=check)
        with patch.object(apps, "run", side_effect=run):
            apps.install_app("latest", self.root)
            app = self.root / "Applications/Right Shift English.app"
            self.assertEqual(apps.reported_version(app / "Contents/MacOS/shift-english"), "1.0.4")
            agent = plistlib.loads((self.root / f"Library/LaunchAgents/{apps.LABEL}.plist").read_bytes())
            self.assertEqual(agent["KeepAlive"], {"Crashed": True})
            self.assertEqual(agent["ProgramArguments"], [str(app / "Contents/MacOS/shift-english")])
            commands.clear()
            apps.install_app("1.0.4", self.root)
            self.assertFalse(any(c[0] in ("swiftc", "codesign") for c in commands))

    def test_build_failure_preserves_existing_app(self):
        app = self.root / "Applications/Right Shift English.app"
        app.mkdir(parents=True)
        sentinel = app / "keep-me"
        sentinel.write_text("working app")
        with patch.object(apps.shutil, "which", return_value="/bin/fixture"), patch.object(apps, "run", side_effect=subprocess.CalledProcessError(1, "swiftc")):
            with self.assertRaises(subprocess.CalledProcessError): apps.install_app("1.0.0", self.root)
        self.assertEqual(sentinel.read_text(), "working app")


if __name__ == "__main__":
    unittest.main()
