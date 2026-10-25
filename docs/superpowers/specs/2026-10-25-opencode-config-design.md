# opencode-config: shared OpenCode setup

Date: 2026-10-25
Status: draft, awaiting review

## Goal

One repository holds the OpenCode setup shared by every machine: global
instructions, `opencode.json`, `cli.json`, skills, and plugin settings. Each
machine can add its own instructions, skills, plugins and config overrides
without touching the repository. Proveasio installs and updates it on
workstations; the planned NAS container uses the same installer.

Success criteria:

- A fresh machine gets the full setup from `git clone` + `./install.sh`.
- Nothing in the repository names a machine, a user, a project or an absolute
  path.
- Machine-only additions need no edits to tracked files.
- Overriding a shared setting (model, MCP server, permission) on one machine
  takes one file.
- Re-running the installer is idempotent and reports whether it changed
  anything.
- A Proveasio run updates the repository, the vendored skill repositories and
  the package plugins (for example superpowers).

Out of scope: the NAS container itself (separate spec once this repo exists),
Windows support, and the Proveasio-owned OpenCode files (lazygit agents, the
hunk-review skill, the ccmux and revdiff plugins), which stay where they are.

## Background: what OpenCode v2 layers on its own

Documented v2 behaviour this design relies on (checked against
<https://opencode.ai/v2/docs/>, OpenCode 2.1.4):

- `~/.config/opencode/AGENTS.md` is always loaded as the global instruction file.
- `instructions` entries accept `~/` paths and globs; missing files are skipped.
- `skills` entries accept `~/` paths; every directory below a source is
  searched (up to six levels) for `SKILL.md`. `~/.config/opencode/skills` is
  scanned automatically.
- `~/.config/opencode/{agents,commands,plugins}/` are scanned automatically.
- `plugins` accepts npm and Git package specs; `opencode plugin update`
  updates every outdated package plugin. A `-name` entry disables a plugin.
- There is only one global `opencode.json`, and it cannot include another
  config file.

So instructions, skills and plugins layer without help. Only `opencode.json`
and `cli.json` need a merge, and only when a machine overrides something.

## Layout

Repository (clone location does not matter):

```text
opencode-config/
├── AGENTS.md            shared global instructions
├── opencode.json        shared server config (v2 field names)
├── cli.json             shared TUI preferences
├── skills/<id>/SKILL.md shared skills
├── skill-repos.txt      Git repositories that provide more skills
├── vendor/              clones of those repositories (gitignored)
├── agents/ commands/ plugins/   optional; empty until needed
├── install.sh           installer (bash + git + jq)
├── README.md
└── docs/superpowers/specs/      this document
```

After `install.sh`, in `~/.config/opencode` (or `$XDG_CONFIG_HOME/opencode`):

```text
shared -> <repo>                        symlink, the only path the config uses
opencode.json -> shared/opencode.json   or a merged file, see below
cli.json      -> shared/cli.json        or a merged file
agents/<x>, commands/<x>, plugins/<x> -> shared/...   one symlink per entry
AGENTS.md, skills/, plugins/, agents/   machine-only, never touched
opencode.local.json, cli.local.json     machine-only overrides, optional
skill-repos.local.txt                   machine-only skill repositories, optional
```

The `shared` symlink makes the repository location irrelevant: the shared
`opencode.json` refers to `~/.config/opencode/shared/AGENTS.md`,
`~/.config/opencode/shared/skills` and `~/.config/opencode/shared/vendor`.

## Instructions

- Shared rules: `shared/AGENTS.md`, loaded through
  `"instructions": ["~/.config/opencode/shared/AGENTS.md"]`.
- Machine rules: `~/.config/opencode/AGENTS.md`, loaded by OpenCode itself.
  The installer never creates or edits it.

Both are always loaded; OpenCode combines them without resolving conflicts,
so the machine file should add to the shared rules, not contradict them.

The shared `AGENTS.md` carries a short "Where OpenCode changes go" section so
that an agent asked to add a rule, skill, plugin, MCP server or setting knows
where it belongs:

- Applies on every machine → the shared repository (found through
  `~/.config/opencode/shared`, edit the clone that link points to), then
  `install.sh`.
- Applies to one machine, or names a path, host, OS quirk or local project →
  the matching machine file in `~/.config/opencode/` (`AGENTS.md`, `skills/`,
  `plugins/`, `opencode.local.json`, `cli.local.json`,
  `skill-repos.local.txt`).
- A project's own rules → that project's `AGENTS.md`, never either of the
  above.
- Never edit `~/.config/opencode/opencode.json` or `cli.json` directly; they
  are symlinks or generated files.
- When unsure, ask.

## Skills

Three sources, all combined by OpenCode:

1. `shared/skills/` – skills kept in this repository.
2. `shared/vendor/<name>/` – Git repositories listed in `skill-repos.txt`
   (shared) and `~/.config/opencode/skill-repos.local.txt` (machine). The
   installer clones missing ones and fast-forwards existing ones. `vendor/` is
   gitignored. One `skills` entry, `~/.config/opencode/shared/vendor`, covers
   all of them because OpenCode searches subdirectories.
3. `~/.config/opencode/skills/` – machine-only skills, unmanaged.

`skill-repos.txt` format, one repository per line, `#` comments allowed:

```text
<name> <git-url> [<ref>]
```

`<ref>` defaults to the remote's default branch. A repository dropped from
both lists is deleted from `vendor/` on the next run.

Precedence caveat: explicit `skills` entries outrank
`~/.config/opencode/skills`, so a machine skill cannot replace a shared skill
with the same ID. Give machine skills unique IDs.

Plugins that ship skills (superpowers) are handled as plugins, not here.

## Plugins

- Package plugins (npm or Git specs) go in the `plugins` array of
  `opencode.json` (shared) or `opencode.local.json` (machine).
- Local plugin directories kept in this repository go in `plugins/<name>/` and
  are symlinked into `~/.config/opencode/plugins/`. They are not listed in
  config, because the docs do not say how relative or `~/` plugin paths resolve
  through a symlinked config file.
- Machine-only local plugins go straight into `~/.config/opencode/plugins/`.

`agents/` and `commands/` work like local plugins: each entry is symlinked into
the matching directory under `~/.config/opencode/`.

## Config files: symlink or merge

`install.sh` handles `opencode.json` and `cli.json` the same way:

- No `<name>.local.json`: `~/.config/opencode/<name>.json` is a symlink to
  `shared/<name>.json`.
- `<name>.local.json` exists: `<name>.json` becomes a regular file holding the
  merge of the shared file and the local file. Objects merge recursively,
  arrays are concatenated (shared first, duplicates dropped), local scalars
  win. Removing a shared plugin works through a `-name` entry in the local
  `plugins` array. Deleting the local file restores the symlink on the next
  run.

Shared and local files are plain JSON, not JSONC, because the merge uses `jq`.

### Protecting edits

`opencode mcp add --global`, `opencode plugin add` and the TUI settings screen
write to these files. The installer must not silently discard such writes:

- The installer records the SHA-256 of every file it generates in
  `~/.config/opencode/.opencode-config.state`.
- A target that is a regular file whose hash does not match the recorded one
  was edited (or predates the installer). The installer moves it to
  `<name>.json.bak-<timestamp>`, prints a warning naming the backup, and
  continues.
- If OpenCode writes through the symlink, the repository shows the change in
  `git status`; nothing is lost.

Which of the two cases OpenCode triggers is not documented. Implementation
checks it with `opencode mcp add --global` against a throwaway
`XDG_CONFIG_HOME` and records the result in the README.

## Installer contract

```text
install.sh [--config-dir DIR] [--no-update]
```

- Config directory: `--config-dir`, else `$XDG_CONFIG_HOME/opencode`, else
  `~/.config/opencode`.
- Steps: link `shared`; link agents, commands and plugins, removing dangling
  links that point into `shared/`; clone or update vendor repositories
  (skipped with `--no-update`); write `opencode.json` and `cli.json`.
- Requires `bash`, `git`, `jq`. Fails with a clear message if one is missing.
- Never writes inside the repository except `vendor/`.
- Prints `changed` as the last line when it modified anything, `ok`
  otherwise, so Ansible can set `changed_when` from it.
- Exit codes: 0 success, 1 error.

Updating the repository itself (`git pull`) and the package plugins
(`opencode plugin update`) is left to the caller: Proveasio uses its `git`
module for the first and runs the second after the installer; a manual user
runs both by hand, as the README describes.

## Shared content taken from the current setup

- `AGENTS.md`: the current global file without machine-specific lines. The
  WSL2 bullet moves to the workstation's own `~/.config/opencode/AGENTS.md`.
- `opencode.json`: model, superpowers plugin, external-directory permissions,
  Context7 and Serena MCP servers, rewritten with v2 field names (`plugins`,
  `permissions`, `mcp.servers`).
- `cli.json`: the current TUI preferences.
- `skills/unslop`.

Requirements this puts on every machine, the NAS container included: `uvx`
(Serena), Node or Bun for package plugins as OpenCode requires, network access
to Context7.

## Proveasio integration

New config task `roles/config/tasks/opencode-config.yml`, modelled on
`neovim-config.yml`:

- Variables in `roles/config/vars/main.yml`: `opencode_config_url`,
  `opencode_config_version` (default `main`), `opencode_config_path`
  (`~/.local/share/opencode-config`), `opencode_config_source` (`git` or
  `local`) and `opencode_config_local_path`, with the same validation as
  Neovim.
- `git` source: `ansible.builtin.git` with `update: true`. `local` source:
  `install.sh` runs straight from `opencode_config_local_path`, which suits
  working on the repository itself.
- Run `install.sh`; `changed_when` from its last output line.
- Run `opencode plugin update`; `changed_when` from its output (to be
  confirmed during implementation).
- Save the used version to `current-versions.yml` like Neovim.
- Registered in `config/tasks/main.yml` with
  `when: "'opencode-config' not in config_tasks_exclude"` and tags
  `config, versions, opencode-config`. Skipped when `opencode` is in
  `software_tasks_exclude`.
- `docker/test.sh`: `check_config_opencode_config` (symlinks resolve,
  `opencode.json` is valid JSON).
- Docs: `docs-web/docs/main/roles/` config page, the matching features page,
  `customization/50-partial-run.md`, the Docker comparison table, README.

The existing Proveasio-owned OpenCode files keep their current tasks.

## Testing

- `install.sh` against a temporary `XDG_CONFIG_HOME`: first run (`changed`),
  second run (`ok`), with and without local overrides, with a pre-existing
  regular `opencode.json` (backed up), with a vendor repository added and
  removed.
- `jq` merge checked on a sample with nested objects, arrays and a `-plugin`
  entry.
- `opencode debug config` on the result lists the expected sources.
- Proveasio: `ansible-lint`, `--syntax-check`, a `--tags opencode-config` run
  on this workstation (after approval), the Docker smoke build with the tag
  added, and `npm run build` for the docs.
