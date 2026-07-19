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
| `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` | symlink → `config/ai/AGENTS.md` (unified mode) |
| `~/.claude/settings.json` | **merge** — keys in `config/ai/claude/settings.base.json` win, machine-local keys (hooks, additionalDirectories) preserved |
| `~/.codex/config.toml` | **merge** — keys in `config/ai/codex/config.base.toml` win, machine state (`[projects]`, `[hooks.state]`, plugins…) preserved |
| `~/.claude/skills/`, `~/.codex/skills/` | real dir + per-skill symlinks (shared `config/ai/skills/` + tool-specific) |
| `~/.agents/skills/` | third-party skills installed by `npx skills` from `config/ai/skills-manifest.toml` |
| `~/.zshrc`, `~/.zshrc.d/{macos,linux}.zsh` | symlinks; `~/.zshrc.d/local.zsh` & `secrets.zsh` are real local files (never synced) |

Never edit `~/.claude/settings.json` / `~/.codex/config.toml` expecting the change to sync — shared intent goes in the `*.base.*` files in `config/`; machine-local things stay in the live file.

## Multi-machine deploy

From the control machine:

```bash
dotfiles push --all     # commit-gated: aborts if repos dirty; secret-scans config/ first
dotfiles status         # per-machine HEAD/dirty report
dotfiles machines       # list registered machines (config/machines.toml)
```

Register machines in `config/machines.toml` (see file header for format). Use `/sync-setup` for guided setup.

## Troubleshooting

- **Re-run anytime**: all scripts are idempotent.
- **Settings drifted**: `verify.sh` reports it; re-run `link-tool.sh <tool>` (or `dotfiles apply`) to re-merge.
- **Undo everything**: `/uninstall` removes links, restores `backup/`, and leaves merged files self-contained.
