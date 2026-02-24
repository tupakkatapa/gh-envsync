# gh-envsync

Sync local `.env.<name>` files to GitHub Environment Secrets. Only changed secrets are synced (additions, modifications, and deletions).

## Setup

Create a `.gh-envsync` config mapping branches to environments:

```
main=prd
staging=stg
*=dev
```

Example: when you run `gh-envsync` on branch `main`, it syncs `.env.prd` to the `prd` GitHub environment and copies it to `.env` for local use.

GitHub environments must exist before syncing (Settings > Environments) and `gh` CLI must be authenticated (`gh auth login`).

## Usage

```sh
nix run github:tupakkatapa/gh-envsync -- --help
```

**Without Nix**: Only depends on [`gh`](https://cli.github.com), `git`, and coreutils.

```bash
curl -O https://raw.githubusercontent.com/tupakkatapa/gh-envsync/main/gh-envsync.sh
chmod +x gh-envsync.sh
./gh-envsync.sh --help
```
