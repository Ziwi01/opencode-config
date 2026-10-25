#!/usr/bin/env bash
set -euo pipefail

CHANGED=0
UPDATE=1
CFG=""

usage() {
  cat <<'EOF'
Usage: install.sh [--config-dir DIR] [--no-update]

Links the shared OpenCode config into DIR (default: $XDG_CONFIG_HOME/opencode,
else ~/.config/opencode). Prints "changed" or "ok" as the last line.

  --config-dir DIR  target config directory
  --no-update       skip cloning, updating and pruning vendor repositories
  -h, --help        show this help
EOF
}

die() {
  echo "install.sh: $*" >&2
  exit 1
}

warn() {
  echo "install.sh: warning: $*" >&2
}

while (($#)); do
  case "$1" in
    --config-dir)
      [[ $# -ge 2 ]] || die "--config-dir needs a value"
      CFG="$2"
      shift 2
      ;;
    --no-update)
      UPDATE=0
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "install.sh: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

for dep in git jq; do
  command -v "$dep" >/dev/null 2>&1 || die "required command not found: $dep"
done

REPO="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
if [[ -z "$CFG" ]]; then
  CFG="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
fi
CFG="$(readlink -m "$CFG")"
STATE="$CFG/.opencode-config.state"

state_get() {
  [[ -f "$STATE" ]] || return 0
  awk -v n="$1" '$1 == n { print $2 }' "$STATE"
}

state_del() {
  [[ -f "$STATE" ]] || return 0
  grep -q "^$1 " "$STATE" || return 0
  local tmp="$STATE.tmp.$$"
  { grep -v "^$1 " "$STATE" || true; } >"$tmp"
  mv "$tmp" "$STATE"
}

state_set() {
  [[ "$(state_get "$1")" == "$2" ]] && return 0
  local tmp="$STATE.tmp.$$"
  if [[ -f "$STATE" ]]; then
    { grep -v "^$1 " "$STATE" || true; } >"$tmp"
  else
    : >"$tmp"
  fi
  echo "$1 $2" >>"$tmp"
  mv "$tmp" "$STATE"
}

hash_of() {
  sha256sum "$1" | awk '{ print $1 }'
}

backup() {
  local target="$1" base n=0 dest
  base="$target.bak-$(date +%Y%m%d%H%M%S)"
  dest="$base"
  while [[ -e "$dest" || -L "$dest" ]]; do
    n=$((n + 1))
    dest="$base.$n"
  done
  mv "$target" "$dest"
  warn "$target was edited or not created by this installer; moved to $dest"
  CHANGED=1
}

validate_json() {
  jq empty "$1" >/dev/null 2>&1 || die "invalid JSON in $1"
}

link_shared() {
  mkdir -p "$CFG"
  if [[ -L "$CFG/shared" ]]; then
    if [[ "$(readlink "$CFG/shared")" != "$REPO" ]]; then
      ln -sfn "$REPO" "$CFG/shared"
      CHANGED=1
    fi
  elif [[ -e "$CFG/shared" ]]; then
    die "$CFG/shared exists and is not a symlink; move it away first"
  else
    ln -s "$REPO" "$CFG/shared"
    CHANGED=1
  fi
}

link_entries() {
  local d src name link want cur
  shopt -s nullglob
  for d in agents commands plugins; do
    for src in "$REPO/$d"/*; do
      name="$(basename "$src")"
      link="$CFG/$d/$name"
      want="$CFG/shared/$d/$name"
      if [[ -L "$link" ]]; then
        cur="$(readlink "$link")"
        [[ "$cur" == "$want" ]] && continue
        if [[ "$cur" == "$CFG/shared/"* ]]; then
          ln -sfn "$want" "$link"
          CHANGED=1
        else
          warn "$link points elsewhere; skipped"
        fi
      elif [[ -e "$link" ]]; then
        warn "$link exists and is not a symlink; skipped"
      else
        mkdir -p "$CFG/$d"
        ln -s "$want" "$link"
        CHANGED=1
      fi
    done
    for link in "$CFG/$d"/*; do
      [[ -L "$link" && ! -e "$link" ]] || continue
      if [[ "$(readlink "$link")" == "$CFG/shared/"* ]]; then
        rm "$link"
        CHANGED=1
      fi
    done
  done
  shopt -u nullglob
}

sync_vendor() {
  local file line name url ref dir d
  local -A wanted=()
  mkdir -p "$REPO/vendor"
  for file in "$REPO/skill-repos.txt" "$CFG/skill-repos.local.txt"; do
    [[ -f "$file" ]] || continue
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      name="" url="" ref=""
      read -r name url ref <<<"$line"
      [[ -n "$name" ]] || continue
      if [[ -z "$url" || "$name" == */* || "$name" == .* ]]; then
        warn "bad line in $file: $line"
        continue
      fi
      wanted[$name]=1
      dir="$REPO/vendor/$name"
      if [[ -d "$dir/.git" ]]; then
        if ! git -C "$dir" fetch -q --depth 1 origin "${ref:-HEAD}" 2>/dev/null; then
          warn "could not update $name"
          continue
        fi
        if [[ "$(git -C "$dir" rev-parse HEAD)" != "$(git -C "$dir" rev-parse FETCH_HEAD)" ]]; then
          git -C "$dir" reset -q --hard FETCH_HEAD
          CHANGED=1
        fi
      else
        rm -rf "$dir"
        if git clone -q --depth 1 ${ref:+--branch "$ref"} "$url" "$dir" 2>/dev/null; then
          CHANGED=1
        else
          rm -rf "$dir"
          warn "could not clone $name from $url"
        fi
      fi
    done <"$file"
  done
  for d in "$REPO/vendor"/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    if [[ -z "${wanted[$name]:-}" ]]; then
      rm -rf "${d%/}"
      CHANGED=1
    fi
  done
}

write_config() {
  local name="$1" shared local_f target want tmp h rec
  shared="$REPO/$name.json"
  local_f="$CFG/$name.local.json"
  target="$CFG/$name.json"
  want="$CFG/shared/$name.json"

  if [[ -d "$target" && ! -L "$target" ]]; then
    die "$target is a directory"
  fi

  if [[ ! -f "$local_f" ]]; then
    if [[ -L "$target" ]]; then
      if [[ "$(readlink "$target")" != "$want" ]]; then
        ln -sfn "$want" "$target"
        CHANGED=1
      fi
    else
      if [[ -f "$target" ]]; then
        if [[ "$(hash_of "$target")" == "$(state_get "$name.json")" ]]; then
          rm "$target"
        else
          backup "$target"
        fi
      fi
      ln -s "$want" "$target"
      CHANGED=1
    fi
    state_del "$name.json"
    return 0
  fi

  tmp="$CFG/.$name.json.tmp.$$"
  jq -n --slurpfile a "$shared" --slurpfile b "$local_f" -L "$REPO/lib" \
    'include "merge"; merge($a[0]; $b[0])' | jq . >"$tmp"
  h="$(hash_of "$tmp")"
  if [[ -f "$target" && ! -L "$target" ]]; then
    if [[ "$(hash_of "$target")" == "$h" ]]; then
      rm "$tmp"
      state_set "$name.json" "$h"
      return 0
    fi
    rec="$(state_get "$name.json")"
    if [[ "$(hash_of "$target")" != "$rec" ]]; then
      backup "$target"
    fi
  fi
  mv -T "$tmp" "$target"
  state_set "$name.json" "$h"
  CHANGED=1
}

validate_json "$REPO/opencode.json"
validate_json "$REPO/cli.json"
for f in "$CFG/opencode.local.json" "$CFG/cli.local.json"; do
  [[ ! -f "$f" ]] || validate_json "$f"
done

link_shared
link_entries
if ((UPDATE)); then
  sync_vendor
fi
write_config opencode
write_config cli

if ((CHANGED)); then
  echo changed
else
  echo ok
fi
