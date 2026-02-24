# gh-dotenv-sync

Sync local `.env.<name>` files to GitHub Environment Secrets. Only changed secrets are synced (additions, modifications, and deletions).

## Setup

Create a `.gh-dotenv-sync` config mapping branches to environments:

```
main=prd
staging=stg
*=dev
```

Example: when you run `gh-dotenv-sync` on branch `main`, it syncs `.env.prd` to the `prd` GitHub environment and copies it to `.env` for local use.

GitHub environments must exist before syncing (Settings > Environments) and `gh` CLI must be authenticated (`gh auth login`).

## Usage

```sh
nix run github:tupakkatapa/gh-dotenv-sync -- --help
```

**Without Nix**: Only depends on [`gh`](https://cli.github.com), `git`, and coreutils.

```bash
curl -O https://raw.githubusercontent.com/tupakkatapa/gh-dotenv-sync/main/gh-dotenv-sync.sh
chmod +x gh-dotenv-sync.sh
./gh-dotenv-sync.sh --help
```
