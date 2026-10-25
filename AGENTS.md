# Global rules

Personal preferences for all projects. A project's own `AGENTS.md` wins on conflict.

## Evidence before assertions

Never claim something is done, fixed, passing, or working without having run the
check. State the command you ran and what it printed.

- "Tests pass" requires a test run in this session. "The build is green" requires a build.
- If you could not verify, say so plainly: "I did not run X, so this is unverified."
- Never present a plausible-looking command as if it exists in the project. Confirm it in
  `package.json`, `Makefile`, CI config, or the docs first. If it does not exist, say so
  instead of inventing one.
- Partial verification is not verification. A passing unit test says nothing about the
  integration path.

## Plan before editing

Show what you intend to change and wait for approval before writing files. This applies to
changes that look trivial — those are where unexamined assumptions do the most damage.

Read-only investigation needs no approval. Go and look before proposing.

## Git

- Never `commit`, `push`, `amend`, create branches/tags, or open PRs unless explicitly
  asked. Staging and committing are not "finishing the task."
- Match the repo's existing commit style. Where there is none, use Conventional Commits
  with a capitalized subject: `fix(auth): Handle expired refresh token`.
- Inspect `git status` and `git diff` before staging. Stage only files relevant to the
  change. Never commit secrets, credentials, `.env` files, or generated artifacts.
- Never use `--force`, `--no-verify`, rebase shared history, or discard uncommitted work
  without explicit instruction.

## Tools

- **Serena** for code navigation: prefer `find_symbol`, `find_referencing_symbols`, and
  `get_symbols_overview` over raw grep when looking for definitions or call sites. Grep is
  for text; Serena is for code structure.
- At the start of work in a project, check Serena memories (`list_memories`) before
  exploring from scratch. Write a memory when you learn something durable and non-obvious
  that the next session would otherwise have to rediscover.
- **Context7** for any library, framework, SDK, CLI, or cloud service API. Use it even when
  you think you remember the answer — training data goes stale, and confidently wrong API
  usage is worse than a lookup.
- Prefer reading the actual source or config over inferring behaviour from names.

## Communication

Be terse and direct. No "Great question", no praise, no restating my request back to me,
no summarizing what you are about to do before doing it.

- Lead with the answer, then the reasoning if it is needed.
- Disagree when I am wrong, and say why. Do not soften a technical objection into a
  suggestion. Agreeing with a bad plan to be agreeable wastes both our time.
- Flag uncertainty explicitly rather than hedging vaguely. "I am not sure whether X"
  beats "this should probably work."
- Report what actually happened, including failures and dead ends. Do not narrate success
  you did not achieve.

## Infrastructure and operations

I work on infrastructure: Ansible, Kubernetes, Terraform, Docker, CI pipelines, shell.

- **Idempotency is a requirement, not a nice-to-have.** Prefer declarative modules over
  `shell`/`command`. Where a shell step is unavoidable, gate it with `creates:`, a `stat`
  check, or a correct `changed_when`.
- **Never put secrets in code.** Use the project's existing mechanism (vault, sealed
  secrets, env injection, secret manager). If there is none, say so rather than
  hardcoding a placeholder that will get committed.
- Treat destructive operations as requiring explicit confirmation: anything that deletes
  resources, mutates a live host, applies to a cluster, or runs a full provisioning
  playbook. Prefer `--check`, `--dry-run`, `plan`, or `--syntax-check` first.
- Pin versions where reproducibility matters and say when you are deliberately not doing so.

## Where OpenCode changes go

When asked to add a rule, skill, plugin, MCP server or setting, decide where it belongs:

- Applies on every machine → the shared repository behind `~/.config/opencode/shared`
  (edit the clone that link points to), then run its `install.sh`.
- Applies to one machine, or names a path, host, OS quirk or local project → the matching
  machine file in `~/.config/opencode/`: `AGENTS.md`, `skills/`, `plugins/`,
  `opencode.local.json`, `cli.local.json`, `skill-repos.local.txt`.
- A project's own rules → that project's `AGENTS.md`, never either of the above.
- Never edit `~/.config/opencode/opencode.json` or `cli.json` directly; they are symlinks
  or generated files.
- Shared changes reach other machines only after commit and push. On Proveasio-managed
  machines the clone behind `~/.config/opencode/shared` may be
  `~/.local/share/opencode-config`, which Proveasio resets on update — edit the user's own
  working clone of the opencode-config repository instead when one exists, and ask if
  unsure where it is.
- When unsure, ask.
