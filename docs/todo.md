# TODO

## Current Features

### Finished

- `:Cvs` / `:CvsStatus`
  - Current status view for a CVS workspace.
  - Considered finished for now.

- `:Cdiffsplit` / `:CvsDiff`
  - Vertical diff against the checked-out CVS revision.
  - Considered finished for now.

- `:CvsAnnotate`
  - Companion annotate view for the current file.
  - Considered finished for now.

### Existing, But Not Good Enough Yet

- `:CvsAdd`
  - Add command exists.
  - Needs better flow and better integration with the main `:Cvs` workflow.

- `:CvsUpdate`
  - Update command exists.
  - Needs better presentation and workflow polish.

- `:CvsRemove`
  - Remove command exists.
  - Not a priority right now.

- `:CvsCommit`
  - Separate commit buffer exists.
  - Not in a good final shape yet.

### Partial Or Still Scaffolded

- `:CvsLog`
  - Command exists, but the real history/log workflow is not done.

- `:CvsConflicts`
  - Conflict detection exists.
  - Real conflict resolution workflow is not done.

- Optional integrations
  - Picker integration is not implemented.
  - Signs integration is not implemented.

## Priority Plan

### First Priority

1. Continue refining `:Cvs` into the main workflow we actually want to use.
2. Improve `:CvsAdd` so it feels natural inside the main workflow.
3. Improve `:CvsUpdate` so it supports the main workflow cleanly.

### Second Priority

1. Revisit `:CvsAnnotate` for polish after the main workflow is in place.
2. Revisit `:CvsRemove` and `:CvsCommit` after the main workflow is stable.
3. Finish the partial / scaffolded features:
   - `:CvsLog`
   - `:CvsConflicts`
   - picker integration
   - signs integration

## Product Direction Notes

- Right now, the plugin has three workflows that feel finished: status, annotate, and file diff.
- Everything else should be treated as either in-progress, needing redesign, or still scaffolded.
- The next real focus should be the main `:Cvs` experience, with `add` and `update` supporting that workflow.
