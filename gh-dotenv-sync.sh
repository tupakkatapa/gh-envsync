#!/usr/bin/env bash
# Sync local .env.<name> files to GitHub Environment Secrets
# Usage: gh-dotenv-sync [options]

set -euo pipefail

display_usage() {
    cat <<USAGE
Usage: gh-dotenv-sync [options]

Description:
  Sync local .env.<name> files to GitHub Environment Secrets.
  Each .env.<name> file maps to a GitHub environment called <name>.

  Without flags, auto-detects environment from git branch:
    main -> prd, staging -> stg, * -> dev

Options:
  -e, --env <name>
    Sync a specific environment (e.g., --env prd syncs .env.prd)

  -a, --all
    Sync all .env.<name> files found in the current directory

  -f, --force
    Force re-sync by clearing state files

  -n, --dry-run
    Show what would be synced without making changes

  -h, --help
    Display this help message and exit

Examples:
  gh-dotenv-sync                  # Auto-detect from branch
  gh-dotenv-sync --env prd        # Sync .env.prd to 'prd' environment
  gh-dotenv-sync --all            # Sync all .env.<name> files
  gh-dotenv-sync --force --all    # Force re-sync everything

USAGE
}

# Check gh is available
if ! command -v gh &>/dev/null; then
    echo "error: gh CLI not found. Install it: https://cli.github.com" >&2
    exit 1
fi

# Parse args
FORCE=""
SYNC_ALL=""
DRY_RUN=""
TARGET_ENV=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f | --force) FORCE="1"; shift ;;
        -a | --all) SYNC_ALL="1"; shift ;;
        -n | --dry-run) DRY_RUN="1"; shift ;;
        -e | --env)
            if [[ -z "${2:-}" ]]; then
                echo "error: --env requires a value" >&2
                exit 1
            fi
            TARGET_ENV="$2"; shift 2 ;;
        -h | --help) display_usage; exit 0 ;;
        *)
            echo "error: unknown option -- '$1'" >&2
            echo "try '--help' for more information" >&2
            exit 1 ;;
    esac
done

# Check gh auth
if ! gh auth status >/dev/null 2>&1; then
    echo "error: gh not authenticated. Run 'gh auth login'" >&2
    exit 1
fi

sync_env() {
    local env_file="$1"
    local gh_env="$2"
    local state_file=".env.sync.${gh_env}.last"

    if [[ ! -f "$env_file" ]]; then
        echo "skip: $env_file not found"
        return 0
    fi

    # Force mode: clear state file
    if [[ -n "$FORCE" && -f "$state_file" ]]; then
        echo "force: clearing state for $gh_env"
        rm "$state_file"
    fi

    # Check if sync needed
    if [[ -z "$FORCE" ]] && diff -q "$env_file" "$state_file" >/dev/null 2>&1; then
        echo "skip: $gh_env unchanged"
        return 0
    fi

    echo "sync: $gh_env ($env_file)"
    local changes=0

    # Find deleted secrets
    if [[ -f "$state_file" ]]; then
        while IFS='=' read -r key _; do
            [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
            if ! grep -q "^${key}=" "$env_file"; then
                if [[ -n "$DRY_RUN" ]]; then
                    echo "  - $key (delete)"
                else
                    gh secret delete "$key" --env "$gh_env" 2>/dev/null && echo "  - $key"
                fi
                changes=$((changes + 1))
            fi
        done < "$state_file"
    fi

    # Find new/changed secrets
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
        old_line=$(grep "^${key}=" "$state_file" 2>/dev/null || true)
        new_line="${key}=${value}"
        if [[ "$old_line" != "$new_line" ]]; then
            # Strip surrounding quotes
            value="${value#\"}"; value="${value%\"}"
            value="${value#\'}"; value="${value%\'}"
            if [[ -n "$DRY_RUN" ]]; then
                echo "  + $key (set)"
            else
                gh secret set "$key" --env "$gh_env" --body "$value" 2>/dev/null && echo "  + $key"
            fi
            changes=$((changes + 1))
        fi
    done < "$env_file"

    if [[ -z "$DRY_RUN" ]]; then
        cp "$env_file" "$state_file"
    fi
    echo "  $changes change(s)"
}

if [[ -n "$SYNC_ALL" ]]; then
    # Sync all .env.<name> files
    found=0
    for env_file in .env.*; do
        [[ ! -f "$env_file" ]] && continue
        # Skip state files and .env.example
        [[ "$env_file" == .env.sync.* ]] && continue
        [[ "$env_file" == .env.example ]] && continue

        gh_env="${env_file#.env.}"
        sync_env "$env_file" "$gh_env"
        found=1
    done
    if [[ "$found" -eq 0 ]]; then
        echo "error: no .env.<name> files found" >&2
        exit 1
    fi
elif [[ -n "$TARGET_ENV" ]]; then
    # Sync specific environment
    sync_env ".env.${TARGET_ENV}" "$TARGET_ENV"
else
    # Auto-detect from git branch
    branch=$(git branch --show-current 2>/dev/null || echo "dev")
    case "$branch" in
        main | master) gh_env="prd" ;;
        staging) gh_env="stg" ;;
        *) gh_env="dev" ;;
    esac

    env_file=".env.${gh_env}"
    if [[ ! -f "$env_file" ]]; then
        echo "error: $env_file not found (branch: $branch)" >&2
        exit 1
    fi

    # Copy to .env for local use
    cp "$env_file" .env
    echo "load: $env_file -> .env (branch: $branch)"

    sync_env "$env_file" "$gh_env"
fi
