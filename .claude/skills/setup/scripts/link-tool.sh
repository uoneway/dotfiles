#!/bin/bash
# link-tool.sh — AI 도구별 심링크 생성
# Usage: bash link-tool.sh <claude|codex|gemini> [--unified|--separate]
#   --unified:  config/ai/AGENTS.md 하나로 모든 도구의 인스트럭션을 공유 (기본값)
#   --separate: 각 도구 폴더의 개별 인스트럭션 파일 사용
set -e

DOTFILES="$(cd "$(dirname "$0")/../../../../" && pwd)"
CONFIG="$DOTFILES/config"
BACKUP="$DOTFILES/backup"
TOOL="${1:?Usage: link-tool.sh <claude|codex|gemini> [--unified|--separate]}"
MODE="${2:---unified}"

backup_and_link() {
  local src="$1" dst="$2"
  local rel_path="${dst#$HOME/}"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ]; then
    rm "$dst"
  elif [ -e "$dst" ]; then
    mkdir -p "$(dirname "$BACKUP/$rel_path")"
    cp -a "$dst" "$BACKUP/$rel_path"
    rm "$dst"
    echo "  [backup] $dst -> backup/$rel_path"
  fi
  ln -sf "$src" "$dst"
  echo "  [ok] $dst -> $src"
}

backup_and_link_dir() {
  local src="$1" dst="$2"
  local rel_path="${dst#$HOME/}"
  if [ -L "$dst" ]; then
    rm "$dst"
  elif [ -d "$dst" ]; then
    mkdir -p "$(dirname "$BACKUP/$rel_path")"
    cp -a "$dst" "$BACKUP/$rel_path"
    rm -rf "$dst"
    echo "  [backup] $dst -> backup/$rel_path"
  fi
  ln -sfn "$src" "$dst"
  echo "  [ok] $dst -> $src"
}

# 스킬 디렉토리 구성: 대상은 실디렉토리로 만들고, 소스(공용 + 도구 전용)의 스킬을
# per-skill 심링크로 합친다. 디렉토리 통째 심링크가 아닌 이유: 도구마다 공용/전용
# 조합이 다르고, npx skills 등이 설치하는 서드파티 스킬과 공존해야 하기 때문.
link_skills() {
  local dst="$1"; shift
  if [ -L "$dst" ]; then
    rm "$dst"
    echo "  [ok] Converted $dst from dir-symlink to real dir"
  fi
  mkdir -p "$dst"
  # 소스가 사라진 config 관리 심링크 정리 (스킬 삭제/이동 반영)
  local link tgt
  for link in "$dst"/*; do
    [ -L "$link" ] || continue
    tgt="$(readlink "$link")"
    case "$tgt" in
      "$CONFIG"/*)
        [ -e "$tgt" ] || { rm "$link"; echo "  [clean] stale skill link removed: $(basename "$link")"; } ;;
    esac
  done
  local src skill name n=0
  for src in "$@"; do
    [ -d "$src" ] || continue
    for skill in "$src"/*/; do
      skill="${skill%/}"
      [ -f "$skill/SKILL.md" ] || continue
      name="$(basename "$skill")"
      if [ -e "$dst/$name" ] && [ ! -L "$dst/$name" ]; then
        echo "  [warn] $dst/$name is a real directory — skipped (config로 옮기거나 지운 뒤 재실행)"
        continue
      fi
      ln -sfn "$skill" "$dst/$name"
      n=$((n+1))
    done
  done
  echo "  [ok] skills: $n linked into $dst"
}

echo "--- $TOOL ---"

case "$TOOL" in
  claude)
    mkdir -p "$HOME/.claude"
    # settings.json은 심링크가 아니라 병합: Claude Code가 런타임에 머신 상태를 쓰는 파일이라
    # 심링크하면 머신 간 충돌이 남. base 키만 교체하고 나머지(hooks 등)는 보존한다.
    [ -f "$CONFIG/ai/claude/settings.base.json" ] && bash "$(cd "$(dirname "$0")" && pwd)/merge-claude-settings.sh"
    [ -f "$CONFIG/ai/claude/statusline-command.sh" ] && backup_and_link "$CONFIG/ai/claude/statusline-command.sh" "$HOME/.claude/statusline-command.sh"
    # 선택 항목: config에 존재할 때만 링크
    [ -f "$CONFIG/ai/claude/keybindings.json" ] && backup_and_link "$CONFIG/ai/claude/keybindings.json" "$HOME/.claude/keybindings.json"
    [ -d "$CONFIG/ai/claude/output-styles" ] && backup_and_link_dir "$CONFIG/ai/claude/output-styles" "$HOME/.claude/output-styles"
    [ -d "$CONFIG/ai/claude/commands" ] && backup_and_link_dir "$CONFIG/ai/claude/commands" "$HOME/.claude/commands"
    if [ "$MODE" = "--unified" ]; then
      [ -f "$CONFIG/ai/AGENTS.md" ] && backup_and_link "$CONFIG/ai/AGENTS.md" "$HOME/.claude/CLAUDE.md"
    else
      [ -f "$CONFIG/ai/claude/CLAUDE.md" ] && backup_and_link "$CONFIG/ai/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
    fi
    link_skills "$HOME/.claude/skills" "$CONFIG/ai/skills" "$CONFIG/ai/claude/skills"
    [ -d "$CONFIG/ai/claude/agents" ] && backup_and_link_dir "$CONFIG/ai/claude/agents" "$HOME/.claude/agents"
    ;;
  codex)
    mkdir -p "$HOME/.codex"
    # config.toml은 심링크가 아니라 병합: codex가 런타임에 머신 상태를 쓰는 파일이라
    # 심링크하면 머신 간 충돌이 남. base 키만 교체하고 나머지는 보존한다.
    [ -f "$CONFIG/ai/codex/config.base.toml" ] && bash "$(cd "$(dirname "$0")" && pwd)/merge-codex-config.sh"
    if [ "$MODE" = "--unified" ]; then
      [ -f "$CONFIG/ai/AGENTS.md" ] && backup_and_link "$CONFIG/ai/AGENTS.md" "$HOME/.codex/AGENTS.md"
    else
      [ -f "$CONFIG/ai/codex/AGENTS.md" ] && backup_and_link "$CONFIG/ai/codex/AGENTS.md" "$HOME/.codex/AGENTS.md"
    fi
    [ -d "$CONFIG/ai/codex/rules" ] && backup_and_link_dir "$CONFIG/ai/codex/rules" "$HOME/.codex/rules"
    # 선택 항목: config에 존재할 때만 링크
    [ -d "$CONFIG/ai/codex/prompts" ] && backup_and_link_dir "$CONFIG/ai/codex/prompts" "$HOME/.codex/prompts"
    link_skills "$HOME/.codex/skills" "$CONFIG/ai/skills" "$CONFIG/ai/codex/skills"
    ;;
  gemini)
    mkdir -p "$HOME/.gemini"
    [ -f "$CONFIG/ai/gemini/settings.json" ] && backup_and_link "$CONFIG/ai/gemini/settings.json" "$HOME/.gemini/settings.json"
    if [ "$MODE" = "--unified" ]; then
      [ -f "$CONFIG/ai/AGENTS.md" ] && backup_and_link "$CONFIG/ai/AGENTS.md" "$HOME/.gemini/GEMINI.md"
    else
      [ -f "$CONFIG/ai/gemini/GEMINI.md" ] && backup_and_link "$CONFIG/ai/gemini/GEMINI.md" "$HOME/.gemini/GEMINI.md"
    fi
    link_skills "$HOME/.gemini/skills" "$CONFIG/ai/skills"
    ;;
  *)
    echo "  [error] Unknown tool: $TOOL (expected claude, codex, or gemini)"
    exit 1
    ;;
esac
