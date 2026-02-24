#!/usr/bin/env bash
# Sync local .env.<name> files to GitHub Environment Secrets
# Usage: gh-envsync [options]

set -euo pipefail

CONFIG_FILE=".gh-envsync"

display_usage() {
    cat <<USAGE
Usage: gh-envsync [options]

  Sync .env.<name> files to GitHub Environment Secrets.

  Requires a .gh-envsync config mapping branches to environments:
    main=prd
    staging=stg
    *=dev

  Without flags, resolves the current branch to an environment via
  the config, copies .env.<name> to .env, and syncs to GitHub.

Options:
  -e, --env <name>    Sync .env.<name> directly, without config
  -a, --all           Sync all environments in config
  -f, --force         Re-sync even if nothing changed
  -n, --dry-run       Preview without syncing
  -h, --help          Show this help

USAGE
}

die() {
    for msg in "$@"; do
        echo "$msg" >&2
    done
    exit 1
}

require_config() {
    [[ -f "$CONFIG_FILE" ]] || die \
        "error: no $CONFIG_FILE config file found" \
        "hint: create one with branch=env mappings (e.g., main=prd)"
}

# Parse a config line. Sets _key and _value globals. Returns 1 to skip.
parse_config_line() {
    _key="$1"; _value="$2"
    [[ "$_key" =~ ^[[:space:]]*# || -z "$_key" ]] && return 1
    _key="${_key## }"; _key="${_key%% }"
    _value="${_value## }"; _value="${_value%% }"
}

# Check gh is available
command -v gh &>/dev/null || die "error: gh CLI not found. Install it: https://cli.github.com"

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
            [[ -n "${2:-}" ]] || die "error: --env requires a value"
            TARGET_ENV="$2"; shift 2 ;;
        -h | --help) display_usage; exit 0 ;;
        *) die "error: unknown option -- '$1'" "try '--help' for more information" ;;
    esac
done

# Validate flag combinations
[[ -z "$SYNC_ALL" || -z "$TARGET_ENV" ]] || die "error: --all and --env cannot be used together"

# Check gh auth
gh auth status >/dev/null 2>&1 || die "error: gh not authenticated. Run 'gh auth login'"

sync_env() {
    local env_file="$1"
    local gh_env="$2"
    local state_file=".env.sync.${gh_env}.last"

    if [[ ! -f "$env_file" ]]; then
        echo "skip: $env_file not found"
        return 0
    fi

    # Skip if unchanged (unless forcing)
    if [[ -z "$FORCE" ]] && diff -q "$env_file" "$state_file" >/dev/null 2>&1; then
        echo "skip: $gh_env unchanged"
        return 0
    fi

    echo "sync: $gh_env ($env_file)"

    # Load previous state (empty when forcing to re-sync everything)
    declare -A old_secrets=()
    if [[ -z "$FORCE" && -f "$state_file" ]]; then
        while IFS='=' read -r key value || [[ -n "$key" ]]; do
            [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
            old_secrets["$key"]="$value"
        done < "$state_file"
    fi

    # Load current env file
    declare -A new_secrets=()
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
        new_secrets["$key"]="$value"
    done < "$env_file"

    local changes=0

    # Deleted: keys in old not in new
    for key in "${!old_secrets[@]}"; do
        if [[ -z "${new_secrets[$key]+x}" ]]; then
            if [[ -n "$DRY_RUN" ]]; then
                echo "  - $key (delete)"
            else
                gh secret delete "$key" --env "$gh_env" 2>/dev/null && echo "  - $key"
            fi
            changes=$((changes + 1))
        fi
    done

    # Changed/added: keys new or different from old
    for key in "${!new_secrets[@]}"; do
        if [[ -z "${old_secrets[$key]+x}" ]] || [[ "${old_secrets[$key]}" != "${new_secrets[$key]}" ]]; then
            local value="${new_secrets[$key]}"
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
    done

    if [[ -z "$DRY_RUN" ]]; then
        cp "$env_file" "$state_file"
    fi
    echo "  $changes change(s)"
}

resolve_env() {
    local branch="$1"
    local wildcard=""
    while IFS='=' read -r _key _value || [[ -n "$_key" ]]; do
        parse_config_line "$_key" "$_value" || continue
        if [[ "$_key" == "$branch" ]]; then
            echo "$_value"
            return 0
        fi
        if [[ "$_key" == "*" ]]; then
            wildcard="$_value"
        fi
    done < "$CONFIG_FILE"

    if [[ -n "$wildcard" ]]; then
        echo "$wildcard"
        return 0
    fi

    die "error: branch '$branch' not mapped in $CONFIG_FILE"
}

if [[ -n "$SYNC_ALL" ]]; then
    require_config
    declare -A seen_envs
    while IFS='=' read -r _key _value || [[ -n "$_key" ]]; do
        parse_config_line "$_key" "$_value" || continue
        [[ -n "${seen_envs[$_value]:-}" ]] && continue
        seen_envs[$_value]=1
        sync_env ".env.${_value}" "$_value"
    done < "$CONFIG_FILE"
    [[ ${#seen_envs[@]} -gt 0 ]] || die "error: no environments defined in $CONFIG_FILE"
elif [[ -n "$TARGET_ENV" ]]; then
    sync_env ".env.${TARGET_ENV}" "$TARGET_ENV"
else
    branch=$(git branch --show-current 2>/dev/null)
    [[ -n "$branch" ]] || die \
        "error: could not detect branch (detached HEAD?)" \
        "hint: use --env <name> to sync a specific environment"

    require_config
    gh_env=$(resolve_env "$branch") || exit 1

    env_file=".env.${gh_env}"
    [[ -f "$env_file" ]] || die "error: $env_file not found (branch: $branch -> $gh_env)"

    # Copy to .env for local use, protecting manual edits
    local_state=".env.sync.local"
    if [[ -f .env ]]; then
        current_sum=$(md5sum .env | cut -d' ' -f1)
        stored_sum=$(cut -d' ' -f1 < "$local_state" 2>/dev/null || true)
        [[ "$current_sum" == "$stored_sum" ]] || die \
            "error: .env has unsaved changes" \
            "hint: move your changes to $env_file and re-run"
    fi
    cp "$env_file" .env
    md5sum .env > "$local_state"
    echo "load: $env_file -> .env (branch: $branch)"

    sync_env "$env_file" "$gh_env"
fi
