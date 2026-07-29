# CVS Command Architecture

## Main `:CVS` Direction

The first step in the new architecture is to make `:CVS` open a Fugitive-like
workspace buffer instead of dropping straight into a commit message flow.

That buffer should be the user's starting point for the CVS workflow:

- show the current workspace snapshot from `cvs -nq update`
- group files by real CVS states instead of inventing Git-style staging
- list tracked changes like modified, added, removed, conflict, updated,
  patched, and unknown files
- let the user drill into files with `<CR>`
- let the user refresh with `R`
- keep lightweight file actions in place, like add/restore and remove

## Why This Shape

CVS already models file state directly. The plugin should reflect that model
instead of forcing a staged/unstaged mental model from Git.

That makes the main screen feel closer to Fugitive in layout and navigation,
while still staying honest to CVS semantics.

## Initial Implementation Slice

For the first slice of the redesign:

- `:CVS` and `:CvsStatus` can share the same workspace status buffer
- `:CvsCommit` remains the dedicated commit-message workflow
- the main buffer is read-only and acts as the entry point into the rest of the
  CVS workflow

## Data Source

Use `cvs -nq update` as the source of truth for the buffer snapshot.

Reasons:

- it exposes CVS status codes directly
- it matches how classic CVS tools build workspace views
- it avoids building fake index semantics that CVS does not have

## Follow-Up Work

After this first step is stable, the next pieces can build on top of it:

- wire commit flow back into the main buffer in a cleaner way
- improve update flow so incoming states feel connected to `:CVS`
- add better per-file actions and deeper drill-down views
