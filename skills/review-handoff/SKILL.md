---
name: review-handoff
description: Use when you changed files the user will review and they are not in the session's directory (a worktree, a separate clone, another repository), when the user cannot see your changes in /revdiff or hunk, and when such a review ends. Points /revdiff and hunk at the changes and moves back afterwards.
---

# Review handoff

The user reviews with two tools, and each looks at one directory:

- `/revdiff` (revdiff opencode plugin) reviews the **session's directory**. It accepts one ref,
  `--staged` and `--only`, nothing else.
- hunk, shown with Alt+h in tmux, reviews the directory **hunk was started in**: the opencode
  pane's directory unless `hunk-popup open` started it elsewhere.

Changes anywhere else are invisible to both. Point the tools at the changes before you
report, and point them back when the review ends.

## Hand over

1. **Note where you are.** Record the session's current directory: you move back to it at
   the end. Keep it in your reply so it survives a long session.
2. **Pick the base.**
   - Uncommitted changes: no ref.
   - Committed on a branch: the branch the work started from, e.g. `develop`. Prefer the
     branch name over a commit id; it reads better in the report.
3. **Move the session:** `opencode.session_move({ directory: "<dir>" })`. The move takes effect
   at the end of the turn; `/revdiff` then reviews `<dir>`.
4. **Start hunk there**, when `$TMUX` is set and `command -v hunk-popup` succeeds:

   ```bash
   hunk-popup open <dir> [ref]
   ```

   It restarts hunk if hunk shows another directory or ref. While the user has notes there,
   it refuses: read them (see "Read hunk notes"), deal with them, then repeat with `--force`.
   Without tmux or `hunk-popup`, skip this step and say that hunk is not set up.
5. **New files.** hunk shows untracked files. revdiff shows them only with `untracked = true`
   in `~/.config/revdiff/config`; `/revdiff` cannot pass `--untracked`. If the setting is
   missing and you created files, say that they will not appear in `/revdiff`.
6. **Report**, in this shape:

   ```text
   Changes are in <dir> (<worktree of X | clone of X>), diffed against <working tree | ref>.
   Review: /revdiff [ref]   or Alt+h for hunk.
   ```

Several directories: hand over one at a time. Finish the review of one, then hand over the
next, and tell the user each time.

## During the review

- **revdiff** notes arrive as a user message when the user quits revdiff. Nothing to fetch.
- **hunk** notes do not arrive. When the user says to check hunk, or that the review is done,
  read them (below). hunk restarts its diff on its own (`--watch`), so after a fix the user
  only reopens it with Alt+h; `/revdiff` has to be run again.
- Reply inside hunk when an answer belongs next to the code:

  ```bash
  hunk session comment add --repo <dir> --reply-to <noteId> --summary "<answer>"
  ```

  Agent notes start hidden; pass `--focus` on the first one or tell the user to press `a`.
  The hunk-review skill has the rest of the `hunk session` commands.

### Read hunk notes

```bash
hunk-popup notes
```

prints `{"source": ..., "dir": ..., "ref": ..., "comments": [...]}`: from the running hunk
(`"source": "live"`), else from the newest file `hunk-popup close` or a restart saved
(`"source"` is that file). Check `dir`, and for a saved file `saved`, before acting on them:
an old file may belong to an earlier review.

Without `hunk-popup`: `hunk session comment list --repo <dir> --type user --json`.

Do not trust the `comments:` count of `hunk session list`; it leaves the user's notes out.
If hunk was quit with `q` in hunk, the notes are gone: say so, do not report "no notes".

## End the review

The review ends when the user accepts the changes, says the review is done or asks to go
back, or the worktree or clone is removed. Then:

1. Read the hunk notes one last time, and handle what they ask for. A note that asks for a
   change means the review is not over: fix it and hand over again.
2. **Copy the changes into the main checkout** the worktree or clone came from, when the
   review ended with no change requests left. Leave them uncommitted.
   - Check first: `git -C <main> status --short` shows none of the files you touched, and
     `<main>` is at the commit the work started from. Otherwise stop and ask.
   - Tracked files: `git -C <dir> diff --binary [ref] > <patch>`, then
     `git -C <main> apply --check <patch>` and `git -C <main> apply <patch>`. With a ref,
     the patch also carries the committed changes.
   - New files: `git -C <dir> ls-files --others --exclude-standard`; copy each one.
   - Verify with `cmp` on every copied file and show `git -C <main> status --short`.
3. **Remove the worktree or clone** once step 2 verified every file, if you created it.
   Its changes are uncommitted, so removal needs force: `git -C <main> worktree remove --force
   <dir>` (or the `worktree_remove` tool with `force: true` from that repository), or
   `rm -rf <dir>` for a clone. Before that, check that it holds nothing step 2 did not copy:
   no commits that are not in `<main>`, no files `cmp` did not cover. Remove the empty parent
   directory you made for it. Never remove a worktree or clone the user created; ask.
4. `opencode.session_move({ directory: "<original dir>" })`.
5. If you started hunk, `hunk-popup open <original dir>`. If it refuses because of notes, you
   read them in step 1: repeat with `--force`. If hunk no longer runs, skip this; Alt+h starts
   it in the pane's directory.
6. Tell the user that the session and hunk are back in `<original dir>`, where the changes
   were copied, and that the worktree or clone is removed.

Do not commit, merge or push as part of this. Ask.
