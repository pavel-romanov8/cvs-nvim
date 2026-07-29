# CvsAnnotate

## Goal

`CvsAnnotate` adds a review-oriented companion pane for the current file.

- open a narrow left-side buffer next to the source window
- show per-line CVS authorship metadata
- keep the source file as the main editing surface
- preserve committed history while identifying local, uncommitted lines

The target experience is closer to the annotate or blame panes in VSCode and WebStorm than to inline virtual text.

## Scope

The implementation favors speed, correctness, and architectural fit over more intrusive inline blame UI.

- file-scoped command: `:CvsAnnotate [file]`
- left companion split by default
- one metadata row per source line
- default columns: `author | date`
- manual refresh with `R`
- close with `q`
- automatic refresh on `BufWritePost`

## Why A Left Companion Buffer

This project already has the right module boundaries for a feature-local buffer workflow:

- command registration in `lua/cvs/commands.lua`
- CVS command execution through `lua/cvs/cvs/cmd.lua` and `lua/cvs/cvs/runner.lua`
- feature-local service, parser, and buffer modules under `lua/cvs/features/annotate/`
- shared window helpers in `lua/cvs/ui/window.lua`

A sibling buffer is a better fit than extmarks, virtual text, or signs because it:

- matches the requested IDE-like layout
- keeps line-oriented metadata visually separate from code
- works with the existing split-based UI primitives
- avoids introducing a new inline rendering abstraction too early

## Local Edit Model

`cvs annotate` answers a committed-history question: who last changed a repository line.

That means the pane does not describe unsaved local edits as if they were already committed.

### Behavior

- annotate data is pinned to the checked-out revision recorded in `CVS/Entries`
- committed annotation text is diffed against the live Neovim buffer
- unchanged lines retain their repository author and date after nearby edits
- inserted or replaced lines render as `[local] | Not committed`
- deleted repository lines have no row in the current-file view
- saved and unsaved local changes use the same mapping
- live remapping is debounced while editing; saving also refreshes the CVS baseline

### Tradeoff

CVS cannot attribute an uncommitted line to a repository revision. The local marker keeps that distinction explicit while preserving useful history for surrounding unchanged lines.

## Known Limitations

- wrapped lines are not treated as a first-class layout case
- folds and other non-1:1 display transforms are not handled specially
- the pane shows `author | date` only, even though revision data is parsed
- no inline blame or gutter integration

The command remains accurate about committed history without letting local edits shift unrelated annotations.

## Future Improvements

The next UX pass can improve local-edit handling without changing the command boundary.

Possible follow-ups:

- add a revision toggle or hover/details action
- integrate line or revision drilldown with `CvsLog`
- explore inline current-line blame as a separate mode

## Product Principle

The plugin should not pretend CVS knows the author of lines that have not been committed yet.

For `CvsAnnotate`, correctness of repository history comes first. Better local-edit UX can be layered on top later.
