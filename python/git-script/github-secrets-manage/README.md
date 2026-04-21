# GitHub Secrets Manager

Bulk-manage **Actions** and **Dependabot** secrets across all repositories in a GitHub organization or user account.

<br/>

## Features

- **list** — View secrets for every repository at a glance
- **add** — Add a single secret to Actions and auto-sync to Dependabot in one shot
- **sync** — Copy Actions secrets to Dependabot secrets (with optional value injection)
- **update** — Add or update a specific secret across all repositories
- **delete** — Remove a specific secret from all repositories
- Automatic **rate-limit** handling
- **Dry-run** mode for safe previewing
- JSON **execution logs** saved to `logs/`

<br/>

## Prerequisites

- Python 3.10+
- A GitHub **Personal Access Token** with `repo` scope

<br/>

### Setup (Virtual Environment)

#### macOS / Linux

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

#### Windows (PowerShell)

```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

#### Windows (CMD)

```cmd
python -m venv venv
venv\Scripts\activate.bat
pip install -r requirements.txt
```

Dependencies: `requests`, `PyNaCl`

<br/>

## Authentication

```bash
export GITHUB_TOKEN='ghp_xxxxxxxxxxxx'
```

<br/>

## Providing Secret Values

The tool needs the **actual values** of secrets to sync or update them (GitHub's API does not expose secret values). Three methods are supported, in priority order:

<br/>

### 1. Environment Variables (direct name matching)

Export variables whose names match the secret names exactly — no prefix needed:

```bash
export GITLAB_TOKEN='glpat-xxxxxxxxxxxx'
export PAT_TOKEN='ghp_xxxxxxxxxxxx'
export DOCKERHUB_TOKEN='dckr_pat_xxxxxxxxxxxx'

python3 github-secrets-manage.py sync --org somaz94
```

<br/>

### 2. `.env` File

Keep secrets out of your shell history by using a file:

```env
# .secrets.env
GITLAB_TOKEN=glpat-xxxxxxxxxxxx
PAT_TOKEN=ghp_xxxxxxxxxxxx
DOCKERHUB_TOKEN=dckr_pat_xxxxxxxxxxxx
```

```bash
python3 github-secrets-manage.py sync --org somaz94 --env-file .secrets.env
```

<br/>

### 3. JSON Environment Variable

```bash
export SECRET_VALUES='{"GITLAB_TOKEN":"glpat-xxx","PAT_TOKEN":"ghp_xxx"}'

python3 github-secrets-manage.py sync --org somaz94
```

<br/>

## Usage

<br/>

### List Secrets

```bash
# List all secrets (Actions + Dependabot) for every repository
python3 github-secrets-manage.py list --org somaz94

# Dependabot secrets only
python3 github-secrets-manage.py list --org somaz94 --target dependabot
```

<br/>

### Add a Secret (Actions + Dependabot)

Adds a single new secret to Actions and immediately propagates it to Dependabot — one command, two secret stores. The value is read from an env var whose name matches `--secret-name` (no need to pass the value on the command line).

```bash
# Export the value, then run `add`
export GITLAB_TOKEN='glpat-xxxxxxxxxxxx'
python3 github-secrets-manage.py add --org somaz94 --secret-name GITLAB_TOKEN

# Actions only (skip Dependabot sync)
python3 github-secrets-manage.py add --org somaz94 --secret-name GITLAB_TOKEN --no-sync

# Target specific repositories only
python3 github-secrets-manage.py add --org somaz94 --secret-name GITLAB_TOKEN \
  --repos kube-diff,git-bridge

# Dry-run preview
python3 github-secrets-manage.py add --org somaz94 --secret-name GITLAB_TOKEN --dry-run
```

> If you prefer passing the value inline, `--secret-value 'glpat-xxx'` is supported too, but `export` keeps secrets out of shell history.

`add` differs from `update` in intent:
- **add** — one secret, default target is *both* stores (Actions → Dependabot sync built in)
- **update** — bulk rotation; choose target explicitly via `--target actions|dependabot|both`

<br/>

### Sync Actions → Dependabot

```bash
# Sync all Actions secrets to Dependabot
python3 github-secrets-manage.py sync --org somaz94

# Sync specific secrets only
python3 github-secrets-manage.py sync --org somaz94 --secrets GITLAB_TOKEN,PAT_TOKEN

# Overwrite existing Dependabot secrets
python3 github-secrets-manage.py sync --org somaz94 --force

# Dry-run (preview without changes)
python3 github-secrets-manage.py sync --org somaz94 --dry-run
```

<br/>

### Update a Secret

```bash
# Update across Actions (default target)
python3 github-secrets-manage.py update --org somaz94 \
  --secret-name GITLAB_TOKEN --secret-value 'glpat-xxxxxxxxxxxx'

# Update across both Actions and Dependabot
python3 github-secrets-manage.py update --org somaz94 \
  --secret-name GITLAB_TOKEN --secret-value 'glpat-xxxxxxxxxxxx' --target both
```

<br/>

### Delete a Secret

```bash
# Delete from Actions (default target)
python3 github-secrets-manage.py delete --org somaz94 --secret-name OLD_SECRET

# Delete from both Actions and Dependabot
python3 github-secrets-manage.py delete --org somaz94 --secret-name OLD_SECRET --target both
```

<br/>

### Target Specific Repositories

All commands support `--repos` to limit scope:

```bash
python3 github-secrets-manage.py sync --org somaz94 --repos kube-diff,git-bridge
```

<br/>

## Common Options

| Flag | Description |
|------|-------------|
| `--org` | GitHub organization or username (required) |
| `--repos` | Comma-separated list of specific repositories |
| `--target` | `actions`, `dependabot`, or `both` |
| `--dry-run` | Preview changes without applying them |
| `-y, --yes` | Skip confirmation prompts |
| `-v, --verbose` | Enable verbose logging |

<br/>

## Logs

Every execution writes a JSON log to the `logs/` directory:

```
logs/secrets_sync_20260416_143022.json
```

The log includes command details, stats (total/success/failed/skipped), and per-repository results.

<br/>

## Project Structure

```
github-secrets-manage/
├── github-secrets-manage.py       # English version
├── github-secrets-manage-kr.py    # Korean version
├── requirements.txt
├── README.md
└── logs/                          # Auto-generated execution logs
```

<br/>

## License

MIT
