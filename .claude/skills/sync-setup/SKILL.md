---
name: sync-setup
description: "Multi-machine deployment setup. Guides machine registration (machines.toml), remote bootstrap, and cleanup of existing Syncthing. Triggers on requests for sync (동기화), machine registration (머신 등록), or push setup (push 설정)."
model: sonnet
disable-model-invocation: true
allowed-tools:
  - Bash(bash .claude/skills/sync-setup/scripts/*)
  - Bash(bin/dotfiles *)
  - Bash(grep * ~/.ssh/config)
  - Bash(ssh *)
  # Git
  - Bash(cd */config && git *)
  - Bash(gh repo create *)
  - Bash(gh api *)
  - Bash(brew services *)
  - Bash(syncthing *)
  - AskUserQuestion
  - Read
  - Write
  - Edit
---

# /sync-setup — Multi-machine deployment setup

Talk to the user in the user's language.

Sync model: **edit and commit on the control machine → `dotfiles push` → each machine runs git pull + apply.**
Transport is git (hub = private repo); orchestration is handled by the `bin/dotfiles` CLI.

## Step 1: Check the hub (private repo)

```bash
bash .claude/skills/sync-setup/scripts/check-git-config.sh
```

- `has_git=false` → `cd ~/dotfiles/config && git init && git add -A && git commit -m "initial config"`
- `has_remote=false` → confirm the repo name (default `dotfiles-config`) with AskUserQuestion, then:

```bash
gh repo create <username>/<repo-name> --private --description "Personal dotfiles config"
cd ~/dotfiles/config
git remote add origin git@github.com:<username>/<repo-name>.git
git push -u origin main
```

- Also check that the framework (`~/dotfiles`) has a remote (because remote machines need to clone it).

## Step 2: Machine registration (machines.toml)

1. List and show the `Host` entries in `~/.ssh/config` (`grep '^Host ' ~/.ssh/config`).
2. Have the user pick the machines to register with AskUserQuestion (multiple selection).
3. Ask for components for each machine:
   - Personal machine → `shell,claude,codex`
   - Shared-account server → `shell` or `shell,codex` (be careful about exposing personal permission settings and skills)
   - Machine without GitHub access (air-gapped network, etc.) → set `transport = "direct"`
4. Select the apps to install for each machine. Installation methods are read from the catalog that merges the shared `apps.json` and the personal `config/apps.json`. `components` is the scope of applied settings, so do not use it for app selection.
5. Write the list in `config/machines.toml`, like `apps = ["codex", "claude"]`. `apps = []` turns off automatic app installation for that machine. If omitted, it inherits `[defaults].apps`. `[defaults]` can also specify `components`, `transport`, `path`, `agents_addition`, and `zsh_addition`. A machine inherits only the fields it omits; values it sets explicitly replace the defaults. `[local]`, which is only for unnamed local runs, does not inherit defaults and is not inherited by registered machines.

See the per-machine examples in the [app installation guide](../../../docs/INSTALL_APPS.md). Before the remote bootstrap, check the policy with `dotfiles install --machine <이름> --dry-run`. This command checks the policy on the current machine and does not install over SSH.

## Step 3: Remote machine bootstrap (once per machine)

On the new machine (or over ssh):

```bash
git clone <framework-repo> ~/dotfiles
git clone <config-repo> ~/dotfiles/config
bash ~/dotfiles/bin/dotfiles apply <components> --machine <machines.toml의-이름>
```

- For `transport = "direct"` machines, additionally: `git -C ~/dotfiles config receive.denyCurrentBranch updateInstead` (same for the config repo)
- `--machine` installs that machine's `apps` list, applies the selected `agents_addition` and `zsh_addition`, then remembers the machine name locally. You do not need to pass it again to later `dotfiles apply` runs.
- If the machine needs secrets, create `~/.zshrc.d/secrets.zsh` manually (it is not synced)

After that, deploy from the control machine:

```bash
dotfiles push --all        # or dotfiles push <machine>
dotfiles status            # check deployment state per machine
```

## Step 4: Clean up existing Syncthing

The git push model and Syncthing real-time sync **must not be run side by side**
(if Syncthing carries files, the remote tree becomes dirty and `git pull --ff-only` falsely reports drift).

1. Check status:

```bash
bash .claude/skills/sync-setup/scripts/check-syncthing.sh
```

2. If a dotfiles/config folder is registered in `folder=`:
   - Tell the user to remove it **after the first real push succeeds** (turning it off before that leaves a sync gap)
   - Removal: remove the folder in the Syncthing UI (http://localhost:8384), or remove it with a script if the user wants
   - After removing the folder, ask whether to keep using Syncthing itself (for other folders); if not, `brew services stop syncthing`

3. If `config/.stfolder` or `~/dotfiles/.stignore` remain, clean them up as well.
