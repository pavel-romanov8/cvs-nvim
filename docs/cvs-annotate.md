# CvsAnnotate

## Goal

`CvsAnnotate` adds a review-oriented companion pane for the current file.

- open a narrow left-side buffer next to the source window
- show per-line CVS authorship metadata
- keep the source file as the main editing surface
- start with committed history only, not live ownership of unsaved edits

The target experience is closer to the annotate or blame panes in VSCode and WebStorm than to inline virtual text.

## V1 Scope

The first version intentionally favors speed, correctness, and architectural fit over perfect live-edit UX.

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

For v1, a sibling buffer is a better fit than extmarks, virtual text, or signs because it:

- matches the requested IDE-like layout
- keeps line-oriented metadata visually separate from code
- works with the existing split-based UI primitives
- avoids introducing a new inline rendering abstraction too early

## Local Edit Model

`cvs annotate` answers a committed-history question: who last changed a repository line.

That means the pane does not describe unsaved local edits as if they were already committed.

### Chosen V1 Behavior

- annotate data is based on the saved file on disk and repository history
- if the source buffer is modified, the pane stays open but is marked stale
- newly inserted local lines do not get fake author information
- saving the file triggers a refresh and realigns the pane with the latest saved content

### Tradeoff

This keeps the feature honest and easy to trust, but it does mean visual alignment can drift while the buffer contains unsaved inserted or deleted lines.

## Known Limitations In V1

- unsaved inserted or deleted lines can misalign metadata rows
- wrapped lines are not treated as a first-class layout case
- folds and other non-1:1 display transforms are not handled specially
- the pane shows `author | date` only, even though revision data is parsed
- no inline blame or gutter integration

These are acceptable limits for the first usable version because the command remains accurate about committed history.

## Future Improvements

The next UX pass can improve local-edit handling without changing the command boundary.

Possible follow-ups:

- show placeholders such as `[local]` for inserted unsaved lines
- diff saved content against the current buffer and remap rows more intelligently
- add a revision toggle or hover/details action
- integrate line or revision drilldown with `CvsLog`
- explore inline current-line blame as a separate mode

## Product Principle

The plugin should not pretend CVS knows the author of lines that have not been committed yet.

For `CvsAnnotate`, correctness of repository history comes first. Better local-edit UX can be layered on top later.
