#!/usr/bin/env python3
"""
Dependabot PR Bulk Merger
=========================
조직/사용자의 모든 리포지토리에서 열려 있는 Dependabot PR을 찾아
순차적으로 머지합니다.

주요 기능:
  - list   : 모든 리포지토리의 열린 Dependabot PR 목록 조회
  - merge  : Dependabot PR을 하나씩(순차적으로) 머지

사용 예시:
  # 열린 Dependabot PR 미리보기
  python dependabot-pr-merge.py list --org somaz94

  # 모든 Dependabot PR 순차 머지 (기본 squash)
  python dependabot-pr-merge.py merge --org somaz94

  # 머지 방식 지정
  python dependabot-pr-merge.py merge --org somaz94 --merge-method merge

  # 각 PR 머지 전에 필수 CI 체크 대기 (PR당 최대 10분)
  python dependabot-pr-merge.py merge --org somaz94 --wait-checks

  # 특정 리포지토리만
  python dependabot-pr-merge.py merge --org somaz94 --repos kube-diff,git-bridge

  # Dry-run 모드 (실제 머지 안 함)
  python dependabot-pr-merge.py merge --org somaz94 --dry-run

  # 확인 프롬프트 생략
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
# 상수
# ─────────────────────────────────────────────
GITHUB_API = "https://api.github.com"
PER_PAGE = 100
RATE_LIMIT_BUFFER = 10
REQUEST_TIMEOUT = 30

# Dependabot 작성자 로그인 (현재 + 레거시 preview 앱)
DEPENDABOT_LOGINS = {"dependabot[bot]", "dependabot-preview[bot]"}

# 방금 push된 머지가 워크플로 실행을 queue에 등록할 시간을 준 뒤 idle을 폴링한다.
# 이 유예가 없으면 changelog/release 워크플로가 시작되기도 전에
# count_active_runs()가 0을 읽고 통과해버릴 수 있다.
WORKFLOW_START_GRACE = 12

# "지금 바로 머지 가능"을 의미하는 mergeable_state 값
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
# 데이터 클래스
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
# GitHub API 클라이언트
# ─────────────────────────────────────────────
class GitHubClient:
    """레이트 리밋 처리를 포함한 GitHub API 클라이언트."""

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
                f"레이트 리밋 임박 (remaining={remaining}). {wait}초 대기..."
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
                    f"리포지토리 목록 조회 실패: HTTP {resp.status_code}\n{resp.text}"
                )
            data = resp.json()
            if not data:
                break
            repos.extend(
                r["name"]
                for r in data
                if not r.get("archived", False) and not r.get("disabled", False)
            )
            logging.info(f"  페이지 {page}: {len(data)}개 repo (누적 {len(repos)}개)")
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
                f"PR 조회 실패 {org}/{repo}#{number}: HTTP {resp.status_code}"
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
        """PR 브랜치를 최신 base로 리베이스 (PUT .../update-branch)."""
        resp = self.put(f"/repos/{org}/{repo}/pulls/{number}/update-branch")
        if resp.status_code == 202:
            return True, "update requested"
        try:
            msg = resp.json().get("message", resp.text)
        except ValueError:
            msg = resp.text
        return False, f"HTTP {resp.status_code}: {msg}"

    def count_active_runs(self, org: str, repo: str) -> int:
        """리포지토리의 queued + in_progress Actions 워크플로 실행 수를 센다."""
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
# 명령
# ─────────────────────────────────────────────
def cmd_list(client: GitHubClient, args: argparse.Namespace):
    """모든 리포지토리의 열린 Dependabot PR 목록 조회."""
    repos = _resolve_repos(client, args)

    print(f"\n{Color.BOLD}열린 Dependabot Pull Request{Color.RESET}")
    print(f"범위: {len(repos)}개 리포지토리\n")

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
        print(f"{Color.GREEN}열린 Dependabot PR이 없습니다.{Color.RESET}")
    else:
        print(f"{Color.BOLD}총 {total}개의 Dependabot PR{Color.RESET}")


def cmd_merge(client: GitHubClient, args: argparse.Namespace):
    """모든 Dependabot PR을 순차적으로 머지."""
    repos = _resolve_repos(client, args)

    print(f"\n{Color.BOLD}Dependabot PR 순차 머지{Color.RESET}")
    print(f"범위: {len(repos)}개 리포지토리 | 머지 방식: {args.merge_method}")
    if args.one_per_repo:
        print("모드: run당 repo별 1개만 머지 (나머지는 재실행)")
    if args.wait_checks:
        print(f"CI 체크 대기: PR당 최대 {args.checks_timeout}초")
    if args.dry_run:
        _print_warn("DRY-RUN 모드: 실제 머지를 수행하지 않습니다")
    print()

    # 머지 전에 범위를 보여주기 위해 모든 Dependabot PR을 먼저 수집한다.
    logging.info("Dependabot PR 수집 중...")
    all_prs: list[PullRequest] = []
    for repo in repos:
        all_prs.extend(client.list_dependabot_prs(args.org, repo))

    if not all_prs:
        print(f"{Color.GREEN}머지할 Dependabot PR이 없습니다.{Color.RESET}")
        return

    groups = _group_by_repo(all_prs)
    multi = [r for r, prs in groups.items() if len(prs) > 1]

    print(f"{Color.BOLD}{len(all_prs)}{Color.RESET}개의 Dependabot PR 발견:")
    for pr in all_prs:
        print(f"  {Color.CYAN}{args.org}/{pr.repo}{Color.RESET} #{pr.number} {pr.title}")
    if multi:
        # 같은 repo의 PR은 한 번에 하나씩, 각 머지의 changelog/release 워크플로가
        # 끝난 뒤 다음을 머지해 두 워크플로가 동시에 돌지 않게 한다.
        print(
            f"\n  {Color.YELLOW}참고: {len(multi)}개 repo에 PR이 2개 이상 "
            f"({', '.join(multi)}) — 해당 repo는 직렬로 머지합니다.{Color.RESET}"
        )
    print()

    if not args.dry_run and not args.yes:
        if not _confirm(f"{len(all_prs)}개의 Dependabot PR을 순차적으로 머지할까요?"):
            return

    stats = Stats()
    idx = 0

    for repo, prs in groups.items():
        for i, pr in enumerate(prs):
            idx += 1
            _print_progress(idx, len(all_prs), f"{args.org}/{pr.repo} #{pr.number}")
            print(f"  {Color.DIM}{pr.title}{Color.RESET}")

            followup = i > 0  # 같은 repo의 2번째+ Dependabot PR

            if followup and not args.dry_run:
                if args.one_per_repo:
                    msg = "보류 (one-per-repo; Dependabot 리베이스 후 재실행)"
                    stats.record(
                        PRResult(pr.repo, pr.number, pr.title, "skipped", True, msg)
                    )
                    _print_skip(msg)
                    continue
                # 직전 머지가 changelog/release 워크플로를 트리거했을 수 있으므로,
                # 두 워크플로가 동시에 돌지 않도록 먼저 끝날 때까지 대기한다.
                _wait_repo_idle(client, args, pr.repo)

            _merge_one(client, args, pr, stats, followup=followup)

            if idx < len(all_prs) and not args.dry_run:
                time.sleep(args.delay)

    _print_summary(stats, args)


# ─────────────────────────────────────────────
# 머지 로직
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

    # 충돌 / 머지 불가 상태는 건너뛴다.
    if mergeable is False or state == "dirty":
        msg = f"머지 불가 (충돌, state={state})"
        stats.record(PRResult(pr.repo, pr.number, pr.title, "skipped", True, msg))
        _print_skip(msg)
        return

    # behind 브랜치 (base가 앞서감 — 예: 직전 같은 repo 머지로 changelog 커밋이
    # 막 올라옴). followup이거나 --merge-behind면 PR 브랜치를 새 base로 리베이스하고
    # 안정될 때까지 기다린 뒤 머지한다. 아니면 건너뛴다.
    if state == "behind":
        if not (followup or args.merge_behind):
            msg = "브랜치가 base보다 뒤처짐 (--merge-behind, 또는 같은 repo followup은 자동 리베이스)"
            stats.record(PRResult(pr.repo, pr.number, pr.title, "skipped", True, msg))
            _print_skip(msg)
            return
        if args.dry_run:
            stats.record(
                PRResult(pr.repo, pr.number, pr.title, "merged", True, "dry-run (리베이스+머지 예정)")
            )
            _print_ok("update-branch 후 머지 예정 (dry-run)")
            return
        ok, m = client.update_branch(args.org, pr.repo, pr.number)
        if not ok:
            msg = f"update-branch 실패: {m}"
            stats.record(PRResult(pr.repo, pr.number, pr.title, "failed", False, msg))
            _print_err(msg)
            return
        _print_wait("브랜치를 base로 리베이스 중 (update-branch), 체크 대기...")
        time.sleep(args.poll_interval)
        try:
            # 리베이스 후 CI가 재시작되므로 여기서는 항상 대기한다.
            detail = _resolve_mergeable(client, args, pr, wait_checks=True)
        except RuntimeError as e:
            stats.record(PRResult(pr.repo, pr.number, pr.title, "failed", False, str(e)))
            _print_err(str(e))
            return
        state = detail.get("mergeable_state", "unknown")
        mergeable = detail.get("mergeable")
        sha = (detail.get("head") or {}).get("sha", "")
        if mergeable is False or state in ("dirty", "behind", "blocked"):
            msg = f"리베이스 후에도 머지 불가 (state={state})"
            stats.record(PRResult(pr.repo, pr.number, pr.title, "skipped", True, msg))
            _print_skip(msg)
            return

    if state == "blocked":
        msg = "머지 차단됨 (필수 체크/리뷰 미충족)"
        stats.record(PRResult(pr.repo, pr.number, pr.title, "skipped", True, msg))
        _print_skip(msg)
        return

    if state not in MERGEABLE_STATES:
        msg = f"예상치 못한 mergeable_state={state}"
        stats.record(PRResult(pr.repo, pr.number, pr.title, "skipped", True, msg))
        _print_skip(msg)
        return

    if args.dry_run:
        stats.record(
            PRResult(pr.repo, pr.number, pr.title, "merged", True, f"dry-run (state={state})")
        )
        _print_ok(f"머지 예정 (state={state}, dry-run)")
        return

    ok, msg = client.merge_pr(args.org, pr.repo, pr.number, sha, args.merge_method)
    if ok:
        stats.record(PRResult(pr.repo, pr.number, pr.title, "merged", True))
        _print_ok("머지 완료")
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
    PR 상세를 조회해 머지 가능 상태를 확정한다.

    GitHub는 `mergeable` / `mergeable_state`를 비동기로 계산하므로 첫 응답은
    `mergeable: null` / `mergeable_state: unknown`일 수 있다. 확정될 때까지
    폴링한다. 체크 대기가 켜져 있으면 상태가 `blocked`(필수 체크 진행 중)인 동안
    --checks-timeout까지 계속 대기한다.

    `wait_checks`는 args.wait_checks를 오버라이드한다 (리베이스 후에는 CI가 항상
    재시작되므로 플래그와 무관하게 대기해야 함).
    """
    if wait_checks is None:
        wait_checks = args.wait_checks
    poll_interval = max(args.poll_interval, 1)
    settle_deadline = time.time() + 30  # null/unknown 확정 최대 대기
    checks_deadline = time.time() + args.checks_timeout

    while True:
        detail = client.get_pr(args.org, pr.repo, pr.number)
        state = detail.get("mergeable_state", "unknown")
        mergeable = detail.get("mergeable")

        # 아직 계산 중 — 확정될 때까지 대기.
        if mergeable is None or state == "unknown":
            if time.time() < settle_deadline:
                time.sleep(2)
                continue
            return detail

        # 필수 CI 체크 완료 대기.
        if wait_checks and state == "blocked":
            if time.time() < checks_deadline:
                _print_wait(f"체크 진행 중 (state={state}), {poll_interval}초 대기...")
                time.sleep(poll_interval)
                continue
            return detail

        return detail


# ─────────────────────────────────────────────
# 헬퍼
# ─────────────────────────────────────────────
def _resolve_repos(client: GitHubClient, args: argparse.Namespace) -> list[str]:
    if args.repos:
        return [r.strip() for r in args.repos.split(",")]
    logging.info("리포지토리 목록 조회 중...")
    repos = client.list_repos(args.org)
    logging.info(f"{len(repos)}개 리포지토리 발견 (아카이브 제외)")
    return repos


def _group_by_repo(prs: list[PullRequest]) -> dict[str, list[PullRequest]]:
    """PR을 repo별로 그룹핑 (dict는 삽입 순서를 보존하므로 발견 순서 유지)."""
    groups: dict[str, list[PullRequest]] = {}
    for pr in prs:
        groups.setdefault(pr.repo, []).append(pr)
    return groups


def _wait_repo_idle(client: GitHubClient, args: argparse.Namespace, repo: str):
    """
    리포지토리에 queued / in_progress Actions 실행이 없을 때까지 대기.

    같은 repo의 머지 사이에 호출해, 직전 머지가 트리거한 changelog/release
    워크플로가 끝난 뒤 다음 머지를 진행한다 — 둘이 동시에 돌지 않는다.
    """
    deadline = time.time() + args.workflow_timeout
    poll_interval = max(args.poll_interval, 1)
    # 방금 push된 머지가 워크플로를 등록할 시간을 준 뒤 첫 폴링을 한다.
    _print_wait(f"{repo}의 워크플로 등록 대기 ({WORKFLOW_START_GRACE}초)...")
    time.sleep(WORKFLOW_START_GRACE)
    while True:
        active = client.count_active_runs(args.org, repo)
        if active == 0:
            return
        if time.time() >= deadline:
            _print_warn(
                f"{repo}의 워크플로가 {args.workflow_timeout}초 후에도 실행 중; 그대로 진행"
            )
            return
        _print_wait(
            f"{repo}에 워크플로 {active}개 실행 중 (changelog/release?), {poll_interval}초 대기..."
        )
        time.sleep(poll_interval)


def _confirm(message: str) -> bool:
    print(f"\n{Color.YELLOW}{message} [y/N]{Color.RESET} ", end="")
    answer = input().strip().lower()
    if answer not in ("y", "yes"):
        print("취소했습니다.")
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
    print(f"{Color.BOLD}요약{Color.RESET}")
    print(f"{Color.BOLD}{Color.BLUE}{'='*60}{Color.RESET}")
    print(f"  전체:     {stats.total}")
    print(f"  {Color.GREEN}머지:     {stats.merged}{Color.RESET}")
    print(f"  {Color.DIM}건너뜀:   {stats.skipped}{Color.RESET}")
    if stats.failed:
        print(f"  {Color.RED}실패:     {stats.failed}{Color.RESET}")

    skipped = [d for d in stats.details if d.action == "skipped"]
    if skipped:
        print(f"\n{Color.DIM}건너뜀 상세:{Color.RESET}")
        for r in skipped:
            print(f"  - {r.repo} #{r.number} {r.message}")

    failed = [d for d in stats.details if not d.success]
    if failed:
        print(f"\n{Color.RED}실패 상세:{Color.RESET}")
        for r in failed:
            print(f"  - {r.repo} #{r.number} {r.message}")

    # 로그 저장
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
    print(f"\n로그 저장: {Color.BOLD}{log_file}{Color.RESET}")


# ─────────────────────────────────────────────
# CLI (parents 패턴 -> --org 위치 자유)
# ─────────────────────────────────────────────
def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--org", required=True, help="GitHub 조직 또는 사용자명")
    common.add_argument(
        "--repos",
        help="특정 리포지토리만 (쉼표 구분, 예: repo1,repo2)",
    )
    common.add_argument(
        "--dry-run", action="store_true", help="실제 머지 없이 시뮬레이션"
    )
    common.add_argument(
        "-y", "--yes", action="store_true", help="확인 프롬프트 생략"
    )
    common.add_argument(
        "-v", "--verbose", action="store_true", help="상세 로깅 활성화"
    )

    parser = argparse.ArgumentParser(
        prog="dependabot-pr-merge",
        description="여러 리포지토리의 Dependabot PR을 찾아 순차적으로 머지",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
예시:
  # 열린 Dependabot PR 미리보기
  python dependabot-pr-merge.py list --org somaz94

  # 모든 Dependabot PR 순차 머지 (기본 squash)
  python dependabot-pr-merge.py merge --org somaz94

  # 각 머지 전에 필수 CI 체크 대기
  python dependabot-pr-merge.py merge --org somaz94 --wait-checks

  # 특정 리포지토리만
  python dependabot-pr-merge.py merge --org somaz94 --repos kube-diff,git-bridge

  # Dry-run 모드
  python dependabot-pr-merge.py merge --org somaz94 --dry-run
        """,
    )

    sub = parser.add_subparsers(dest="command", required=True, help="실행할 명령")

    # list
    sub.add_parser(
        "list", parents=[common], help="모든 리포지토리의 열린 Dependabot PR 목록 조회"
    )

    # merge
    p_merge = sub.add_parser(
        "merge", parents=[common], help="Dependabot PR 순차 머지"
    )
    p_merge.add_argument(
        "--merge-method",
        choices=["merge", "squash", "rebase"],
        default="squash",
        help="머지 방식 (기본: squash)",
    )
    p_merge.add_argument(
        "--one-per-repo",
        action="store_true",
        help="run당 repo별 Dependabot PR 1개만 머지하고 나머지는 보류 "
        "(changelog/release repo에 가장 안전 — Dependabot 리베이스 후 재실행)",
    )
    p_merge.add_argument(
        "--wait-checks",
        action="store_true",
        help="각 PR 머지 전에 필수 CI 체크 완료를 대기",
    )
    p_merge.add_argument(
        "--checks-timeout",
        type=int,
        default=600,
        help="PR당 체크 대기 최대 초 (기본: 600)",
    )
    p_merge.add_argument(
        "--workflow-timeout",
        type=int,
        default=300,
        help="같은 repo 머지 사이에 repo의 워크플로(changelog/release) 완료를 "
        "기다리는 최대 초 (기본: 300)",
    )
    p_merge.add_argument(
        "--poll-interval",
        type=int,
        default=15,
        help="체크 상태 / 워크플로 폴링 간격 초 (기본: 15)",
    )
    p_merge.add_argument(
        "--merge-behind",
        action="store_true",
        help="behind 상태 PR은 update-branch로 리베이스 후 머지 "
        "(같은 repo followup은 자동 수행; 그 외 기본: 건너뜀)",
    )
    p_merge.add_argument(
        "--delay",
        type=int,
        default=3,
        help="머지 사이 대기 초 (기본: 3)",
    )

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

    # `list`에는 merge 전용 속성이 없으므로 공용 헬퍼를 위해 기본값을 채운다.
    if not hasattr(args, "merge_method"):
        args.merge_method = "-"

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
    )

    token = os.environ.get("GITHUB_TOKEN", "")
    if not token:
        print(f"{Color.RED}✗ GITHUB_TOKEN 환경변수를 설정해주세요.{Color.RESET}")
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
        print(f"\n{Color.YELLOW}중단되었습니다.{Color.RESET}")
        sys.exit(130)
    except Exception as e:
        logging.error(f"예기치 못한 오류: {e}")
        if args.verbose:
            import traceback

            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
