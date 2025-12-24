#!/usr/bin/env python3
"""
GitHub Repository Secrets 일괄 업데이트 스크립트
GITLAB_TOKEN을 모든 리포지토리에 추가/업데이트합니다.
"""

import os
import sys
import requests
from base64 import b64encode
from nacl import encoding, public
from datetime import datetime

# ==================== 설정 ====================
GITHUB_TOKEN = os.environ.get('GITHUB_TOKEN', '')  # 또는 직접 입력
GITHUB_ORG = 'somaz94'  # Organization 이름 또는 username
NEW_GITLAB_TOKEN = ''  # 새로운 GitLab Token
SECRET_NAME = 'GITLAB_TOKEN'

# Dry-run 모드 (True면 실제로 업데이트 안 함)
DRY_RUN = False

# ===============================================

class Colors:
    """터미널 색상"""
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    BLUE = '\033[94m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

def print_header(text):
    """헤더 출력"""
    print(f"\n{Colors.BOLD}{Colors.BLUE}{'='*60}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{text}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{'='*60}{Colors.RESET}\n")

def print_success(text):
    """성공 메시지"""
    print(f"{Colors.GREEN}✓ {text}{Colors.RESET}")

def print_warning(text):
    """경고 메시지"""
    print(f"{Colors.YELLOW}⚠ {text}{Colors.RESET}")

def print_error(text):
    """에러 메시지"""
    print(f"{Colors.RED}✗ {text}{Colors.RESET}")

def encrypt_secret(public_key: str, secret_value: str) -> str:
    """GitHub Secret 암호화"""
    try:
        pk = public.PublicKey(public_key.encode("utf-8"), encoding.Base64Encoder())
        sealed_box = public.SealedBox(pk)
        encrypted = sealed_box.encrypt(secret_value.encode("utf-8"))
        return b64encode(encrypted).decode("utf-8")
    except Exception as e:
        raise Exception(f"암호화 실패: {e}")

def get_all_repos(org: str, token: str):
    """모든 리포지토리 가져오기 (pagination 처리)"""
    headers = {
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github.v3+json'
    }
    
    repos = []
    page = 1
    
    print("리포지토리 목록 가져오는 중...")
    
    while True:
        url = f'https://api.github.com/orgs/{org}/repos?per_page=100&page={page}'
        # Organization이 아닌 개인 계정이면:
        # url = f'https://api.github.com/users/{org}/repos?per_page=100&page={page}'
        
        response = requests.get(url, headers=headers)
        
        if response.status_code == 404:
            # Organization이 아니면 개인 리포지토리 시도
            url = f'https://api.github.com/users/{org}/repos?per_page=100&page={page}'
            response = requests.get(url, headers=headers)
        
        if response.status_code != 200:
            print_error(f"리포지토리 목록 가져오기 실패: HTTP {response.status_code}")
            print_error(f"응답: {response.text}")
            sys.exit(1)
        
        data = response.json()
        if not data:
            break
        
        repos.extend([repo['name'] for repo in data])
        print(f"  페이지 {page}: {len(data)}개 발견 (누적: {len(repos)}개)")
        page += 1
    
    return repos

def check_secret_exists(org: str, repo: str, secret_name: str, token: str):
    """Secret 존재 여부 확인"""
    headers = {
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github.v3+json'
    }
    
    url = f'https://api.github.com/repos/{org}/{repo}/actions/secrets/{secret_name}'
    response = requests.get(url, headers=headers)
    
    return response.status_code == 200

def update_secret(org: str, repo: str, secret_name: str, secret_value: str, token: str, dry_run=False):
    """Secret 업데이트/추가"""
    headers = {
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github.v3+json'
    }
    
    try:
        # 1. Secret 존재 여부 확인
        exists = check_secret_exists(org, repo, secret_name, token)
        action = 'update' if exists else 'add'
        
        if dry_run:
            return True, f'Would {action} (dry-run)', action
        
        # 2. Public key 가져오기
        key_url = f'https://api.github.com/repos/{org}/{repo}/actions/secrets/public-key'
        key_response = requests.get(key_url, headers=headers)
        
        if key_response.status_code != 200:
            return False, f'Public key 가져오기 실패: HTTP {key_response.status_code}', action
        
        key_data = key_response.json()
        key_id = key_data['key_id']
        public_key = key_data['key']
        
        # 3. Secret 암호화
        encrypted_value = encrypt_secret(public_key, secret_value)
        
        # 4. Secret 업데이트
        secret_url = f'https://api.github.com/repos/{org}/{repo}/actions/secrets/{secret_name}'
        secret_data = {
            'encrypted_value': encrypted_value,
            'key_id': key_id
        }
        
        response = requests.put(secret_url, headers=headers, json=secret_data)
        
        if response.status_code in [201, 204]:
            return True, 'Success', action
        else:
            return False, f'HTTP {response.status_code}: {response.text}', action
            
    except Exception as e:
        return False, str(e), 'error'

def save_log(stats, failed_repos):
    """로그 파일 저장"""
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    log_file = f'github_secrets_update_{timestamp}.log'
    
    with open(log_file, 'w') as f:
        f.write(f"GitHub Secrets Update Log\n")
        f.write(f"{'='*60}\n\n")
        f.write(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"Organization: {GITHUB_ORG}\n")
        f.write(f"Secret Name: {SECRET_NAME}\n")
        f.write(f"Dry Run: {DRY_RUN}\n\n")
        f.write(f"Results:\n")
        f.write(f"  Total: {stats['total']}\n")
        f.write(f"  Updated: {stats['updated']}\n")
        f.write(f"  Added: {stats['added']}\n")
        f.write(f"  Failed: {stats['failed']}\n\n")
        
        if failed_repos:
            f.write(f"Failed Repositories:\n")
            for repo, reason in failed_repos:
                f.write(f"  - {repo}: {reason}\n")
    
    return log_file

def main():
    """메인 함수"""
    
    # 입력 검증
    if not GITHUB_TOKEN:
        print_error("GITHUB_TOKEN이 설정되지 않았습니다!")
        print("환경변수로 설정하거나 스크립트에 직접 입력해주세요:")
        print("  export GITHUB_TOKEN='your_token_here'")
        sys.exit(1)
    
    if not NEW_GITLAB_TOKEN:
        print_error("NEW_GITLAB_TOKEN이 설정되지 않았습니다!")
        print("스크립트에 새로운 GitLab Token을 입력해주세요.")
        sys.exit(1)
    
    print_header(f"GitHub Repository Secrets 업데이트")
    
    print(f"Organization: {Colors.BOLD}{GITHUB_ORG}{Colors.RESET}")
    print(f"Secret Name: {Colors.BOLD}{SECRET_NAME}{Colors.RESET}")
    print(f"Dry Run: {Colors.BOLD}{DRY_RUN}{Colors.RESET}")
    
    if DRY_RUN:
        print_warning("DRY-RUN 모드: 실제로 업데이트하지 않습니다.")
    
    # 확인
    if not DRY_RUN:
        print(f"\n{Colors.YELLOW}정말로 모든 리포지토리의 {SECRET_NAME}을 업데이트하시겠습니까?{Colors.RESET}")
        confirm = input("계속하려면 'yes' 입력: ")
        if confirm.lower() != 'yes':
            print("취소되었습니다.")
            sys.exit(0)
    
    # 리포지토리 목록 가져오기
    print_header("1. 리포지토리 목록 가져오기")
    repos = get_all_repos(GITHUB_ORG, GITHUB_TOKEN)
    print_success(f"총 {len(repos)}개의 리포지토리 발견")
    
    # Secret 업데이트
    print_header("2. Secret 업데이트 중...")
    
    stats = {'total': 0, 'updated': 0, 'added': 0, 'failed': 0}
    failed_repos = []
    
    for idx, repo in enumerate(repos, 1):
        stats['total'] += 1
        print(f"\n[{idx}/{len(repos)}] {Colors.BOLD}{GITHUB_ORG}/{repo}{Colors.RESET}")
        
        success, message, action = update_secret(
            GITHUB_ORG, repo, SECRET_NAME, NEW_GITLAB_TOKEN, GITHUB_TOKEN, DRY_RUN
        )
        
        if success:
            if action == 'add':
                stats['added'] += 1
                print_success(f"Secret 추가됨")
            else:
                stats['updated'] += 1
                print_success(f"Secret 업데이트됨")
        else:
            stats['failed'] += 1
            print_error(f"실패: {message}")
            failed_repos.append((repo, message))
    
    # 결과 요약
    print_header("3. 결과 요약")
    print(f"총 리포지토리: {Colors.BOLD}{stats['total']}{Colors.RESET}")
    print_success(f"업데이트: {stats['updated']}")
    print_success(f"추가: {stats['added']}")
    if stats['failed'] > 0:
        print_error(f"실패: {stats['failed']}")
    
    # 실패한 리포지토리 상세
    if failed_repos:
        print(f"\n{Colors.RED}실패한 리포지토리:{Colors.RESET}")
        for repo, reason in failed_repos:
            print(f"  - {repo}: {reason}")
    
    # 로그 저장
    log_file = save_log(stats, failed_repos)
    print(f"\n로그 파일 저장: {Colors.BOLD}{log_file}{Colors.RESET}")
    
    print_header("완료!")

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n\n{Colors.YELLOW}사용자에 의해 중단되었습니다.{Colors.RESET}")
        sys.exit(0)
    except Exception as e:
        print_error(f"예상치 못한 에러: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)