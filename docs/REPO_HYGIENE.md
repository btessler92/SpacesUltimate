# Repo Hygiene

## Git

The public repository is https://github.com/btessler92/SpacesUltimate.
Publish source and release documentation only; local configuration and build artifacts stay ignored.

Current baseline:

```sh
git log --oneline -1
```

Build outputs, local config, and generated screenshots are ignored through `.gitignore`.

## Common Commands

```sh
make build
make app
make app-release
make install
make package
make launch
make status
make smoke
make quit
```

Use `make smoke-destructive` only when it is okay to temporarily update and reset Space config.

## Commit Notes

Keep commits small and describe user-visible behavior. Run at least:

```sh
make build
make smoke
```

before committing app changes.

Use your GitHub noreply email for public commits if you prefer to keep your personal email private.
