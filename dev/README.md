# Disposable test instance

Builds Home Assistant from a clean clone of this repo with demo entities, so the dashboards render without real devices.

```
dev/ha-dev.sh up            # clean clone, fetch cards, start, onboard
dev/ha-dev.sh down          # remove container and dev/.work
dev/ha-dev.sh down --purge  # also delete the HA image
dev/ha-dev.sh reset         # down + up
dev/ha-dev.sh test          # throwaway instance, run the checks, tear it down
HA_WORKTREE=1 dev/ha-dev.sh test   # same, using uncommitted files
dev/ha-dev.sh test --keep   # leave the instance running; remove with `down --test`
```

`test` uses its own container, port (8125) and work folder, so it never touches an instance from `up`. Checks, with exit code 1 on any failure:
- `check_config` passes.
- The startup log has no errors beyond known offline noise (`LOG_NOISE` in the script).
- Every dashboard loads, every `custom:` card type has a loaded resource, every button-card `template` exists, and every entity a dashboard references exists. Entities that need a real integration go in `overlay/allow-missing.txt`.

- `up`, `down` and `test` use the Apple `container` CLI and bind the port to `127.0.0.1` only.
- Compose-compatible runtime, from `dev/`: `./ha-dev.sh prepare` (writes `dev/.env` and `dev/.work/config`), then `compose up -d`, then `./ha-dev.sh bootstrap` (creates the user, adds the Minimalist integration, restarts). `compose.yaml` has no defaults; it reads everything from `dev/.env`. Tested here by starting the container by hand with the same values, not with a Compose runtime.
- The clone contains committed files only. Commit changes first, set `HA_WORKTREE=1` to copy the working tree instead, or point `HA_SRC` at another path or URL (`HA_REF` picks a branch or tag).
- Overrides: `HA_PORT`, `HA_VERSION`, `HA_NAME`, `HA_USER`, `HA_PASS`, `TZ`.
- Demo mapping lives in `dev/overlay/`: dummy secrets, stand-in thermostats and weather (`standin/`), and the Lovelace resource list.
- Login: `dev` / `dev-pass-123`, on this instance only.
