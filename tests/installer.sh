# shellcheck shell=bash disable=SC2329
# Installer tests, sourced by tests/run.sh (uses $REPO, $TMP, assert_eq).
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

mkfix() {
  local fx="$1"
  mkdir -p "$fx/skills" "$fx/agents" "$fx/commands" "$fx/plugins"
  cp "$REPO/install.sh" "$fx/install.sh"
  cp -r "$REPO/lib" "$fx/lib"
  echo '# stub' >"$fx/AGENTS.md"
  echo '{"model":"a/b","plugins":["p1"]}' >"$fx/opencode.json"
  echo '{}' >"$fx/cli.json"
  : >"$fx/skill-repos.txt"
}

inst() {
  bash "$FX/install.sh" --config-dir "$TMP/cfg" "$@"
}

setup_fx() {
  FX="$TMP/fx"
  CFG="$TMP/cfg"
  mkfix "$FX"
}

last_line() {
  tail -n1 <<<"$1"
}

snapshot() {
  find "$CFG" -printf '%p %T@ %l %s\n' | sort
}

mkbare() {
  mkdir -p "$TMP/work"
  git -c init.defaultBranch=main init -q "$TMP/work"
  echo one >"$TMP/work/SKILL.md"
  git -C "$TMP/work" add -A
  git -C "$TMP/work" commit -q -m one
  git clone -q --bare "$TMP/work" "$TMP/bare.git"
}

test_first_run_links() {
  setup_fx
  out=$(inst)
  assert_eq "$FX" "$(readlink "$CFG/shared")" shared
  assert_eq "$CFG/shared/opencode.json" "$(readlink "$CFG/opencode.json")" opencode.json
  assert_eq "$CFG/shared/cli.json" "$(readlink "$CFG/cli.json")" cli.json
  assert_eq changed "$(last_line "$out")"
}

test_second_run_ok() {
  setup_fx
  inst >/dev/null
  before=$(snapshot)
  out=$(inst)
  assert_eq ok "$(last_line "$out")"
  assert_eq "$before" "$(snapshot)" snapshot
}

test_local_override_merges() {
  setup_fx
  inst >/dev/null
  echo '{"model":"m"}' >"$CFG/opencode.local.json"
  out=$(inst)
  assert_eq changed "$(last_line "$out")"
  [[ -f "$CFG/opencode.json" && ! -L "$CFG/opencode.json" ]]
  assert_eq m "$(jq -r .model "$CFG/opencode.json")"
  assert_eq p1 "$(jq -r '.plugins[0]' "$CFG/opencode.json")"
  assert_eq "opencode.json $(sha256sum "$CFG/opencode.json" | cut -d' ' -f1)" \
    "$(grep '^opencode.json ' "$CFG/.opencode-config.state")"
  assert_eq ok "$(last_line "$(inst)")"
}

test_local_removed_restores_symlink() {
  setup_fx
  mkdir -p "$CFG"
  echo '{"model":"m"}' >"$CFG/opencode.local.json"
  inst >/dev/null
  rm "$CFG/opencode.local.json"
  out=$(inst)
  assert_eq changed "$(last_line "$out")"
  assert_eq "$CFG/shared/opencode.json" "$(readlink "$CFG/opencode.json")"
  ! grep -q '^opencode.json ' "$CFG/.opencode-config.state"
}

test_preexisting_file_backed_up() {
  setup_fx
  mkdir -p "$CFG"
  echo '{"mine":true}' >"$CFG/opencode.json"
  inst >"$TMP/out" 2>"$TMP/err"
  assert_eq changed "$(last_line "$(cat "$TMP/out")")"
  grep -q 'opencode.json.bak-' "$TMP/err"
  compgen -G "$CFG/opencode.json.bak-*" >/dev/null
  assert_eq '{"mine":true}' "$(cat "$CFG"/opencode.json.bak-*)"
  [[ -L "$CFG/opencode.json" ]]
}

test_edited_generated_file_backed_up() {
  setup_fx
  mkdir -p "$CFG"
  echo '{"model":"m"}' >"$CFG/opencode.local.json"
  inst >/dev/null
  jq '. + {extra:1}' "$CFG/opencode.json" >"$TMP/e" && mv "$TMP/e" "$CFG/opencode.json"
  inst >"$TMP/out" 2>"$TMP/err"
  assert_eq changed "$(last_line "$(cat "$TMP/out")")"
  grep -q 'bak-' "$TMP/err"
  assert_eq 1 "$(jq .extra "$CFG"/opencode.json.bak-*)"
  assert_eq null "$(jq .extra "$CFG/opencode.json")"
}

test_invalid_local_json_fails_safely() {
  setup_fx
  inst >/dev/null
  echo '{bad' >"$CFG/opencode.local.json"
  before=$(snapshot)
  rc=0
  inst >"$TMP/out" 2>"$TMP/err" || rc=$?
  assert_eq 1 "$rc" rc
  grep -q 'opencode.local.json' "$TMP/err"
  assert_eq "$before" "$(snapshot)" snapshot
  [[ -L "$CFG/opencode.json" ]]
}

test_repo_moved_relinks() {
  setup_fx
  inst >/dev/null
  mkfix "$TMP/fx2"
  out=$(bash "$TMP/fx2/install.sh" --config-dir "$CFG")
  assert_eq "$TMP/fx2" "$(readlink "$CFG/shared")"
  assert_eq changed "$(last_line "$out")"
}

test_shared_entries_linked() {
  setup_fx
  mkdir -p "$FX/plugins/demo"
  : >"$FX/plugins/demo/index.ts"
  : >"$FX/plugins/.gitkeep"
  inst >/dev/null
  assert_eq "$CFG/shared/plugins/demo" "$(readlink "$CFG/plugins/demo")"
  [[ ! -e "$CFG/plugins/.gitkeep" ]]
  mkdir -p "$CFG/plugins/own"
  rm -r "$FX/plugins/demo"
  out=$(inst)
  assert_eq changed "$(last_line "$out")"
  [[ ! -L "$CFG/plugins/demo" ]]
  [[ -d "$CFG/plugins/own" ]]
}

test_vendor_clone_update_prune() {
  setup_fx
  mkbare
  echo "demo file://$TMP/bare.git" >"$FX/skill-repos.txt"
  out=$(inst)
  assert_eq changed "$(last_line "$out")"
  assert_eq one "$(cat "$FX/vendor/demo/SKILL.md")"
  assert_eq ok "$(last_line "$(inst)")"

  echo two >"$TMP/work/SKILL.md"
  git -C "$TMP/work" commit -q -am two
  git -C "$TMP/work" push -q "$TMP/bare.git" main
  assert_eq ok "$(last_line "$(inst --no-update)")"
  assert_eq one "$(cat "$FX/vendor/demo/SKILL.md")"
  assert_eq changed "$(last_line "$(inst)")"
  assert_eq two "$(cat "$FX/vendor/demo/SKILL.md")"

  : >"$FX/skill-repos.txt"
  inst --no-update >/dev/null
  [[ -d "$FX/vendor/demo" ]]
  assert_eq changed "$(last_line "$(inst)")"
  [[ ! -e "$FX/vendor/demo" ]]

  echo "loc file://$TMP/bare.git" >"$CFG/skill-repos.local.txt"
  inst --no-update >/dev/null
  [[ ! -e "$FX/vendor/loc" ]]
  inst >/dev/null
  assert_eq two "$(cat "$FX/vendor/loc/SKILL.md")"
  rm "$CFG/skill-repos.local.txt"
  assert_eq changed "$(last_line "$(inst)")"
  [[ ! -e "$FX/vendor/loc" ]]
}

test_missing_jq_fails() {
  setup_fx
  mkdir "$TMP/bin"
  ln -s "$(command -v git)" "$TMP/bin/git"
  rc=0
  PATH="$TMP/bin" "$(command -v bash)" "$FX/install.sh" --config-dir "$CFG" >"$TMP/out" 2>"$TMP/err" || rc=$?
  assert_eq 1 "$rc" rc
  grep -q jq "$TMP/err"
}

test_merge_failure_cleans_temp() {
  setup_fx
  mkdir -p "$CFG" "$TMP/bin"
  echo '{"model":"m"}' >"$CFG/opencode.local.json"
  real=$(command -v jq)
  # shellcheck disable=SC2016
  printf '#!/bin/bash\nfor a in "$@"; do [[ "$a" == *include* ]] && exit 5; done\nexec %s "$@"\n' "$real" >"$TMP/bin/jq"
  chmod +x "$TMP/bin/jq"
  rc=0
  PATH="$TMP/bin:$PATH" inst >"$TMP/out" 2>"$TMP/err" || rc=$?
  [[ "$rc" != 0 ]]
  [[ ! -e "$CFG/opencode.json" || -L "$CFG/opencode.json" ]]
  assert_eq "" "$(find "$CFG" -name '*.tmp.*')" leftover
}

test_shared_non_symlink_fails() {
  setup_fx
  mkdir -p "$CFG/shared"
  echo keep >"$CFG/shared/f"
  rc=0
  inst >"$TMP/out" 2>"$TMP/err" || rc=$?
  assert_eq 1 "$rc" rc
  grep -q shared "$TMP/err"
  assert_eq "$CFG
$CFG/shared
$CFG/shared/f" "$(find "$CFG" | sort)"
}

test_shared_entry_name_clash_skipped() {
  setup_fx
  mkdir -p "$FX/plugins/demo" "$CFG/plugins/demo"
  : >"$FX/plugins/demo/index.ts"
  : >"$CFG/plugins/demo/mine"
  inst >"$TMP/out" 2>"$TMP/err"
  grep -q 'demo' "$TMP/err"
  [[ -d "$CFG/plugins/demo" && ! -L "$CFG/plugins/demo" && -f "$CFG/plugins/demo/mine" ]]
  assert_eq changed "$(last_line "$(cat "$TMP/out")")"
}

test_foreign_symlink_backed_up() {
  setup_fx
  mkdir -p "$CFG"
  echo '{"mine":true}' >"$TMP/mine.json"
  ln -s "$TMP/mine.json" "$CFG/opencode.json"
  inst >"$TMP/out" 2>"$TMP/err"
  grep -q 'opencode.json.bak-' "$TMP/err"
  [[ -L "$(compgen -G "$CFG/opencode.json.bak-*")" ]]
  assert_eq "$TMP/mine.json" "$(readlink "$CFG"/opencode.json.bak-*)" backup
  assert_eq "$CFG/shared/opencode.json" "$(readlink "$CFG/opencode.json")" ours
  echo '{}' >"$CFG/cli.local.json"
  rm "$CFG/cli.json"
  ln -s "$TMP/mine.json" "$CFG/cli.json"
  inst >/dev/null 2>"$TMP/err"
  compgen -G "$CFG/cli.json.bak-*" >/dev/null
  [[ -f "$CFG/cli.json" && ! -L "$CFG/cli.json" ]]
}

test_jsonc_present_warns() {
  setup_fx
  mkdir -p "$CFG"
  echo '{}' >"$CFG/opencode.jsonc"
  inst >/dev/null 2>"$TMP/err"
  grep -q 'opencode.jsonc' "$TMP/err"
  assert_eq '{}' "$(cat "$CFG/opencode.jsonc")" untouched
}
