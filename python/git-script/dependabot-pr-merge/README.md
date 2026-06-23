# Dependabot PR Bulk Merger

Find every open **Dependabot** pull request across all repositories in a GitHub organization or user account and merge them **sequentially**.

<br/>

## Features

- **list** — Preview every open Dependabot PR grouped by repository
- **merge** — Merge the Dependabot PRs one by one (sequentially)
- Matches both `dependabot[bot]` and the legacy `dependabot-preview[bot]`
- **Per-repo serialization** — when a repo has 2+ PRs, merges them one at a time and waits for each merge's changelog/release workflow to finish before the next (so two never run concurrently)
- **Auto-rebase followups** — after the first merge in a repo, the next PR is `behind`; the tool runs `update-branch`, waits for CI, then merges
- `--one-per-repo` — safest mode: merge at most one PR per repo per run
- Skips PRs with conflicts (`dirty`) or blocked checks/reviews
- Optional **wait for CI checks** before merging each PR
- Automatic **rate-limit** handling
- **Dry-run** mode for safe previewing
- JSON **execution logs** saved to `logs/`

<br/>

## Prerequisites

- Python 3.10+
- A GitHub **Personal Access Token** with `repo` scope (write access to merge)

<br/>

### Setup (Virtual Environment)

#### macOS / Linux

```bash
python3 -m venv venv
source venv/bin/activate
pip3 install -r requirements.txt
```

#### Windows (PowerShell)

```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
pip3 install -r requirements.txt
```

Dependencies: `requests`

<br/>

## Authentication

```bash
export GITHUB_TOKEN='ghp_xxxxxxxxxxxx'
```

<br/>

## Usage

```bash
# Preview every open Dependabot PR
python dependabot-pr-merge.py list --org somaz94

# Merge all Dependabot PRs sequentially (squash by default)
python dependabot-pr-merge.py merge --org somaz94

# Merge with a specific method
python dependabot-pr-merge.py merge --org somaz94 --merge-method merge

# Wait for required CI checks before each merge (up to 10 min per PR)
python dependabot-pr-merge.py merge --org somaz94 --wait-checks

# Safest for changelog/release repos: one PR per repo per run
python dependabot-pr-merge.py merge --org somaz94 --one-per-repo

# Target specific repositories only
python dependabot-pr-merge.py merge --org somaz94 --repos kube-diff,git-bridge

# Dry-run mode (no actual merge)
python dependabot-pr-merge.py merge --org somaz94 --dry-run

# Skip the confirmation prompt
python dependabot-pr-merge.py merge --org somaz94 -y
```

<br/>

## Options (`merge`)

| Option | Default | Description |
|---|---|---|
| `--merge-method {merge,squash,rebase}` | `squash` | Merge strategy |
| `--one-per-repo` | off | Merge at most one PR per repo per run; defer the rest (safest for changelog/release repos) |
| `--wait-checks` | off | Wait for required CI checks before merging each PR |
| `--checks-timeout <sec>` | `600` | Max seconds to wait for checks per PR |
| `--workflow-timeout <sec>` | `300` | Max seconds to wait for a repo's workflows (changelog/release) to finish between same-repo merges |
| `--poll-interval <sec>` | `15` | Seconds between check-status / workflow polls |
| `--merge-behind` | off | For behind-base PRs, rebase via `update-branch` then merge (same-repo followups do this automatically) |
| `--delay <sec>` | `3` | Seconds between merges (API courtesy) |
| `--repos a,b` | all | Limit to specific repositories |
| `--dry-run` | off | Simulate without merging |
| `-y`, `--yes` | off | Skip confirmation prompt |
| `-v`, `--verbose` | off | Verbose logging |

<br/>

## Merge-state handling

GitHub reports a `mergeable_state` per PR. The tool acts as follows:

| State | Action |
|---|---|
| `clean` / `unstable` / `has_hooks` | Merge |
| `dirty` (conflict) | Skip |
| `blocked` (required checks/reviews pending) | Skip — or wait with `--wait-checks` |
| `behind` (base moved ahead) | Skip — or attempt with `--merge-behind` |
| `unknown` (still computing) | Poll until it settles |

<br/>

## Changelog / release race handling

Repos with **2+ Dependabot PRs** where merging generates a changelog/release
(e.g. git-cliff regenerating `CHANGELOG.md`, release-please) are the tricky case:
merging back-to-back makes the second workflow run concurrently with the first
and clobber the changelog. The tool handles this:

1. PRs are **grouped by repo** — different repos run independently (their
   changelog files don't collide).
2. Within one repo, PRs merge **one at a time**. After each merge, the tool
   gives the push ~12s to register its workflow run, then **waits for that
   repo's Actions workflows to go idle** (`--workflow-timeout`) before the next
   merge, so two changelog workflows never overlap.
3. The next same-repo PR is now `behind` base — the tool runs `update-branch`
   to rebase it onto the changelog commit, waits for CI, then merges.

If you'd rather avoid in-run rebasing entirely, use `--one-per-repo`: it merges
one PR per repo per run and defers the rest. Re-run later (Dependabot will have
rebased the remaining PRs by then).

<br/>

## Notes

- Merges run strictly **one at a time**; same-repo merges are additionally serialized behind their changelog/release workflows.
- Each PR is merged against its current head `sha`; if the branch changes mid-run, GitHub rejects the merge and it is reported as failed.
- A JSON run log is written to `logs/dependabot_merge_<timestamp>.json`.

<br/>

> `dependabot-pr-merge-kr.py` is a Korean-comment mirror of `dependabot-pr-merge.py` — identical behavior, Korean docstrings/messages.
