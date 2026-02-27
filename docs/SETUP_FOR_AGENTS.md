# Setup Guide for AI Agents

You are helping the user set up **dotfiles** — a tool that manages shell and AI coding tool configurations via symlinks.

Follow these steps exactly.

## Step 1: Clone

```bash
git clone https://github.com/uoneway/dotfiles ~/dotfiles
cd ~/dotfiles
```

## Step 2: Run the installer

```bash
bash install.sh
```

On first run, the installer will:
1. Copy `templates/` → `config/` as a starting point
2. Detect the user's shell (zsh or bash)
3. Detect installed AI tools (claude, codex, gemini)
4. Create symlinks from `config/` to the appropriate home directory locations

## Step 3: Verify

```bash
# Check symlinks were created
ls -la ~/.zshrc        # or ~/.bashrc
ls -la ~/.claude/      # if Claude Code is installed
ls -la ~/.codex/       # if Codex CLI is installed
ls -la ~/.gemini/      # if Gemini CLI is installed
```

## Step 4: Customize

Edit files in `~/dotfiles/config/` to customize:

```
config/
├── CLAUDE.md                  # Claude Code global instructions
├── AGENTS.md                  # Codex CLI global instructions
├── GEMINI.md                  # Gemini CLI global instructions
├── claude/
│   ├── settings.json          # Claude Code permissions & plugins
│   ├── skills/                # Custom skills
│   └── agents/                # Custom sub-agents
├── codex/
│   ├── config.toml            # Codex model & policy settings
│   └── rules/                 # Execution policy rules
├── gemini/
│   └── settings.json          # Gemini CLI settings
└── shell/
    ├── zshrc                  # Zsh config
    ├── zshrc.d/               # OS-specific zsh extensions
    ├── bashrc                 # Bash config
    └── bashrc.d/              # OS-specific bash extensions
```

Since `config/` is gitignored, changes stay local. The user can optionally track them in a separate private repo:

```bash
cd ~/dotfiles/config
git init
git remote add origin git@github.com:uoneway/dotfiles-private.git
```

## Step 5: Apply

```bash
source ~/.zshrc   # or source ~/.bashrc
```

## Troubleshooting

- **"First run detected" didn't appear**: `config/` already exists. Delete it and re-run to start fresh.
- **A tool wasn't detected**: Install the tool first, then re-run `bash install.sh`.
- **Existing files were backed up**: Look for `*.bak` files in your home directory.
