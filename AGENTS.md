# AGENTS.md

Project rules for work inside `~/dotfiles`. Claude Code and Codex read this file directly.

`config/ai/AGENTS.md` is a different file: it holds the global instructions deployed to every tool and every project. This file applies only to work on the dotfiles repository itself.

## Repository layout

- `dotfiles/` (this repository, public): the framework. It holds the CLI (`bin/dotfiles`), the shared app catalog (`apps.json`), `templates/`, and versioned app sources.
- `dotfiles/config/` (private, a separate git repository named `dotfiles-config`): the actual personal settings. It is a nested repository with its own git history, fully separate from `dotfiles`. Check `git status` and `git -C config status` separately every time, because it is easy to commit one and forget the other.
- How an app is installed is defined in the shared `apps.json`. The personal `config/apps.json` adds apps or overrides single fields. Which apps a machine installs is chosen in `config/machines.toml`: `local.apps` (an unnamed local run), `defaults.apps` (the default for registered machines that omit it), and `machines.<name>.apps`. The local section does not inherit `[defaults]`. Besides apps, `[defaults]` supplies shared defaults for `components`, `transport`, `path`, `agents_addition`, and `zsh_addition`. `components` sets which settings are applied and is not used to select apps. Personal install scripts go in `config/installers/`.
- `VISION.md` holds the principles for the agent setup (global instructions, skills, workflow). Read it before adding, changing, or removing a skill or an instruction file.
- `README.md` is the reference for the full architecture (the symlink versus merge table, the sync scope). This file does not repeat it and covers working rules only.

## Core principles

1. **Sync intent, keep machine state local.** Intent means preferences and policy. Machine state means runtime records, credentials, and machine paths. Everything placed in `config/` is deployed to every machine.
2. **Only commits are deployed.** `dotfiles push` warns and continues when the local `dotfiles` or `config` repository is dirty. Uncommitted changes are not deployed.
3. **A dirty remote is skipped and reported.** Nothing overwrites it without `--force`. For the same reason `dotfiles status` is read-only and never repairs anything: it judges and does not touch.
4. **Claude Code and the Codex CLI are updated every time they are used.** Write settings for the latest version, and add a workaround for an older version only when the need is confirmed.

## What not to do (mistakes that have recurred)

- **Keep machine-local shell setup out of `config/terminal/zsh/zshrc`, including writes that reach it through the `~/.zshrc` symlink.** These files are git-managed and symlinked on every machine. Installers for `nvm`, `pyenv`, `rustup`, and many CLIs append PATH or init blocks to the login shell rc file, and that write follows the symlink into this repository and shows up as drift. Before running an installer, check whether it appends to `~/.zshrc`, and move machine-specific content to `~/.zshrc.d/local.zsh`, which is a real file and is never synced. If something was already appended, it is most likely just below the warning banner at the end of `config/terminal/zsh/zshrc`.
- **Do not edit `settings.json` or `config.toml` directly.** They are merge results. To change a setting, edit the base key in `config/ai/claude/settings.base.json`, `config/ai/codex/config.base.toml`, or `config/terminal/herdr/config.base.toml`, then run `dotfiles apply` to merge again. For TOML and the Claude Code JSON, a base key that was deleted is removed locally only when the local value equals the last applied value. `[conflict]` means the local value was kept; do not force its removal. Snapshot, first-apply, and migration rules are in `docs/SETUP_FOR_AGENTS.md`. Do not extend this deletion rule to shell symlinks or macOS system settings.
- **Do not commit secrets to `config/`.** `dotfiles push` runs a secret scan before deploying, but that is a backstop and does not catch everything. API keys and tokens go in each machine's `~/.zshrc.d/secrets.zsh`, which is excluded from sync.
- **Change `bin/dotfiles` (framework code) on a feature branch, and merge to `main` before deploying with `dotfiles push`.** Every hub-transport remote pulls only its own `main`. Running `dotfiles push` with commits left on a branch backs the branch up to origin and deploys nothing. Check `git branch --show-current` before pushing.

## Code ownership

This is a personal repository. You are the owner and long-term maintainer of its code, and its design is up to you: improve the structure as you work instead of adding to a shape that no longer fits. List every change you made beyond the request in your report. A request to change as little as possible overrides this.

## Deployment workflow

```
edit config/ (or change bin/dotfiles) → commit in that repository
  → dotfiles push --all         # each machine: git pull → apply → verify
  → dotfiles status             # deployment state and drift (read-only)
```

- `dotfiles status` and `dotfiles status --json` report STATE (`synced` / `behind N` / `drift` / `not bootstrapped` / `unreachable(reason)`) and APPLIED (`ok` / `stale` / `never`, with the time since the last apply). They collect everything in one ssh round trip per remote and reuse a ControlMaster socket to speed up repeated connections.
- Do not register a roaming laptop, one that changes networks or sleeps, in `config/machines.toml`. On the laptop, run `dotfiles pull`: it fast-forwards both repositories, then applies and verifies the settings.
- `~/.local/state/dotfiles/applied` records `<fw-sha> <cfg-sha> <epoch>` when an apply succeeds. It is the only evidence for detecting "pulled but apply failed or was skipped", so take care when changing the code that writes it (the end of `cmd_apply`).
- Decisions about the agent setup and their reasons go in `docs/decisions.md`, newest first.
- New features and next work go in `docs/backlog.md` (this repository, public) by priority (1, 2, 3) as the handoff between sessions. It is the framework's roadmap, not notes about personal settings, so it belongs in the public repository.
