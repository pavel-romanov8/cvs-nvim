# TODO

## Current Features

### Finished

- `:CvsStatus`
  - Current status view for a CVS workspace.
  - Considered finished for now.

- `:CvsAnnotate`
  - Companion annotate view for the current file.
  - Considered finished for now.

### Existing, But Not Good Enough Yet

- `:CVS`
  - Main session / main workflow command exists.
  - Needs a rethink in architecture, UX, and overall feel.

- `:CvsAdd`
  - Add command exists.
  - Needs better flow and better integration with the main `:CVS` workflow.

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

- `:CvsDiff`
  - Command exists, but the real diff workflow is not done.

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

1. Rework `:CVS` into the main workflow we actually want to use.
2. Improve `:CvsAdd` so it feels natural inside the main workflow.
3. Improve `:CvsUpdate` so it supports the main workflow cleanly.

### Second Priority

1. Revisit `:CvsAnnotate` for polish after the main workflow is in place.
2. Revisit `:CvsRemove` and `:CvsCommit` after the main workflow is stable.
3. Finish the partial / scaffolded features:
   - `:CvsDiff`
   - `:CvsLog`
   - `:CvsConflicts`
   - picker integration
   - signs integration

## Product Direction Notes

- Right now, the plugin has two commands that feel truly finished: `:CvsStatus` and `:CvsAnnotate`.
- Everything else should be treated as either in-progress, needing redesign, or still scaffolded.
- The next real focus should be the main `:CVS` experience, with `add` and `update` supporting that workflow.
