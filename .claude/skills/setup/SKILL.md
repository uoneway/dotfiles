---
name: setup
description: "Initial dotfiles installation. Automatically handles environment analysis, AI tool configuration, and shell setup. Triggers on setup, install, or configure requests."
model: sonnet
allowed-tools:
  - Bash(bash .claude/skills/setup/scripts/*)
  - Bash(bash bin/dotfiles *)
  - Bash(ln -sf *)
  - Bash(curl *)
  - Bash(sh -c *)
  - Bash(npm install -g *)
  - Bash(cd *)
  - AskUserQuestion
  - Read
  - Write
  - Edit
  - Glob
---

# /setup — dotfiles installer

Talk to the user in the user's language.

Run the whole dotfiles installation step by step.
At each step, parse the script output and let the AI decide the next action.

## Step 0: Welcome message

Show the user a message with the following content:

```
Starting dotfiles setup.

AI tool settings (Claude Code, Codex CLI) and shell settings are
managed in one place, config/, and linked to each tool.

Existing config files are backed up automatically to dotfiles/backup/ before
any change (keeping the home directory structure), and can be restored at any time with /uninstall.

I will analyze the environment, ask a few questions, then configure everything automatically.
```

Then check whether the current directory is the dotfiles repo root.
If not, tell the user and stop.

## Backup policy (applies to every step)

Every script that replaces or modifies a user's existing file backs it up automatically under these rules:

| Target | When | Location |
|---|---|---|
| Files/directories replaced by symlinks (AGENTS.md, skills, zshrc, etc.) | Right before replacement | `dotfiles/backup/<홈 기준 상대경로>` |
| Merged files (settings.json, config.toml) | **Once before the first merge** + `.pre-merge.bak` on every merge | `dotfiles/backup/` + next to the original |

- `backup/` mirrors the home directory structure, so you can tell at once which file a backup is the original of
- If a backup already exists, do not overwrite it (preserves the original from the time of first installation)
- Restoring is done by `/uninstall` (`--restore` mode)
- When a `[backup]` log appears during a step, show the user a summary of the backup paths

## Step 1: Environment analysis

```bash
bash .claude/skills/setup/scripts/check-env.sh
```

Parse the output to determine:
- OS (macOS / Linux)
- Current shell (zsh / bash)
- Installed AI tools (claude, codex, gemini)
- Whether Oh My Zsh is installed
- Whether nvm is installed
- Whether config/ exists (whether this is the first run)

Show the user a summary of the results.

## Step 2: Questions for the user

Ask three questions with AskUserQuestion.

### Q1. AI tool selection

Ask which AI tools to configure.

- Options: Claude Code, Codex CLI, Gemini CLI (multiple selection allowed)
- Tools that are not installed can also be selected — installation guidance in Step 4
- Default: Claude Code and Codex CLI among the detected tools
  (Gemini CLI is excluded by default because it is in the Antigravity transition period — configure it only if the user explicitly selects it)

### Q2. Global instruction sharing strategy

Ask how global instructions should be managed across AI tools.

- **Unified**: write a single `AGENTS.md` and link each tool's instruction entry point to it. If a per-machine additional file is selected, link the combined result of the two
  - Advantage: editing one file applies to all tools
  - Suited for: when you want consistent instructions across tools
- **Separate**: keep an independent instruction file for each tool
  - Advantage: can be optimized per tool
  - Suited for: when you want to give each tool different instructions

### Q3. Multi-OS use

Ask whether the user uses these dotfiles on multiple OSes (macOS/Linux).

- **Yes** → follow-up question: tell the user the current OS is {Step 1에서 감지된 OS} and ask them to select the additional OS they use (whichever of macOS / Linux is not the current OS).
  - In Step 5, split shell settings into common/per-OS, and in Step 7, explain how to sync
- **No** → proceed with settings for the current OS only (in Step 5, only clean up settings that do not fit the current OS)

## Step 3: config initialization

If the config/ directory does not exist (first run):

```bash
bash .claude/skills/setup/scripts/init-config.sh
```

If config/ already exists, skip this step. The initial copy also prepares `config/apps.json`, `config/machines.toml`, and `config/installers/`.

App installation methods are read by merging the shared `apps.json` and the personal `config/apps.json`. Install targets are stored in `config/machines.toml`. An unnamed local run uses `[local].apps`; a registered machine uses its own `apps`, or `[defaults].apps` if omitted. `[defaults]` also supports non-app settings such as `components`, `transport`, `path`, and additional instruction and shell files. `[local]` does not inherit defaults and is not inherited by registered machines. Reflect the CLIs selected in Q1 in the corresponding list. Keep other apps that were already selected, and do not add new apps on your own. For detailed fields and examples, see the [app installation guide](../../../docs/INSTALL_APPS.md).

### Instruction mode handling (depending on the Q2 answer)

After running init-config.sh, do additional work depending on the Q2 choice:

**Unified mode**: use only `config/ai/AGENTS.md`. Delete per-tool instruction files if they exist.

```bash
rm -f ~/dotfiles/config/ai/claude/AGENTS.md
rm -f ~/dotfiles/config/ai/codex/AGENTS.md
rm -f ~/dotfiles/config/ai/gemini/GEMINI.md
```

**If Gemini is selected** (only if explicitly selected in Q1): init-config excludes it by default, so copy the template.

```bash
cp -r ~/dotfiles/templates/ai/gemini ~/dotfiles/config/ai/gemini
```

**Separate mode**: create a separate instruction file in each tool folder. Copy the content of `config/ai/AGENTS.md` as the initial value.

```bash
cp ~/dotfiles/config/ai/AGENTS.md ~/dotfiles/config/ai/claude/AGENTS.md
cp ~/dotfiles/config/ai/AGENTS.md ~/dotfiles/config/ai/codex/AGENTS.md
cp ~/dotfiles/config/ai/AGENTS.md ~/dotfiles/config/ai/gemini/GEMINI.md
```

## Step 4: AI tool setup

The AI decides based on the Step 1 results.

### Guidance for AI tools that are not installed

If any tool selected in Q1 is not installed, confirm whether to install it now or later. Do not repeat the question for a tool the user has already asked to install.

Codex CLI and Claude Code use the catalog's official installation method and version policy. Run it naming only the tools the user decided to install. The example below is for when both tools are selected.

```bash
bash bin/dotfiles install codex,claude --dry-run
bash bin/dotfiles install codex,claude
```

If only one tool is selected, pass only that name. Also reflect install targets that should stay managed in the corresponding `apps` list in `machines.toml`. To pin a version, write only `version` on that app in the personal `apps.json`. If the run fails, fix the problem before linking settings.

Gemini CLI is not currently in the shared app catalog. If selected, define it in the personal catalog using Homebrew or a personal install script, and add it to the install list. If you are only preparing settings for a tool that was not installed, report that installation was skipped.

### Create symlinks + merge settings

Claude Code reads `AGENTS.md` directly only from version 2.1.277 or later. If the installed version is lower, update Claude Code first.

Pass the `--unified` or `--separate` flag to each selected AI tool, depending on the Q2 answer:

```bash
# Unified mode
bash .claude/skills/setup/scripts/link-tool.sh claude --unified
bash .claude/skills/setup/scripts/link-tool.sh codex --unified

# Separate mode
bash .claude/skills/setup/scripts/link-tool.sh claude --separate
bash .claude/skills/setup/scripts/link-tool.sh codex --separate
```

What link-tool.sh does:

- **Instructions**: symlink to `~/AGENTS.md` for Claude, `~/.codex/AGENTS.md` for Codex, `~/.gemini/GEMINI.md` for Gemini. If `machines.toml` has `agents_addition`, link to the result combined with the additional instructions
- **agents, rules, statusline**: symlink to per-tool paths
- **settings.json / config.toml**: **merge**, not symlink — replace only the keys from `settings.base.json` / `config.base.toml`
  and preserve machine-local entries (hooks, `[projects]`, etc.) (merge-*.sh)
- **skills**: per-skill symlinks in the target directory (shared `config/ai/skills/` + tool-specific)

### Install third-party skills

```bash
bash .claude/skills/setup/scripts/install-manifest-skills.sh
```

Installs the skills declared in `config/ai/skills-manifest.toml` into `~/.agents/skills/` with `npx skills`.
Requires network — if it fails, continue and rerun it later.

Check each script's output to determine success/failure.
If config files already existed, they are backed up in the `backup/` folder, mirroring the home directory structure.

## Step 5: Shell setup

The shell settings to deploy are zsh-only. If zsh is not present, install it first. Use existing Bash settings only for migration analysis, and keep them machine-local. For servers where the login shell cannot be changed, `link-shell.sh` adds a block that switches from interactive Bash to zsh.

### 5-1. Analyze existing shell settings

Read the user's current shell config file (`~/.zshrc` or `~/.bashrc`) and analyze its content item by item.
If shell files already exist in `config/terminal/zsh/`, analyze those instead.

Analysis criteria:

| Category | Criterion | Examples |
|------|----------|------|
| **Common** | Settings that work regardless of OS | aliases, environment variables (`PATH` without OS-specific paths), pure shell functions, prompt settings |
| **Per-OS** | Settings whose paths, commands, or package managers differ by OS | Homebrew (`/opt/homebrew/`), `gls` vs `ls`, pnpm path (`~/Library/`) |
| **Framework-dependent** | Settings that only work when a specific tool such as Oh My Zsh or nvm is installed | `source $ZSH/oh-my-zsh.sh`, `plugins=(...)`, `NVM_DIR` |

### 5-2. Environment validity check

Check whether each analyzed item is actually valid in the current environment.

Check items:

- **Referenced tool exists**: whether commands/tools that appear in the settings are actually installed (check with `command -v`)
  - Example: a `gls` alias exists but coreutils is not installed
- **Path validity**: whether paths hardcoded in the settings actually exist
  - Example: the path `/opt/homebrew/opt/mysql-client@8.0/bin` does not exist
- **Framework dependencies**: Oh My Zsh, nvm, p10k, etc. are required but not installed
- **OS fit**: settings that do not work on the current OS are included in the common area

Show the user the check results as a table:

```
Shell settings check results:

[ok]    alias gs='git status'          — git installed
[ok]    Oh My Zsh plugins (git, z)      — Oh My Zsh installed
[warn]  uses gls (lslh_pretty)          — coreutils not installed
[fail]  Oh My Zsh                      — not installed (all shell settings depend on it)
```

### 5-3. Handle problem items

For each item that came out `[warn]` or `[fail]` in the check, propose how to handle it and let the user choose.

#### Core dependency not installed (`[fail]` level)

Core tools that all shell settings depend on (e.g. a shell framework, a version manager). If not installed, the config file does not work properly.

Ask with AskUserQuestion whether to install each one. Present the install command, but do not force installation; the user can skip.

#### Individual item problems (`[warn]` level)

Ask with AskUserQuestion how to handle it. Choices per item:

- **Install**: install the tool now (present the install command)
- **Remove**: remove the setting from the shell file
- **Move to per-OS file**: if the setting is valid only on a specific OS, move it to that OS's file
- **Skip**: ignore it for now and leave it as is

### 5-4. Create shell files

Build the shell files by combining the analysis results and the Q3 answer.

#### Composition principle: guards first, OS branching last

For tool- and path-dependent items, **first consider whether they can be made common with a guard** before moving them to an OS file:

```zsh
command -v nvim >/dev/null 2>&1 && alias v='nvim'
[[ -d "$HOME/.npm-global/bin" ]] && export PATH="$HOME/.npm-global/bin:$PATH"
```

Settings wrapped in a guard are safe on any machine, so they can go in common (zshrc).
Leave in OS files only what has an OS-specific path itself (Homebrew, ~/Library/pnpm, etc.).

Also keep the 3-level loading layers: common (zshrc) → per-OS (zshrc.d/{macos,linux}.zsh) →
machine-local (zshrc.d/local.zsh, secrets.zsh — real files, excluded from sync, sourced last).

#### Multi-OS case

```
config/terminal/zsh/
├── zshrc              ← guard-based common settings (includes per-OS source branching + local layer source)
└── zshrc.d/
    ├── macos.zsh      ← macOS only (Homebrew paths, pnpm, etc.)
    └── linux.zsh      ← Linux only (apt family, etc.)
```

- Include code in `zshrc` that sources the per-OS file with a `uname` branch
- Put in each OS file only those items classified as "Per-OS" in 5-1 that cannot be made common with a guard
- For the OS the user is not directly using, create the file as a skeleton based on the current OS file, and tell the user that paths and similar settings need to be checked and fixed on a machine running that OS

#### Single-OS case

```
config/terminal/zsh/
├── zshrc              ← full settings for the current OS
└── zshrc.d/           ← (empty or omitted)
```

- Keep all settings in the single `zshrc`
- Exclude items for which "Remove" was chosen in 5-3

### 5-5. Create symlinks

```bash
bash .claude/skills/setup/scripts/link-shell.sh zsh
python3 .claude/skills/setup/scripts/terminal-config.py apply
```

Check each script's output to determine success/failure.
If config files already existed, they are backed up in the `backup/` folder, mirroring the home directory structure.

## Step 6: Verification

Pass the tools selected in Q1 and the Q2 mode. If `--tools` is omitted, only tools that have symlinks are detected automatically.

```bash
bash .claude/skills/setup/scripts/verify.sh --unified --tools claude,codex
# or
bash .claude/skills/setup/scripts/verify.sh --separate --tools claude,codex,gemini
```

Parse the output:
- `[ok]` items → normal
- `[fail]` items → problem found

If a problem is found:
1. Analyze the cause (path error, permission problem, missing source file, etc.)
2. Try to repair it automatically
3. After the repair, rerun verify.sh to confirm
4. If it cannot be fixed, tell the user how to fix it manually

## Step 7: Completion and follow-up guidance

Once verification passes, show the user a message with the following content:

```
Setup complete! dotfiles has been configured successfully.

Configured items:
```

Below that, show a summary of the tools and shell actually configured. For example:

```
  - Claude Code: ~/.claude/ -> config/ai/claude/
  - Codex CLI:   ~/.codex/  -> config/ai/codex/
  - zsh:         ~/.zshrc   -> config/terminal/zsh/zshrc

Editing files in config/ now applies to all tools.
```

Then give the following guidance:

### Apply the shell

```bash
source ~/.zshrc
```

### Multi-machine deployment suggestion

If the user uses multiple machines, briefly explain the control-machine model (`dotfiles push`) and ask with AskUserQuestion whether to set it up.

- **Yes** → invoke the `sync-setup` skill directly with the Skill tool and continue (private repo + machines.toml + bootstrap).
- **No** → skip. Tell the user they can set it up at any time later with `/sync-setup`.

### Customization guide

- Edit files in `config/`. Directly symlinked items take effect immediately; per-machine additional instructions take effect after `dotfiles apply`.
- Changing shared settings: edit `settings.base.json` / `config.base.toml`, then `dotfiles apply` (or rerun link-tool.sh)
- New shared skill: `config/ai/skills/<name>/SKILL.md` / Claude-only: `config/ai/claude/skills/<name>/SKILL.md`
- Third-party skills: declare in `config/ai/skills-manifest.toml`
- App installation methods and versions: add apps or override some fields of the shared definitions in the personal `config/apps.json`
- Install targets: choose in `[local].apps`, `[defaults].apps`, and per-machine `apps` in `config/machines.toml`
- Personal install code: put scripts in `config/installers/` and connect them from personal app definitions
- `templates/` is an example of the initial setup, so change personal settings in `config/`
- After changes, refresh with `dotfiles apply` or by rerunning `/setup`
