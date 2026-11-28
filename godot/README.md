# Godot lab veneer

Thin **physical-world UI** for `sep_26_concrete` ([ADR 0001](../docs/decisions/0001-lab-toolchain.md) / [0004](../docs/decisions/0004-world-state-supervisor.md) / [0009](../docs/decisions/0009-godot-scenario-worlds.md)). **Not** ground truth — talks only to OTP HTTP at `http://127.0.0.1:4000`.

**Main scene:** `scenes/world.tscn` — one 3D room, desk, laptop (`node-1`), **identity desk** (sign: Collect identities here), listen-server session. Nested console `scenes/main.tscn` is the node-1 screen (also `--console-only`). Each generated **persona is a separate coloured dummy** (capsule torso, sphere head, hinged cylinder limbs) in the room; first-person hides that body's head. Switching control does not retarget the OTP console (that stays with whoever is seated). HUD says **at node-1** only for the seated body.

The CONCRETE mark is `images/concrete_icon_200.png`, copied from the March prototype’s Godot scene. It is the project icon, and it is drawn on the Personas landing, the room HUD, and the node console.

The seated console is drawn into its own texture, then shown in the laptop panel. That texture is the panel size multiplied by the display scale (screen scale, window content scale, or the window's pixel size divided by the 1280×720 project size — whichever is larger). The controls are laid out at the panel size and rasterised into the larger texture, so letters stay sharp instead of being a small picture enlarged to fit. GraphEdit uses a font size of 16 and zoom `1`. Its built-in wire is at least four pixels wide and paints that padding in the rim colour, so the connection shader keeps a one-pixel core and fades the rest. Every workspace places its stored block positions at `1.5×`, a gap between the original layout and the earlier `2×` spread. Keystrokes are forwarded into the console texture, so fields such as the W0 PIN still accept typing after the window is resized or taken fullscreen. A fractional desktop scale cannot land on a whole pixel; the texture still matches the window's framebuffer.

Helen → Alice CoT: [docs/11](../docs/11-helen-alice-cot-beats.md), coded per [docs/12](../docs/12-helen-alice-build.md). Sessions are **not** signed HTTP (ADR 0008 stage 5 later); OTP still trusts `principal_id`.

## Prerequisites

```bash
./scripts/session-up.sh  # wipe, IPFS + IOTA, identity publish, OTP :4000
# lower level, if a session is already up:
./scripts/lab-up.sh
./scripts/node-up.sh     # empty CoT, no auto-King
```

Requires **Godot 4.7** on the host (`godot` or `godot4` on `PATH`, or `GODOT_BIN`). A fresh checkout has no `godot/.godot/` class cache; `./scripts/godot-up.sh` and `./scripts/godot-scenario.sh` import the project once before launching. A fresh `session-up` is a blank Circle of Trust. Replay of genesis fails unless **Zeroise**.

## Godot AI (editor connection)

[Godot AI](https://github.com/hi-godot/godot-ai) 4.4.2 is installed at `addons/godot_ai` and enabled in `project.godot`. It is free (MIT). It lets a Cursor agent work in the **open Godot editor**: read the scene, edit it with undo, run the game, send keys and clicks, read the error log, and screenshot the running game. That is how console, HUD, and fullscreen changes get checked without guessing from a log file.

Use it when the Godot **editor** is open on this project. A game started only by `./scripts/godot-up.sh` is not connected, and a screenshot of the running game only works when the plugin started that play session.

Another checkout gets the plugin, the project rule `.cursor/rules/godot-ai.mdc`, and the shared client entry `.cursor/mcp.json`. That entry runs `uvx` with `godot-ai==4.4.2`, `attach` on ports 8000 and 9500, and `--disable-telemetry`. Telemetry is otherwise on.

On a machine that will drive it:

1. Install [uv](https://docs.astral.sh/uv/) so `uvx` is on the path Cursor uses. If Cursor cannot see it, point the `command` in `.cursor/mcp.json` at that `uvx`.
2. Reload Cursor once so it reads the project entry. A new chat then sees the tools.
3. Leave the Godot editor open.

## Session (listen-server from the start)

Windowed `godot-up` is the **host** (ENet port **24567**). A second process **joins** and appears as another coloured capsule. Host simulates the room; each process still calls OTP HTTP.

```bash
./scripts/godot-up.sh                          # host, windowed
./scripts/godot-join.sh                        # second body (windowed)
# or: godot --path godot --headless -- --join 127.0.0.1:24567
```

WASD + mouse look. Start on the **Personas** landing (type Helen / Alice / any name, Generate, then enter). Each name **spawns a body** (capsule dummy, distinct colour). HUD switcher changes who you walk; Helen stays at the laptop if she was seated. **E** picks up paper or sits. **G** gives a nearby avatar the giver’s **public-key slip** (not whichever paper was picked up last). **Esc** stands up only if **you** are the seater (OTP **session remains** until **Exit session**). **Exit to menu** on a workspace or on Discovery returns to the console menu (empty-CoT **Overview**, or **Home / launcher** after login) and leaves the session logged in. One seater.

## Helen → Alice play (scenes 1–7)

1. Power/sit. Empty-CoT console opens on **Overview** (not linked; wait to connect later, or start genesis). Colour key is on that tab.
2. Open **W0 - Genesis**. **Populate** copies username / public / private from the persona or inventory (fields stay empty until you press it). Type a **5-digit numeric PIN**. One **Genesis** block pass-throughs those fields into D1–D5 / Vault and **Go / Commit** writes them (button and data blocks show a working cue). **Exit to menu** on that tab returns to Overview without writing. Replay fails unless **Zeroise**.

Live HTTP check (no Godot): `./scripts/w0-smoke.sh` (W0) and `./scripts/beat-smoke.sh` (scenes 1–7 through Alice W2). Lab-up + node-up. IOTA down is the 502 PTB.
3. Launcher (the menu): **Exit to menu** from W1, W2, or Discovery comes back here and stays logged in. Helen stays seated. Switch to **Alice** (new body near the identity desk). Pick up her **public-key copy**, walk to Helen, **G** to put it in Helen’s inventory. Switch back to Helen → **W1** → **Populate** (Alice’s name and public key — never Helen’s). Generated PIN is shown once — tell Alice. Helen can run W1 because she holds **any**; Alice cannot (no covering cap). GraphEdit still cannot mint verbs (save layout is denied server-side).
4. **Exit session** (not only Esc).
5. **Login** as Alice: username + PIN + paper **private** key. Starts Alice’s vault. Wrong PIN / not on D1 / no key fail closed.
6. **Discovery**: force graph from D5[Alice]; it settles still. Click an info node to read it in the side panel, then close it. Data markers only (no D4 bytes).
7. Run **W2**: text; one D3 node feeds the read/write picker (you start ticked for both); read list and write list wire into Go / Commit; Wendy-link DID (e.g. G). Auto-links her D5. Discovery shows the new info node.

**Power off** on the console makes OTP product routes **503**. **Zeroise** re-opens King-making (full chain/D2 wipe is stubbed).

Vaults are Elixir processes (comment: lab stand-in — rewrite as seL4 later). No NIFs. Paper/genesis fields may show keys; Godot does not keep seeds in `.tscn`.

## Host scenarios

A **host scenario** is a named JSON file in `godot/scenarios/`. The host process generates the personas, teleports them, and presses the same console controls (Populate, Go / Commit, Exit session, Login). It is one operator at one node. It is not a playbook bot, and it is not an ADR 0009 scenario world (blank vs snapshot save). OTP must already be up, and genesis must still be open (`./scripts/session-up.sh` on a clean lab). The listen port must be free.

```bash
./scripts/session-up.sh
./scripts/godot-scenario.sh helen-alice
# watch the window instead of quitting when the JSON result prints:
GODOT_SCENARIO_WINDOW=1 ./scripts/godot-scenario.sh helen-alice
```

A windowed run starts in its own session and stays up if the launching shell is aborted. Godot's output, the launch environment, and any caught signal are written to `lab/run/scenario.log` (gitignored). The pid is `lab/run/scenario.pid`. A successful run also writes the PINs to `lab/run/scenario-pins.txt`, which `session-down` leaves in place.

`helen-alice` is Helen's key paper, W0 (PIN `13579`), Alice's public slip handed to the seated Helen, W1, Exit session, Alice's key paper, login with the PIN W1 showed. Stdout is one JSON object. Add another file under `godot/scenarios/` and pass its name. Chain writes still wait on IOTA; the script polls the console instead of sleeping a fixed gap. One clean run on 2026-11-22, after `session-up` had already finished, took 53 seconds and printed `"ok": true` with Alice logged in.

## Headless peer playbook (option C)

Phase 1 `first-login.json` (paper-as-King + plaque) is leftover. Pickup no longer keys anyone; `create_plaque` / `eve_deny` fail-fast (`superseded_step`). `./scripts/godot-playbook.sh` is still a **known red path**. The Helen→Alice beat above is the host scenario, not this peer. Curl mutate is still not the user.

```bash
./scripts/godot-up.sh
./scripts/godot-playbook.sh
```

## 2D console only (debug)

```bash
godot --path godot -- --console-only
# or open scenes/main.tscn in the editor
```
