#!/usr/bin/env bash
# 用 bash 安装 / 清理 skills
#   用法:
#     ./install.sh            # 默认先 cleanup 再 install
#     ./install.sh install    # 复制 skills/ 到 INSTALL_DIRS（先把目标同名目录全部删除，再复制）
#     ./install.sh cleanup    # 删除安装目录里已过期的 skill
#     ./install.sh help

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$ROOT/skills"

INSTALL_DIRS=(
  "~/.agents/skills"
  "~/.codebuddy/skills"
  "~/.workbuddy/skills"
  "~/.dsh/skills"
)

# 手动配置的旧 skill 名称：即使源里还有，也强制清理（留空则仅按源清单自动清理）
STALE_SKILLS=(
  g-commit-code
  xlsx
  docx
  pptx
  pdf
  research
  ladder
  show-me
  create-prd
  big-pics-little-words
)

expand() {
  case "$1" in
    "~") echo "$HOME" ;;
    "~/"*) echo "$HOME/${1#\~/}" ;;
    *) echo "$1" ;;
  esac
}

list_skill_dirs() {
  [[ -d "$1" ]] || return 0
  local entry
  for entry in "$1"/*/; do
    [[ -d "$entry" ]] || continue
    basename "$entry"
  done
}

is_stale() {
  local name="$1" known stale
  for known in $SOURCE_SKILLS; do
    [[ "$known" == "$name" ]] || continue
    for stale in "${STALE_SKILLS[@]}"; do
      [[ "$stale" == "$name" ]] && return 0
    done
    return 1
  done
  return 0
}

install() {
  if [[ -z "$SOURCE_SKILLS" ]]; then
    echo "未找到任何 skill：$SKILLS_SRC" >&2
    exit 1
  fi

  local raw dir name src dest
  for raw in "${INSTALL_DIRS[@]}"; do
    dir="$(expand "$raw")"
    mkdir -p "$dir"

    # 先删除所有待安装的同名目录
    for name in $SOURCE_SKILLS; do
      rm -rf "$dir/$name"
    done

    # 再统一复制
    for name in $SOURCE_SKILLS; do
      src="$SKILLS_SRC/$name"
      dest="$dir/$name"

      cp -R "$src" "$dest"
      echo "安装 $name -> $dir"
    done
  done
  echo "安装完成！"
}

cleanup() {
  local removed=0
  local raw dir name
  for raw in "${INSTALL_DIRS[@]}"; do
    dir="$(expand "$raw")"
    for name in $(list_skill_dirs "$dir"); do
      is_stale "$name" || continue

      rm -rf "$dir/$name"
      echo "清理 $name <- $dir"
      removed=$((removed + 1))
    done
  done

  if [[ $removed -gt 0 ]]; then
    echo "清理完成，共删除 $removed 个 skill"
  else
    echo "没有需要清理的 skill"
  fi
}

SOURCE_SKILLS="$(list_skill_dirs "$SKILLS_SRC")"

case "${1:-all}" in
  all)
    cleanup
    install
    ;;
  install) install ;;
  cleanup) cleanup ;;
  help | *)
    echo "用法: ./install.sh [install|cleanup|help]"
    echo "  无参数   先 cleanup 再 install（默认）"
    echo "  install  只复制 skills/ 到 INSTALL_DIRS（先删除目标同名目录，再复制）"
    echo "  cleanup  只删除安装目录里已过期的 skill"
    ;;
esac
