---
name: uninstall
description: "Remove dotfiles symlinks and restore the originals. Triggers on uninstall, remove, or restore requests."
model: sonnet
allowed-tools:
  - Bash(bash .claude/skills/uninstall/scripts/*)
  - Bash(bash .claude/skills/setup/scripts/verify.sh)
  - AskUserQuestion
  - Read
  - Write
  - Edit
---

# /uninstall — Remove dotfiles symlinks

Talk to the user in the user's language.

Remove the symlinks created by dotfiles and restore the pre-installation state.
This does not simply revert backups; it goes through a compare-and-merge process so that settings changed while using dotfiles are not lost.

## Prerequisites

- Check that the current directory is `~/dotfiles` (or the dotfiles repo root)

## Step 1: Check current state

```bash
bash .claude/skills/setup/scripts/verify.sh
```

Identify the symlinked items.

## Step 2: User confirmation

Confirm the scope with AskUserQuestion:

- **Full removal**: remove all dotfiles symlinks
- **Selective removal**: select specific tools to remove (claude, codex, gemini, shell)

## Step 3: Compare changes

**This step is the core.** For each item that has an original saved in the `backup/` folder, check the changes made to `config/` files during the period dotfiles was in use.

Backups are stored under `dotfiles/backup/`, mirroring the home directory structure:
- `backup/.zshrc` — `~/.zshrc` from before installation
- `backup/.claude/settings.json` — `~/.claude/settings.json` from before installation
- and so on

For each backup file:

1. Read the `backup/` file (pre-installation original) and the corresponding `config/` file (current settings)

2. Compare the two files and analyze the differences:
   - Example: `backup/.zshrc` vs `config/terminal/zsh/zshrc`
   - Example: `backup/.claude/settings.json` vs `config/ai/claude/settings.base.json`

3. If there are differences, show them to the user and ask for a choice:

   **If there are no differences:**
   Tell the user the original and current settings are identical, so the original will be restored.

   **If there are differences:**
   Show a summary of what changed and use AskUserQuestion:
   - **Restore original**: revert to the pre-installation file as is (changes made in dotfiles are lost)
   - **Keep current settings**: remove only the symlink, and copy the `config/` file content into a real file
   - **Merge**: show the differences between the two files and let the user choose which parts to keep

4. For items without a backup, remove only the symlink (the tool will use its defaults)

## Step 4: Remove symlinks and restore

Process each item according to the method the user decided in Step 3:

- Items where **Restore original** was chosen:
  ```bash
  bash .claude/skills/uninstall/scripts/unlink.sh <도구> --restore
  ```

- Items where **Keep current settings** was chosen:
  ```bash
  bash .claude/skills/uninstall/scripts/unlink.sh <도구> --keep
  ```

- **Remove symlink only** (no backup):
  ```bash
  bash .claude/skills/uninstall/scripts/unlink.sh <도구> --remove-only
  ```

- Items where **Merge** was chosen:
  Work through it with the user to produce a file that combines the `backup/` original and the current `config/` settings, and save it at the corresponding location.

## Step 5: Report results

Summarize the results per item:
- Items restored to the original
- Items where current settings were kept
- Merged items
- Items where only the symlink was removed (no backup)

> **Note**: do not delete the `config/` directory. The user's settings are preserved as is.
> The `backup/` folder also remains. It can be deleted manually if not needed.
> To reinstall, run `/setup`.
