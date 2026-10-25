# opencode-config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A shared OpenCode config repository with an idempotent installer, and a Proveasio config task that installs and updates it.

**Architecture:** `install.sh` links `~/.config/opencode/shared` to the clone, links shared agents/commands/plugins, syncs vendored skill repositories, and either symlinks or jq-merges `opencode.json`/`cli.json`. Proveasio clones the repo (or uses a local checkout), runs the installer, then `opencode plugin update`.

**Tech Stack:** bash, git, jq 1.6+, Ansible (ansible-core, ansible-lint), Docusaurus docs.

**Spec:** `docs/superpowers/specs/2026-10-25-opencode-config-design.md` (this repo)

## Global Constraints

- Nothing tracked in `opencode-config` names a machine, user, project or absolute path; config refers only to `~/.config/opencode/shared/...`.
- Installer requires only `bash`, `git`, `jq`; last output line is exactly `changed` or `ok`; exit 0 on success, 1 on error.
- Installer never writes inside the repository except `vendor/`.
- Shared/local config files are plain JSON with v2 field names (`plugins`, `permissions`, `mcp.servers`).
- Merge: objects recursive, arrays shared-first concatenated with duplicates dropped, local scalars win.
- Generated-file hashes live in `<config-dir>/.opencode-config.state`; an unrecognised regular file is moved to `<name>.json.bak-<YYYYmmddHHMMSS>`.
- Proveasio: `cd ansible && ansible-lint` must report `Passed: 0 failure(s)`; docs build must pass; follow every convention in Proveasio `AGENTS.md` (task name prefix, `set -e -o pipefail` + `/bin/bash` in shell tasks, exclude guard, outer tags).
- No commits, pushes or branches unless the user asks.

## Review Focus

- Config dir has a real `opencode.json` from before the installer (this workstation) → backed up, not lost. Test: `test_preexisting_file_backed_up`.
- OpenCode rewrote the generated merged file (`opencode mcp add --global`) → backed up on next run. Test: `test_edited_generated_file_backed_up`.
- `opencode.local.json` deleted after a merge run → symlink restored. Test: `test_local_removed_restores_symlink`.
- Repository moved/re-cloned elsewhere → `shared` link repointed, `changed` reported. Test: `test_repo_moved_relinks`.
- Invalid JSON in a local file → error exit 1, existing target untouched. Test: `test_invalid_local_json_fails_safely`.

---

## File map

`~/projects/opencode-config/`:

| File | Responsibility |
|---|---|
| `install.sh` | installer, contract in spec |
| `lib/merge.jq` | the merge function, kept separate so tests and installer share it |
| `tests/run.sh` | plain-bash test runner (no bats on the machine) against temp dirs |
| `AGENTS.md` | shared rules, including "Where OpenCode changes go" |
| `opencode.json`, `cli.json` | shared config |
| `skills/unslop/SKILL.md` | copied from current setup |
| `skill-repos.txt` | header comment only, no entries yet |
| `agents/.gitkeep`, `commands/.gitkeep`, `plugins/.gitkeep` | empty dirs |
| `.gitignore` | `vendor/` |
| `README.md` | install, layout, per-machine customisation, updating |

Proveasio: `ansible/roles/config/tasks/opencode-config.yml` (new), `roles/config/tasks/main.yml`, `roles/config/vars/main.yml`, `docker/test.sh`, docs pages listed in Task 5.

---

### Task 1: Merge function

**Files:** Create `lib/merge.jq`, `tests/run.sh`

**Interfaces:** Produces `def merge($a; $b)` in `lib/merge.jq`, used as `jq -n --slurpfile a S --slurpfile b L -L lib 'include "merge"; merge($a[0]; $b[0])'`. Produces `tests/run.sh` runner: every function named `test_*` runs in a subshell with fresh `TMP`, prints `PASS name` / `FAIL name: reason`, exits non-zero on any failure; helper `assert_eq EXPECTED ACTUAL`.

- [ ] **Step 1: Write failing tests** `test_merge_objects_recursive` (`{"a":{"x":1,"y":2}}` + `{"a":{"y":3}}` → `{"a":{"x":1,"y":3}}`), `test_merge_arrays_concat_dedup` (`{"p":["a","b"]}` + `{"p":["b","-a"]}` → `{"p":["a","b","-a"]}`), `test_merge_scalar_local_wins` (`{"model":"x"}` + `{"model":"y"}` → `{"model":"y"}`), `test_merge_type_mismatch_local_wins` (`{"a":[1]}` + `{"a":{"b":1}}` → `{"a":{"b":1}}`).
- [ ] **Step 2:** `bash tests/run.sh` → the four FAIL.
- [ ] **Step 3:** Implement `merge` (recursive over object keys; arrays `$a + ($b - $a)`; otherwise `$b`).
- [ ] **Step 4:** `bash tests/run.sh` → PASS; `shellcheck tests/run.sh` clean.

### Task 2: Installer

**Files:** Create `install.sh`; extend `tests/run.sh`

**Interfaces:** Consumes `lib/merge.jq`. Produces `install.sh [--config-dir DIR] [--no-update]`, contract per spec; repo dir = directory of the script (`readlink -f`).

- [ ] **Step 1: Write failing tests**, each with a throwaway fixture repo (copy of the real tree minus `.git`, plus a local bare git repo for vendor tests) and `--config-dir "$TMP/cfg"`:
  - `test_first_run_links` — `shared` → repo, `opencode.json`/`cli.json` symlinks into `shared/`, last line `changed`.
  - `test_second_run_ok` — rerun prints `ok`, nothing modified.
  - `test_local_override_merges` — `opencode.local.json` `{"model":"m"}` → regular file, `.model == "m"`, shared keys kept, hash recorded in `.opencode-config.state`.
  - `test_local_removed_restores_symlink`.
  - `test_preexisting_file_backed_up` — regular file present, no state → moved to `opencode.json.bak-*`, warning on stderr, symlink created.
  - `test_edited_generated_file_backed_up` — merge run, then append a key to the target → next run backs it up and regenerates.
  - `test_invalid_local_json_fails_safely` — exit 1, target unchanged.
  - `test_repo_moved_relinks` — second fixture copy, run its installer → `shared` points at it, `changed`.
  - `test_shared_entries_linked` — `plugins/demo/index.ts` in fixture → `cfg/plugins/demo` link; remove from fixture → dangling link removed; a machine-only `cfg/plugins/own/` untouched.
  - `test_vendor_clone_update_prune` — `skill-repos.txt` line `demo file://$TMP/bare.git` → cloned to `vendor/demo`; new commit in bare repo → fast-forwarded and `changed`; line removed → `vendor/demo` deleted; `skill-repos.local.txt` in config dir contributes the same way; `--no-update` skips all three.
  - `test_missing_jq_fails` — `PATH` without jq → exit 1 with message naming jq.
- [ ] **Step 2:** `bash tests/run.sh` → new tests FAIL.
- [ ] **Step 3:** Implement `install.sh`: `set -euo pipefail`; dependency check; compute targets; each step sets `CHANGED=1` when it modifies something; vendor lines parsed with `read -r name url ref`, comments/blank skipped, clone with `--depth 1` (and `--branch ref` when given), update with `git fetch` + `git reset --hard FETCH_HEAD` only if HEAD differs; config files written via temp file + `mv`; state file lines `<name> <sha256>`.
- [ ] **Step 4:** `bash tests/run.sh` → all PASS; `shellcheck install.sh` clean.

### Task 3: Shared content and README

**Files:** Create `AGENTS.md`, `opencode.json`, `cli.json`, `skills/unslop/SKILL.md`, `skill-repos.txt`, `.gitignore`, `.gitkeep`s, `README.md`

- [ ] **Step 1:** `AGENTS.md` = current `~/.config/opencode/AGENTS.md` minus the WSL2 bullet, plus section "Where OpenCode changes go" with the rules from the spec's Instructions section, plus: "Shared changes reach other machines only after commit and push; on Proveasio machines the clone may be `~/.local/share/opencode-config`, managed by Proveasio — edit the user's working clone instead when one exists."
- [ ] **Step 2:** `opencode.json` = current config converted to v2 shapes, plus `"instructions": ["~/.config/opencode/shared/AGENTS.md"]` and `"skills": ["~/.config/opencode/shared/skills", "~/.config/opencode/shared/vendor"]`. Check the v2 shapes of `permissions` (external_directory) and `mcp.servers` against <https://opencode.ai/v2/docs/permissions> and `/mcp-servers` before writing.
- [ ] **Step 3:** Verify: `grep -rnE '/home/|ziwi|proveasio|wsl' --exclude-dir=docs --exclude-dir=.git .` → no hits other than the README's Proveasio mention; `jq . opencode.json cli.json` succeeds; `bash tests/run.sh` still PASS (tests copy the real tree).
- [ ] **Step 4:** Live check against a temp config dir: `./install.sh --config-dir /tmp/opencode/cfg`, then `XDG_CONFIG_HOME=/tmp/opencode opencode debug config` (and `debug paths`) lists the shared instructions and skills. Record what `opencode mcp add --global` does to a symlinked `opencode.json` in that temp dir and put the finding in the README.
- [ ] **Step 5:** README: what it is, requirements (bash, git, jq; uvx for Serena), install, layout table (shared vs machine), overriding settings, adding skills/skill repos/plugins, updating (`git pull && ./install.sh && opencode plugin update`), what happens to edited config files.

### Task 4: Proveasio task

**Files:** Create `ansible/roles/config/tasks/opencode-config.yml`; modify `roles/config/tasks/main.yml` (after the Neovim config include), `roles/config/vars/main.yml`

**Interfaces:** Vars `opencode_config_url: https://github.com/Ziwi01/opencode-config.git`, `opencode_config_version: main`, `opencode_config_path: "{{ ansible_facts['env']['HOME'] }}/.local/share/opencode-config"`, `opencode_config_source: git`, `opencode_config_local_path: ""`.

- [ ] **Step 1:** Run `opencode plugin check` and `opencode plugin update` once by hand, note the output with and without updates, and whether a running service is needed. Pick `changed_when` from that.
- [ ] **Step 2:** Write the task file: validate source (same assert as Neovim); `git` clone/update when `git`; set `opencode_config_dir` to the path in use; `[opencode-config] Install` → `"{{ opencode_config_dir }}/install.sh"`, `changed_when: result.stdout_lines[-1] == 'changed'`, PATH including `~/.local/bin`; `[opencode-config] Update package plugins` → `opencode plugin update`; save version like Neovim (`local` when local).
- [ ] **Step 3:** Register in `main.yml` with `when: "'opencode-config' not in config_tasks_exclude and 'opencode' not in software_tasks_exclude"`, tags `config, versions, opencode-config` (outer) and `config, opencode-config` (apply).
- [ ] **Step 4:** `cd ansible && ansible-lint` → `Passed: 0 failure(s)`; `ansible-playbook -i inventory.yml setup-ubuntu.yml --syntax-check`; `--list-tags` shows `opencode-config`.
- [ ] **Step 5 (needs user approval, mutates this workstation):** with `opencode_config_source: local`, `opencode_config_local_path: ~/projects/opencode-config` in `ansible/vars/overrides.yml`, run `--tags opencode-config -K` twice; second run reports no change. Before it, propose replacing this machine's `~/.config/opencode/AGENTS.md` with just the WSL2 bullet.

### Task 5: Proveasio test and docs

**Files:** Modify `docker/test.sh`, `docs-web/docs/main/roles/20-config.md`, `docs-web/docs/main/customization/10-variables.md`, `30-config-files.md`, `40-excludes.md`, `50-partial-run.md`, `docs-web/docs/main/docker/10-build.md` (comparison table), `docs-web/docs/usage/80-ai.md`, `README.md`

- [ ] **Step 1:** `check_config_opencode_config`: `shared` link resolves, `opencode.json` passes `jq -e .`, `opencode debug config` runs; `DETAIL` = number of skills under `shared/skills` and `shared/vendor`.
- [ ] **Step 2:** `PROVEASIO_HOME="$PWD" bash docker/test.sh --coverage` → no missing checks.
- [ ] **Step 3:** Docs: config role row; variables table rows; note in "Own config files" (fork it like the Neovim config); excludes sentence (`opencode` → also `opencode-config`); tag list; Docker table; a short "Shared OpenCode config" section in usage/80-ai.md pointing to the repo README.
- [ ] **Step 4:** `cd docs-web && npm install && npm run build` → success.
- [ ] **Step 5 (needs user approval, ~5–7 min, check WSL memory first):** smoke build with `opencode-config` added to `ANSIBLE_TAGS`; the new check passes. Requires the repo to be pushed so the `git` source can clone it.
