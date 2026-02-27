# dotfiles

Shell and AI coding tool configurations, managed with symlinks.

Supports **Claude Code**, **Codex CLI**, **Gemini CLI**, and both **zsh** and **bash**.

## Quick Start

```bash
git clone https://github.com/uoneway/dotfiles ~/dotfiles
cd ~/dotfiles
bash install.sh
```

The installer:
1. Copies `templates/` → `config/` on first run (your starting point)
2. Detects your shell and installed AI tools automatically
3. Symlinks `config/` files to the right locations (`~/.claude/`, `~/.codex/`, etc.)

## Structure

```
dotfiles/
├── install.sh              # Installer (auto-detects shell & tools)
├── templates/              # Starting point (copied to config/ on first run)
│   ├── claude/             #   Claude Code defaults
│   ├── codex/              #   Codex CLI defaults
│   ├── gemini/             #   Gemini CLI defaults
│   └── shell/              #   zshrc, bashrc, OS extensions
├── config/                 # Your actual config (gitignored)
│   ├── claude/
│   ├── codex/
│   ├── gemini/
│   └── shell/
├── docs/
│   └── SETUP_FOR_AGENTS.md # Hand this to your AI agent
└── README.md
```

## How It Works

**`templates/`** — Sensible defaults shipped with the repo. Never symlinked directly.

**`config/`** — Your real config files. The installer symlinks only from here. Gitignored so personal settings (API permissions, custom skills, project paths) stay out of the public repo.

**`install.sh`** — Detects what you have installed and creates symlinks accordingly. Safe to re-run.

## Managing Personal Config

`config/` is gitignored, but you can track it separately:

```bash
cd ~/dotfiles/config
git init
git add -A && git commit -m "initial config"
git remote add origin git@github.com:uoneway/dotfiles-private.git
git push -u origin main
```

This gives you:
- **Public repo** (`dotfiles`): the framework + templates anyone can use
- **Private repo** (`dotfiles-private`): your personal skills, agents, settings

## Syncing Across Machines

Options:
- **Git only**: push/pull `config/` private repo on each machine
- **Syncthing**: real-time sync of the whole `~/dotfiles/` directory (add `.git` to `.stignore`)
- **Both**: Syncthing for real-time, Git for history

## What Gets Symlinked

| Tool | Config in `config/` | Symlink target |
|------|---------------------|----------------|
| **Shell (zsh)** | `shell/zshrc` | `~/.zshrc` |
| | `shell/zshrc.d/*.zsh` | `~/.zshrc.d/` |
| **Shell (bash)** | `shell/bashrc` | `~/.bashrc` |
| | `shell/bashrc.d/*.bash` | `~/.bashrc.d/` |
| **Claude Code** | `claude/settings.json` | `~/.claude/settings.json` |
| | `CLAUDE.md` | `~/.claude/CLAUDE.md` |
| | `claude/skills/` | `~/.claude/skills/` |
| | `claude/agents/` | `~/.claude/agents/` |
| **Codex CLI** | `codex/config.toml` | `~/.codex/config.toml` |
| | `AGENTS.md` | `~/.codex/AGENTS.md` |
| | `codex/rules/` | `~/.codex/rules/` |
| **Gemini CLI** | `gemini/settings.json` | `~/.gemini/settings.json` |
| | `GEMINI.md` | `~/.gemini/GEMINI.md` |

## Agent-Friendly Setup

Give `docs/SETUP_FOR_AGENTS.md` to your AI agent — it contains step-by-step instructions an agent can follow to set everything up for you.
