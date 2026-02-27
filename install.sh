#!/bin/bash
# dotfiles installer
# Detects installed AI tools and shell, symlinks config/ to the right places.
# First run copies templates/ → config/ as a starting point.
set -e

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$DOTFILES/config"
TEMPLATES="$DOTFILES/templates"

# ============================================================
# Helpers
# ============================================================

info()  { echo "  $1"; }
ok()    { echo "  [ok] $1"; }
skip()  { echo "  [skip] $1"; }

link_file() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ]; then
    rm "$dst"
  elif [ -e "$dst" ]; then
    info "backup: $dst -> ${dst}.bak"
    mv "$dst" "${dst}.bak"
  fi
  ln -sf "$src" "$dst"
  ok "$dst -> $src"
}

link_dir() {
  local src="$1" dst="$2"
  if [ -L "$dst" ]; then
    rm "$dst"
  elif [ -d "$dst" ]; then
    info "backup: $dst -> ${dst}.bak"
    mv "$dst" "${dst}.bak"
  fi
  ln -sfn "$src" "$dst"
  ok "$dst -> $src"
}

# ============================================================
# First run: copy templates → config
# ============================================================

if [ ! -d "$CONFIG/shell" ] && [ ! -d "$CONFIG/claude" ] && [ ! -d "$CONFIG/codex" ]; then
  echo ""
  echo "First run detected. Copying templates to config/..."
  echo "Edit config/ files to customize your setup."
  echo ""
  cp -r "$TEMPLATES"/* "$CONFIG/"
fi

# ============================================================
# Detect tools and shell
# ============================================================

detect_shell() {
  case "$SHELL" in
    */zsh)  echo "zsh" ;;
    */bash) echo "bash" ;;
    *)      echo "zsh" ;;  # default
  esac
}

HAS_CLAUDE=false; command -v claude &>/dev/null && HAS_CLAUDE=true
HAS_CODEX=false;  command -v codex  &>/dev/null && HAS_CODEX=true
HAS_GEMINI=false; command -v gemini &>/dev/null && HAS_GEMINI=true
USER_SHELL="$(detect_shell)"

echo ""
echo "=== dotfiles installer ==="
echo "  shell:  $USER_SHELL"
echo "  claude: $HAS_CLAUDE"
echo "  codex:  $HAS_CODEX"
echo "  gemini: $HAS_GEMINI"
echo ""

# ============================================================
# Shell
# ============================================================

echo "--- shell ---"

if [ "$USER_SHELL" = "zsh" ]; then
  if [ -f "$CONFIG/shell/zshrc" ]; then
    link_file "$CONFIG/shell/zshrc" "$HOME/.zshrc"
    mkdir -p "$HOME/.zshrc.d"
    if [ -d "$CONFIG/shell/zshrc.d" ]; then
      for f in "$CONFIG/shell/zshrc.d"/*.zsh; do
        [ -f "$f" ] && link_file "$f" "$HOME/.zshrc.d/$(basename "$f")"
      done
    fi
  else
    skip "config/shell/zshrc not found"
  fi
elif [ "$USER_SHELL" = "bash" ]; then
  if [ -f "$CONFIG/shell/bashrc" ]; then
    link_file "$CONFIG/shell/bashrc" "$HOME/.bashrc"
    mkdir -p "$HOME/.bashrc.d"
    if [ -d "$CONFIG/shell/bashrc.d" ]; then
      for f in "$CONFIG/shell/bashrc.d"/*.bash; do
        [ -f "$f" ] && link_file "$f" "$HOME/.bashrc.d/$(basename "$f")"
      done
    fi
  else
    skip "config/shell/bashrc not found"
  fi
fi
echo ""

# ============================================================
# Claude Code (~/.claude/)
# ============================================================

if $HAS_CLAUDE; then
  echo "--- claude ---"
  mkdir -p "$HOME/.claude"
  [ -f "$CONFIG/claude/settings.json" ] && link_file "$CONFIG/claude/settings.json" "$HOME/.claude/settings.json"
  [ -f "$CONFIG/CLAUDE.md" ]            && link_file "$CONFIG/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  [ -d "$CONFIG/claude/skills" ]        && link_dir  "$CONFIG/claude/skills" "$HOME/.claude/skills"
  [ -d "$CONFIG/claude/agents" ]        && link_dir  "$CONFIG/claude/agents" "$HOME/.claude/agents"
  echo ""
fi

# ============================================================
# Codex CLI (~/.codex/)
# ============================================================

if $HAS_CODEX; then
  echo "--- codex ---"
  mkdir -p "$HOME/.codex"
  [ -f "$CONFIG/codex/config.toml" ] && link_file "$CONFIG/codex/config.toml" "$HOME/.codex/config.toml"
  [ -f "$CONFIG/AGENTS.md" ]         && link_file "$CONFIG/AGENTS.md" "$HOME/.codex/AGENTS.md"
  [ -d "$CONFIG/codex/rules" ]       && link_dir  "$CONFIG/codex/rules" "$HOME/.codex/rules"
  echo ""
fi

# ============================================================
# Gemini CLI (~/.gemini/)
# ============================================================

if $HAS_GEMINI; then
  echo "--- gemini ---"
  mkdir -p "$HOME/.gemini"
  [ -f "$CONFIG/gemini/settings.json" ] && link_file "$CONFIG/gemini/settings.json" "$HOME/.gemini/settings.json"
  [ -f "$CONFIG/GEMINI.md" ]            && link_file "$CONFIG/GEMINI.md" "$HOME/.gemini/GEMINI.md"
  echo ""
fi

# ============================================================
# Done
# ============================================================

echo "=== Done! ==="
if [ "$USER_SHELL" = "zsh" ]; then
  echo "Run 'source ~/.zshrc' or open a new terminal."
else
  echo "Run 'source ~/.bashrc' or open a new terminal."
fi
