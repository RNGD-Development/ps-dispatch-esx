# Changes

This file records modifications made to ps-dispatch in this fork, as required
by section 5(a) of the GNU General Public License v3.0, under which both the
original work and this derivative are distributed. The original authors are
Project Sloth & OK1ez — see [`CREDITS.md`](CREDITS.md).

---

## 2026-09-05 — ESX Legacy support (RNGD-Development)

Modified from upstream ps-dispatch v3.0.1.

This fork adds **ESX Legacy** support to ps-dispatch as an additive bridge
layer, alongside — not in place of — the existing QBCore/QBX support. The
active framework is detected automatically at runtime from the state of
`qbx_core`, `qb-core` and `es_extended`; there is no configuration switch. On a
QBCore or QBX server every bridge call is a pass-through to the same
`QBCore.Functions` this resource always used, so behaviour there is unchanged.

The bridge lives in new files of its own, and the edits to upstream's files are
deliberately confined to swapping an accessor or adding an event listener
beside an existing one, to keep the conflict surface small when pulling future
upstream updates.

No new third-party dependency is introduced. ESX and oxmysql are reached
through their exports rather than through `fxmanifest.lua` `@`-imports,
specifically so that this resource still loads on QBCore servers where those
resources are not installed.

### Files added

| File | Description |
| --- | --- |
| `bridge/shared.lua` | Runtime framework detection (`Framework.Name/IsESX/IsQB`) and the ESX job-name → dispatch job-type mapping. |
| `bridge/client.lua` | Client-side framework API: core object, normalised player data, gender, handcuff state, duty state, item check, login state. |
| `bridge/server.lua` | Server-side framework API: connected players and single-player lookup in the QBCore object shape, ESX `users`-table name lookup with caching, and the duty/callsign hooks. |
| `CREDITS.md` | Attribution for the original authors and for the one borrowed idea. |
| `CHANGES.md` | This file. |

### Files changed

| File | Description |
| --- | --- |
| `fxmanifest.lua` | Added the three `bridge/` files to the shared/client/server script blocks (bridge first, so it exists before the rest loads) and a header comment crediting the bridge contribution. The `author` field is untouched. |
| `shared/config.lua` | Added `Config.ESXJobTypes` (job-name → `leo`/`ems` map), `Config.ESXDutyCheck` (duty hook, defaults to always on duty) and `Config.ESXGetCallsign` (callsign hook, defaults to nil), all documented in place. Added a temporary `renegaderacers` test job to `Config.Jobs` and to the job-type map. Corrected a comment that named QBCore as the only filtered framework. |
| `client/main.lua` | The unguarded `exports['qb-core']:GetCoreObject()` became `Bridge.GetCoreObject()`; `setupDispatch` builds `PlayerData` from `Bridge.GetPlayerData()`, refreshes ESX identity first, and returns early instead of erroring when no character is loaded; the post-restart zone rebuild uses `Bridge.IsLoggedIn()` instead of the QBCore-only `isLoggedIn` state bag; `esx:playerLoaded`, `esx:setJob` and `esx:onPlayerLogout` handlers added beside the QBCore ones. |
| `client/utils.lua` | `GetPlayerGender`, `GetIsHandcuffed`, `IsOnDuty` and the phone-item check now call the bridge; the phone-required notification became `lib.notify`. |
| `client/alerts.lua` | The 911/311 cooldown notification became `lib.notify`. |
| `client/plates.lua` | `esx:setJob` handler added beside the QBCore/QBX ones, so the Plates tab follows a job change on ESX too. |
| `client/incidents.lua` | `esx:playerLoaded` and `esx:setJob` handlers added beside the QBCore/QBX ones, so the "may declare" answer is refreshed on ESX too. |
| `server/main.lua` | The defensive `qb-core` pcall was removed; the four broadcast/filter paths use `Bridge.Available()` and `Bridge.GetPlayers()`, and `mayModifyCall` uses `Bridge.GetPlayer()`. Filtering semantics are unchanged. |
| `server/incidents.lua` | Same: the `qb-core` pcall removed, `MayDeclareIncident` and the declare handler use `Bridge.GetPlayer()`. Grade comparison is unchanged — the bridge normalises ESX's integer grade into the table shape this code already read. |

### Not changed

`LICENSE` is untouched, and the `author "Project Sloth & OK1ez"` field in
`fxmanifest.lua` is unchanged.
