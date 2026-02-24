# gh-dotenv-sync

Sync local `.env.<name>` files to GitHub Environment Secrets. A free replacement for [Doppler](https://www.doppler.com/) when all you need is to keep your `.env` files in sync with GitHub Actions.

Each `.env.<name>` file maps to a GitHub environment called `<name>`. Only changed secrets are synced -- additions, modifications, and deletions are all tracked.

## Usage

```sh
nix run github:tupakkatapa/gh-dotenv-sync -- --help
```

```
Usage: gh-dotenv-sync [options]

Description:
  Sync local .env.<name> files to GitHub Environment Secrets.
  Each .env.<name> file maps to a GitHub environment called <name>.

  Without flags, auto-detects environment from git branch:
    main -> prd, staging -> stg, * -> dev

Options:
  -e, --env <name>    Sync a specific environment (e.g., --env prod syncs .env.prod)
  -a, --all           Sync all .env.<name> files found in the current directory
  -f, --force         Force re-sync by clearing state files
  -n, --dry-run       Show what would be synced without making changes
  -h, --help          Display this help message and exit
```

### Branch auto-detection

Without flags, the current git branch determines which env file to sync:

| Branch | Env file | GitHub environment |
|--------|----------|--------------------|
| `main`/`master` | `.env.prd` | `prd` |
| `staging` | `.env.stg` | `stg` |
| anything else | `.env.dev` | `dev` |

The active env file is also copied to `.env` for local use.

```bash
gh-dotenv-sync
# load: .env.dev -> .env (branch: feature/foo)
# sync: dev (.env.dev)
#   + DATABASE_URL
#   + API_KEY
#   2 change(s)
```

### Examples

```bash
gh-dotenv-sync --env prod       # Sync .env.prod to 'prod' environment
gh-dotenv-sync --all            # Sync all .env.<name> files
gh-dotenv-sync --force --all    # Force re-sync everything
gh-dotenv-sync --dry-run --all  # Preview changes without syncing
```

## Without Nix

The script only depends on [`gh`](https://cli.github.com), `git`, and standard coreutils:

```bash
curl -O https://raw.githubusercontent.com/tupakkatapa/gh-dotenv-sync/main/gh-dotenv-sync.sh
chmod +x gh-dotenv-sync.sh
./gh-dotenv-sync.sh --help
```

## How it works

1. Reads key-value pairs from `.env.<name>`
2. Compares against the last synced state (`.env.sync.<name>.last`)
3. Sets new/changed secrets and deletes removed ones via `gh secret set/delete --env <name>`
4. Saves current state for next comparison

GitHub environments must exist in the repository before syncing (Settings > Environments). The `gh` CLI must be authenticated (`gh auth login`).
