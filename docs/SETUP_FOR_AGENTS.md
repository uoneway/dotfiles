# Setup Guide for AI Agents

You are helping the user set up **dotfiles** — a tool that manages AI coding tool and shell configurations via symlinks.

## Recommended: `/setup` Skill

If you are running inside **Claude Code**, use the `/setup` skill:

```
/setup
```

This handles the entire flow automatically:
1. Environment detection (OS, shell, installed tools)
2. User preference questions (tool selection, instruction sharing, multi-OS)
3. Config initialization (templates → config)
4. Dependency installation (Oh My Zsh, nvm)
5. AI tool symlink creation
6. Shell symlink creation
7. Verification and auto-repair

## Manual Setup (without Claude Code)

If `/setup` is not available, follow these steps:

### Step 1: Clone

```bash
git clone https://github.com/<username>/dotfiles ~/dotfiles
cd ~/dotfiles
```

### Step 2: Check environment

```bash
bash templates/ai/claude/skills/setup/scripts/check-env.sh
```

### Step 3: Initialize config (first run only)

```bash
bash templates/ai/claude/skills/setup/scripts/init-config.sh
```

### Step 4: Create AI tool symlinks

```bash
bash templates/ai/claude/skills/setup/scripts/link-tool.sh claude
bash templates/ai/claude/skills/setup/scripts/link-tool.sh codex
bash templates/ai/claude/skills/setup/scripts/link-tool.sh gemini
```

### Step 5: Create shell symlinks

```bash
bash templates/ai/claude/skills/setup/scripts/link-shell.sh zsh   # or bash
```

### Step 6: Verify

```bash
bash templates/ai/claude/skills/setup/scripts/verify.sh
```

### Step 7: Apply

```bash
source ~/.zshrc   # or source ~/.bashrc
```

## Customize

Edit files in `~/dotfiles/config/` to customize:

```
config/
├── ai/                        # AI 도구 설정
│   ├── CLAUDE.md              # Claude Code global instructions
│   ├── AGENTS.md              # Codex CLI global instructions (or shared)
│   ├── GEMINI.md              # Gemini CLI global instructions
│   ├── claude/
│   │   ├── settings.json      # Claude Code permissions & plugins
│   │   ├── skills/            # Custom skills
│   │   └── agents/            # Custom sub-agents
│   ├── codex/
│   │   ├── config.toml        # Codex model & policy settings
│   │   └── rules/             # Execution policy rules
│   └── gemini/
│       └── settings.json      # Gemini CLI settings
└── shell/                     # 셸 설정
    ├── zshrc                  # Zsh config
    ├── zshrc.d/               # OS-specific zsh extensions
    ├── bashrc                 # Bash config
    └── bashrc.d/              # OS-specific bash extensions
```

Since `config/` is gitignored, changes stay local. The user can optionally track them in a separate private repo.

## Troubleshooting

- **Re-run**: `/setup` (or the manual scripts) is safe to re-run anytime.
- **A tool wasn't detected**: Install the tool first, then re-run.
- **Existing files were backed up**: Look for `*.bak` files in your home directory.
- **Undo everything**: Run `/uninstall` to remove all symlinks and restore backups.
