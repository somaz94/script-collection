#!/usr/bin/env python3
"""
GitHub Repository Secrets Manager
==================================
Bulk-manage Actions / Dependabot Secrets across repositories.

Features:
  - list       : List secrets for all repositories
  - sync       : Copy Actions Secrets -> Dependabot Secrets
  - update     : Add/update a specific secret across all repositories
  - delete     : Delete a specific secret from all repositories

Usage examples:
  # List secrets
  python github_secrets_manager.py list --org somaz94
  python github_secrets_manager.py list --org somaz94 --target dependabot

  # Sync Actions secrets to Dependabot (env var names matched directly)
  export GITLAB_TOKEN='glpat-xxx'
  export PAT_TOKEN='ghp-xxx'
  python github_secrets_manager.py sync --org somaz94

  # Sync using a .env file
  python github_secrets_manager.py sync --org somaz94 --env-file .secrets.env

  # Sync using JSON env var
  export SECRET_VALUES='{"GITLAB_TOKEN":"glpat-xxx","PAT_TOKEN":"ghp-xxx"}'
  python github_secrets_manager.py sync --org somaz94

  # Update a specific secret (Actions + Dependabot simultaneously)
  python github_secrets_manager.py update --org somaz94 \
    --secret-name GITLAB_TOKEN --secret-value 'glpat-xxx' --target both

  # Target specific repositories only
  python github_secrets_manager.py sync --org somaz94 --repos kube-diff,git-bridge

  # Dry-run mode
  python github_secrets_manager.py sync --org somaz94 --dry-run
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
from base64 import b64encode
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

import requests
from nacl import encoding, public

# ─────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────
GITHUB_API = "https://api.github.com"
PER_PAGE = 100
RATE_LIMIT_BUFFER = 10
REQUEST_TIMEOUT = 30


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
class RepoResult:
    repo: str
    action: str
    target: str
    success: bool
    message: str = ""


@dataclass
class Stats:
    total: int = 0
    success: int = 0
    failed: int = 0
    skipped: int = 0
    details: list[RepoResult] = field(default_factory=list)

    def record(self, result: RepoResult):
        self.total += 1
        if result.success:
            if result.action == "skipped":
                self.skipped += 1
            else:
                self.success += 1
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

    def delete_req(self, path: str, **kwargs) -> requests.Response:
        return self._request("DELETE", f"{GITHUB_API}{path}", **kwargs)

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
            repos.extend(r["name"] for r in data if not r.get("archived", False))
            logging.info(f"  Page {page}: {len(data)} repos (total {len(repos)})")
            page += 1
        return sorted(repos)

    def _secret_base(self, target: str) -> str:
        return "actions" if target == "actions" else "dependabot"

    def list_secrets(self, org: str, repo: str, target: str) -> list[str]:
        base = self._secret_base(target)
        secrets: list[str] = []
        page = 1
        while True:
            resp = self.get(
                f"/repos/{org}/{repo}/{base}/secrets",
                params={"per_page": PER_PAGE, "page": page},
            )
            if resp.status_code != 200:
                return []
            data = resp.json()
            secrets.extend(s["name"] for s in data.get("secrets", []))
            if len(data.get("secrets", [])) < PER_PAGE:
                break
            page += 1
        return secrets

    def get_public_key(self, org: str, repo: str, target: str) -> dict:
        base = self._secret_base(target)
        resp = self.get(f"/repos/{org}/{repo}/{base}/secrets/public-key")
        if resp.status_code != 200:
            raise RuntimeError(
                f"Failed to get public key ({org}/{repo}, {target}): HTTP {resp.status_code}"
            )
        return resp.json()

    def put_secret(
        self, org: str, repo: str, target: str, name: str, encrypted: str, key_id: str
    ) -> bool:
        base = self._secret_base(target)
        resp = self.put(
            f"/repos/{org}/{repo}/{base}/secrets/{name}",
            json={"encrypted_value": encrypted, "key_id": key_id},
        )
        return resp.status_code in (201, 204)

    def delete_secret(self, org: str, repo: str, target: str, name: str) -> bool:
        base = self._secret_base(target)
        resp = self.delete_req(f"/repos/{org}/{repo}/{base}/secrets/{name}")
        return resp.status_code == 204

    def secret_exists(self, org: str, repo: str, target: str, name: str) -> bool:
        base = self._secret_base(target)
        resp = self.get(f"/repos/{org}/{repo}/{base}/secrets/{name}")
        return resp.status_code == 200


# ─────────────────────────────────────────────
# Encryption
# ─────────────────────────────────────────────
def encrypt_secret(public_key: str, secret_value: str) -> str:
    pk = public.PublicKey(public_key.encode("utf-8"), encoding.Base64Encoder())
    sealed = public.SealedBox(pk).encrypt(secret_value.encode("utf-8"))
    return b64encode(sealed).decode("utf-8")


# ─────────────────────────────────────────────
# Commands
# ─────────────────────────────────────────────
def cmd_list(client: GitHubClient, args: argparse.Namespace):
    """List secrets for all repositories."""
    repos = _resolve_repos(client, args)
    targets = _resolve_targets(args.target)

    print(f"\n{Color.BOLD}Secret Listing{Color.RESET}")
    print(f"Scope: {len(repos)} repositories | target: {args.target}\n")

    for repo in repos:
        print(f"{Color.BOLD}{Color.CYAN}{args.org}/{repo}{Color.RESET}")
        for t in targets:
            secrets = client.list_secrets(args.org, repo, t)
            label = f"  [{t:>10}]"
            if secrets:
                print(f"{label} {', '.join(secrets)}")
            else:
                print(f"{label} {Color.DIM}(none){Color.RESET}")
        print()


def cmd_sync(client: GitHubClient, args: argparse.Namespace):
    """Sync Actions Secrets -> Dependabot Secrets."""
    repos = _resolve_repos(client, args)
    filter_secrets = (
        {s.strip().upper() for s in args.secrets.split(",")} if args.secrets else None
    )

    print(f"\n{Color.BOLD}Actions -> Dependabot Secret Sync{Color.RESET}")
    if filter_secrets:
        print(f"Target secrets: {', '.join(filter_secrets)}")
    print(f"Target repositories: {len(repos)}")
    if args.dry_run:
        _print_warn("DRY-RUN mode: no actual changes will be made")
    print()

    # Load secret values
    env_file = getattr(args, "env_file", None)
    secret_values = _load_secret_values(env_file)

    if not args.dry_run and not args.yes:
        if not _confirm("Proceed with synchronization?"):
            return

    stats = Stats()

    for idx, repo in enumerate(repos, 1):
        _print_progress(idx, len(repos), f"{args.org}/{repo}")

        actions_secrets = client.list_secrets(args.org, repo, "actions")
        if filter_secrets:
            actions_secrets = [s for s in actions_secrets if s in filter_secrets]

        if not actions_secrets:
            result = RepoResult(repo, "skipped", "dependabot", True, "no secrets to sync")
            stats.record(result)
            _print_skip("No Actions secrets to sync")
            continue

        for secret_name in actions_secrets:
            value = _get_secret_value(secret_name, secret_values)
            if value is None:
                result = RepoResult(
                    repo, "skipped", "dependabot", True,
                    f"{secret_name}: value not provided",
                )
                stats.record(result)
                _print_skip(f"{secret_name}: value not provided")
                continue

            exists = client.secret_exists(args.org, repo, "dependabot", secret_name)
            if exists and not args.force:
                result = RepoResult(
                    repo, "skipped", "dependabot", True, f"{secret_name}: already exists"
                )
                stats.record(result)
                _print_skip(f"{secret_name}: already exists in Dependabot (use --force to overwrite)")
                continue

            if args.dry_run:
                action = "update" if exists else "add"
                result = RepoResult(repo, action, "dependabot", True, f"{secret_name}: dry-run")
                stats.record(result)
                _print_ok(f"{secret_name}: would {'update' if exists else 'add'} (dry-run)")
                continue

            ok = _set_secret(
                client, args.org, repo, "dependabot", secret_name, value,
            )
            action = "updated" if exists else "added"
            result = RepoResult(repo, action, "dependabot", ok, secret_name)
            stats.record(result)
            if ok:
                _print_ok(f"{secret_name}: {action}")
            else:
                _print_err(f"{secret_name}: failed")

    _print_summary(stats, args)


def cmd_update(client: GitHubClient, args: argparse.Namespace):
    """Add/update a specific secret across all repositories."""
    repos = _resolve_repos(client, args)
    targets = _resolve_targets(args.target)

    secret_value = args.secret_value or os.environ.get("SECRET_VALUE", "") or os.environ.get(args.secret_name, "")
    if not secret_value:
        _print_err(f"Secret value is required. Provide it via --secret-value or the {args.secret_name} env var.")
        sys.exit(1)

    print(f"\n{Color.BOLD}Secret Update: {args.secret_name}{Color.RESET}")
    print(f"Scope: {len(repos)} repositories | target: {args.target}")
    if args.dry_run:
        _print_warn("DRY-RUN mode: no actual changes will be made")
    print()

    if not args.dry_run and not args.yes:
        if not _confirm(f"Update {args.secret_name} across all repositories?"):
            return

    stats = Stats()

    for idx, repo in enumerate(repos, 1):
        _print_progress(idx, len(repos), f"{args.org}/{repo}")

        for t in targets:
            exists = client.secret_exists(args.org, repo, t, args.secret_name)
            action = "update" if exists else "add"

            if args.dry_run:
                result = RepoResult(repo, action, t, True, "dry-run")
                stats.record(result)
                _print_ok(f"[{t}] would {action} (dry-run)")
                continue

            ok = _set_secret(client, args.org, repo, t, args.secret_name, secret_value)
            result = RepoResult(repo, action, t, ok)
            stats.record(result)
            if ok:
                _print_ok(f"[{t}] {action}d")
            else:
                _print_err(f"[{t}] failed")

    _print_summary(stats, args)


def cmd_delete(client: GitHubClient, args: argparse.Namespace):
    """Delete a specific secret from all repositories."""
    repos = _resolve_repos(client, args)
    targets = _resolve_targets(args.target)

    print(f"\n{Color.BOLD}{Color.RED}Secret Deletion: {args.secret_name}{Color.RESET}")
    print(f"Scope: {len(repos)} repositories | target: {args.target}")
    if args.dry_run:
        _print_warn("DRY-RUN mode: no actual changes will be made")
    print()

    if not args.dry_run and not args.yes:
        if not _confirm(f"Are you sure you want to delete {args.secret_name}? (irreversible)"):
            return

    stats = Stats()

    for idx, repo in enumerate(repos, 1):
        _print_progress(idx, len(repos), f"{args.org}/{repo}")

        for t in targets:
            exists = client.secret_exists(args.org, repo, t, args.secret_name)
            if not exists:
                result = RepoResult(repo, "skipped", t, True, "does not exist")
                stats.record(result)
                _print_skip(f"[{t}] does not exist")
                continue

            if args.dry_run:
                result = RepoResult(repo, "delete", t, True, "dry-run")
                stats.record(result)
                _print_ok(f"[{t}] would delete (dry-run)")
                continue

            ok = client.delete_secret(args.org, repo, t, args.secret_name)
            result = RepoResult(repo, "deleted", t, ok)
            stats.record(result)
            if ok:
                _print_ok(f"[{t}] deleted")
            else:
                _print_err(f"[{t}] deletion failed")

    _print_summary(stats, args)


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


def _resolve_targets(target: str) -> list[str]:
    if target == "both":
        return ["actions", "dependabot"]
    return [target]


def _load_secret_values(env_file: str | None = None) -> dict[str, str]:
    """
    Load secret values (priority order):
      1) --env-file (.env file)
         GITLAB_TOKEN=glpat-xxx
         PAT_TOKEN=ghp-xxx
      2) SECRET_VALUES env var (JSON)
         export SECRET_VALUES='{"GITLAB_TOKEN":"glpat-xxx","PAT_TOKEN":"ghp-xxx"}'
    """
    values: dict[str, str] = {}

    # 1) .env file
    if env_file:
        env_path = Path(env_file)
        if not env_path.exists():
            logging.error(f".env file not found: {env_file}")
            sys.exit(1)
        for line in env_path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, _, val = line.partition("=")
                key = key.strip()
                val = val.strip().strip("'\"")
                if key:
                    values[key] = val
        logging.info(f"Loaded {len(values)} secrets from .env file")

    # 2) JSON format
    raw = os.environ.get("SECRET_VALUES", "")
    if raw:
        try:
            parsed = json.loads(raw)
            for k, v in parsed.items():
                values.setdefault(k, v)
        except json.JSONDecodeError:
            logging.warning("Failed to parse SECRET_VALUES JSON.")

    return values


def _get_secret_value(name: str, preloaded: dict[str, str]) -> str | None:
    """
    Look up a single secret value.
    If not found in preloaded (.env / SECRET_VALUES), falls back to env vars
    matched by the exact same name.
      export GITLAB_TOKEN='glpat-xxx'  ->  matched directly
    """
    if name in preloaded:
        return preloaded[name]
    val = os.environ.get(name, "")
    return val if val else None


def _set_secret(
    client: GitHubClient, org: str, repo: str, target: str, name: str, value: str
) -> bool:
    try:
        key_data = client.get_public_key(org, repo, target)
        encrypted = encrypt_secret(key_data["key"], value)
        return client.put_secret(org, repo, target, name, encrypted, key_data["key_id"])
    except Exception as e:
        logging.error(f"Failed to set secret ({org}/{repo}, {target}, {name}): {e}")
        return False


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


def _print_summary(stats: Stats, args: argparse.Namespace):
    print(f"\n{Color.BOLD}{Color.BLUE}{'='*60}{Color.RESET}")
    print(f"{Color.BOLD}Summary{Color.RESET}")
    print(f"{Color.BOLD}{Color.BLUE}{'='*60}{Color.RESET}")
    print(f"  Total:    {stats.total}")
    print(f"  {Color.GREEN}Success:  {stats.success}{Color.RESET}")
    print(f"  {Color.DIM}Skipped:  {stats.skipped}{Color.RESET}")
    if stats.failed:
        print(f"  {Color.RED}Failed:   {stats.failed}{Color.RESET}")

    failed = [d for d in stats.details if not d.success]
    if failed:
        print(f"\n{Color.RED}Failure details:{Color.RESET}")
        for r in failed:
            print(f"  - {r.repo} [{r.target}] {r.message}")

    # Save log
    log_dir = Path("logs")
    log_dir.mkdir(exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = log_dir / f"secrets_{args.command}_{ts}.json"
    log_data = {
        "command": args.command,
        "org": args.org,
        "timestamp": datetime.now().isoformat(),
        "dry_run": args.dry_run,
        "stats": {
            "total": stats.total,
            "success": stats.success,
            "failed": stats.failed,
            "skipped": stats.skipped,
        },
        "details": [
            {
                "repo": d.repo,
                "action": d.action,
                "target": d.target,
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
    common.add_argument(
        "--org", required=True, help="GitHub organization or username"
    )
    common.add_argument(
        "--repos", help="Target specific repositories only (comma-separated, e.g. repo1,repo2)"
    )
    common.add_argument(
        "--dry-run", action="store_true", help="Simulate without making actual changes"
    )
    common.add_argument(
        "-y", "--yes", action="store_true", help="Skip confirmation prompts"
    )
    common.add_argument(
        "-v", "--verbose", action="store_true", help="Enable verbose logging"
    )

    parser = argparse.ArgumentParser(
        prog="github_secrets_manager",
        description="Bulk management tool for GitHub repository secrets",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # List secrets
  python github_secrets_manager.py list --org somaz94
  python github_secrets_manager.py list --org somaz94 --target dependabot

  # Sync Actions secrets to Dependabot (env var names matched directly)
  export GITLAB_TOKEN='glpat-xxx'
  export PAT_TOKEN='ghp-xxx'
  python github_secrets_manager.py sync --org somaz94

  # Sync using a .env file
  python github_secrets_manager.py sync --org somaz94 --env-file .secrets.env

  # Sync using JSON env var
  export SECRET_VALUES='{"GITLAB_TOKEN":"glpat-xxx","PAT_TOKEN":"ghp-xxx"}'
  python github_secrets_manager.py sync --org somaz94

  # Update a specific secret (Actions + Dependabot simultaneously)
  python github_secrets_manager.py update --org somaz94 \\
    --secret-name GITLAB_TOKEN --secret-value 'glpat-xxx' --target both

  # Target specific repositories only
  python github_secrets_manager.py sync --org somaz94 --repos kube-diff,git-bridge
        """,
    )

    sub = parser.add_subparsers(dest="command", required=True, help="Command to execute")

    # list
    sub.add_parser("list", parents=[common], help="List secrets").add_argument(
        "--target",
        choices=["actions", "dependabot", "both"],
        default="both",
        help="Target secret store (default: both)",
    )

    # sync
    p_sync = sub.add_parser(
        "sync", parents=[common], help="Sync Actions Secrets -> Dependabot Secrets"
    )
    p_sync.add_argument(
        "--secrets", help="Secret names to sync (comma-separated; syncs all if omitted)"
    )
    p_sync.add_argument(
        "--force", action="store_true", help="Overwrite existing Dependabot secrets"
    )
    p_sync.add_argument(
        "--env-file", help="Path to .env file (KEY=value format)"
    )

    # update
    p_update = sub.add_parser("update", parents=[common], help="Add/update a specific secret")
    p_update.add_argument("--secret-name", required=True, help="Secret name")
    p_update.add_argument("--secret-value", help="Secret value (or use same-name env var)")
    p_update.add_argument(
        "--target",
        choices=["actions", "dependabot", "both"],
        default="actions",
        help="Target secret store (default: actions)",
    )

    # delete
    p_delete = sub.add_parser("delete", parents=[common], help="Delete a specific secret")
    p_delete.add_argument("--secret-name", required=True, help="Secret name to delete")
    p_delete.add_argument(
        "--target",
        choices=["actions", "dependabot", "both"],
        default="actions",
        help="Target secret store (default: actions)",
    )

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

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
        "sync": cmd_sync,
        "update": cmd_update,
        "delete": cmd_delete,
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
