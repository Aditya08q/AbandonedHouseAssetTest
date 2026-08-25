# Abandoned House — Mobile Multiplayer Prop Hunt

## Project purpose

**Abandoned House** is a landscape mobile, third-person, funny-horror multiplayer game. It is a prop-hunt game set inside an abandoned house:

- One player is the **Seeker**.
- Every other player is a **Hider**.
- Hiders can possess selected furniture and objects, move them to a convincing hiding place, and swap to another eligible object.
- The Seeker explores the house, inspects suspicious players or props, and tries to eliminate all Hiders before the round timer ends.

The project uses Godot 4, KayKit characters/animations, the Abandoned House environment pack, and Kenney UI/mobile-control assets. The target platform is Android in landscape mode. Mac is used only as a development and local-host machine.

---

## Project architecture

The project is deliberately structured so that game logic, scenes, imported assets, and
Android exports remain separate. Only code, scene definitions, project configuration, and
documentation are stored in GitHub.

```text
AbandonedHouseAssetTest/
│
├── project.godot                 # Godot project settings: Android, rendering, input, permissions
├── export_presets.cfg            # Android export configuration; generated APK is not committed
├── README.md                     # Full game design, development flow, test status, architecture
├── CREDITS.md                    # Asset sources, links, licenses, and setup instructions
├── .gitignore                    # Keeps assets, cache, imports, and builds out of GitHub
│
├── scenes/
│   ├── main.tscn                 # Main playable scene: world UI, lobby, mobile HUD, round UI
│   └── explorer.tscn             # Reusable third-person player character scene
│
├── scripts/
│   ├── main.gd                   # Main game controller: map setup, UI, rounds, LAN host/client,
│   │                              # player synchronization, props, inspection, mobile controls
│   ├── explorer.gd               # Player controller: movement, camera, collision, animation,
│   │                              # possession/release, remote-player state interpolation
│   ├── round_rules.gd            # Pure game rules: 2–6 player limit, lobby lists, random roles,
│   │                              # character selection by player slot
│   ├── prop_hunt.gd              # Possessable-prop data/behaviour support
│   └── phone_player.gd           # Earlier/local test controller retained for development support
│
├── assets/                       # Local only — ignored by GitHub
│   ├── abandoned_house/          # Abandoned House environment, models, textures, furniture
│   ├── kaykit_reference/         # KayKit player models and compatible animation libraries
│   ├── audio/                    # Background music and future sound effects
│   └── ui/                       # Kenney mobile control and fantasy UI assets
│
├── .godot/                       # Local Godot editor/import cache — ignored
└── build/                        # Local exported Android APKs — ignored
```

### Scene and runtime hierarchy

```text
main.tscn / main.gd
│
├── World
│   ├── Abandoned House GLB environment
│   ├── generated collision bodies
│   ├── lighting, fog, safety floor, and possessable-prop markers
│   └── runtime player avatars
│       ├── local avatar (controlled only by this device)
│       └── remote avatars (display synchronized state only)
│
├── Interface
│   ├── LAN panel: player name, Host Room, Join Nearby, connection messages
│   ├── Host Lobby: accepted/pending players, accept/reject/remove, Start Game
│   ├── round HUD: role, timer, attempts, round banners, end screen
│   ├── Hider Guide and Game Info pop-ups
│   └── Android mobile HUD: joystick, camera drag, action buttons, menu
│
└── Network services
    ├── ENet game connection on UDP port 7000
    └── local nearby-room discovery on UDP port 7001
```

### Player architecture

Every player uses the reusable `explorer.tscn` scene with `explorer.gd`.

- **Local player:** reads keyboard or mobile touch input, moves with physics, runs its camera,
  plays local animation, and sends its state to the Host.
- **Remote player:** never reads local input. It receives position, facing, animation, role, and
  possession state from the network and displays a smooth interpolated replica.
- **Character selection:** `round_rules.gd` defines six compatible KayKit character models:
  Knight, Mage, Rogue, Rogue Hooded, Ranger, and Barbarian.
- **Camera:** only the local player’s third-person camera is active on that device.

This ownership separation is why a Mac and a phone can move independently while each screen
still shows the other player moving.

### Multiplayer authority architecture

The game uses a **Host-authoritative local LAN model**:

```text
Android / Mac Client
  └── sends own input-derived movement, possession requests, and inspect request
          ↓
Host
  ├── approves/rejects players
  ├── stores accepted players and names
  ├── assigns one random Seeker and all remaining Hiders
  ├── runs hiding countdown, seeking timer, attempt counter, capture results, and round end
  ├── validates client actions
  └── broadcasts the approved game state to every connected device
          ↓
All clients
  └── render the synchronized state; show private Hider-only possession guidance locally
```

The Host is the only device allowed to start a round, accept/reject/remove players, assign
roles, advance the timer, decide captures, and publish the final result. This prevents each
phone from inventing a different version of the same round.

### Data and build flow

1. Third-party assets are downloaded locally into `assets/` using the paths recorded in
   `CREDITS.md`.
2. Godot imports models, textures, audio, and UI into `.godot/`; those cache files are
   regenerated automatically and are not source files.
3. `main.tscn`, `explorer.tscn`, and the GDScript files reference the documented asset folders.
4. Godot exports an Android test APK to `build/abandoned-house-mobile.apk`.
5. The APK is installed on a phone for testing; it is a generated binary and is not committed.

To clone this project on another computer, clone the code repository first, then download the
asset packs listed in `CREDITS.md` and place them in the documented local folders before opening
the project in Godot.

---

## Game design

### Camera and controls

- Third-person perspective for every player.
- Camera collision prevents it from passing through house walls where possible; it moves closer to the player when an obstacle blocks the view.
- Android landscape touch controls are built directly into the game:
  - left joystick: movement;
  - right-side camera drag: look around;
  - jump;
  - possess/release;
  - inspect for Seeker;
  - raise/lower while controlling an object;
  - Hider Guide and Menu buttons.
- Keyboard controls remain available on Mac for development/testing.

### Roles

| Role | Goal | Abilities | Information |
|---|---|---|---|
| Seeker | Find and eliminate every Hider before time ends. | Move, look, jump, inspect. | Does **not** see green possession arrows. |
| Hider | Stay undiscovered until time ends. | Move, look, jump, possess/release eligible props, move possessed prop, swap to another eligible prop. | Sees green arrows above eligible props. |

Roles are randomly assigned at the beginning of each round. Exactly one player becomes Seeker; all other accepted players become Hiders. A player cannot switch their role during an actual multiplayer round.

### Player count

- Minimum players to start: **2**.
- Maximum players: **6**.
- One device creates the room as **Host**.
- Up to five other devices can join.
- The Host approves or rejects each join request and can remove an accepted player before the round starts.

For two players, the random role assignment is simple: one becomes Seeker and the other becomes Hider.

---

## Correct multiplayer round flow

### 1. Host creates a room

1. Players connect to the same Wi-Fi network or the same phone hotspot.
2. One player opens the game and taps **Host Room**.
3. The Host game opens the Host Lobby and advertises the room on the local network.
4. The round timer is **not running** in the lobby.

### 2. Other players join

1. Each other player enters their name and taps **Join Nearby**.
2. The joining device discovers the local room and sends a join request.
3. Its screen shows that it is waiting for Host approval.
4. The Host sees the request in Host Lobby.
5. The Host taps the white **ACCEPT PLAYER** button to admit that player, or rejects/removes them.
6. The lobby updates its accepted-player count, from `2/6` through `6/6`.

Only accepted players are part of the round. A sixth total player is the maximum; further requests are refused as a full room.

### 3. Host starts the round

1. When at least two players are accepted, the Host taps **Start Game**.
2. The Host randomly selects exactly one Seeker.
3. The host sends each player only their own assigned role.
4. Every accepted player receives an independent avatar, camera and controls.
5. Players appear inside the playable house area near the entrance/start area.

### 4. Hiding phase

1. The Hiding phase begins with a clear countdown.
2. Hiders can move and find/possess green-arrow props.
3. The Seeker is held in place for the hiding countdown.
4. Green arrows are intended to be visible only to Hiders in real multiplayer. They are not information for the Seeker.
5. No player can change their random role.

### 5. Seeking phase

1. The game displays **SEEKER RELEASED**.
2. The Seeker can move through the house and inspect nearby suspicious targets.
3. The Seeker begins with a set number of inspection attempts.
4. A wrong inspection uses one attempt.
5. A successful capture eliminates the found Hider and grants `+2` attempts.
6. Hiders continue hiding or relocating through allowed possessable objects.

### 6. Round end

- **Seeker win:** every Hider is eliminated.
- **Hider win:** the timer reaches zero while one or more Hiders remain.
- **Early end:** if a required player disconnects during a locked round, the round ends safely rather than leaving a broken state.

The end screen announces the winner. The Host can start the next round, which resets attempts, roles, and round state.

---

## Multiplayer ownership rule

Every physical device controls only its own player.

Example with one Mac host and one Android phone:

| Device | Local player it controls | Remote player it displays |
|---|---|---|
| Mac host | Player 1 | Phone player |
| Android phone | Phone player | Player 1 |

It is normal for the Mac to show the phone character moving, and normal for the phone to show the Mac character moving. This is the remote synchronized replica. It is not shared control: Mac and phone movements must be independent.

Current real-device LAN test result: **Mac Player 1 and Android Player 2 can move independently and see each other move.**

---

## Current implemented features

### Environment and gameplay

- Playable abandoned-house test environment.
- Third-person explorer character with KayKit visual character and walk/idle animation.
- Night/horror lighting and soft ambient music.
- House collision and third-person camera obstacle handling.
- Eligible prop markers/green arrows for Hider discovery.
- Possession, release, object movement, vertical raise/lower support, and object reset logic in the prototype.
- Seeker inspection and attempt counter prototype.
- Hiding countdown, Seeker release, round timer, round end screen, and next-round flow.

### Lobby and LAN multiplayer

- Real local Wi-Fi/hotspot room hosting.
- Nearby-room discovery.
- Host / Join interface.
- Name entry, join request, Host approval/rejection/removal.
- Minimum 2 and maximum 6 players enforced in game rules and host setup.
- Random one-Seeker role assignment for each started round.
- Separate avatars for accepted players, using different KayKit character models.
- Sync foundation for player movement, animation state, roles, timer, attempts, captures, props, and round results.
- Host authoritative lobby/round flow.

### Mobile support

- Landscape Android layout.
- Built-in touch joystick and touch buttons.
- Hider/Seeker-specific action UI.
- Pop-up instruction panels designed to avoid permanently covering the play screen.
- Debug Android APK export and USB installation workflow.

---

## Known testing status

### Verified

- Project launches on Mac.
- Latest debug APK installs and launches on Android.
- Host room and phone join/approval flow has been tested.
- Two real devices (Mac + Android phone) display two separate characters.
- Mac Player 1 and Android Player 2 have independent movement.
- Each device receives the other player’s movement updates.
- Two-player rounds can randomly assign one Seeker and one Hider.

### Implemented but still needs real-device confirmation

- Three to six real simultaneous players.
- Role assignment with more than two players.
- Several players possessing/moving different props at once.
- Multiple captures and attempt updates across all devices.
- Player removal and disconnect behaviour while a live round is running.
- Android performance with a full six-player room.

---

## Future testing and hardening checklist

This is the required remaining work before calling the Android multiplayer game finished.

### Multiplayer testing

- [ ] Test 3–6 real devices and fix any synchronization issue found.
- [ ] Test each player joining, Host approval, Host rejection, and Host removal.
- [ ] Test random role assignment for 2, 3, 4, 5, and 6 accepted players.
- [ ] Test Host starting the round only after at least two players are accepted.
- [ ] Test player disconnection in lobby, hiding phase, and seeking phase.
- [ ] Verify all players see movement and walking/idle animation smoothly.

### Possession and props

- [ ] Make possession fully reliable for every intended prop in real LAN multiplayer.
- [ ] Add the full curated set of movable/possessable house props.
- [ ] Place props naturally so they do not intersect walls, floors, or furniture.
- [ ] Test prop movement, raise/lower, release, return-to-original-place, and player exit positioning.
- [ ] Ensure green arrows are private to Hiders only in real multiplayer.
- [ ] Prevent props from blocking the player, getting stuck in walls, or trapping a released player.

### Seeker gameplay and feedback

- [ ] Add a clear inspect target highlight.
- [ ] Add success/failure capture feedback.
- [ ] Add an eliminated-player label or effect.
- [ ] Verify attempts reduce on failed inspection and increase by `+2` for each elimination.
- [ ] Improve Seeker inspection range and target selection so it feels fair.

### Audio and visual polish

- [ ] Add footsteps.
- [ ] Add possess and release sounds.
- [ ] Add inspect, correct capture, wrong capture, countdown, and round-result sounds.
- [ ] Tune background music volume so it remains smooth and horror-like without hiding gameplay feedback.
- [ ] Improve lighting, fog, and room readability without making Android performance too heavy.

### Android optimization and final release

- [ ] Reduce expensive shadows, lights, and unnecessary props.
- [ ] Test Android frame rate, heat, battery drain, memory use, and loading time.
- [ ] Make every panel legible on small landscape phone screens.
- [ ] Improve lobby, role reveal, reconnect/disconnect messages, menu, and settings.
- [ ] Create a release signing key and export a signed release APK.
- [ ] Install the release APK and complete a final phone test.

### Optional future expansion

- [ ] Add more house rooms/maps once the first house is stable.
- [ ] Add additional prop categories and cosmetics.
- [ ] Add online multiplayer outside a shared Wi-Fi/hotspot. This requires internet relay/server or matchmaking work; the current project is local LAN only.

---

## Recommended next development milestone

**Finish the complete prop set and make possession/release/movement reliable for all of those props in real multiplayer.**

This is the most important next milestone because the game’s main fun comes from Hiders becoming believable moving house objects. Once that is stable, complete the 3–6 player device test, then focus on audio, Android performance, and release packaging.

---

## Development rules

- Keep the house test project separate from unrelated game experiments.
- Do not mix unrelated art styles or random asset packs into the playable map.
- Test new multiplayer features first with Mac host + Android phone before expanding scope.
- Do not treat a feature as complete until it is tested on actual devices, not only local simulated players.
- Preserve the latest working APK before risky multiplayer or prop-system changes.
