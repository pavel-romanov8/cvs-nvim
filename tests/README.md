# Tests

Run the suite with:

```sh
nvim --headless -u NONE --cmd 'set rtp+=.' -l tests/run.lua
```

## What belongs here

Prefer tests that protect CVS semantics, destructive-operation safety, parser
boundaries, asynchronous ownership, and complete user workflows.

Avoid assertions that merely mirror implementation details, mapping
descriptions, every rendered label, every window option, or several equivalent
layout variants. One representative assertion is enough unless the variants
have different behavior.

The test layers are:

- `fixtures/cvs/`: captured or representative CVS command output.
- `unit/`: parsers, command construction, state transitions, and pure helpers.
- `ui/`: one smoke workflow per meaningful editor interaction.
- `integration/`: reserved for workflows against a temporary real CVS repository.

For mutating features, prioritize tests proving the target set, command
direction, preflight behavior, and failure boundary over cosmetic rendering.
