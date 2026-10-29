# Setup Guide for AI Agents

You are helping the user set up **dotfiles** — a tool that manages AI coding tool and shell configurations from a single `config/` directory (symlinks for instructions/skills, key-level merge for settings files), and deploys them to multiple machines over git.

## Recommended: `/setup` Skill

If you are running inside **Claude Code**, use the `/setup` skill:

```
/setup
```

This handles the entire flow automatically:
1. Environment detection (OS, shell, installed tools)
2. User preference questions (tool selection, instruction sharing, multi-OS)
3. Config initialization (templates → config)
4. AI tool setup (symlinks + settings merge)
5. Shell setup (analysis, validation, symlinks)
6. Verification and auto-repair

## Manual Setup (without Claude Code)

The one-shot path:

```bash
git clone <framework-repo> ~/dotfiles
git clone <config-repo> ~/dotfiles/config     # personal config (private repo), skip if none
bash ~/dotfiles/bin/dotfiles apply            # init + link + merge + verify
```

Or step by step:

```bash
cd ~/dotfiles
bash .claude/skills/setup/scripts/check-env.sh          # 1. check environment
bash .claude/skills/setup/scripts/init-config.sh        # 2. templates → config (first run only)
bash .claude/skills/setup/scripts/link-tool.sh claude   # 3. per-tool setup
bash .claude/skills/setup/scripts/link-tool.sh codex
bash .claude/skills/setup/scripts/link-shell.sh zsh     # 4. shell symlinks
bash .claude/skills/setup/scripts/install-manifest-skills.sh  # 5. third-party skills (network)
bash .claude/skills/setup/scripts/verify.sh             # 6. verify
source ~/.zshrc                                          # 7. apply
```

## How files are managed

| File | Mechanism |
|---|---|
| `~/AGENTS.md`, `~/.codex/AGENTS.md` | symlink → `config/ai/AGENTS.md` (unified mode) |
| `~/.claude/settings.json` | **merge** — keys in `config/ai/claude/settings.base.json` win, machine-local keys (hooks, additionalDirectories) preserved |
| `~/.codex/config.toml` | **merge** — keys in `config/ai/codex/config.base.toml` win, machine state (`[projects]`, `[hooks.state]`, plugins…) preserved |
| `~/.claude/skills/` (Claude), `~/.agents/skills/` (Codex) | real dir + per-skill symlinks (shared `config/ai/skills/` + tool-specific); `~/.agents/skills/` also holds third-party skills from `npx skills` |
| `~/.agents/skills/` | third-party skills installed by `npx skills` from `config/ai/skills-manifest.toml` |
| `~/.zshrc`, `~/.zshrc.d/{macos,linux}.zsh` | symlinks; `~/.zshrc.d/local.zsh` & `secrets.zsh` are real local files (never synced) |

Never edit `~/.claude/settings.json` / `~/.codex/config.toml` expecting the change to sync — shared intent goes in the `*.base.*` files in `config/`; machine-local things stay in the live file.

### Retiring shared settings

`merge-settings.py` powers both `merge-toml.sh` and `merge-claude-settings.sh`.
It saves the last successfully applied base per target under
`${XDG_STATE_HOME:-~/.local/state}/dotfiles/{toml,json}/`. `DOTFILES_STATE_DIR` can override
the dotfiles state directory. These snapshots are local to each machine; do not
copy them between machines or commit them. They contain base values and use mode 0600.

- Current base keys still overwrite live values. This policy has not changed.
- A key removed from the previous base is deleted only if its live value still
  equals the old base value, including its type. Other local keys remain intact.
- A changed retired key is preserved and reported as `[conflict]`. Its old value
  remains in pending state, so subsequent runs still report it. To resolve it,
  have the user choose whether to remove the retired local setting or restore its
  old managed value and reapply. Do not silently force deletion.
- The first apply without a snapshot cannot infer past ownership. It preserves
  unknown keys and seeds the snapshot. Existing machines must apply once before
  future base deletions can be tracked. Losing the snapshot loses that history.
- The Codex wrapper also runs `codex-toml-migrations.json`. This one-time migration
  removes `commit_attribution` only for the exact known value `Codex (AI-generated)`;
  other values are preserved and reported. Extend explicit migration records only
  with verified historical values; never infer ownership from a key name alone.
- `--check` writes no configuration, backup, or snapshot. It returns 1 for drift
  or unresolved deletion conflicts, 0 otherwise. Apply reports preserved conflicts
  but succeeds if the merge and snapshot succeed. Logs omit setting values.
- Rendering and semantic validation finish before any persistent write. A changed
  target gets a first-install backup and `.pre-merge.bak`, then an atomic replacement;
  the snapshot is written last. If saving the snapshot fails after replacement,
  repair the state directory and retry; do not delete the old snapshot.

TOML bases retain the existing restriction to single-line assignments and ordinary
tables. Unsupported renderings fail validation without updating the target or
snapshot. Empty TOML table headers can remain after key removal. JSON objects
merge recursively; arrays and scalars are owned as whole values. Removing an item
from a still-managed array follows the existing base-wins policy; retiring the
whole array uses the old-value comparison. Empty JSON parents left by retired keys
are pruned only when absent from the current base; local siblings remain.
Claude marketplace paths are expanded before saving the snapshot, so deletion
compares against the actual absolute path applied on that machine.

For a focused Codex preview and apply, use:

```bash
bash ~/dotfiles/.claude/skills/setup/scripts/merge-codex-config.sh --check
bash ~/dotfiles/.claude/skills/setup/scripts/merge-codex-config.sh
```

Review base drift before applying: this applies all current Codex base keys as
well as retired-key migrations, and can reset a locally changed managed setting.
For Claude Code, use `merge-claude-settings.sh --check` and then
`merge-claude-settings.sh` in the same scripts directory. Check is read-only even
when the target is missing or a symlink. An unchanged file retains its formatting.

Shell source files use symlinks, so edits and deletions inside a shared file already
propagate; do not parse shell commands into managed keys or touch local/secrets
files. Removing an entire source file can leave a dangling symlink and requires a
separate link-ownership check, not this settings merger.

macOS preferences keep explicit per-key removal. Deleting a `defaults` override
returns to the OS/domain fallback, which may differ from the user's value before
management. Do not translate removal from base into automatic `defaults delete`;
a future restore mechanism must record the original typed value and its absence,
and define restore-versus-default behavior before touching system preferences.

## Multi-machine deploy

Use control-initiated push only for machines that are normally reachable over SSH:

```bash
dotfiles push --all     # commit-gated: aborts if repos dirty; secret-scans config/ first
dotfiles status         # per-machine HEAD/dirty report
dotfiles machines       # list registered machines (config/machines.toml)
```

Register machines in `config/machines.toml` (see file header for format). Use `/sync-setup` for guided setup.

For roaming laptops that sleep or change networks, do not register the laptop in `config/machines.toml`. After cloning both repositories and configuring GitHub access, run this command on the laptop:

```bash
dotfiles pull           # fast-forward both repos, then apply and verify locally
```

`dotfiles pull` keeps uncommitted local changes when they do not touch files changed by the incoming commits. It aborts before updating either repository if local changes overlap incoming changes or a repository cannot be fast-forwarded. It does not require inbound SSH access to the laptop.

## Troubleshooting

- **Re-run anytime**: all scripts are idempotent.
- **Settings drifted**: `verify.sh` reports it; re-run `link-tool.sh <tool>` (or `dotfiles apply`) to re-merge.
- **Undo everything**: `/uninstall` removes links, restores `backup/`, and leaves merged files self-contained.
