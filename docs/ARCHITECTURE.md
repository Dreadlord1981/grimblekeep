# Code organization and extension contracts

The scene in `scenes/` uses `app/dungeon_app.gd` as a composition root. It loads
module resources, creates a session, starts feature nodes and attaches independent
presentation/input/UI nodes. Keep orchestration here; gameplay rules live elsewhere.

| Area | Owns | May depend on |
| --- | --- | --- |
| `core/` | Grid, runtime state, definition schemas, registry and feature contract | Godot data types/resources; no presentation or input |
| `content/` | Manifests, definitions, starting scenario and optional mechanics | Core contracts |
| `presentation/` | Terrain, props, creatures, lighting, animation | Read session state and definitions |
| `interaction/` | Perspective camera, ray targeting, keeper hand and input | Core; sends explicit selection/commands |
| `ui/` | Information panels and diagnostics | Core and documented controller API |
| `tests/` | Rule scenarios and isolated extension examples | Contracts under test |
| `tools/` | Repeatable local development commands | Installed Godot executable |

## Add a creature or room

Create a `CreatureDefinition` or `RoomDefinition` resource with a unique namespaced
ID such as `marsh.mossling` or `marsh.nest`. Add it to a `ContentModule` resource's
`definitions` array, then add the manifest path to `grimblekeep/content_modules` in
`project.godot`. Registration rejects duplicates across creatures/rooms, invalid
values and unsupported types, and commits a manifest only after all entries pass.

Definitions are treated as read-only at runtime; state belongs to individual actors
or the dungeon. Register during startup, before creating views. Hot-loading,
untrusted external mods and arbitrary schema migration are not implemented.

Creatures may supply an optional `view_scene` (Node3D root). Otherwise they use the
foundation placeholder renderer with definition color/scale. The view follows
`CreatureState.position`, `heading` and `phase`. Room definitions drive build
buttons, placement cost, sale ratio, capacity, paving and optional per-tile
`view_scene` (Node3D root). Set `buildable=false` for unreleased definitions such
as the provisional Lair. Registering a room does not implement its specialist
needs/production behavior; those can use a feature observing `context.rooms`.

## Add a mechanic

Extend `GameFeature` and include its script in a module's `feature_scripts` array.
`setup(context)` receives explicit session dependencies. `tick(delta)` is called at
the physics timestep, in manifest/script order. Feature nodes are owned and freed
by the app scene. Subscribe to context/grid signals for specific changes; do not
reach into UI or unrelated scene paths. Connect to external signals using the
Node receiver so Godot disconnects them when the feature is freed.

The original `wander_feature.gd` remains a small test/example feature but is no
longer in the foundation manifest. `worker_feature.gd` now owns worker movement;
do not enable both for the same actors.
The context publishes `actor_added`, `actor_removed`, `excavation_marks_changed`, and `simulation_ticked`;
the grid publishes `tile_changed`. Define new events/contracts deliberately when
new systems require them rather than building a generic global event bus.

Excavation designations live in `GameContext.excavation_marks`; use
`mark_excavation()` and `clear_excavation_marks()` to publish updates. There is no
separate generic selection or Hand/Dig mode. The keeper toggles clicked/dragged
rectangles by default, preserving tiles outside the rectangle; Shift/Ctrl request
explicit add/remove operations. `DungeonGrid.surface_height()` is the shared
terrain contract for geometry and nearest-hit picking. Views do not decide which
world tiles an input affects.

The context enforces `grid.can_excavate` (stone, gold, gems) even for callers outside
input/UI. Floor and landmarks cannot be marked. Marks are automatically removed
when terrain becomes non-excavatable, ready for future worker/job consumers.
They persist independently of hover/camera movement and are executed by workers.
Room construction uses separate placement commands rather than weakening default
excavation eligibility. Gem terrain is solid mineral rock, not a new currency;
it produces gold slowly and remains in place.

The controller publishes `preview_changed` and `get_preview_changes()` with exact
`add`, `remove` and invalid-hover `blocked` cells. UI counts and the separate
`KeeperSelectionOverlay` use this same delta. Green plus and red X geometry makes
mixed toggle operations readable without relying only on color. Modifier changes
recompute preview immediately, including a stationary pointer.
Persistent mark visuals use an additive amber box-shell shader covering tops and
sides; pulsing runs on the GPU. Temporary plus/X previews sit above that glow.

## Worker jobs and physical economy

`CreatureDefinition.capabilities`, `work_rate`, `move_speed` and `carry_capacity`
control which creatures can participate, without species switches in job code.
`CreatureState` holds action/job/target/progress and carried gold. This state feeds
animation and the HUD. Experience/levels are planned separately, not implemented.

`WorkerFeature` composes three focused classes in `content/systems/`:

- `WorkerJob` stores a target, workplace, route and kind.
- `WorkerJobBoard` discovers reachable marked work and loose-gold/treasury jobs,
  then reserves targets and workplaces per actor. It does not move actors or mine.
- `WorkerBehavior` validates and executes its assignment, follows safe A* routes,
  works adjacent to solid terrain, carries gold and handles interruptions.

`GridPathfinder` uses authoritative walkability, not rendered meshes. It wraps
Godot's native `AStarGrid2D` on the dungeon's X/Z tile coordinates; the presentation
remains perspective 3D. Octile compute/estimate costs give straight steps cost 1
and diagonal steps sqrt(2). Diagonals require both cardinal flank cells to be open.
A weak single-grid cache uses `DungeonGrid.navigation_revision` to rebuild after
terrain changes without retaining discarded sessions. This is a main-thread API.

`can_step()` shares the diagonal-edge rule with worker route validation, including
flank-only changes mid-segment. Replanning recenters through the worker's current
walkable cell without teleporting it. Job candidates compare `path_cost()`, not
waypoint count, and movement consumes actual world distance so diagonals are not
faster. Jump-point skipping, path smoothing and crowd avoidance are not enabled.
See the [Godot AStarGrid2D reference](https://docs.godotengine.org/en/stable/classes/class_astargrid2d.html).

Idle job
discovery polls at a bounded interval. Canceled/blocked/removed actors release
reservations. Buried marks become candidates as neighboring stone is excavated.

Mining targets use nested reservations: `target -> {actor_id: work_cell}`. Gold
and gem nodes support up to four reachable cardinal workplaces, one miner per face.
Stone targets and loose-gold pickup remain exclusive. Global workplace reservations
also prevent two different targets from claiming the same standing position.
Releasing one miner retains its neighbors' reservations. All miners debit the
same finite seam ledger; depletion changes the tile once and invalidates other
miners' jobs. Diagonal travel never permits diagonal mining through a corner.

`GoldEconomy` owns finite seam balances, loose piles, physical `stored_by_cell`
balances, spent gold and sale refunds. `stored_gold` is a derived sum, never a
second writable balance. Initially a finite gold tile contains 200 gold; workers
extract 20 per strike. Gem nodes yield 20 more slowly and stay in place, recording
generated supply explicitly. Neither mineral creates a separate inventory currency.

Gold conservation after each simulation tick is:
`unmined + carried + loose + stored + pending recovery + spent = initial finite supply + gem generation + sale refunds`.
`accounted_gold()` returns the left side minus refunds, preserving the common
comparison against initial finite supply plus gem generation. Starting room tiles
also have salvage value, so refunds are explicit sources, never assumed to have
come from prior mining. Repeated sales of the same tile cannot create refunds.
The ledger retains detached actors with cargo when no walkable drop location exists;
the worker feature adopts this pending state on reload and retries safe recovery.
Workers deposit only after physically reaching a Treasury tile with free space.
Finite storage prefers the least-filled reachable tile, then weighted route cost;
partial deposits retain the remaining cargo. If no free storage is reachable,
workers leave recoverable loose piles and avoid pickup/drop loops. Sale refunds
credit remaining storage directly or drop at the sold tile when full.
Mineral job discovery and active-strike validation both require reachable free
storage. When full/missing/unreachable, gold/gem extraction pauses without clearing
the marks, and spending or expansion resumes it through bounded polling. Stone
excavation remains available. Existing cargo/loose gold is preserved; in-transit
cargo is not forecast as a reservation against capacity.

## Room commands and extension boundary

Terrain distinguishes `is_solid()` from `can_excavate()`. `BEDROCK` appends numeric
ID6 after the original terrain IDs; it is raised/solid but never walkable or eligible
for excavation, mining or room construction. Its fixed `surface_height()`2.15 is
shared by rendering/picking. Views must not treat `not can_excavate()` as open floor;
mineral/rubble exposure uses authoritative walkability. Bedrock is batched separately
with a flat crown and layered bands. Room wall dressing only covers ordinary rock,
so indestructible terrain remains recognizable.

The starting scenario paints a one-cell bedrock border and a small interior shape.
`add_bedrock_border(grid, thickness)` and `paint_bedrock(grid, cells)` are trusted
level-authoring helpers; invalid pattern coordinates reject the whole pattern.
Core `set_tile()` remains a trusted terrain editing API, so level authors/tests can
replace bedrock deliberately. Player excavation has no such authority. Existing
mark/job/room/bed invalidation and revision-aware A* handle terrain changes without
new view-driven gameplay rules.

`DungeonRooms` owns `tiles: cell -> definition_id`. Any empty `FLOOR` is eligible
immediately after digging. Heart, portal and solid terrain remain protected.
There is no separate territory/claiming state or worker task.

`quote_build()` / `quote_remove()` return unique add/remove/blocked cells, cost,
refund, validity and reason. Mixed rectangles skip invalid cells. Build atomically
charges all eligible cells or fails for insufficient stored gold; it revalidates
on release. Building never removes existing rooms. Only the controller's explicit
Sell context calls `remove()`, with click/drag feedback before release. Esc/Done
returns to excavation while preserving excavation marks. Preview refreshes when
terrain, rooms or the economy change under a stationary pointer.

`RoomState` groups four-connected tiles of the same definition; diagonals do not
merge. Membership, generic capacity and gold capacity rebuild after each room edit.
Group IDs use the definition and first cell and identify the current snapshot;
future long-lived reservations should refer to tiles, not retain a group object
across merge/split events. `rooms.changed` announces updated state.

`gold_storage_per_tile` supplies per-cell capacity through
`economy.configure_treasury()`. Each removed tile spills its exact local stock,
and capacity reductions spill overflow locally. Sale refunds use each room's
`sell_refund_ratio` (0.5 by default), rounded down separately for each tile.
Spending debits physical stock in deterministic row-major order. No wages or
save migration are implemented yet.

The starting Treasury is placed by trusted scenario `place_initial()`; ordinary
input uses priced `build()`. Generic paving/color and optional tile scenes belong
to `DungeonRoomView`. Gold props read each actual tile balance and the definition's
small/large chest thresholds. New room mechanics can observe this state through
feature modules. Independent tests build a new room and storage type, including
their toolbar entries, without adding ID switches to core or presentation.

## Residents, personal beds and rest ownership

`CreatureDefinition` supplies `bed_size`, `rest_room_tag`, normalized initial
energy, drain/recovery rates and sleep/wake thresholds. Only creatures with the
`rest` capability participate. `food_per_meal` and `wage_gold` are future species
requirements, not active consumers. Zero `portal_population_limit` disables
automatic arrivals; the first Grubbin definition currently limits arrivals to one.

`DungeonBeds` owns personal `BedState` objects by actor ID. It fits every cell of
the rectangular footprint inside the same connected room whose definition has
the required tag, excluding other personal footprints. It checks A* reachability,
compares weighted route costs and stores physical cells rather than transient room
group references. New reservations are pending: `BedState.established=false`.
They exclude rival footprints and gate arrivals but do not produce bed meshes.
The resident goes straight to the space, even while healthy, and performs a short
local `claiming_bed` action. `DungeonBeds.establish(actor)` validates the physical
owner, definition/footprint and proximity to the footprint center using shared
`CLAIM_DISTANCE`; remote commands fail. Only successful establishment publishes
the visible cot. Displacement, replacement or cancellation resets claim progress.
Harmless group merges retain personal ownership; selling or
blocking any footprint cell invalidates the whole bed. `beds.changed` updates
presentation/HUD. Removed actors release beds; periodic pruning also handles
direct actor-array edits and lost capabilities. Oversized footprints fail before
scanning cells.

`ResidentFeature` handles existing residents before scanning portals for a free,
reachable fitting bed. A bounded arrival scan creates at most one actor, reserves
pending space immediately and rolls back a failed spawn reservation. No arrival
creates gold. `ResidentBehavior` handles exploration, fatigue, travel, sleeping and
waking using strict A* edge validation and world-distance movement. Even-size beds
use their actual center, reached through validated floor before the final segment.
No bed/path means bounded retries and an explicit unmet-bed state, not wall crossing.

The manifest ticks resident needs **before** worker jobs. `rest_requested` gives
rest control of movement while traveling/sleeping or seeking a needed bed. A
multi-talent awake worker keeps its work behavior; rest only updates its needs.
When rest takes priority, `WorkerFeature` releases the current job reservation,
retains cargo and preserves resident action/target state. It resumes ordinary work
after waking. Future cooking/crafting/combat consumers must respect the same
ownership contract or deliberately extend it with reviewed arbitration.

`GameContext.despawn_creature()` releases beds and retains carried gold in the
economy until a worker can safely recover it. The worker feature clears this
pending entry after recovery, including feature reloads.

## Room art and desktop icon controls

Room definitions supply `floor_style`, `wall_style`, colors and optional per-tile
`view_scene` / per-wall `wall_scene`. Built-in style keys describe reusable visual
skins; there are no stable room-ID dispatch switches. Wall decoration appears
only on neighboring rock faces, never over exposed gold/gems or open passages.
Rooms, beds, terrain and excavation marks trigger deferred refreshes. Marked wall
faces leave dressing hidden so the authoritative top/side glow stays visible.

Personal cots and the Grubbin are original procedural low-poly assets derived
from the approved concept. Creature `view_scene` may implement `sync(actor)` and
optional `setup_context(context)` to read session state without deciding gameplay.
The Grubbin uses this to fit its sleep/wake pose to its own cot.

`RoomDefinition.icon` and `CreatureDefinition.portrait` supply textures for the
tabbed `DungeonHub` in the bottom HUD. It defaults to Creatures, with one portrait
per definition and an overlaid population count. Rooms shows one icon per buildable
type with connected-group count; tooltips distinguish tile totals, actual gold
capacity/stock and pending/established beds. `ui/dungeon_hub.gd` owns these cards
and publishes tab/tool intents; it does not run simulation. Switching to Creatures
cancels construction while preserving dig marks. No fixed right sidebar or verbose
footer remains. Individual energy/work/bed cards and controls live in the hidden
F3 debug window; concise construction quotes follow the cursor. Original SVG assets
in `assets/ui` supply replaceable icons. A
right-click during construction cancels pending drag before GUI consumption and
returns to excavation; default RMB camera orbit remains outside construction.

The dungeon view batches dirty terrain updates per frame and preserves unrelated
landmarks/heartbeat when workers clear stone. Gold piles/treasury presentation
refreshes from the ledger; it never creates resources. Presentation and HUD poll
small changing displays, not expensive actor logic every frame.

The module list is an explicit trusted composition order, not a dependency resolver.
Initial actor spawns and terrain belong to the replaceable foundation scenario.
Adding a new species does not imply automatic portal recruitment: attraction arrives
in Milestone 3. Core contracts can evolve when required, with regression coverage.

## Review expectations

Check clear ownership, stable IDs, validation, lifecycle cleanup, state/view
separation and concise functions. `tests/run_tests.gd` registers a test-only
creature, room and mechanic without modifying core dispatch. It also exercises
registration rollback, unknown references, coordinates and wandering safety.

Art baseline: 2 world units per tile; workers approximately 1–1.5 units tall;
chunky low-poly procedural meshes with a limited earthy palette. No textures or
external asset licenses are required for these original code-generated placeholders.
Target 60 FPS at 1280x800 with the small foundation map on the development machine;
record observed performance separately, not as a guarantee for larger dungeons.
