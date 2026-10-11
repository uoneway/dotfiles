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
source "$(dirname "$0")/machine-config.sh"

instruction_source() {
  local base="$1" label="$2" name extra source_file output tmp
  name="$(dotfiles_machine_name)"
  extra="$(dotfiles_machine_extra "$name" agents_addition)"
  if [ -z "$extra" ]; then
    printf '%s\n' "$base"
    return
  fi
  source_file="$CONFIG/ai/agents-additions/$extra"
  [ -f "$source_file" ] || { echo "[error] agents addition not found: $source_file" >&2; return 1; }
  output="$HOME/.local/state/dotfiles/AGENTS.$label.md"
  mkdir -p "$(dirname "$output")"
  tmp="$(mktemp "$output.XXXXXX")"
  { cat "$base"; printf '\n'; cat "$source_file"; } > "$tmp"
  mv "$tmp" "$output"
  printf '%s\n' "$output"
}

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

link_instruction() {
  local src
  src="$(instruction_source "$1" "$2")" || return 1
  backup_and_link "$src" "$3"
}

version_at_least() {
  local version="$1" required="$2"
  local v_major v_minor v_patch r_major r_minor r_patch
  IFS=. read -r v_major v_minor v_patch <<EOF
$version
EOF
  IFS=. read -r r_major r_minor r_patch <<EOF
$required
EOF
  [ "$v_major" -gt "$r_major" ] ||
    { [ "$v_major" -eq "$r_major" ] && [ "$v_minor" -gt "$r_minor" ]; } ||
    { [ "$v_major" -eq "$r_major" ] && [ "$v_minor" -eq "$r_minor" ] && [ "$v_patch" -ge "$r_patch" ]; }
}

require_claude_agents_md_support() {
  command -v claude >/dev/null 2>&1 || return 0
  local version
  version="$(claude --version 2>/dev/null)"
  version="${version%% *}"
  case "$version" in
    [0-9]*.[0-9]*.[0-9]*)
      if ! version_at_least "$version" "2.1.277"; then
        echo "  [error] Claude Code 2.1.277+ is required for AGENTS.md (installed: $version)"
        return 1
      fi
      ;;
    *) echo "  [warn] Could not determine Claude Code version; AGENTS.md requires 2.1.277+" ;;
  esac
}

remove_legacy_claude_link() {
  local dst="$HOME/.claude/CLAUDE.md" target
  if [ -L "$dst" ]; then
    target="$(readlink "$dst")"
    case "$target" in
      "$CONFIG"/*)
        rm "$dst"
        echo "  [clean] legacy managed link removed: $dst"
        ;;
      *) echo "  [warn] $dst is not managed by dotfiles — left unchanged" ;;
    esac
  elif [ -e "$dst" ]; then
    echo "  [warn] $dst is a user file — left unchanged"
  fi
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

# 예전 배포 위치에 남은 config 스킬 정리. config가 관리하는 이름만 다루며,
# 심링크는 지우고 실디렉토리(과거 복사본)는 backup/으로 옮긴다. 다른 항목은 건드리지 않는다.
retire_skill_dir() {
  local legacy="$1"; shift
  [ -d "$legacy" ] || return 0
  local src skill name entry rel_path
  for src in "$@"; do
    [ -d "$src" ] || continue
    for skill in "$src"/*/; do
      skill="${skill%/}"
      [ -f "$skill/SKILL.md" ] || continue
      name="$(basename "$skill")"
      entry="$legacy/$name"
      if [ -L "$entry" ]; then
        rm "$entry"
        echo "  [clean] legacy skill link removed: $entry"
      elif [ -d "$entry" ]; then
        rel_path="${entry#$HOME/}"
        mkdir -p "$(dirname "$BACKUP/$rel_path")"
        rm -rf "$BACKUP/$rel_path"
        mv "$entry" "$BACKUP/$rel_path"
        echo "  [backup] legacy skill copy $entry -> backup/$rel_path"
      fi
    done
  done
  # 소스가 사라진 config 관리 심링크도 정리한다.
  for entry in "$legacy"/*; do
    [ -L "$entry" ] || continue
    case "$(readlink "$entry")" in
      "$CONFIG"/*) rm "$entry"; echo "  [clean] legacy skill link removed: $entry" ;;
    esac
  done
}

# config/ai/codex/disabled-system-skills에 적힌 Codex 내장 스킬을 끈다(한 줄에 이름 하나, # 주석).
# 내장 스킬 경로가 머신마다 달라 base 병합이 아니라 여기서 [[skills.config]] 항목을 보장한다.
# 이미 같은 path 항목이 있으면 사용자가 바꾼 enabled 값을 그대로 둔다.
disable_codex_system_skills() {
  local list="$CONFIG/ai/codex/disabled-system-skills" cfg="$HOME/.codex/config.toml" name path
  [ -f "$list" ] && [ -f "$cfg" ] || return 0
  while IFS= read -r name; do
    name="${name%%#*}"; name="$(echo "$name" | tr -d '[:space:]')"
    [ -n "$name" ] || continue
    path="$HOME/.codex/skills/.system/$name/SKILL.md"
    grep -Fq "path = \"$path\"" "$cfg" && continue
    printf '\n[[skills.config]]\npath = "%s"\nenabled = false\n' "$path" >> "$cfg"
    echo "  [ok] disabled Codex system skill: $name"
  done < "$list"
}

echo "--- $TOOL ---"

case "$TOOL" in
  claude)
    mkdir -p "$HOME/.claude"
    require_claude_agents_md_support
    # settings.json은 심링크가 아니라 병합: Claude Code가 런타임에 머신 상태를 쓰는 파일이라
    # 심링크하면 머신 간 충돌이 남. base 키만 교체하고 나머지(hooks 등)는 보존한다.
    [ -f "$CONFIG/ai/claude/settings.base.json" ] && bash "$(cd "$(dirname "$0")" && pwd)/merge-claude-settings.sh"
    [ -f "$CONFIG/ai/claude/statusline-command.sh" ] && backup_and_link "$CONFIG/ai/claude/statusline-command.sh" "$HOME/.claude/statusline-command.sh"
    # 선택 항목: config에 존재할 때만 링크
    [ -f "$CONFIG/ai/claude/keybindings.json" ] && backup_and_link "$CONFIG/ai/claude/keybindings.json" "$HOME/.claude/keybindings.json"
    [ -d "$CONFIG/ai/claude/output-styles" ] && backup_and_link_dir "$CONFIG/ai/claude/output-styles" "$HOME/.claude/output-styles"
    [ -d "$CONFIG/ai/claude/commands" ] && backup_and_link_dir "$CONFIG/ai/claude/commands" "$HOME/.claude/commands"
    if [ "$MODE" = "--unified" ]; then
      if [ -f "$CONFIG/ai/AGENTS.md" ]; then
        link_instruction "$CONFIG/ai/AGENTS.md" unified "$HOME/AGENTS.md"
        remove_legacy_claude_link
      fi
    elif [ -f "$CONFIG/ai/claude/AGENTS.md" ]; then
      link_instruction "$CONFIG/ai/claude/AGENTS.md" claude "$HOME/AGENTS.md"
      remove_legacy_claude_link
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
      [ -f "$CONFIG/ai/AGENTS.md" ] && link_instruction "$CONFIG/ai/AGENTS.md" unified "$HOME/.codex/AGENTS.md"
    else
      [ -f "$CONFIG/ai/codex/AGENTS.md" ] && link_instruction "$CONFIG/ai/codex/AGENTS.md" codex "$HOME/.codex/AGENTS.md"
    fi
    [ -d "$CONFIG/ai/codex/rules" ] && backup_and_link_dir "$CONFIG/ai/codex/rules" "$HOME/.codex/rules"
    # 선택 항목: config에 존재할 때만 링크
    [ -d "$CONFIG/ai/codex/prompts" ] && backup_and_link_dir "$CONFIG/ai/codex/prompts" "$HOME/.codex/prompts"
    # Codex는 user-level 스킬을 도구 중립 경로 ~/.agents/skills에서 읽는다 (npx skills 서드파티와 공존).
    # 예전 위치 ~/.codex/skills에 남은 config 스킬은 중복 노출을 막기 위해 정리한다. .system 등은 그대로 둔다.
    link_skills "$HOME/.agents/skills" "$CONFIG/ai/skills" "$CONFIG/ai/codex/skills"
    retire_skill_dir "$HOME/.codex/skills" "$CONFIG/ai/skills" "$CONFIG/ai/codex/skills"
    disable_codex_system_skills
    ;;
  gemini)
    mkdir -p "$HOME/.gemini"
    [ -f "$CONFIG/ai/gemini/settings.json" ] && backup_and_link "$CONFIG/ai/gemini/settings.json" "$HOME/.gemini/settings.json"
    if [ "$MODE" = "--unified" ]; then
      [ -f "$CONFIG/ai/AGENTS.md" ] && link_instruction "$CONFIG/ai/AGENTS.md" unified "$HOME/.gemini/GEMINI.md"
    else
      [ -f "$CONFIG/ai/gemini/GEMINI.md" ] && link_instruction "$CONFIG/ai/gemini/GEMINI.md" gemini "$HOME/.gemini/GEMINI.md"
    fi
    link_skills "$HOME/.gemini/skills" "$CONFIG/ai/skills"
    ;;
  *)
    echo "  [error] Unknown tool: $TOOL (expected claude, codex, or gemini)"
    exit 1
    ;;
esac
