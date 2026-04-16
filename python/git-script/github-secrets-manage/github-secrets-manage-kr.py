#!/usr/bin/env python3
"""
GitHub Repository Secrets Manager
==================================
Actions / Dependabot Secret을 일괄 관리합니다.

주요 기능:
  - list       : 모든 리포지토리의 Secret 목록 조회
  - sync       : Actions Secrets → Dependabot Secrets 복사
  - update     : 특정 Secret을 모든 리포지토리에 추가/업데이트
  - delete     : 특정 Secret을 모든 리포지토리에서 삭제

사용 예시:
  # Secret 목록 조회
  python github_secrets_manager.py list --org somaz94
  python github_secrets_manager.py list --org somaz94 --target dependabot

  # Actions secrets를 Dependabot으로 동기화 (환경변수 이름 그대로)
  export GITLAB_TOKEN='glpat-xxx'
  export PAT_TOKEN='ghp-xxx'
  python github_secrets_manager.py sync --org somaz94

  # .env 파일로 동기화
  python github_secrets_manager.py sync --org somaz94 --env-file .secrets.env

  # JSON 환경변수로도 가능
  export SECRET_VALUES='{"GITLAB_TOKEN":"glpat-xxx","PAT_TOKEN":"ghp-xxx"}'
  python github_secrets_manager.py sync --org somaz94

  # 특정 secret 업데이트 (Actions + Dependabot 동시)
  python github_secrets_manager.py update --org somaz94 \
    --secret-name GITLAB_TOKEN --secret-value 'glpat-xxx' --target both

  # 특정 리포지토리만
  python github_secrets_manager.py sync --org somaz94 --repos kube-diff,git-bridge

  # Dry-run 모드
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
    """GitHub API 클라이언트 (rate-limit 핸들링 포함)"""

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
                f"Rate limit 임박 (remaining={remaining}). {wait}초 대기..."
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
            repos.extend(r["name"] for r in data if not r.get("archived", False))
            logging.info(f"  페이지 {page}: {len(data)}개 (누적 {len(repos)}개)")
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
                f"Public key 조회 실패 ({org}/{repo}, {target}): HTTP {resp.status_code}"
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
    """Secret 목록 조회"""
    repos = _resolve_repos(client, args)
    targets = _resolve_targets(args.target)

    print(f"\n{Color.BOLD}Secret 목록 조회{Color.RESET}")
    print(f"대상: {len(repos)}개 리포지토리 | target: {args.target}\n")

    for repo in repos:
        print(f"{Color.BOLD}{Color.CYAN}{args.org}/{repo}{Color.RESET}")
        for t in targets:
            secrets = client.list_secrets(args.org, repo, t)
            label = f"  [{t:>10}]"
            if secrets:
                print(f"{label} {', '.join(secrets)}")
            else:
                print(f"{label} {Color.DIM}(없음){Color.RESET}")
        print()


def cmd_sync(client: GitHubClient, args: argparse.Namespace):
    """Actions Secrets -> Dependabot Secrets 동기화"""
    repos = _resolve_repos(client, args)
    filter_secrets = (
        {s.strip().upper() for s in args.secrets.split(",")} if args.secrets else None
    )

    print(f"\n{Color.BOLD}Actions -> Dependabot Secret 동기화{Color.RESET}")
    if filter_secrets:
        print(f"대상 Secrets: {', '.join(filter_secrets)}")
    print(f"대상 리포지토리: {len(repos)}개")
    if args.dry_run:
        _print_warn("DRY-RUN 모드: 실제 변경 없음")
    print()

    # Secret 값 로드
    env_file = getattr(args, "env_file", None)
    secret_values = _load_secret_values(env_file)

    if not args.dry_run and not args.yes:
        if not _confirm("동기화를 진행하시겠습니까?"):
            return

    stats = Stats()

    for idx, repo in enumerate(repos, 1):
        _print_progress(idx, len(repos), f"{args.org}/{repo}")

        actions_secrets = client.list_secrets(args.org, repo, "actions")
        if filter_secrets:
            actions_secrets = [s for s in actions_secrets if s in filter_secrets]

        if not actions_secrets:
            result = RepoResult(repo, "skipped", "dependabot", True, "동기화할 secret 없음")
            stats.record(result)
            _print_skip("동기화할 Actions secret 없음")
            continue

        for secret_name in actions_secrets:
            value = _get_secret_value(secret_name, secret_values)
            if value is None:
                result = RepoResult(
                    repo, "skipped", "dependabot", True,
                    f"{secret_name}: 값 미제공",
                )
                stats.record(result)
                _print_skip(f"{secret_name}: 값이 제공되지 않음")
                continue

            exists = client.secret_exists(args.org, repo, "dependabot", secret_name)
            if exists and not args.force:
                result = RepoResult(
                    repo, "skipped", "dependabot", True, f"{secret_name}: 이미 존재"
                )
                stats.record(result)
                _print_skip(f"{secret_name}: Dependabot에 이미 존재 (--force로 덮어쓰기)")
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
                _print_err(f"{secret_name}: 실패")

    _print_summary(stats, args)


def cmd_update(client: GitHubClient, args: argparse.Namespace):
    """특정 Secret을 모든 리포지토리에 추가/업데이트"""
    repos = _resolve_repos(client, args)
    targets = _resolve_targets(args.target)

    secret_value = args.secret_value or os.environ.get("SECRET_VALUE", "") or os.environ.get(args.secret_name, "")
    if not secret_value:
        _print_err(f"Secret 값이 필요합니다. --secret-value 또는 환경변수 {args.secret_name}으로 제공하세요.")
        sys.exit(1)

    print(f"\n{Color.BOLD}Secret 업데이트: {args.secret_name}{Color.RESET}")
    print(f"대상: {len(repos)}개 리포지토리 | target: {args.target}")
    if args.dry_run:
        _print_warn("DRY-RUN 모드: 실제 변경 없음")
    print()

    if not args.dry_run and not args.yes:
        if not _confirm(f"모든 리포지토리의 {args.secret_name}을 업데이트하시겠습니까?"):
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
                _print_err(f"[{t}] 실패")

    _print_summary(stats, args)


def cmd_delete(client: GitHubClient, args: argparse.Namespace):
    """특정 Secret을 모든 리포지토리에서 삭제"""
    repos = _resolve_repos(client, args)
    targets = _resolve_targets(args.target)

    print(f"\n{Color.BOLD}{Color.RED}Secret 삭제: {args.secret_name}{Color.RESET}")
    print(f"대상: {len(repos)}개 리포지토리 | target: {args.target}")
    if args.dry_run:
        _print_warn("DRY-RUN 모드: 실제 변경 없음")
    print()

    if not args.dry_run and not args.yes:
        if not _confirm(f"정말로 {args.secret_name}을 삭제하시겠습니까? (복구 불가)"):
            return

    stats = Stats()

    for idx, repo in enumerate(repos, 1):
        _print_progress(idx, len(repos), f"{args.org}/{repo}")

        for t in targets:
            exists = client.secret_exists(args.org, repo, t, args.secret_name)
            if not exists:
                result = RepoResult(repo, "skipped", t, True, "존재하지 않음")
                stats.record(result)
                _print_skip(f"[{t}] 존재하지 않음")
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
                _print_ok(f"[{t}] 삭제됨")
            else:
                _print_err(f"[{t}] 삭제 실패")

    _print_summary(stats, args)


# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────
def _resolve_repos(client: GitHubClient, args: argparse.Namespace) -> list[str]:
    if args.repos:
        return [r.strip() for r in args.repos.split(",")]
    logging.info("리포지토리 목록 가져오는 중...")
    repos = client.list_repos(args.org)
    logging.info(f"총 {len(repos)}개 리포지토리 발견 (archived 제외)")
    return repos


def _resolve_targets(target: str) -> list[str]:
    if target == "both":
        return ["actions", "dependabot"]
    return [target]


def _load_secret_values(env_file: str | None = None) -> dict[str, str]:
    """
    Secret 값 로드 (우선순위):
      1) --env-file (.env 파일)
         GITLAB_TOKEN=glpat-xxx
         PAT_TOKEN=ghp-xxx
      2) SECRET_VALUES 환경변수 (JSON)
         export SECRET_VALUES='{"GITLAB_TOKEN":"glpat-xxx","PAT_TOKEN":"ghp-xxx"}'
    """
    values: dict[str, str] = {}

    # 1) .env 파일
    if env_file:
        env_path = Path(env_file)
        if not env_path.exists():
            logging.error(f".env 파일을 찾을 수 없습니다: {env_file}")
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
        logging.info(f".env 파일에서 {len(values)}개 secret 로드")

    # 2) JSON 형식
    raw = os.environ.get("SECRET_VALUES", "")
    if raw:
        try:
            parsed = json.loads(raw)
            for k, v in parsed.items():
                values.setdefault(k, v)
        except json.JSONDecodeError:
            logging.warning("SECRET_VALUES JSON 파싱 실패.")

    return values


def _get_secret_value(name: str, preloaded: dict[str, str]) -> str | None:
    """
    개별 secret 값 조회.
    preloaded(.env/SECRET_VALUES)에 없으면 환경변수에서 이름 그대로 조회.
      export GITLAB_TOKEN='glpat-xxx'  ->  그대로 매칭
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
        logging.error(f"Secret 설정 실패 ({org}/{repo}, {target}, {name}): {e}")
        return False


def _confirm(message: str) -> bool:
    print(f"\n{Color.YELLOW}{message} [y/N]{Color.RESET} ", end="")
    answer = input().strip().lower()
    if answer not in ("y", "yes"):
        print("취소되었습니다.")
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
    print(f"{Color.BOLD}결과 요약{Color.RESET}")
    print(f"{Color.BOLD}{Color.BLUE}{'='*60}{Color.RESET}")
    print(f"  총 작업:  {stats.total}")
    print(f"  {Color.GREEN}성공:    {stats.success}{Color.RESET}")
    print(f"  {Color.DIM}스킵:    {stats.skipped}{Color.RESET}")
    if stats.failed:
        print(f"  {Color.RED}실패:    {stats.failed}{Color.RESET}")

    failed = [d for d in stats.details if not d.success]
    if failed:
        print(f"\n{Color.RED}실패 상세:{Color.RESET}")
        for r in failed:
            print(f"  - {r.repo} [{r.target}] {r.message}")

    # 로그 저장
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
    print(f"\n로그 저장: {Color.BOLD}{log_file}{Color.RESET}")


# ─────────────────────────────────────────────
# CLI (parents 패턴 -> --org 위치 자유)
# ─────────────────────────────────────────────
def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument(
        "--org", required=True, help="GitHub Organization 또는 username"
    )
    common.add_argument(
        "--repos", help="특정 리포지토리만 대상 (쉼표 구분, 예: repo1,repo2)"
    )
    common.add_argument(
        "--dry-run", action="store_true", help="실제 변경 없이 시뮬레이션"
    )
    common.add_argument(
        "-y", "--yes", action="store_true", help="확인 프롬프트 건너뛰기"
    )
    common.add_argument(
        "-v", "--verbose", action="store_true", help="상세 로그 출력"
    )

    parser = argparse.ArgumentParser(
        prog="github_secrets_manager",
        description="GitHub Repository Secrets 일괄 관리 도구",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
사용 예시:
  # 목록 조회
  python github_secrets_manager.py list --org somaz94
  python github_secrets_manager.py list --org somaz94 --target dependabot

  # Actions secrets를 Dependabot으로 동기화 (환경변수 이름 그대로)
  export GITLAB_TOKEN='glpat-xxx'
  export PAT_TOKEN='ghp-xxx'
  python github_secrets_manager.py sync --org somaz94

  # .env 파일 사용
  python github_secrets_manager.py sync --org somaz94 --env-file .secrets.env

  # JSON 환경변수
  export SECRET_VALUES='{"GITLAB_TOKEN":"glpat-xxx","PAT_TOKEN":"ghp-xxx"}'
  python github_secrets_manager.py sync --org somaz94

  # 특정 secret 업데이트 (Actions + Dependabot 동시)
  python github_secrets_manager.py update --org somaz94 \\
    --secret-name GITLAB_TOKEN --secret-value 'glpat-xxx' --target both

  # 특정 리포지토리만
  python github_secrets_manager.py sync --org somaz94 --repos kube-diff,git-bridge
        """,
    )

    sub = parser.add_subparsers(dest="command", required=True, help="실행할 명령")

    # list
    sub.add_parser("list", parents=[common], help="Secret 목록 조회").add_argument(
        "--target",
        choices=["actions", "dependabot", "both"],
        default="both",
        help="조회 대상 (기본: both)",
    )

    # sync
    p_sync = sub.add_parser(
        "sync", parents=[common], help="Actions Secrets -> Dependabot Secrets 동기화"
    )
    p_sync.add_argument(
        "--secrets", help="동기화할 secret 이름 (쉼표 구분, 미지정 시 전체)"
    )
    p_sync.add_argument(
        "--force", action="store_true", help="이미 존재하는 Dependabot secret도 덮어쓰기"
    )
    p_sync.add_argument(
        "--env-file", help=".env 파일 경로 (GITLAB_TOKEN=xxx 형식)"
    )

    # update
    p_update = sub.add_parser("update", parents=[common], help="특정 Secret 추가/업데이트")
    p_update.add_argument("--secret-name", required=True, help="Secret 이름")
    p_update.add_argument("--secret-value", help="Secret 값 (또는 동명 환경변수)")
    p_update.add_argument(
        "--target",
        choices=["actions", "dependabot", "both"],
        default="actions",
        help="업데이트 대상 (기본: actions)",
    )

    # delete
    p_delete = sub.add_parser("delete", parents=[common], help="특정 Secret 삭제")
    p_delete.add_argument("--secret-name", required=True, help="삭제할 Secret 이름")
    p_delete.add_argument(
        "--target",
        choices=["actions", "dependabot", "both"],
        default="actions",
        help="삭제 대상 (기본: actions)",
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
        print(f"{Color.RED}✗ GITHUB_TOKEN 환경변수를 설정해주세요.{Color.RESET}")
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
        print(f"\n{Color.YELLOW}중단되었습니다.{Color.RESET}")
        sys.exit(130)
    except Exception as e:
        logging.error(f"예상치 못한 에러: {e}")
        if args.verbose:
            import traceback

            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()