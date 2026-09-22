# mc (Multicooker) — local dev setup, mocks & browser simulator

> Notes from the 2026-09-22 session. Everything described here is **local-only and not
> git-tracked** — the two repos stay clean (`git status` empty). This doc is the record
> of what we changed, why, and how to run/repair it.

---

## TL;DR — daily commands

```fish
# terminal 1 (tmux pane %18)
cd ~/repos/mc-api && mise run dev      # API on :3000, mocked hardware, auto-restarts

# terminal 2 (tmux pane %19)
cd ~/repos/mc-ui && mise run dev       # Vite on :3001
```

Then open **http://localhost:3001** in the dedicated automation Chrome with the DevTools
device simulator **"mc"** selected (800×1280 — same as the machine monitor).

- Repos/branches: `mc-api` @ `v6`, `mc-ui` @ `v6`
- Node: **20.20.2** via mise (pinned in the onboarding mock configs, symlinked as each
  repo's local `mise.local.toml`)
- tmux: session `mc`, window 3 → pane `%18` = mc-api, pane `%19` = mc-ui

---

## 0. Bootstrap on a fresh machine (start here)

Prerequisites: `git`, [mise](https://mise.jdx.dev), and mise activated in your shell
(`eval "$(mise activate bash)"` / `mise activate fish | source`). Node itself comes from mise.

```fish
# 1. clone both repos (branch v6)
git clone git@github.com:Hestia-Technology/mc-api.git ~/repos/mc-api
cd ~/repos/mc-api && git checkout v6
git clone git@github.com:Hestia-Technology/mc-ui.git ~/repos/mc-ui
cd ~/repos/mc-ui && git checkout v6

# 2. create the local-only mise config in each repo
#    → the mock configs are versioned in the onboarding repo; clone it and symlink them in
git clone git@github.com:kai-hestia/onboarding.git ~/repos/onboarding
ln -s ../onboarding/mc-api.toml ~/repos/mc-api/mise.local.toml
ln -s ../onboarding/mc-ui.toml  ~/repos/mc-ui/mise.local.toml

# 3. hide those files from git locally (per-clone; nothing is committed)
printf 'mise.local.toml\n.mise.local.toml\n' >> ~/repos/mc-api/.git/info/exclude
printf 'mise.local.toml\n.mise.local.toml\n' >> ~/repos/mc-ui/.git/info/exclude

# 4. trust the configs and install dependencies
cd ~/repos/mc-api && mise trust && npm ci
cd ~/repos/mc-ui  && mise trust && npm ci

# 5. run (two terminals)
cd ~/repos/mc-api && mise run dev      # API  :3000
cd ~/repos/mc-ui  && mise run dev      # UI   :3001
```

Notes:
- Use **`npm ci`**, never `npm install` (lockfile churn — see §2).
- No `.env` files are required; every local setting lives in `mise.local.toml` and the
  generated, gitignored `api/` tree. Stubs, fixtures and the simulator are created
  automatically by `mise run build` (run by `mise run dev`).
- The whole mock lives in **`~/repos/onboarding/mc-api.toml`** (symlinked as mc-api's
  `mise.local.toml`); the UI config is `~/repos/onboarding/mc-ui.toml`. Edit those files,
  not this doc.
- Browser automation (§6) is optional for running the apps: any browser at
  `http://localhost:3001` works. The `mc` device simulator is a DevTools convenience.

---

## 1. Why all this exists

1. **`npm start` in mc-api is broken at v6 HEAD.** `src/Menu.js` mixes CommonJS
   (`require`) with ESM (`export`, lines 372/398) since commit `8344138`
   ("refactor: rewrite menu with async file io").
   - Node < 20.19 → `SyntaxError: Unexpected token 'export'`
   - Node ≥ 20.19 (ours) → syntax detection loads it as ESM → `require is not defined in ES module scope`
   - The ncc bundle (webpack) tolerates the mix, and that is exactly what production runs.
2. **mc-api is hardware-coupled.** `src/Serial.js` calls `start_serial()` at require time →
   `bin/board_disable.sh` (WiringPi `gpio`), `bin/serialcom` (ARM aarch64 binary),
   `bin/service_restart.sh` (`systemctl restart multicooker`). None of that exists on this box.
3. **mc-ui needs data the API only has on a real device**: `menu/` files and a live machine
   status stream. Without them the UI loops `/ → /error` and `/menu/menu` 404s.

Instead of modifying the team repos, every workaround lives in **gitignored/local-only files**:
`mise.local.toml` (excluded via `.git/info/exclude`) and everything generated inside
`mc-api/api/` (already in `.gitignore` as `api/*`).

---

## 2. Node / npm notes

- **Node 20** is the right pin:
  - mc-ui CI uses `20.x` (`azure-pipelines.yml`)
  - Vite 6 engines: `^18.0.0 || ^20.0.0 || >=22.0.0`
  - mc-api Azure SDK deps require `>=20.0.0`
  - mc-api's README says Node 21.x — that's a non-LTS, EOL since 2024. Ignore it.
- **Use `npm ci`, not `npm install`.**
  The committed `package-lock.json` (mc-api) contains a stale `"peer": true` on `express`
  (which is a direct dependency). Every npm version tested (9.9.4, 10.7.0, 10.8.2, 10.9.4,
  11.19.0) removes that line on plain `npm install`. `npm ci` never writes the lockfile ⇒
  no git diff. `npm install --package-lock=false` also writes nothing but silently installs
  different versions (it pulled express 4.22.3 instead of 4.21.2) — do not use it.

---

## 3. What is local-only (not in git)

### 3.1 Mock configs — source of truth: the onboarding repo

| Real file (versioned in onboarding) | Symlinked as (in the repo) |
|---|---|
| `~/repos/onboarding/mc-api.toml` | `~/repos/mc-api/mise.local.toml` |
| `~/repos/onboarding/mc-ui.toml`  | `~/repos/mc-ui/mise.local.toml`  |

- `mc-api.toml`: Node 20 pin, the `build` task (ncc bundle + gpio/systemctl/serialcom
  mocks + menu fixtures + settings patch) and the watchdog `dev` task.
- `mc-ui.toml`: Node 20 pin + the `dev` task (`npm run dev`).
- Both repo paths are **symlinks** to the onboarding files, so editing either side edits
  the same file and every change is git-tracked in onboarding. On a machine without the
  onboarding clone, a plain copy of those two files works just as well.
- mise resolves `{{config_root}}` through the symlink to the repo directory, so
  `mise run build` still writes `api/` inside `mc-api` (verified 2026-09-22).
- The simulator's cook timing is the `at(...)` calls in `mc-api.toml`.

### 3.2 `.git/info/exclude` (both repos, appended)

```
mise.local.toml
.mise.local.toml
```

This keeps the local config invisible to teammates and out of `git status`
(we deliberately did **not** touch the tracked `.gitignore`).

### 3.3 Generated files inside `mc-api/api/` (all gitignored via `api/*`)

| Path | What it is |
|---|---|
| `api/index.js` | ncc bundle of `index.js` (what production runs) |
| `api/bin/gpio` | no-op stub for WiringPi `gpio` (board_disable/enable.sh) |
| `api/bin/systemctl` | stub: kills the API pid from `.api.pid` then exits 0 |
| `api/bin/serialcom` | **protocol simulator** (Node) — see §5 |
| `api/bin/*` | copies of `bin/` with `chmod +x` applied |
| `api/menu/cuisinesbymenu.json` | sample menu fixture (Menu → Category → Recipe) |
| `api/menu/1.json` | sample cuisine/recipe detail (`uuid`, `cuisine_name`, `actions`) |
| `api/menu/machine/1_1_v1.json` | machine recipe; must contain `id`, `version`, `uuid` |
| `api/tmp/` | needed because `machine_start_cook` copies to `./tmp/recipe.json` |
| `api/settings.json` | patched: `disable_ui_clients_check=true`, `machine_name="DEV"` |
| `api/.api.pid` | current API node PID, written by the watchdog (used by systemctl stub) |

---

## 4. How each hack works

| Hack | Why |
|---|---|
| `npx ncc build` into `api/` | sidesteps the mixed CJS/ESM source; matches production |
| `gpio` stub | `board_disable.sh`/`board_enable.sh` need WiringPi, Pi-only |
| `systemctl` stub | `service_restart.sh` runs `systemctl restart multicooker`; locally it kills the API so the watchdog brings it back (mimics systemd) |
| watchdog loop | local `Restart=always`; API also survives crashes (e.g. unhandled rejections) |
| `chmod +x api/bin/*` | git stores several `bin/` files as `100644`; the Pi's updater runs `chmod -R 755 ./bin/*`, dev clones don't. Without it the UI touch-check spawn crashes the API ~30 s in with `EACCES` |
| `serialcom` simulator | provides `~STATUS` heartbeats (prevents `server_state='FAILURE'` after 10 s), answers upload/command protocol, drives a cook cycle |
| `disable_ui_clients_check=true` | otherwise the API restarts itself every 15 s whenever no browser is connected |
| `machine_name="DEV"` | the mock status is published via MQTT at 1 Hz; using real name `CM1` would pollute the team broker topic |
| menu fixtures | `/menu/menu` returns 404 without `menu/cuisinesbymenu.json`; COOK needs `menu/machine/*` |

Gotcha baked into the watchdog: mise runs task scripts with `sh -o errexit`, so
`wait "$NODE_PID"` returning non-zero would kill the loop. It's wrapped in `if wait ...; then`.

---

## 5. Controller protocol simulator (`api/bin/serialcom`)

Wire format (observed from `src/Machine.js`):

- **Commands**: `<text>\n` padded with NULs to 50 bytes, then 2-byte CRC16 (LE) ⇒ **52-byte frames**.
- **File chunks**: up to **1024 bytes + 2-byte CRC** each.
- Simulator ignores CRC, parses frames, and replies:

| Emitted line | Meaning / code path |
|---|---|
| `~STATUS: {...}` | 1 Hz heartbeat; keeps `alive_counter` at 0, feeds the UI ws |
| `~CMD: OK` | clears `cmd_in_progress` after every command |
| `~UPLOADF: START` | begins file upload; then one `~UPLOADF: CHUNK` per chunk |
| `~ORDER: <id>` | sets `MachineStatus.cook.id` (used by UI routing) |
| `~PREPINFO: 0 1 1 1 1 1 1 1 0` | cook mode + 7 slot statuses |
| `~COOKINFO: <mode> (<cur>) (<next>) <step> <total> <remain> <total_sec>` | step/action/countdown |

Cook cycle triggered by a real `COOK <id>` command:

```
t=0s   ~ORDER, ~PREPINFO, PRECOOK cook=1   → UI #/cook/prepare
t=4s   PRECOOK cook=2                       → UI #/cook/cooking
t=8s   ~COOKINFO step 1/3, COOK cook=3, target=180 → cooking screen
t=14s  ~COOKINFO step 2/3
t=20s  ~COOKINFO step 3/3 (0 left), IDLE    → UI back to #/home
```

**Status JSON rules:** `status.status` ∈ IDLE/BUSY; `sys` is the UI's `system_state`
(IDLE is safe; ERROR/RESET/PRECOOK/COOK trigger navigation); **`alert` must be `-1`**
(the UI treats any other value as an active alert; with an unmapped id it calls an
undefined `global.$t` and throws).

**Recipe fixture rules:** `menu/machine/<id>_<n>_v<n>.json` must exist and contain
`id`, `version`, `uuid`; `menu/<recipe_id>.json` must share the same `uuid` so
`/menu/recipe_duration` works. `menu/machine/` is scanned by filename regex
`/^\d+_\d+_v\d+\.json$/` (no `recipesdir.json` needed despite the name).

Timings are the `at(...)` calls in the mock — edit and restart to taste.

---

## 6. Browser: dedicated Chrome + the "mc" device simulator

Setup lives in `~/.config/browser-harness/`:

- `agent-workspace/.env` → `BU_CDP_URL=http://127.0.0.1:19333`
- WSL↔Windows bridge: `~/.config/browser-harness/wsl-bridge/`
  - start/repair: `~/.config/browser-harness/wsl-bridge/start_bridge.sh`
  - stop: `~/.config/browser-harness/wsl-bridge/stop_bridge.sh`
  - Chrome runs on Windows with its own profile:
    `C:\Users\hestia\AppData\Local\browser-harness\chrome-profile`
- Drive it with the `browser-harness` skill (helpers pre-imported; heredocs).

### The "mc" simulator
In the automation Chrome: `Ctrl+Shift+I` → device toolbar → **Dimensions: mc**
(800×1280, DPR 1.5, touch) — matches the real cooking machine monitor.
We must keep **touch emulation on**: with it, taps work; mouse clicks can be used too
after coordinate correction.

**Recreate it on a new machine:** DevTools (`Ctrl+Shift+I`) → device toolbar →
Dimensions dropdown → *Edit…* → *Add custom device*: name `mc`, width `800`,
height `1280`, DPR `1.5`, check **Touch**. Save, then select it in the dropdown.

On a non-WSL machine no bridge is needed — browser-harness attaches to the local
Chrome (install/enable it per the browser-harness skill). The WSL↔Windows bridge
scripts under `~/.config/browser-harness/wsl-bridge/` are machine-specific helpers,
not part of any repo; a new Windows+WSL setup must recreate/copy them from the
browser-harness install docs. Everything else in §6 still applies (input-scale
calibration, touch taps, `capture_screenshot`).

### Input-coordinate gotcha (important for automation)
With DevTools device mode active, the 800×1280 page is scaled to fit the window
(real inner width was 760 ⇒ factor **1.0525**). Raw CDP input coordinates are in the
*un-scaled* window space, so a tap at CSS `(400,1208)` actually landed at CSS `(421,1271)`.
Calibrate per session with a probe before tapping:

```python
js("window.__mm = []; document.addEventListener('mousemove', e => window.__mm.push(e.clientX), true)")
cdp("Input.dispatchMouseEvent", type="mouseMoved", x=400, y=400); wait(0.25)
F = float(js("window.__mm[-1]/400"))          # 1.0525
# then send input at (css_x / F, css_y / F)
```

Useful facts when calibrating:
- `Page.getLayoutMetrics`: `cssLayoutViewport` = 800×1280, `layoutViewport` = 1200×1920.
- `capture_screenshot(path)` saves a 1200×1920 PNG at DPR 1.5.
- The harness marks tabs with a 🐴 prefix. Stop the daemon with
  `browser-harness --reload` (it auto-starts on the next call).

---

## 7. Known upstream bugs (found while doing this — report, don't fix locally)

1. **`src/Menu.js` mixed CJS/ESM** at v6 (commit `8344138`) — `npm start` from source
   cannot work on any Node version. Source-level dev requires a fix (convert the two
   `export`s back to `module.exports`, or finish the ESM migration).
2. **`GET /machine/restart` has no try/catch** (`src/Machine.js:848`) — when
   `service_restart.sh` fails, the unhandled rejection kills the API process. Production
   is saved by systemd; locally our stub + watchdog mask it.
3. **UI `global.restart()` pushes `/start`** (`mc-ui/src/main.js:261`) — there is no
   `/start` route (only `/`), so the restart button strands the app.
4. **`protocol.js:135` calls `global.$t`** in the alert fallback — undefined in this
   branch; any unmapped `alert_id` crashes the UI (`Uncaught TypeError`).
5. **`bin/` files missing exec bit in git** (e.g. `serialcom`, `touch_check_alive.sh`,
   `wifi_onoff.sh` are `100644`) — dev clones crash; the Pi's updater chmods them.

---

## 8. Cheatsheet / troubleshooting

```fish
# restart API after editing the mock/config
#   (in tmux pane %18): Ctrl+C then
mise run dev

# rebuild bundle only
cd ~/repos/mc-api && mise run build

# API up? menu responding?
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3000/menu/menu   # 200

# ports
ss -ltn | grep -E ':3000|:3001'

# who holds the API port / kill leftovers
ss -ltnp | grep :3000
kill -9 <pid>          # watchdog restarts it; or Ctrl+C the mise task

# UI reload without mouse: browser harness
browser-harness <<'PY'
js("location.href='http://localhost:3001/#/home'; location.reload()")
PY

# tmux: restart both dev servers (from a pane outside window 3)
for p in (tmux list-panes -t mc:3 -F '#{pane_id}')
    tmux send-keys -t $p C-c
    sleep 0.3
    tmux send-keys -t $p 'mise run dev' Enter
end
```

- Interface mapping: `%18` = mc-api pane, `%19` = mc-ui pane (tmux session `mc`, window 3).
- API logs: console (tmux pane) + `api/logs/mcapi-current.log`.
- Changing the simulated cook timing: edit `at(...)` in `~/repos/onboarding/mc-api.toml`, restart.
- Adding real recipes: drop files into `api/menu/` + `api/menu/machine/` (persist across
  builds; fixtures are only created if missing), or use the UI's menu upload.
- If the bridge is down (`curl http://127.0.0.1:19333/json/version` fails):
  `~/.config/browser-harness/wsl-bridge/start_bridge.sh`.

---

## 9. What we verified (2026-09-22)

- `mise run dev` builds, listens on :3000, survives kills/crashes, exits cleanly on Ctrl+C.
- 42 s+ uptime with no EACCES crash (touch-check fixed by `chmod +x`).
- UI restart flow: `GET /machine/restart` kills the API (pid changed `244507 → 244674`)
  and the watchdog brought it back; UI reconnects automatically.
- `ws://localhost:3000/machine/status`: `server_state=IDLE`, `system_state=IDLE`,
  `online=1`, `alert_id=-1`, 1 Hz updates.
- `/menu/menu` → 200 with fixture; menu → recipe → select → prepare → cooking
  (step 1/3 → 2/3, live countdown ring, next action) → back home, all under the
  `mc` device simulator (800×1280, DPR 1.5, touch).
- No protocol parse errors; both repos `git status` clean.

Screenshots from the session: `/tmp/mcdev-*.png` (e.g. `mcdev-cooking.png`).
