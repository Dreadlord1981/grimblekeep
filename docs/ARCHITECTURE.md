# Code organization and extension contracts

The scene in `scenes/` uses `app/dungeon_app.gd` as a composition root. It loads
module resources, creates a session, starts feature nodes and attaches independent
presentation/input/UI nodes. Keep orchestration here; gameplay rules live elsewhere.

| Area | Owns | May depend on |
| --- | --- | --- |
| `core/` | Grid, runtime state, definition schemas, registry and feature contract | Godot data types/resources; no presentation or input |
| `persistence/` | Versioned JSON codecs, validation and safe disk replacement | Core contracts; no views/input or arbitrary resource loading |
| `content/` | Manifests, definitions, starting scenario and optional mechanics | Core contracts |
| `presentation/` | Terrain, props, creatures, lighting, animation | Read session state and definitions |
| `interaction/` | Perspective camera, ray targeting, keeper hand and input | Core; sends explicit selection/commands |
| `ui/` | Information panels and diagnostics | Core and documented controller API |
| `tests/` | Rule scenarios and isolated extension examples | Contracts under test |
| `tools/` | Repeatable local development commands | Installed Godot executable |

## Add a creature or room

Create a `CreatureDefinition`, `RoomDefinition` or `FoodDefinition` resource with a unique namespaced
ID such as `marsh.mossling` or `marsh.nest`. Add it to a `ContentModule` resource's
`definitions` array, then add the manifest path to `grimblekeep/content_modules` in
`project.godot`. Registration rejects duplicates across all definition types, invalid
values, unknown room food references and unsupported types, and commits a manifest
only after all entries pass. Food references can target the same manifest in any
definition order, or an already registered manifest.

Definitions are treated as read-only at runtime; state belongs to individual actors
or the dungeon. Register during startup, before creating views. Hot-loading,
untrusted external mods and arbitrary schema migration are not implemented.

Creatures may supply an optional `view_scene` (Node3D root). Otherwise they use the
foundation placeholder renderer with definition color/scale. The view follows
`CreatureState.position`, `heading` and `phase`. Room definitions drive build
buttons, placement cost, sale ratio, capacity, paving and optional per-tile
`view_scene` (Node3D root). Set `buildable=false` for unreleased definitions.
Registering a room does not implement its specialist
needs/production behavior; those can use a feature observing `context.rooms`.

## Add a mechanic

Extend `GameFeature` and include its script in a module's `feature_scripts` array.
`setup(context)` receives explicit session dependencies. `tick(delta)` is called at
the physics timestep, in manifest/script order. Feature nodes are owned and freed
by the app scene. Subscribe to context/grid signals for specific changes; do not
reach into UI or unrelated scene paths. Connect to external signals using the
Node receiver so Godot disconnects them when the feature is freed.

The original `wander_feature.gd` remains a small test/example feature but is no
longer in the foundation manifest. It respects keeper custody and clears old
targets on pickup/drop. `worker_feature.gd` owns worker movement in the actual
game; do not enable both for the same actors.
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
`unmined + carried + keeper hand + loose + stored + pending recovery + spent = initial finite supply + gem generation + sale refunds`.
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

Legacy scenario fixtures can place Treasury rooms with trusted `place_initial()`;
ordinary input uses priced `build()`. Generic paving/color and optional tile scenes belong
to `DungeonRoomView`. Gold props read each actual tile balance and the definition's
small/large chest thresholds. New room mechanics can observe this state through
feature modules. Independent tests build a new room and storage type, including
their toolbar entries, without adding ID switches to core or presentation.

Fresh app scenes set `starting_gold=3000` for the user's room playtesting, deposited
once into eight protected floor cells around the Heart (500 each). No Treasury
room is prebuilt. `GoldEconomy.protected_storage` is a trusted scenario source;
`configure_treasury()` merges its capacity with built-room capacity. Room edits
cannot erase it, and room commands refuse construction/sales on protected cells.
Trusted terrain edits retain displaced stock as loose gold; reopening restores
capacity. Initial supply includes the finite bank and seams, with no Heart income.
The layout helper defaults to zero gold and Heart storage. Legacy fixed-Treasury
fixtures pass its third argument false or set app `use_heart_storage=false`.

## Residents, personal beds and rest ownership

`CreatureDefinition` supplies `bed_size`, `rest_room_tag`, normalized initial
energy, drain/recovery rates and sleep/wake thresholds. Only creatures with the
`rest` capability participate in rest; `eat` independently enables hunger.
`food_per_meal` scales nutrition by appetite; `wage_gold` is future data with no
active payment system. Zero `portal_population_limit` disables
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
creates gold or food. `ResidentBehavior` arbitrates home, hunger, rest and work;
`ResidentFeeding` owns eating, while `ResidentNavigation` shares strict A* edge
validation and world-distance movement. Even-size beds
use their actual center, reached through validated floor before the final segment.
No bed/path means bounded retries and an explicit unmet-bed state, not wall crossing.

The manifest ticks food production, resident needs, then worker jobs.
`needs_requested` derives from `rest_requested or food_requested`, giving needs
control while traveling, sleeping, eating or seeking a needed bed. A
multi-talent awake worker keeps its work behavior; rest only updates its needs.
When rest takes priority, `WorkerFeature` releases the current job reservation,
retains cargo and preserves resident action/target state. It resumes ordinary work
after waking. Future cooking/crafting/combat consumers must respect the same
ownership contract or deliberately extend it with reviewed arbitration.

`GameContext.despawn_creature()` releases beds and retains carried gold in the
economy until a worker can safely recover it. The worker feature clears this
pending entry after recovery, including feature reloads. Despawning releases meal
reservations as well as bed space.

## Physical food and producer extension

`FoodDefinition` supplies tags, nutrition, color and an optional Node3D `view_scene`.
`RoomDefinition.food_type`, `food_capacity_per_tile` and `food_production_seconds`
describe physical output/storage. A positive interval enables automatic production;
zero means storage/output only. `FoodFeature` creates bounded output through
`context.food.produce()`, without room-ID switches. Full sources discard timer
backlog. Source state retains partial progress through harmless room merges.

An optional positive `food_tiles_per_unit` pools capacity and one production clock
across each connected room. `food_minimum_size` must fit, allowing rotation. The
Pig Pen requires 2x1, supports floor(tile count / 2) pigs and produces one per 12
seconds. Other producers retain per-tile storage by default. Source `cells` track
the full pool, so old stock on any member tile counts against its shared limit.
Shrinking a room never deletes food; excess stock pauses births until space exists.

`FoodEconomy` owns per-cell/per-food stock, source capacity, production/consumption
counters and exclusive meal reservations. Stable `FoodUnitState` IDs identify each
unit, with allocation cell, authoritative position/heading and bounded simulation
age. Only produce/consume change unit membership and matching quantity balances.
The invariant is `stock + consumed = produced`, including per-food counters.
Selling/replacing a source retains stock; blocked stock stays accounted.

`FoodRoaming` moves enabled food units within their connected producer area using
strict corner rules. Positions and age belong to simulation, not rendered frames.
Reserved pigs return to their feeding cell; `meal_ready()` and `consume()` enforce
that the exact pig and eater are both present before a local debit. One eater
reserves a feeding cell at a time. Reservation alone consumes nothing. Consumption
removes that exact ID once and returns nutrition divided by species appetite.
Growth scales the view from newborn to adult without changing nutrition.

Species set `food_tags` (any matching tag, empty accepts any food), normalized
satiety, drain/trigger/sated thresholds and local eating duration. The need flag
persists until sated. Home establishment comes first; active feeding completes,
critical hunger may wake a sleeper only after reserving reachable food, then rest
and ordinary hunger follow. Missing food uses bounded retries and permits rest or
work to continue; no starvation damage, mood or wage effects exist yet. Portal
recruitment remains gated by reachable fitting bed space, not food.

Independent extension tests add fruit/fungus producers and diets, larger appetites,
and a prepared-food definition with zero automatic production. A later cook can
use explicit output production, but ingredient debits, cook jobs and Dining Hall
service need their own reviewed contracts; they are not implemented now.

`FoodView` follows stable unit IDs and instantiates the definition's scene per unit,
with a generic fallback. Cave pig motion is not resident AI: food cannot inflate
creature counts. Reservation changes preserve existing view nodes and growth.

## Keeper custody and creature inspection

`GameContext.keeper` owns a `KeeperState`. Inspection/custody refer to live
`CreatureState` identities; pickup never creates a replacement actor. Stable
definition eligibility (`keeper_pickup_allowed`) is independent of job/species.
`inspect()`, `clear_inspection()` and `rename_selected()` serve the inspector;
custom names are limited to 32 characters, without control characters, with an
empty-name fallback. `pickup()`, `quote_drop()` and `drop()` own the gameplay
commands. `changed` refreshes views; synchronous `actor_control_changed(actor)`
lets each feature release its own routes/jobs before the command returns.

Held actors remain in the session population and gold ledger. `is_held` freezes
behavior, need drain/recovery, work and food consumption; cargo stays on the actor.
An established personal bed stays owned; pending bed claims and exact meal
reservations are released. Features discard old behavior state on pickup/drop,
then replan from the dropped position rather than resuming a stale path or strike.
Core meal/bed commands and direct behavior entry points also reject held actors.
The example wandering feature demonstrates the same contract for another module.

Drop quotes/commits require FLOOR connected by strict A* to a walkable cardinal
neighbor of the Heart. Creature and bed occupancy do not forbid shared floor;
dropping onto another owner's bed does not transfer its ownership.
Heart-less test scenarios use the pickup-origin component. Invalid commits retain
custody and explain the failed condition. Removing a held actor clears its hand
and inspector references, releases needs/bed reservations and retains cargo in
the existing pending recovery ledger. Raw actor-array edits are pruned as well;
the worker module adopts pending cargo even without a previous active behavior.
The keeper uses a weak context reference to avoid a RefCounted ownership cycle.

`KeeperCreatureTargeting` intersects state/definition body volumes against the
camera ray and compares the nearest terrain hit for wall occlusion. Configurable
awake/sleep bounds scale with species; `BedState.lift_at()` shares mattress height
with the Grubbin view. It does not depend on a rendered mesh or node name.
`KeeperCreatureInput` owns creature input separately from excavation.
Left-click picks up immediately and right-click attempts a drop; left release
never drops. Species hub buttons inspect individuals without lifting; G/Pick Up
remain optional commands. UI/focus/tool changes cannot drop the held actor or
commit a stale terrain drag. While holding, right mouse is reserved for dropping;
empty-hand RMB orbit and Build/Sell cancellation remain in the controller.

`CreatureInspector` owns individual details/editing inside the bottom hub and
invokes commands; the main HUD registers it for input isolation. World views hide
the held actor while the cursor shows a gripping hand, the held instance's model
and name. The model preview is independent of inspection selection and never
changes simulation position. Drop feedback uses authoritative quotes. Closing
details clears inspection, not custody. Species portraits cycle through current
individuals for inspection, and I inspects the hovered creature without lifting.

Gold shares the hand queue with creatures. `KeeperState.is_holding()` reports any
queued entries and construction guards use it; input still allows more pickups.
`GoldEconomy.keeper_gold` is the aggregate held-gold balance;
`KeeperState.held_gold` describes only the front batch. `gold_at()` prefers
a visible loose pile over stock on the same floor cell. `pickup_for_keeper()`
debits that source atomically; `drop_from_keeper()` fills local available storage
and leaves overflow loose, debiting only the requested front batch. These operations preserve
accounting across worker competition and room changes. Held gold is not spendable
and never becomes a wage/payment implicitly when dropped near a creature.

`HeldCreaturePreview` uses an isolated transparent SubViewport to render the
definition's view scene or generic fallback, bound to the held actor's ID rather
than inspection. It reads `sync(actor)` but resets only the view's studio transform,
never simulation position. Gold custody uses an original sack/coin model and
amount. Preview binds the front entry's stable ID, not the latest pickup or
inspection; appending leaves its model intact. Old models detach on front changes; empty
hands disable rendering. All preview controls ignore mouse input.
`KeeperHandItem` stores a unique custody ID, kind, actor or gold amount and pickup
origin. `KeeperState` owns its ordered array; `get_items()` returns an array copy
whose entries are read-only to consumers, and `peek_item()` identifies the next
drop. There is no count cap or same-type restriction. Pickup appends, and a valid
drop removes exactly the oldest entry. Invalid drops retain order. Every queued
actor keeps `is_held=true` until its own release; removing one actor prunes only
that entry and recovers cargo without disturbing survivors. Heart-less scenarios
validate each entry's own origin, rather than the most recent pickup location.

`held_actor`/`held_gold` describe only the front; `held_count` counts all entries
and `total_held_gold` reads the aggregate ledger. Each gold pickup remains a
separate FIFO batch. `drop_from_keeper(cell, requested)` debits only that batch;
the total remains included once in conservation. Ledger transfer methods are
trusted primitives owned by KeeperState; gameplay must use keeper commands so
queue membership and the physical balance agree after every completed command.

`KeeperQueue` renders an ordered strip above the bottom hub. A virtual canvas
represents every entry while only visible cards and a small overscan are created.
Scrolling and card inspection never reorder the queue. A pinned count/next-item
summary remains visible when scrolling to later entries. This rendering bound
does not limit gameplay capacity. Persistence captures the complete queue rather
than the visible cards, preserving entry IDs, origins, actor references by stable
ID and per-batch gold. Restored actor references point only into the new session.

## Save/load boundaries

### Exploration, infrastructure and worker extensions

`DungeonExploration` stores persistent revealed cells independently of lighting.
It derives reachable floor from cardinal Heart exits using the same strict-diagonal
navigation rule, then exposes the current dungeon wall and four rows beyond it. Terrain
changes update reachability and add knowledge without erasing previous discovery.
Excavation execution, room and keeper commands enforce visibility;
presentation and hub counts also filter unknown contents. Only the portal's beacon
is deliberately visible before discovery. Isolated rule fixtures may leave exploration
disabled; the actual compact starting scenario enables it explicitly.

Excavation designation is deliberately different from execution. `can_designate_excavation`
accepts any in-bounds unknown tile and known diggable terrain; `can_execute_excavation`
requires a revealed diggable tile. Reveal events prune only now-known non-diggable
plans. Concealed terrain changes never erase a mark. Ray picking and overlays share
the uniform fog height, so neither feedback nor eligibility exposes hidden contents.
Save validation reconstructs knowledge without firing gameplay cleanup before checking
raw marks; corrupt marks on originally known floor reject, while blind plans on hidden
floor/bedrock/landmarks are valid. An optional saved radius migrates older shorter-range
version2 snapshots by validating original knowledge first, then expanding and pruning
only what enters the new range. Revealed rock has a subtle material base for readable
planning silhouettes; it casts no environmental light.

`DungeonInfrastructure` owns wall sconces, their supporting faces and portal work. Local
portal work validates capability, proximity, needs, custody and cargo. Portal claims gate
recruitment; no territory-claim step is added to ordinary dug floor. Lamps are
spaced by traversable distance, survive saving and are invalidated if terrain changes.
An excavation terrain event fits supported sconces synchronously; no later worker
installation job is needed. `lamps` keys identify access floor cells, not occupied
floor space; `lamp_walls` maps them to cardinal rock/bedrock support cells. Building
rooms/beds on the access floor does not remove fixtures. Cutting a support removes
its fixture, and the same event reconciles sparse replacements on remaining walls.
Room fixtures derive from room membership and also require actual wall support.
Outer corner cells receive authoritative fixtures via `ensure_room_corner_lamps()`
when room membership changes or terrain expands. Corner coverage bypasses ordinary
corridor spacing; nearby lamps across another wall do not suppress it. Single-tile
rooms have one unique access cell, not four duplicate fixtures. Unsupported corners
get no invented wall. Saved old rooms receive missing corner fixtures after validating
the original payload; already complete modern saves remain idempotent.
Views never install lamps or claim portals. Optional save mount records preserve exact
faces; older floor/pending fixtures move to nearest valid known support on loading,
or are discarded if no support exists, with no economic/creature changes.

`WorkerJobProvider` supplies optional jobs to the existing shared board, reservations
and route follower. Providers implement discovery stages, validity, local work,
label/progress and optional yielding to new orders. Carrying/deposit and loose gold
remain priorities; reachable portal claiming precedes excavation. Lamp fitting has
no worker assignment and does not delay digging/hauling. Optional
specialists use a generic `work` capability for resident/work arbitration. A test-only
provider verifies extension without core species switches or a second movement owner.

`starting_layout.gd` creates the small player start; `foundation_layout.gd` remains
the explicit development fixture. Saves contain terrain, so loading never reapplies
a scenario or grants another bank. Version2 stores exploration/infrastructure via
their own codec. The version1 migration retains the old fully known map, physical
state and already-operational portals. Unknown future versions still reject.

Darkness uses local shadowed lamps/Heart/room/portal lights and minimal ambient light.
Terrain uses spatial batches to respect Compatibility renderer per-mesh light limits.
Opaque uniform fog substitutes for unknown tile geometry; tall actors, room labels,
food, beds and gold also explicitly hide rather than relying only on that surface.

`DungeonSave.capture(context)` creates JSON-compatible data; `restore(data, registry)`
returns a detached validated context or an error. The versioned facade delegates
to world/gold, creature/bed/keeper and food codecs. Definitions resolve through the
already registered stable IDs, never through save-supplied script/resource paths.
Room groups and storage capacity rebuild from terrain/definitions; physical
stock, accounting counters and monotonic identity sequences restore explicitly.
Corrupt references, duplicate identities, invalid numbers and unbalanced resource
ledgers reject the candidate. Pending beds stay pending; established beds preserve
ownership. Removed actors' pending cargo and food on sold/blocked tiles stay accounted.

`GameFeature.persistence_id()`, `capture_state()` and `restore_state(data)` let a
stateful mechanic extend the feature payload without changing the core codecs.
Use a namespaced stable ID and validate before committing local state. Stateless
features return an empty ID/payload. `FeaturePersistence` rejects missing, duplicate
or unavailable stateful features; the resident module preserves its arrival clock.
Add meaningful round-trip/continuation checks when adding persistent mechanics.

`app/dungeon_app.gd` prepares features against a detached candidate, checks the
optional camera state and replaces live features/views/input/HUD only after every
owner accepts. GUI requests defer replacement until the emitting control returns.
Transient gestures/tools/routes/jobs/meal reservations start clean; creatures replan
with their saved needs, rest/hunger intent, cargo and bed ownership. Sleeping recovery
continues through the hysteresis band. Held creatures remain frozen until dropped.

`DungeonSaveStore` writes verified JSON to an adjacent temporary file before slot
replacement and retains a `.bak`; failed operations report errors without discarding
the last good data. A missing primary can load the backup after an interrupted
replacement. This does not promise filesystem durability under hardware/power loss.
The app passes the registry for full preflight, including validation after exact JSON
encoding. There is one manual `user://saves/dungeon.json` slot and no autosave. Version1
migrates to version2; future versions reject. Camera state has its own validator.

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
F3 debug window, including satiety/eating when supported; concise construction
quotes follow the cursor. The header shows food stock and producer tooltips show
capacity. Original SVG assets
in `assets/ui` supply replaceable icons. A
right-click during construction cancels pending drag before GUI consumption and
returns to excavation; default RMB camera orbit remains outside construction.

The dungeon view batches dirty terrain updates per frame and preserves unrelated
landmarks/heartbeat when workers clear stone. Gold piles/treasury presentation
refreshes from the ledger; it never creates resources. Presentation and HUD poll
small changing displays, not expensive actor logic every frame.

The module list is an explicit trusted composition order, not a dependency resolver.
Initial actor spawns and terrain belong to the replaceable foundation scenario.
Adding a new species does not imply automatic portal recruitment: configure its
population limit and bed requirements. Core contracts can evolve when required,
with regression coverage.

## Review expectations

Check clear ownership, stable IDs, validation, lifecycle cleanup, state/view
separation and concise functions. `tests/run_tests.gd` registers a test-only
creature, room and mechanic without modifying core dispatch. It also exercises
registration rollback, unknown references, coordinates and wandering safety.

Art baseline: 2 world units per tile; workers approximately 1–1.5 units tall;
chunky low-poly procedural meshes with a limited earthy palette. No textures or
external asset licenses are required for these original code-generated placeholders.
Blender 5.3 is available through user `BLENDER_EXE` and PATH. Future authored
models/animations should retain editable sources, export game-ready assets such
as GLB, document provenance, and pass the same in-Godot scale/animation/readability
review before replacing a procedural scene. No current asset was authored in Blender.
Target 60 FPS at 1280x800 with the small foundation map on the development machine;
record observed performance separately, not as a guarantee for larger dungeons.
