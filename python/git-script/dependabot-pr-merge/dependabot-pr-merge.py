#!/usr/bin/env python3
"""
Dependabot PR Bulk Merger
=========================
Find every open Dependabot pull request across an organization / user's
repositories and merge them sequentially.

Features:
  - list   : List all open Dependabot PRs across repositories
  - merge  : Merge the Dependabot PRs one by one (sequentially)

Usage examples:
  # Preview every open Dependabot PR
  python dependabot-pr-merge.py list --org somaz94

  # Merge all Dependabot PRs sequentially (squash by default)
  python dependabot-pr-merge.py merge --org somaz94

  # Merge with a specific method
  python dependabot-pr-merge.py merge --org somaz94 --merge-method merge

  # Wait for required CI checks before each merge (up to 10 min per PR)
  python dependabot-pr-merge.py merge --org somaz94 --wait-checks

  # Target specific repositories only
  python dependabot-pr-merge.py merge --org somaz94 --repos kube-diff,git-bridge

  # Dry-run mode (no actual merge)
  python dependabot-pr-merge.py merge --org somaz94 --dry-run

  # Skip the confirmation prompt
  python dependabot-pr-merge.py merge --org somaz94 -y
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

import requests

# ─────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────
GITHUB_API = "https://api.github.com"
PER_PAGE = 100
RATE_LIMIT_BUFFER = 10
REQUEST_TIMEOUT = 30

# Dependabot author logins (current + legacy preview app)
DEPENDABOT_LOGINS = {"dependabot[bot]", "dependabot-preview[bot]"}

# Seconds to let a just-pushed merge queue its workflow run before polling for
# idle. Without this grace, count_active_runs() can read 0 and return before a
# changelog/release workflow has even started.
WORKFLOW_START_GRACE = 12

# mergeable_state values that mean "ready to merge right now"
MERGEABLE_STATES = {"clean", "unstable", "has_hooks"}


class Color:
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RESET = "\033[0m"


# ─────────────────────────────────────────────
# Data classes
# ─────────────────────────────────────────────
@dataclass
class PullRequest:
    repo: str
    number: int
    title: str
    head: str
    url: str


@dataclass
class PRResult:
    repo: str
    number: int
    title: str
    action: str  # merged / skipped / failed
    success: bool
    message: str = ""


@dataclass
class Stats:
    total: int = 0
    merged: int = 0
    failed: int = 0
    skipped: int = 0
    details: list[PRResult] = field(default_factory=list)

    def record(self, result: PRResult):
        self.total += 1
        if result.success:
            if result.action == "skipped":
                self.skipped += 1
            else:
                self.merged += 1
        else:
            self.failed += 1
        self.details.append(result)


# ─────────────────────────────────────────────
# GitHub API Client
# ─────────────────────────────────────────────
class GitHubClient:
    """GitHub API client with rate-limit handling."""

    def __init__(self, token: str):
        self.token = token
        self.session = requests.Session()
        self.session.headers.update(
            {
                "Authorization": f"token {token}",
                "Accept": "application/vnd.github.v3+json",
            }
        )

    def _request(self, method: str, url: str, **kwargs) -> requests.Response:
        resp = self.session.request(method, url, timeout=REQUEST_TIMEOUT, **kwargs)
        self._handle_rate_limit(resp)
        return resp

    def get(self, path: str, **kwargs) -> requests.Response:
        return self._request("GET", f"{GITHUB_API}{path}", **kwargs)

    def put(self, path: str, **kwargs) -> requests.Response:
        return self._request("PUT", f"{GITHUB_API}{path}", **kwargs)

    def _handle_rate_limit(self, resp: requests.Response):
        remaining = int(resp.headers.get("X-RateLimit-Remaining", 999))
        if remaining <= RATE_LIMIT_BUFFER:
            reset_ts = int(resp.headers.get("X-RateLimit-Reset", 0))
            wait = max(reset_ts - int(time.time()), 1) + 1
            logging.warning(
                f"Rate limit approaching (remaining={remaining}). Waiting {wait}s..."
            )
            time.sleep(wait)

    def list_repos(self, org: str) -> list[str]:
        repos: list[str] = []
        page = 1
        while True:
            resp = self.get(
                f"/orgs/{org}/repos", params={"per_page": PER_PAGE, "page": page}
            )
            if resp.status_code == 404:
                resp = self.get(
                    f"/users/{org}/repos",
                    params={"per_page": PER_PAGE, "page": page, "type": "owner"},
                )
            if resp.status_code != 200:
                raise RuntimeError(
                    f"Failed to list repositories: HTTP {resp.status_code}\n{resp.text}"
                )
            data = resp.json()
            if not data:
                break
            repos.extend(
                r["name"]
                for r in data
                if not r.get("archived", False) and not r.get("disabled", False)
            )
            logging.info(f"  Page {page}: {len(data)} repos (total {len(repos)})")
            page += 1
        return sorted(repos)

    def list_dependabot_prs(self, org: str, repo: str) -> list[PullRequest]:
        prs: list[PullRequest] = []
        page = 1
        while True:
            resp = self.get(
                f"/repos/{org}/{repo}/pulls",
                params={"state": "open", "per_page": PER_PAGE, "page": page},
            )
            if resp.status_code != 200:
                return prs
            data = resp.json()
            if not data:
                break
            for pr in data:
                login = (pr.get("user") or {}).get("login", "")
                if login in DEPENDABOT_LOGINS:
                    prs.append(
                        PullRequest(
                            repo=repo,
                            number=pr["number"],
                            title=pr["title"],
                            head=(pr.get("head") or {}).get("ref", ""),
                            url=pr["html_url"],
                        )
                    )
            if len(data) < PER_PAGE:
                break
            page += 1
        return prs

    def get_pr(self, org: str, repo: str, number: int) -> dict:
        resp = self.get(f"/repos/{org}/{repo}/pulls/{number}")
        if resp.status_code != 200:
            raise RuntimeError(
                f"Failed to fetch PR {org}/{repo}#{number}: HTTP {resp.status_code}"
            )
        return resp.json()

    def merge_pr(
        self, org: str, repo: str, number: int, sha: str, method: str
    ) -> tuple[bool, str]:
        resp = self.put(
            f"/repos/{org}/{repo}/pulls/{number}/merge",
            json={"sha": sha, "merge_method": method},
        )
        if resp.status_code == 200:
            return True, "merged"
        try:
            msg = resp.json().get("message", resp.text)
        except ValueError:
            msg = resp.text
        return False, f"HTTP {resp.status_code}: {msg}"

    def update_branch(self, org: str, repo: str, number: int) -> tuple[bool, str]:
        """Rebase the PR branch onto the latest base (PUT .../update-branch)."""
        resp = self.put(f"/repos/{org}/{repo}/pulls/{number}/update-branch")
        if resp.status_code == 202:
            return True, "update requested"
        try:
            msg = resp.json().get("message", resp.text)
        except ValueError:
            msg = resp.text
        return False, f"HTTP {resp.status_code}: {msg}"

    def count_active_runs(self, org: str, repo: str) -> int:
        """Count queued + in-progress Actions workflow runs for a repo."""
        total = 0
        for status in ("queued", "in_progress"):
            resp = self.get(
                f"/repos/{org}/{repo}/actions/runs",
                params={"status": status, "per_page": 1},
            )
            if resp.status_code == 200:
                total += resp.json().get("total_count", 0)
        return total


# ─────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────
def cmd_list(client: GitHubClient, args: argparse.Namespace):
    """List all open Dependabot PRs across repositories."""
    repos = _resolve_repos(client, args)

    print(f"\n{Color.BOLD}Open Dependabot Pull Requests{Color.RESET}")
    print(f"Scope: {len(repos)} repositories\n")

    total = 0
    for repo in repos:
        prs = client.list_dependabot_prs(args.org, repo)
        if not prs:
            continue
        total += len(prs)
        print(f"{Color.BOLD}{Color.CYAN}{args.org}/{repo}{Color.RESET}")
        for pr in prs:
            print(
                f"  #{pr.number} {pr.title}\n"
                f"      {Color.DIM}{pr.head} | {pr.url}{Color.RESET}"
            )
        print()

    if total == 0:
        print(f"{Color.GREEN}No open Dependabot PRs found.{Color.RESET}")
    else:
        print(f"{Color.BOLD}Total: {total} Dependabot PR(s){Color.RESET}")


def cmd_merge(client: GitHubClient, args: argparse.Namespace):
    """Merge all Dependabot PRs sequentially."""
    repos = _resolve_repos(client, args)

    print(f"\n{Color.BOLD}Dependabot PR Sequential Merge{Color.RESET}")
    print(f"Scope: {len(repos)} repositories | merge method: {args.merge_method}")
    if args.one_per_repo:
        print("Mode: one PR per repo per run (re-run to merge the rest)")
    if args.wait_checks:
        print(f"Waiting for CI checks: up to {args.checks_timeout}s per PR")
    if args.dry_run:
        _print_warn("DRY-RUN mode: no actual merge will be performed")
    print()

    # Collect all Dependabot PRs first so we can show the scope before merging.
    logging.info("Collecting Dependabot PRs...")
    all_prs: list[PullRequest] = []
    for repo in repos:
        all_prs.extend(client.list_dependabot_prs(args.org, repo))

    if not all_prs:
        print(f"{Color.GREEN}No open Dependabot PRs to merge.{Color.RESET}")
        return

    groups = _group_by_repo(all_prs)
    multi = [r for r, prs in groups.items() if len(prs) > 1]

    print(f"Found {Color.BOLD}{len(all_prs)}{Color.RESET} Dependabot PR(s):")
    for pr in all_prs:
        print(f"  {Color.CYAN}{args.org}/{pr.repo}{Color.RESET} #{pr.number} {pr.title}")
    if multi:
        # Same-repo PRs are merged one at a time, waiting for each merge's
        # changelog/release workflow to finish before the next, so two never
        # run concurrently.
        print(
            f"\n  {Color.YELLOW}Note: {len(multi)} repo(s) have 2+ PRs "
            f"({', '.join(multi)}) — these are merged serially per repo.{Color.RESET}"
        )
    print()

    if not args.dry_run and not args.yes:
        if not _confirm(f"Merge {len(all_prs)} Dependabot PR(s) sequentially?"):
            return

    stats = Stats()
    idx = 0

    for repo, prs in groups.items():
        for i, pr in enumerate(prs):
            idx += 1
            _print_progress(idx, len(all_prs), f"{args.org}/{pr.repo} #{pr.number}")
            print(f"  {Color.DIM}{pr.title}{Color.RESET}")

            followup = i > 0  # 2nd+ Dependabot PR in the SAME repo

            if followup and not args.dry_run:
                if args.one_per_repo:
                    msg = "deferred (one-per-repo; re-run after Dependabot rebases)"
                    stats.record(
                        PRResult(pr.repo, pr.number, pr.title, "skipped", True, msg)
                    )
                    _print_skip(msg)
                    continue
                # The previous merge in this repo may have triggered a
                # changelog/release workflow. Let it finish first so the two
                # never run concurrently.
                _wait_repo_idle(client, args, pr.repo)

            _merge_one(client, args, pr, stats, followup=followup)

            if idx < len(all_prs) and not args.dry_run:
                time.sleep(args.delay)

    _print_summary(stats, args)


# ─────────────────────────────────────────────
# Merge logic
# ─────────────────────────────────────────────
def _merge_one(
    client: GitHubClient,
    args: argparse.Namespace,
    pr: PullRequest,
    stats: Stats,
    followup: bool = False,
):
    try:
        detail = _resolve_mergeable(client, args, pr)
    except RuntimeError as e:
        result = PRResult(pr.repo, pr.number, pr.title, "failed", False, str(e))
        stats.record(result)
        _print_err(str(e))
        return

    state = detail.get("mergeable_state", "unknown")
    mergeable = detail.get("mergeable")
    sha = (detail.get("head") or {}).get("sha", "")

    # Skip on conflicts / not-mergeable states.
    if mergeable is False or state == "dirty":
        msg = f"not mergeable (conflict, state={state})"
        stats.record(PRResult(pr.repo, pr.number, pr.title, "skipped", True, msg))
        _print_skip(msg)
        return

    # A behind branch (base moved ahead — e.g. a changelog commit just landed
    # from the previous same-repo merge). For followups, or with --merge-behind,
    # rebase the PR branch onto the new base and wait for it to settle, then
    # merge. Otherwise skip.
    if state == "behind":
        if not (followup or args.merge_behind):
            msg = "branch is behind base (use --merge-behind, or it auto-rebases for same-repo followups)"
            stats.record(PRResult(pr.repo, pr.number, pr.title, "skipped", True, msg))
            _print_skip(msg)
            return
        if args.dry_run:
            stats.record(
                PRResult(pr.repo, pr.number, pr.title, "merged", True, "dry-run (would rebase+merge)")
            )
            _print_ok("would update-branch then merge (dry-run)")
            return
        ok, m = client.update_branch(args.org, pr.repo, pr.number)
        if not ok:
            msg = f"update-branch failed: {m}"
            stats.record(PRResult(pr.repo, pr.number, pr.title, "failed", False, msg))
            _print_err(msg)
            return
        _print_wait("rebasing branch onto base (update-branch), waiting for checks...")
        time.sleep(args.poll_interval)
        try:
            # After a rebase, CI restarts — always wait for it to settle here.
            detail = _resolve_mergeable(client, args, pr, wait_checks=True)
        except RuntimeError as e:
            stats.record(PRResult(pr.repo, pr.number, pr.title, "failed", False, str(e)))
            _print_err(str(e))
            return
        state = detail.get("mergeable_state", "unknown")
        mergeable = detail.get("mergeable")
        sha = (detail.get("head") or {}).get("sha", "")
        if mergeable is False or state in ("dirty", "behind", "blocked"):
            msg = f"still not mergeable after rebase (state={state})"
            stats.record(PRResult(pr.repo, pr.number, pr.title, "skipped", True, msg))
            _print_skip(msg)
            return

    if state == "blocked":
        msg = "merge blocked (required checks/reviews not satisfied)"
        stats.record(PRResult(pr.repo, pr.number, pr.title, "skipped", True, msg))
        _print_skip(msg)
        return

    if state not in MERGEABLE_STATES:
        msg = f"unexpected mergeable_state={state}"
        stats.record(PRResult(pr.repo, pr.number, pr.title, "skipped", True, msg))
        _print_skip(msg)
        return

    if args.dry_run:
        stats.record(
            PRResult(pr.repo, pr.number, pr.title, "merged", True, f"dry-run (state={state})")
        )
        _print_ok(f"would merge (state={state}, dry-run)")
        return

    ok, msg = client.merge_pr(args.org, pr.repo, pr.number, sha, args.merge_method)
    if ok:
        stats.record(PRResult(pr.repo, pr.number, pr.title, "merged", True))
        _print_ok("merged")
    else:
        stats.record(PRResult(pr.repo, pr.number, pr.title, "failed", False, msg))
        _print_err(msg)


def _resolve_mergeable(
    client: GitHubClient,
    args: argparse.Namespace,
    pr: PullRequest,
    wait_checks: bool | None = None,
) -> dict:
    """
    Fetch PR detail and resolve its mergeable state.

    GitHub computes `mergeable` / `mergeable_state` asynchronously, so the first
    response may carry `mergeable: null` / `mergeable_state: unknown`. We poll
    until it settles. When waiting for checks is enabled we keep polling while
    the state is `blocked` (required checks still running) up to --checks-timeout.

    `wait_checks` overrides args.wait_checks (used after a rebase, when CI always
    restarts and we must wait regardless of the flag).
    """
    if wait_checks is None:
        wait_checks = args.wait_checks
    poll_interval = max(args.poll_interval, 1)
    settle_deadline = time.time() + 30  # max wait for the null/unknown to settle
    checks_deadline = time.time() + args.checks_timeout

    while True:
        detail = client.get_pr(args.org, pr.repo, pr.number)
        state = detail.get("mergeable_state", "unknown")
        mergeable = detail.get("mergeable")

        # Still computing — wait for it to settle.
        if mergeable is None or state == "unknown":
            if time.time() < settle_deadline:
                time.sleep(2)
                continue
            return detail

        # Waiting for required CI checks to finish.
        if wait_checks and state == "blocked":
            if time.time() < checks_deadline:
                _print_wait(f"checks pending (state={state}), waiting {poll_interval}s...")
                time.sleep(poll_interval)
                continue
            return detail

        return detail


# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────
def _resolve_repos(client: GitHubClient, args: argparse.Namespace) -> list[str]:
    if args.repos:
        return [r.strip() for r in args.repos.split(",")]
    logging.info("Fetching repository list...")
    repos = client.list_repos(args.org)
    logging.info(f"Found {len(repos)} repositories (excluding archived)")
    return repos


def _group_by_repo(prs: list[PullRequest]) -> dict[str, list[PullRequest]]:
    """Group PRs by repo, preserving discovery order (dict keeps insertion order)."""
    groups: dict[str, list[PullRequest]] = {}
    for pr in prs:
        groups.setdefault(pr.repo, []).append(pr)
    return groups


def _wait_repo_idle(client: GitHubClient, args: argparse.Namespace, repo: str):
    """
    Wait until a repo has no queued / in-progress Actions runs.

    Called between same-repo merges so a changelog/release workflow triggered by
    the previous merge finishes before the next merge — they never run at once.
    """
    deadline = time.time() + args.workflow_timeout
    poll_interval = max(args.poll_interval, 1)
    # Let the just-pushed merge register its workflow run before the first poll.
    _print_wait(f"letting workflows in {repo} register ({WORKFLOW_START_GRACE}s)...")
    time.sleep(WORKFLOW_START_GRACE)
    while True:
        active = client.count_active_runs(args.org, repo)
        if active == 0:
            return
        if time.time() >= deadline:
            _print_warn(
                f"workflows still active in {repo} after {args.workflow_timeout}s; proceeding anyway"
            )
            return
        _print_wait(
            f"{active} workflow run(s) active in {repo} (changelog/release?), waiting {poll_interval}s..."
        )
        time.sleep(poll_interval)


def _confirm(message: str) -> bool:
    print(f"\n{Color.YELLOW}{message} [y/N]{Color.RESET} ", end="")
    answer = input().strip().lower()
    if answer not in ("y", "yes"):
        print("Cancelled.")
        return False
    return True


def _print_progress(idx: int, total: int, label: str):
    print(f"\n[{idx}/{total}] {Color.BOLD}{label}{Color.RESET}")


def _print_ok(msg: str):
    print(f"  {Color.GREEN}✓ {msg}{Color.RESET}")


def _print_err(msg: str):
    print(f"  {Color.RED}✗ {msg}{Color.RESET}")


def _print_warn(msg: str):
    print(f"  {Color.YELLOW}⚠ {msg}{Color.RESET}")


def _print_skip(msg: str):
    print(f"  {Color.DIM}→ {msg}{Color.RESET}")


def _print_wait(msg: str):
    print(f"  {Color.BLUE}… {msg}{Color.RESET}")


def _print_summary(stats: Stats, args: argparse.Namespace):
    print(f"\n{Color.BOLD}{Color.BLUE}{'='*60}{Color.RESET}")
    print(f"{Color.BOLD}Summary{Color.RESET}")
    print(f"{Color.BOLD}{Color.BLUE}{'='*60}{Color.RESET}")
    print(f"  Total:    {stats.total}")
    print(f"  {Color.GREEN}Merged:   {stats.merged}{Color.RESET}")
    print(f"  {Color.DIM}Skipped:  {stats.skipped}{Color.RESET}")
    if stats.failed:
        print(f"  {Color.RED}Failed:   {stats.failed}{Color.RESET}")

    skipped = [d for d in stats.details if d.action == "skipped"]
    if skipped:
        print(f"\n{Color.DIM}Skipped details:{Color.RESET}")
        for r in skipped:
            print(f"  - {r.repo} #{r.number} {r.message}")

    failed = [d for d in stats.details if not d.success]
    if failed:
        print(f"\n{Color.RED}Failure details:{Color.RESET}")
        for r in failed:
            print(f"  - {r.repo} #{r.number} {r.message}")

    # Save log
    log_dir = Path("logs")
    log_dir.mkdir(exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = log_dir / f"dependabot_{args.command}_{ts}.json"
    log_data = {
        "command": args.command,
        "org": args.org,
        "timestamp": datetime.now().isoformat(),
        "dry_run": args.dry_run,
        "merge_method": args.merge_method,
        "stats": {
            "total": stats.total,
            "merged": stats.merged,
            "failed": stats.failed,
            "skipped": stats.skipped,
        },
        "details": [
            {
                "repo": d.repo,
                "number": d.number,
                "title": d.title,
                "action": d.action,
                "success": d.success,
                "message": d.message,
            }
            for d in stats.details
        ],
    }
    log_file.write_text(json.dumps(log_data, ensure_ascii=False, indent=2))
    print(f"\nLog saved: {Color.BOLD}{log_file}{Color.RESET}")


# ─────────────────────────────────────────────
# CLI (parents pattern -> flexible --org placement)
# ─────────────────────────────────────────────
def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--org", required=True, help="GitHub organization or username")
    common.add_argument(
        "--repos",
        help="Target specific repositories only (comma-separated, e.g. repo1,repo2)",
    )
    common.add_argument(
        "--dry-run", action="store_true", help="Simulate without merging"
    )
    common.add_argument(
        "-y", "--yes", action="store_true", help="Skip confirmation prompts"
    )
    common.add_argument(
        "-v", "--verbose", action="store_true", help="Enable verbose logging"
    )

    parser = argparse.ArgumentParser(
        prog="dependabot-pr-merge",
        description="Find and sequentially merge Dependabot pull requests across repositories",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Preview every open Dependabot PR
  python dependabot-pr-merge.py list --org somaz94

  # Merge all Dependabot PRs sequentially (squash by default)
  python dependabot-pr-merge.py merge --org somaz94

  # Wait for required CI checks before each merge
  python dependabot-pr-merge.py merge --org somaz94 --wait-checks

  # Target specific repositories only
  python dependabot-pr-merge.py merge --org somaz94 --repos kube-diff,git-bridge

  # Dry-run mode
  python dependabot-pr-merge.py merge --org somaz94 --dry-run
        """,
    )

    sub = parser.add_subparsers(dest="command", required=True, help="Command to execute")

    # list
    sub.add_parser(
        "list", parents=[common], help="List all open Dependabot PRs across repositories"
    )

    # merge
    p_merge = sub.add_parser(
        "merge", parents=[common], help="Merge Dependabot PRs sequentially"
    )
    p_merge.add_argument(
        "--merge-method",
        choices=["merge", "squash", "rebase"],
        default="squash",
        help="Merge method (default: squash)",
    )
    p_merge.add_argument(
        "--one-per-repo",
        action="store_true",
        help="Merge at most one Dependabot PR per repo per run; defer the rest "
        "(safest for changelog/release repos — re-run after Dependabot rebases)",
    )
    p_merge.add_argument(
        "--wait-checks",
        action="store_true",
        help="Wait for required CI checks to finish before merging each PR",
    )
    p_merge.add_argument(
        "--checks-timeout",
        type=int,
        default=600,
        help="Max seconds to wait for checks per PR (default: 600)",
    )
    p_merge.add_argument(
        "--workflow-timeout",
        type=int,
        default=300,
        help="Max seconds to wait for a repo's workflows (changelog/release) to "
        "finish between same-repo merges (default: 300)",
    )
    p_merge.add_argument(
        "--poll-interval",
        type=int,
        default=15,
        help="Seconds between check-status / workflow polls (default: 15)",
    )
    p_merge.add_argument(
        "--merge-behind",
        action="store_true",
        help="For behind-base PRs, rebase via update-branch then merge "
        "(same-repo followups do this automatically; default for others: skip)",
    )
    p_merge.add_argument(
        "--delay",
        type=int,
        default=3,
        help="Seconds to wait between merges (default: 3)",
    )

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

    # `list` has no merge-specific attributes; default them for shared helpers.
    if not hasattr(args, "merge_method"):
        args.merge_method = "-"

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
    )

    token = os.environ.get("GITHUB_TOKEN", "")
    if not token:
        print(f"{Color.RED}✗ Please set the GITHUB_TOKEN environment variable.{Color.RESET}")
        print("  export GITHUB_TOKEN='ghp_xxxxxxxxxxxx'")
        sys.exit(1)

    client = GitHubClient(token)

    commands = {
        "list": cmd_list,
        "merge": cmd_merge,
    }

    try:
        commands[args.command](client, args)
    except KeyboardInterrupt:
        print(f"\n{Color.YELLOW}Interrupted.{Color.RESET}")
        sys.exit(130)
    except Exception as e:
        logging.error(f"Unexpected error: {e}")
        if args.verbose:
            import traceback

            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
