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
`CreatureState.position`, `heading` and `phase`. Room definitions establish an
extension contract now; room building, capacity and room view instantiation are
Milestone 2 work, not functional merely because a definition can be registered.

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
They persist independently of hover/camera movement; workers and saving are later
milestones. Room construction will have separate placement state and rules rather
than weakening default excavation eligibility. Gem terrain is solid mineral rock,
not a new inventory currency; no gem production system is implemented.

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
- `WorkerBehavior` validates and executes its assignment, follows cardinal routes,
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

`GoldEconomy` owns finite seam balances, loose piles, treasury cells and stored
gold. Initially a finite gold tile contains 200 gold; workers extract 20 per strike.
Gem nodes yield 20 more slowly and stay in place, recording generated supply
explicitly. Neither mineral creates a separate inventory currency. No room storage
capacity, spending, wages or save migration exists yet.

Gold conservation after each simulation tick is:
`unmined + carried + loose + stored + pending recovery = initial finite supply + gem generation`.
The ledger retains detached actors with cargo when no walkable drop location exists;
the worker feature adopts this pending state on reload and retries safe recovery.
Stored gold increases only when cargo physically reaches a valid treasury tile.
If no treasury is reachable, workers leave recoverable loose piles and avoid
endless pickup/drop loops. The starting treasury is scenario data; room-building
will later supply the same storage-cell contract.

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
