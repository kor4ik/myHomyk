# myHomyk

Home Assistant configuration for the home: climate, rollers, lights, lock, TVs, and four YAML dashboards (mobile, tablet, dev, kid) built on [UI Lovelace Minimalist](https://github.com/UI-Lovelace-Minimalist/UI). The repo is the HA `/config` directory.

## Set up a real install

1. Put the repo contents in `/config`.
2. Copy `secrets.example.yaml` to `secrets.yaml` and fill in every value.
3. Create an empty `themes/` folder (`frontend: themes:` fails without it).
4. Install through HACS:
   - Integrations: `ui_lovelace_minimalist`, `smartir`.
   - Frontend cards: `button-card`, `layout-card` (`grid-layout`), `state-switch`, `simple-clock-card`, `my-slider`.
5. Add the Minimalist integration under Settings > Devices & Services, then restart HA.
6. Add these through the UI, since HA no longer accepts them as YAML platforms:
   - Gree (the three bedroom ACs). Rename the entities to `climate.ac_guest`, `climate.ac_laly` and `climate.ac_office`.
   - The door lock (Tuya or Gimdow integration). Set its entity ID in the `lock_entity` secret.

## Layout

| Path | Purpose |
|---|---|
| `configuration.yaml` | Entry point, HTTP settings, dashboard registration |
| `climate.yaml` | SmartIR air conditioners (Gree blocks are commented out) |
| `automations.yaml`, `scripts.yaml`, `sensors.yaml`, `groups.yaml` | Automations, find-my-phone scripts, water-heater sensor, groups |
| `ui_lovelace_minimalist/dashboard/` | Dashboards (`ui-lovelace*.yaml`) and their `views/` (`views_dev/` holds dev-only variants) |
| `ui_lovelace_minimalist/custom_cards/` | Project-specific button-card templates |
| `dev/` | Disposable test instance |

## Test locally

`dev/ha-dev.sh` builds a throwaway Home Assistant with demo entities, using the Apple `container` CLI.

```
dev/ha-dev.sh up                   # start a fresh instance at http://localhost:8123
dev/ha-dev.sh down                 # remove it completely
HA_WORKTREE=1 dev/ha-dev.sh test   # run all checks on the working tree
dev/ha-dev.sh test --browser       # also render every view in a headless browser
```

See `dev/README.md` for the checks and options.
