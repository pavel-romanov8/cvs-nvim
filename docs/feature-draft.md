# CVS Neovim Plugin: Feature Draft

## Research Snapshot

There is no modern Neovim-native CVS plugin with broad adoption.

Older Vim-era references:
- [`vcscommand.vim`](https://www.vim.org/scripts/script.php?script_id=90): the closest historical benchmark; covered commit, diff, annotate, log, status, update, and vimdiff workflows.
- [`cvsmenu.vim`](https://launchpad.net/ubuntu/focal/amd64/vim-scripts/20180807ubuntu1): older menu-driven CVS integration.
- [`CVSconflict`](https://www.vim.org/scripts/script.php?script_id=1370): conflict resolution helper.
- [`cvsdiff.vim`](https://www.vim.org/scripts/script.php?script_id=1214): file diff helper.

Modern Git plugins worth learning from:
- [`vim-fugitive`](https://github.com/tpope/vim-fugitive): command-first workflow, strong status/log/diff/blame buffers.
- [`gitsigns.nvim`](https://github.com/lewis6991/gitsigns.nvim): inline signs, blame, hunk actions.
- [`neogit`](https://github.com/NeogitOrg/neogit): dashboard and action-driven workflow.
- [`diffview.nvim`](https://github.com/sindrets/diffview.nvim): dedicated diff/history review views.

## Product Direction

Build this as a modern CVS workflow for Neovim:
- command-first, similar to Fugitive
- editor-native buffers for status, diff, log, annotate, conflicts
- optional inline signs later, if performance and CVS output quality allow it

Avoid Git-only concepts that do not map well to CVS:
- staging area
- rebase/cherry-pick style workflows
- rename-heavy UX assumptions

## Stage 1: Core Workflow

Critical for daily use:
- detect CVS workspace from current file
- run CVS commands asynchronously
- show file/repo status
- update workspace
- commit changes
- add/remove files
- diff current file against repository/base revision
- view file history/log
- annotate/blame current file
- open and resolve conflicts in vimdiff-style flows

## Stage 2: Productivity Layer

Important, but not required for first usable release:
- dedicated status buffer with actions
- quickfix/location list integration for CVS output
- picker integration for changed files and history
- commit message buffer
- preview windows for diff/log/annotate
- optional gutter signs for changed lines

## Stage 3: Advanced / Repo-Specific

Useful only if the target CVS repo needs them:
- tags and branches support
- checkout/import helpers
- edit/unedit or lock-based workflows
- CVS web viewer integration
- multi-workspace views
- caching for history-heavy operations

## Priority Order

Highest priority:
- status
- update
- commit
- diff
- log
- annotate
- conflict resolution

Second priority:
- status dashboard
- picker/review UX
- commit buffer
- quickfix integration

Lowest priority:
- tags/branches
- checkout/import
- web integrations
- lock-specific workflows
