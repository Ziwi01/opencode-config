# opencode-config

Shared [OpenCode](https://opencode.ai) (v2) setup for several machines: global
instructions, `opencode.json`, `cli.json` and skills. Each machine can add its own
instructions, skills, plugins and config overrides without editing this repository.

## Requirements

- `bash`, `git`, `jq`
- `uvx` for the Serena MCP server
- Node or Bun for package plugins, as OpenCode requires
- Network access to Context7

## Install

```bash
git clone <url> opencode-config
cd opencode-config
bash install.sh
```

The clone can live anywhere. The installer prints `changed` or `ok` as its last line and is
safe to re-run. `--config-dir DIR` targets another config directory (default
`$XDG_CONFIG_HOME/opencode`, else `~/.config/opencode`); `--no-update` skips the skill
repositories. Proveasio can also install and update it
on a workstation.

## Layout

| In this repository | Result in `~/.config/opencode` |
| --- | --- |
| whole repository | `shared` symlink, the only path the config refers to |
| `AGENTS.md` | loaded through `instructions` in `opencode.json` |
| `opencode.json`, `cli.json` | symlinks to `shared/…`, or merged files (see below) |
| `skills/<id>/SKILL.md` | found through the `skills` entry for `shared/skills` |
| `skill-repos.txt` → `vendor/` | clones, found through the `skills` entry for `shared/vendor` |
| `agents/`, `commands/`, `plugins/` | one symlink per entry |

Machine-only files, never touched by the installer:

- `AGENTS.md`, `skills/`, `plugins/`, `agents/`
- `opencode.local.json`, `cli.local.json`
- `skill-repos.local.txt`

## Overriding settings on one machine

Create `opencode.local.json` or `cli.local.json` next to the config files and run
`bash install.sh`. `opencode.json` then becomes a regular file holding the merge of shared
and local: objects merge recursively, arrays are concatenated (shared first, duplicates
dropped), local scalars win. Remove a shared plugin with a `-name` entry in the local
`plugins` array. Delete the local file and re-run the installer to get the symlink back.

The files are plain JSON, not JSONC, because the merge uses `jq`.

## Adding things

- **Skill for every machine:** `skills/<id>/SKILL.md`.
- **Skill repository:** one line `<name> <git-url> [<ref>]` in `skill-repos.txt` (shared) or
  `~/.config/opencode/skill-repos.local.txt` (machine). The installer clones missing
  repositories, fast-forwards existing ones and deletes clones no longer listed.
- **Package plugin:** add it to `plugins` in `opencode.json` (shared) or
  `opencode.local.json` (machine).
- **Local plugin, agent or command:** put it in `plugins/`, `agents/` or `commands/`; the
  installer symlinks each entry. Machine-only ones go straight into the config directory.

Explicit `skills` entries outrank `~/.config/opencode/skills`, so give machine skills IDs
that differ from shared ones.

## Updating

```bash
git pull && bash install.sh && opencode plugin update
```

## Edited config files

`opencode mcp add --global` writes through the `opencode.json` symlink, so the change lands
in this repository's `opencode.json` and shows in `git status` (checked with OpenCode
2.1.4: the symlink stays a symlink). Commit it if it should be shared, otherwise revert it
and put the server in `opencode.local.json`.

When `opencode.json` or `cli.json` is a regular file, the installer records its hash in
`~/.config/opencode/.opencode-config.state`. If the file no longer matches (edited, or it
existed before), the installer moves it to `<name>.json.bak-<timestamp>`, prints a warning
and continues.
