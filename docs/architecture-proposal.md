# CVS Neovim Plugin: Architecture Proposal

## Recommendation

Build `cvs-nvim` as a command-first, Neovim-native plugin with:

- a very thin `plugin/` layer
- a small shared CVS runtime for detection, command execution, and parsing
- vertical feature slices for `status`, `update`, `commit`, `diff`, `log`, `annotate`, and `conflicts`
- no hard runtime dependencies beyond Neovim itself
- optional UX layers such as pickers and signs isolated from the core

This is the best fit for the draft because it keeps the Stage 1 workflow small, matches CVS better than Git-centric abstractions, and keeps the code easy to test: parsers and services stay independent from buffers and keymaps.

## What The References Suggest

### 1. `vim-fugitive`

Keep:

- command-first UX
- repo context attached to buffers
- editor-native scratch buffers for log, blame, diff, and status-like views

Avoid:

- the monolithic shape of the implementation

Reason:

- `vim-fugitive` is still the best model for command ergonomics, but much of its behavior lives in a huge Vimscript/autoload surface. That worked historically, but it is not the shape to copy for a new Neovim plugin.

Source:

- [vim-fugitive](https://github.com/tpope/vim-fugitive)

### 2. `gitsigns.nvim`

Keep:

- thin `plugin/` bootstrap
- a per-buffer attach model
- explicit cache and state management
- debounced updates and file watchers
- strong test coverage around real repository behavior

Avoid:

- making inline UI the center of the architecture in v1

Reason:

- `gitsigns.nvim` is a good example of small Lua modules with clean boundaries between config, attach logic, state, and actions. For CVS, the architectural lesson is the state model and update orchestration, not the signs feature itself.

Source:

- [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim)

### 3. `neogit`

Keep:

- separation between command execution and buffer/action modules
- dedicated modules per view
- repo-local instances rather than one giant global singleton

Avoid:

- dashboard-first scope
- overgrowing the action surface before the underlying domain model is stable

Reason:

- `neogit` has a useful split between Git helpers and UI buffers, but it also shows how quickly a dashboard can become the project center of gravity. For CVS, the status buffer should exist, but it should not dictate the entire architecture.

Source:

- [neogit](https://github.com/NeogitOrg/neogit)

### 4. `diffview.nvim`

Keep:

- dedicated views for diff/history workflows
- a clean adapter boundary between VCS semantics and UI
- separation between data loading and rendering

Avoid:

- building a generic scene/layout framework too early

Reason:

- `diffview.nvim` is the clearest example of isolating VCS-specific logic from UI views. The CVS plugin should borrow that boundary, but not its full framework complexity unless the project later grows beyond the current scope.

Source:

- [diffview.nvim](https://github.com/sindrets/diffview.nvim)

### 5. CVS-specific lessons from GNU CVS docs

Keep:

- workspace detection based on `CVS/Root`, `CVS/Repository`, `CVS/Entries`, and optional `CVS/Tag`
- a status/dashboard flow backed by `cvs -n update`
- conflict handling built around CVS update status codes and backup files

Reason:

- the GNU CVS manual documents the working-directory metadata and the `update` status codes that should drive the plugin's internal model
- PCL-CVS is a useful proof that a CVS status buffer built on `cvs -n update` is a natural workflow

Sources:

- [GNU CVS: Working directory storage](https://www.gnu.org/software/trans-coord/manual/cvs/html_node/Working-directory-storage.html)
- [GNU CVS: update output](https://www.gnu.org/software/trans-coord/manual/cvs/html_node/update-output.html)
- [GNU CVS: Editing files](https://www.gnu.org/software/trans-coord/manual/cvs/html_node/Editing-files.html)
- [GNU Emacs PCL-CVS](https://www.gnu.org/software/emacs/manual/html_mono/pcl-cvs)

## Architecture Choice

Use a hybrid architecture:

- shared low-level runtime for CVS concepts
- vertical feature modules for user-facing workflows

Do not use a purely horizontal split like "all parsers here, all buffers here, all commands here" for everything. That shape tends to scatter one feature across too many folders.

Do not use a purely feature-only split either. CVS workspace detection, command execution, metadata parsing, and queueing are shared concerns and should not be duplicated.

The right compromise is:

- `core/` for shared plugin runtime primitives
- `cvs/` for CVS-specific infrastructure
- `features/` for the actual user workflows
- `ui/` for shared buffer/render/window helpers
- `integrations/` for optional adapters

## Proposed Repository Layout

```text
doc/
  cvs.txt

plugin/
  cvs.lua

lua/cvs/
  init.lua
  config.lua
  commands.lua
  health.lua

  core/
    errors.lua
    events.lua
    queue.lua
    state.lua
    types.lua
    util.lua

  cvs/
    capabilities.lua
    cmd.lua
    context.lua
    entries.lua
    runner.lua

  ui/
    buffer.lua
    highlights.lua
    preview.lua
    quickfix.lua
    render.lua
    window.lua

  features/
    status/
      actions.lua
      buffer.lua
      parse.lua
      render.lua
      service.lua
    update/
      parse.lua
      service.lua
    commit/
      buffer.lua
      service.lua
    diff/
      service.lua
      view.lua
    log/
      buffer.lua
      parse.lua
      service.lua
    annotate/
      buffer.lua
      parse.lua
      service.lua
    conflicts/
      detect.lua
      parse.lua
      service.lua
      view.lua
    files/
      service.lua

  integrations/
    picker.lua
    signs.lua

tests/
  fixtures/
    cvs/
      annotate/
      entries/
      log/
      status/
      update/
  unit/
    cvs/
    features/
  integration/
    harness/
    workflows/
  ui/
```

## Module Responsibilities

### `plugin/cvs.lua`

Only:

- define user commands
- define autocommands
- call `require("cvs").setup()`

Never:

- parse CVS output
- own business logic
- contain feature implementations

### `lua/cvs/core/`

Shared plugin primitives that are not CVS-command-specific:

- `queue.lua`: serialize mutating operations per workspace
- `state.lua`: cache workspace snapshots and per-buffer attachments
- `events.lua`: emit internal events and `User` autocommands such as `CvsChanged`
- `types.lua`: shared enums and typed shapes
- `errors.lua`: normalize execution and parse failures

### `lua/cvs/cvs/`

The CVS boundary. Every feature goes through this layer.

- `context.lua`
  - detect the CVS workspace from a file or directory
  - read `CVS/Root`, `CVS/Repository`, `CVS/Entries`, `CVS/Tag`
  - return a `WorkspaceContext`
- `entries.lua`
  - parse `CVS/Entries`
  - keep the parser separate because it is stable, fixture-friendly, and easy to unit test
- `cmd.lua`
  - turn typed requests into argv lists
  - keep flags and argument order in one place
- `runner.lua`
  - wrap `vim.system`
  - collect stdout, stderr, exit code, cwd, and duration
  - apply timeouts and environment handling
- `capabilities.lua`
  - probe `cvs` availability and optional capabilities such as watch/edit flows

Rule:

- UI modules must never shell out directly. Only `runner.lua` executes CVS.

### `lua/cvs/features/`

Feature slices own the user-facing workflows.

- `status`
  - authoritative workspace snapshot
  - status buffer
  - actions like open diff, commit file, update file, open log
- `update`
  - parse `update` output
  - refresh cache
  - publish changed/conflict events
- `commit`
  - commit message buffer
  - commit execution
- `diff`
  - diff orchestration and view opening
- `log`
  - file history parsing and history buffer
- `annotate`
  - blame/annotate buffer
- `conflicts`
  - detect CVS conflict states
  - resolve via diff/vimdiff-style flow
- `files`
  - add/remove helpers for file lifecycle commands

Rule:

- each feature owns its service module
- buffer and action modules remain feature-local
- shared UI primitives stay in `ui/`

### `lua/cvs/ui/`

Reusable editor primitives:

- scratch buffer creation
- floating/split/tab window helpers
- render helpers
- preview windows
- quickfix publishing
- common highlights

This keeps buffer code consistent without turning the project into a full UI framework.

### `lua/cvs/integrations/`

Only optional integrations:

- picker adapters
- future signs support
- possible third-party UI bridges

The core plugin must work without any of these modules.

## Runtime Model

The execution path for any command should look like this:

```text
User command
  -> feature service
  -> workspace/context lookup
  -> command builder
  -> runner
  -> feature parser
  -> state/cache update
  -> UI render or quickfix output
```

Example:

```text
:CvsStatus
  -> features/status/service.lua
  -> cvs/context.lua
  -> cvs/cmd.lua builds `cvs -nq update`
  -> cvs/runner.lua executes
  -> features/status/parse.lua returns typed file states
  -> core/state.lua stores snapshot
  -> features/status/buffer.lua renders
```

This separation matters because CVS output is noisy and irregular. If parsing leaks into actions or buffer code, the plugin will become hard to reason about very quickly.

## Internal Data Shapes

The project should standardize a few core shapes early:

- `WorkspaceContext`
  - `root_dir`
  - `cvs_root`
  - `repository`
  - `sticky_tag`
  - `entries`
- `CommandResult`
  - `code`
  - `stdout`
  - `stderr`
  - `cwd`
  - `duration_ms`
- `FileState`
  - `path`
  - `status`
  - `revision`
  - `repository_revision`
  - `sticky`
  - `message`
- `StatusSnapshot`
  - `workspace`
  - `files`
  - `generated_at`

These types should live in `core/types.lua` and be the boundary between parsing, state, and UI.

## Concurrency And State

Treat CVS commands in two classes:

- read operations
  - `status`, `diff`, `log`, `annotate`
- mutating operations
  - `update`, `commit`, `add`, `remove`, and later `edit` or `unedit`

Recommendation:

- allow read operations to run independently
- serialize mutating operations per workspace with `core/queue.lua`
- invalidate cached snapshots after every successful mutating operation
- emit `User CvsChanged` on meaningful workspace changes

This borrows the good part of the manager/cache patterns from `gitsigns.nvim` without dragging signs-specific complexity into the design.

## Status Buffer Strategy

Make the status buffer a consumer of the domain model, not the owner of it.

Recommended source of truth:

- `cvs -nq update` for the main snapshot
- `CVS/Entries` for local metadata
- targeted follow-up commands only when the user drills deeper

Why:

- GNU CVS documents `update` output status codes directly
- PCL-CVS uses `cvs -n update` as the basis for its status view
- this is closer to CVS behavior than trying to imitate Git index semantics

Important:

- do not model staging
- do not build the API around "hunks"
- do not assume rename tracking

## Conflict Resolution Strategy

Design conflicts as a dedicated feature, not an afterthought inside `update`.

Recommended model:

- `features/conflicts/detect.lua` identifies conflicts from update output and local backup files
- `features/conflicts/service.lua` prepares the working set
- `features/conflicts/view.lua` opens a vimdiff-style layout

CVS-specific detail:

- the GNU CVS manual documents the `C` update code and the `.#file.revision` backup file convention

That means conflict handling is important enough to deserve its own module boundary from day one.

## Testing Strategy

The code layout above is designed around three test layers.

### 1. Unit tests

Target:

- `entries.lua`
- all `parse.lua` modules
- `cmd.lua`
- small helpers in `context.lua`

Inputs:

- fixture files captured from real CVS output

Goal:

- parser confidence without Neovim UI setup

### 2. Integration tests

Target:

- full workflows against temporary CVS repositories

Examples:

- detect workspace from checked-out file
- status after local modification
- update with patch vs conflict
- commit/add/remove happy paths

Goal:

- prove that command building and parsing match real CVS behavior

### 3. UI smoke tests

Target:

- status buffer rendering
- log buffer opening
- annotate buffer navigation
- conflict view opening

Goal:

- verify buffer options, keymaps, and render output without pushing all logic into UI tests

Key rule:

- keep the runtime dependency-free, even if the test harness uses dev-only helpers

## Do And Don't List

Do:

- keep `plugin/` tiny
- keep CVS execution behind a single runner
- parse raw output exactly once per feature
- let features own their buffers and actions
- use cache and queues at the workspace level
- isolate optional integrations from the core

Don't:

- copy Fugitive's monolithic structure
- build a generic UI framework before the first usable CVS workflow exists
- let the status dashboard become the architecture
- center the plugin on signs in v1
- import Git-only concepts like staging or rename-driven UX
- scatter one feature across unrelated global helper files

## Suggested Delivery Order

### Phase 0: scaffold

- `plugin/cvs.lua`
- `lua/cvs/init.lua`
- `lua/cvs/config.lua`
- `lua/cvs/commands.lua`
- `lua/cvs/cvs/context.lua`
- `lua/cvs/cvs/runner.lua`
- `lua/cvs/cvs/cmd.lua`
- `lua/cvs/core/types.lua`
- `lua/cvs/core/errors.lua`

### Phase 1: first usable CLI and status flow

- `features/status`
- `features/update`
- `features/files`
- `features/commit`

Goal:

- working command-first plugin without advanced UI

### Phase 2: review-oriented buffers

- `features/diff`
- `features/log`
- `features/annotate`
- `features/conflicts`
- shared `ui/` modules

### Phase 3: optional productivity layer

- picker integration
- quickfix polish
- status dashboard actions expansion
- optional signs

### Phase 4: advanced repo-specific behavior

- tags and branches
- checkout/import helpers
- edit/unedit watch workflows
- web integrations

## Defaults I Would Lock In Now

- Neovim-native Lua plugin, not Vim compatibility first
- command-first UX, with richer buffers layered on top
- no runtime dependency requirement for core functionality
- `cvs -nq update` as the main status snapshot source
- conflict resolution as a first-class Stage 1 or early Stage 2 concern
- no signs, no picker requirement, and no lock/watch workflow in the first usable release

## Bottom Line

The safest architecture for this project is:

- thin commands
- one CVS runtime boundary
- feature-local services and buffers
- shared UI primitives
- isolated optional integrations

That gives you the best parts of Fugitive, Gitsigns, Neogit, and Diffview without inheriting their biggest complexity traps.
