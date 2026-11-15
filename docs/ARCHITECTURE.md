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
The context publishes `actor_added`, `excavation_marks_changed`, and `simulation_ticked`;
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

## Room commands and extension boundary

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
