# Grimblekeep verification — 2026-11-15

Foundation, workers, Treasury Build/Sell and the first Grubbin/Lair rest loop are
verified locally with independent review. M3B adds verified Pig Pen production,
growth, roaming and eating, plus a 3,000-gold playtest start. Mood/wages, a second species,
keeper pickup/drop, leveling and saving remain pending. Earlier sections below
the current checkpoint retain their historical counts and scope.

## Pig Pen food loop and funded playtest start — current verification

Final `tools/dev.ps1 check`: **82 scripts, zero failures**. Final full
`tools/dev.ps1 test`: **1,571 checks, zero failures** (earlier1,249 plus food28,
feeding138, food UI27, independent food45, pig life67, starting gold17).
Lead independently ran the complete suite. `tests/food_render_probe.gd` passed
**31 GPU checks**, independently rerun by the lead. Code and rendered output
received separate independent reviews; no blocking findings remain.

The first implementation passed 78 script validations, 1,463 headless checks and
27 GPU checks. The user then requested growing piglets, room-wide roaming, outer
fences and one pig per three tiles, with a corrected minimum of 3x1 (or 1x3),
superseding the intermediate 3x3 suggestion. The final counts above include those
corrections; the initial counts alone do not verify them.

Food checks cover atomic definition registration and references, independent
fruit/fungus producers, dietary compatibility, appetite-scaled nutrition, bounded
production, no full-source backlog, source replacement and mixed stock. Selling
or blocking a source preserves accounted food. Exclusive meals consume locally
exactly once; actor removal, diet changes and inaccessible routes release targets.
Prepared-food definitions with zero automatic production exercise the future
explicit-output API without implementing cooking, ingredients or Dining Hall jobs.

The final model uses stable food-unit IDs, age and authoritative position. Pooled
room capacity counts all stock on member cells; minimum footprints allow rotation.
Piglets grow over 30 simulation seconds, roam their connected room and return for
reserved meals. Both the pig and eater must be present before eating progresses.
Independent feeding checks include waiting for a moving pig, displacement during
eating, exact-ID removal and retained reservations without early nutrition.

UI checks use real Godot Viewport input to choose/build the Pig Pen, spend stored
gold, update actual stock/capacity tooltips, preserve the clean tabbed hub, and
display satiety/eating in F3, including food-only species without bed requirements.
The GPU scenario builds actual rooms, advances ordinary production and needs,
observes repeated meals/rest/wake and compares visible food against the ledger.
Food ages/positions are driven by simulation, not rendering or test-only timers.

Independent review found a retained meal could ignore a newly sealed route; the
ledger now rechecks reachability before retaining it. Roaming review also checks
that cached room components cannot be reused for a different food type after
source replacement. Both fixes have passing independent regression checks.

The GPU harness builds a minimum 3x1 pen through Viewport controls, extends it to
3x2 and tracks the same pig through newborn, juvenile and adult renders. One pig
visits all six cells with speed-bounded movement and remains in its connected
room. Fences cover only outer edges, with one gate and no internal rails. Actual
simulation observes three meals in two feeding trips and a rest/wake cycle.
Selling the pen immediately preserves exact IDs; subsequent ordinary eating may
reduce that retained stock, while births stop and conservation holds. Final run:
four produced, four consumed, zero remaining after continued post-sale eating.

The funded app start has exactly 3,000 gold in six real 500-capacity Treasury
tiles. Seventeen startup checks verify initial supply includes the finite bank,
ticks/feature reloads do not repeat it, full storage pauses mineral work, room
spending frees capacity, and workers resume and refill it without creating gold.
Mining-only rule and GPU fixtures explicitly opt out with `starting_gold=0`;
the legacy scene integration fixture was updated because full storage correctly
prevented its marked gold job from moving workers. A fresh default GPU capture
(`artifacts/foundation.png`) visibly shows `GOLD 3000 / 3000` and six large chests.
No standalone export validation is implied by startup checks.

Final local artifacts include `pig-pen-empty.png`,
`pig-pen-full.png`, `pig-pen-minimum-3x1.png`, `piglet-newborn.png`,
`piglet-growing.png`, `pig-grown-adult.png`, `cave-pigs-roaming-a.png`,
`cave-pigs-roaming-b.png`, `pig-returning-to-feed.png`, `grubbin-eating.png`,
`pig-pen-sold-stock-retained.png`,
`food-loop-resting.png` and `food-loop-overview.png`. They are ignored evidence,
not distributed runtime assets. Pig meshes, room dressing and icons are original
procedural/code-authored assets. There is no starvation damage, mood, wage,
cooking, second-species or save implementation; portal attraction remains bed-gated.

## Blender tooling

Verified Blender 5.3.0 at
`C:\Program Files\Blender Foundation\Blender 5.3\blender.exe` with `--version` and
`--background --factory-startup --python-expr` importing `bpy` and printing its
version. Both exited 0; no document or UI window was created. User `BLENDER_EXE`
points to that executable and user PATH includes its installation directory,
preserving other entries. Already-open shells need reopening or an explicit read
of the user environment. Asset creation/export/import in Blender remains future
work; this check verifies executable and background Python access only.

## Indestructible bedrock and Lair icon — earlier baseline

`tools/dev.ps1 check`: **64 scripts, zero failures**. Full `tools/dev.ps1 test`
passes the earlier 1,176 checks plus 73 independent bedrock checks:
**1,249 checks, zero failures**.

Bedrock appends terrain ID 6 without renumbering the original types. Its solidity
is independent from excavation permission: it blocks A*, room placement, portal
access and personal bed footprints, but accepts no excavation marks/mineral yield.
Rule scenarios replace active stone/gold/gem jobs with bedrock, prove marks/jobs
are canceled before completion and verify physical gold is conserved. Direct
commands and actual Viewport mixed click/drag selection cannot mark bedrock.
Perspective nearest-hit targeting covers 12 camera angle/distance combinations
against the shared 2.15 raised surface.

Scenario checks verify the entire starting border, preserved Heart/portal/start
routes and all eight mineral access points, plus the internal pattern. Public
trusted helpers cover arbitrary disconnected/duplicate cells, atomic rejection
of a mixed invalid pattern with no revision mutation, null/nonpositive inputs
and a two-cell border around a rectangular grid. Trusted terrain edits can still
replace bedrock deliberately; player gameplay cannot destroy it.

GPU `tests/bedrock_render_probe.gd` passes **15 checks**: all bedrock bodies/crowns
exist at the correct raised height, blocked/mixed Viewport selection is correct,
ordinary marks/glow remain functional and live neighbor edits preserve bedrock.
Lead and independent reviewers inspected `bedrock-wide.png`,
`bedrock-internal.png`, `bedrock-blocked-target.png`, `bedrock-mixed-selection.png`,
`bedrock-strata-close.png` and `bedrock-border-close.png` in ignored `artifacts/`.
Flat blue-charcoal crowns and side strata read distinctly from rough brown rock.
Initial crown/core Z-fighting was caught, corrected and rechecked; crown tops
match the authoritative height. Rendering now uses `is_solid`, while ore/rubble
exposure uses walkability so bedrock is never mistaken for open floor.

The Lair's original SVG icon was redrawn as a side-view bed with a tall headboard,
pillow, rectangular patched blanket, footboard and legs. Actual GPU hub capture
`tests/ui_icon_render_probe.gd` passes with `HUB ICON CAPTURE: OK`;
`artifacts/hub-lair-bed-icon.png` was inspected by lead and independent reviewers.
No gem/ruby silhouette remains. No blocking findings remain. The user tried the
updated build and approved this checkpoint for Git; its revision is in Git history.
These changes include the preceding M3A packages; no map editor,
new economy, native desktop automation or export/performance gate is claimed.

## Local beds, tabbed hub and full-Treasury pause — earlier baseline

`tools/dev.ps1 check`: **61 scripts, zero failures**. Full `tools/dev.ps1 test`:
core38, path/economy20, pathfinding366, targeting49, excavation input31,
integration10, workers92, mining sides52, room rules42, Treasury workers33,
construction input47, room review97, bed contracts31, residents118, resident UI41,
independent resident review49, full Treasury60: **1,176 checks, zero failures**.

The user's corrections distinguish reserved capacity from an established home.
Reservations remain exclusive to avoid over-recruitment, but no bed mesh/cot lift
exists until the owner reaches the footprint center and completes a local claim.
The core command rejects remote owners, invalid profiles/footprints, nonfinite
positions and stale completion after selling; repeated valid completion emits
no duplicate notification. Behavior tests cover healthy home-first travel, larger
footprint centers, displacement and progress reset, pending feature reloads,
selling during claiming, re-acquisition and work/rest priority with retained cargo.

The focused `DungeonHub` control now owns the bottom tabs. Creatures is selected
by default, with one portrait per species and live population overlaid. Rooms
shows one icon per type with connected-room count; tooltips distinguish tiles,
gold stock/capacity and pending/established personal beds. The fixed right sidebar
and verbose footer are removed; controls and individual details appear only in
the hidden F3 debug window. Input tests exercise actual tab clicks, default/hidden
states, spawn/despawn updates, room merges/splits, capacity tooltips, no reopened
sidebar, world isolation, preserved dig marks and safe right-click cancellation.
Construction quotes follow event-tracked cursor position, including synthetic
Viewport events; native physical input automation remains unavailable.

Mineral discovery and active-strike validation both require reachable free Treasury
space. Tests fill finite/gem storage through real hauling, fill it mid-strike,
verify zero further extraction/progress/rewards, preserve marks, and resume after
spending/expansion. Ordinary stone/buried stone chains continue. Empty unreachable
storage and temporarily reserved delivery positions are distinguished; full storage
does not prevent a hybrid creature making its bed and resting. Conservation is
checked per tick. Cargo already in transit is preserved, not predicted against
future capacity. The earlier absent-Treasury and shared-workplace fixtures were
updated to the explicitly changed gameplay rule, retaining their original intent.

GPU `tests/lair_render_probe.gd` passes **26 boolean conditions plus two sleep
entries**. It proves the Lair remains bare before arrival, at the portal, during
approach and during the local claiming gesture. The personal-bed node first
appears after establishment while its owner is within the authoritative center
distance. Existing walking/gait, sleep/wake, cot departure/lift reset, wall/glow
restoration, room edits, bed recovery and gold conservation still pass.

Final 1280x800 captures inspected by lead and independent reviewers include
`hub-creatures-default.png`, `lair-and-treasury-overview.png`,
`hub-build-cursor-quote.png`, `hub-f3-diagnostics.png`, `lair-before-arrival.png`,
`lair-arrival-pending.png`, `lair-approach-pending.png`, `grubbin-claiming-bed.png`,
`lair-personal-bed.png` and the earlier rest/movement/glow views in ignored
`artifacts/`. Species counts3/0 then3/1, room counts2/1 and price50 are visually
distinct. F3 fits the viewport and the ordinary world view has no right panel.
No blocking code or visual findings remain. This M3A work/follow-up checkpoint is
tracked in Git history; no additional food/wages/crafting/combat mechanic was started.

## M3A Grubbin, Lair and icon controls — earlier baseline

`tools/dev.ps1 check`: **59 scripts, zero failures**. Full `tools/dev.ps1 test`:
core 38, path/economy 20, pathfinding 366, targeting 49, excavation input 31,
scene integration 10, workers 92, mining sides 52, rooms 42, Treasury workers 33,
room input 44, room review 97, bed contracts 24, residents 89, resident UI 20,
independent resident review 32: **1,039 checks, zero failures**.

Bed/AI checks execute actual fitting of rectangular species footprints within one
tagged connected room, non-overlap, fragments that have enough tile count but no
fitting rectangle, same-tag/different-definition boundaries, ownership through
merges/splits, actor removal and invalid references. Arrival requires a reachable
portal/free bed and respects the definition's population limit. The current
Grubbin limit is one; imps still begin as three scenario workers.

Residents repeatedly explore, tire, walk to personal beds, sleep and wake. Tests
interrupt sleep by selling/blocking bed cells, restore room space, seal/reopen
routes, invalidate diagonal flanks mid-route and reload features. A combined
rest/work creature releases reservations, retains cargo, does not move twice and
resumes mining/hauling all 200 seam gold after waking. The corrected conservation
oracle compares `accounted_gold` against finite supply plus gem output; refunds
are already subtracted by that API. Paid Lair sales exercise nonzero refunds.
Despawn also preserves cargo if no worker feature is loaded and clears pending
recovery entries when a live worker feature safely drops the removed actor's gold.

Viewport input checks cover icon toolbar choices, separate worker/resident cards,
normalized energy, actual bed status, work progress, warning tint, panel bounds at
1280x800 and world input isolation. Right-click cancels Build and Sell, including
a held left drag or a pointer over UI; releasing the left button then has no effect.
Default RMB camera orbit still works. Original SVG icons/portraits are provided by
definitions; names/jobs/cost details remain available through tooltips.

GPU `tests/lair_render_probe.gd` passes **20 boolean flags plus two sleep entries**:
finite funding, Lair/Treasury Viewport construction, distinct styles, mineral-face
readability, portal arrival, personal bed, walking and gait changes across rendered
frames, sleeping, waking/recovery, cot departure, marked-wall glow/restoration,
wall removal after excavation, bed removal/recovery, lift reset, conservation and
successful captures. Test-only accelerated simulation and finite stock fixtures
are confined to the harness; no player speed controls or free game currency added.

Lead and independent reviewers inspected final frames at 1280x800:
`lair-and-treasury-overview.png`, `treasury-wall-inlays.png`, `lair-personal-bed.png`,
`grubbin-walking-a.png`, `grubbin-walking-b.png`, `grubbin-sleeping.png`,
`grubbin-awake.png`, `grubbin-leaving-bed.png`, `lair-rest-cycle.png`,
`lair-marked-wall-glow.png`, `lair-wall-restored.png`, `lair-bed-removed.png`
in local ignored `artifacts/`. Floor inlays/brass wall seals distinguish Treasury
from Lair rugs/ragged skull hangings. Exposed gold/gem faces stay visible. A visual
regression was found and fixed: marked rock temporarily hides wall dressing so
top/side amber glow remains readable. Wake/departure cot lift prevents feet clipping
through the mattress and resets when the personal bed disappears. Two actual
walking frames verify the gait changes; sleeping frames show the rest pose.

Grubbin, cots and room dressing are original procedural low-poly meshes. UI SVGs
are original code-authored assets; provenance is in `assets/ui/README.md`. The
user-approved generated concept was copied into `docs/references/` as direction,
not a runtime 3D asset. `LORE.md` records approved facts and open questions.

Independent core/resident/work/UI and visual reviews found no remaining blockers.
This is the first rest loop, not full Milestone 3: meal amounts/wages are profile
data only, with no food consumption/payment/mood system yet. No native desktop
automation, audio, stress/performance or export gate is claimed. Changes remain
tracked in Git history with the later user-requested corrections.

## Modular Treasury construction and selling — earlier baseline

`tools/dev.ps1 check`: **48 scripts, zero failures**. `tools/dev.ps1 test`:
core 38, path/economy 20, independent pathfinding 366, targeting 49, excavation
input 31, scene integration 10, workers 92, mining sides 52, room rules 42,
Treasury workers 33, room input 40 and independent room review 97:
**870 checks, zero failures**.

The user's final rules supersede the earlier claiming proposal. Excavated floor
is immediately eligible for construction, with no separate claiming jobs/state.
Build click/drag never toggles existing room tiles off; only the explicit Sell
tool removes them. Sales refund 50% per tile, rounded down separately, including
starting-room salvage. Treasury cost 50/tile and capacity 500/tile are provisional.

Rule scenarios cover a complete finite mining -> hauling -> construction sequence,
authoritative quote/commit costs, duplicate cells, skipped invalid tiles, atomic
unaffordable drags, protected landmarks, immediate eligibility after excavation,
four-connected merge/split and diagonal separation. Independent definitions prove
a second room and storage type can build/render through shared contracts without
core ID switches. Input tests add a room toolbar entry from its definition and
send actual events through the Godot Viewport, including UI crossing, tool changes,
Esc preserving excavation orders, stationary terrain/gold preview updates, and
Build refusing to delete existing room tiles.

Storage tests cover exact per-tile limits, normalized-fill worker distribution,
partial deliveries, concurrent reservations, full-storage no-thrash, capacity
expansion, sale during delivery and local overflow. Sale scenarios verify initial
room value, exactly-once refunds, half-price rounding, nearly-full remaining
storage, the last Treasury's stock plus refund remaining on the floor, and repeated
build/sell cycles losing the expected net amount. Conservation includes gross
construction spending and explicit sale refunds; no untracked gold is created.

GPU `tests/rooms_render_probe.gd` passed all 11 flags: deposited, stages, preview,
built, spent, removed, refund_preview, refunded, stage_updates, conserved, captures.
It renders the real scene, transfers finite seam supply into test stock fixtures
to exercise the three visual stages, and sends Viewport events to build and sell.
Ordinary worker deliveries/distribution are separately executed by the worker and
end-to-end mining tests; the visual fixture does not claim to test that journey.

Captures inspected by the lead and independent reviewers at 1280x800:
`artifacts/rooms-overview.png`, `treasury-gold-stages.png`,
`treasury-build-preview.png`, `treasury-built.png`, `treasury-sell-preview.png`,
`treasury-removed-gold.png`, `treasury-stock-spent.png`.
Each Treasury tile displays its own real stock: pile below 35%, small chest from
35%, large chest from 75%. Spending visibly downgrades/removes props; selling a
250-gold tile leaves exactly 250 loose gold and credits its 25-gold refund to
remaining capacity. Paving, labels, costs/refunds and restrained desktop HUD remain
readable. These are original procedural prototype assets, not final commercial art.

Independent code reviews approved core rules, worker storage and construction
controls. One earlier review finding about claim-only workers was fixed, then the
entire claiming feature was removed at the user's request. No blocking findings
remain. Native physical mouse/keyboard automation is still unavailable as recorded
below: only Godot Viewport routing and GPU output are verified. No new performance,
audio or standalone export gate is claimed. The user tried the restarted build
and reported it looks good. This checkpoint is tracked in Git history; no further
room or creature mechanic has been started.

## A* diagonals and shared-side mining — earlier baseline

`tools/dev.ps1 check`: 40 scripts, zero failures. Full test suite: core 38,
path/economy 20, independent pathfinding 366, targeting 49, input 31, scene
integration 10, workers 92, multi-side mining 52: **658 checks, zero failures**.
The reviewer independently ran the complete suite and approved both packages.

Navigation tests compare A* with an independent Dijkstra oracle on seeded maps,
check all diagonal orientations with either/both corner flanks blocked, verify
grid identity/revision cache refresh, equal world movement speeds, mid-segment
flank changes and weighted-distance job choices. Worker workplaces remain
cardinal-adjacent to the mined block.

Mining-side tests cover four distinct reachable faces, a fifth waiting miner,
blocked/isolated sides, stone/pile exclusivity, shared workplace conflicts,
exact finite depletion, cancellation, replacement and renewable gems. All miners
debit the same authoritative node balance.

GPU `tests/mining_sides_render_probe.gd` captured
`artifacts/four-sided-mining.png`: four workers visibly mining one gold block on
four distinct faces, with conserved supply. Lead and independent reviewer inspected
the frame. The existing worker GPU scenario passed again with `diagonal=true`,
`stored=400`, `conserved=true` and `finished=true`. No crowd steering, path smoothing
or native physical input automation is claimed. Implementation stops here for the
user's requested discussion. This verified checkpoint is tracked in Git history.

## Worker digging/mining/hauling — earlier baseline

`tools/dev.ps1 check` validates 37 scripts; `tools/dev.ps1 test` passes core 38,
path/economy 20, targeting 49, input 31, integration 10 and independent worker 92:
240 checks, zero failures. The manifest runs WorkerFeature instead of ambient
wandering. Creature capabilities select participation; job assignment/reservations
and behavior execution are separate components.

Worker scenarios cover stone excavation chains, buried marks, finite gold,
renewable slower gems, cancellation before/after mining, target/workplace
contention, blocked routes, capability filtering/loss, missing/returning treasury,
removed/replaced workers, no-floor cargo recovery, feature reload and actor
reinsertion. Fixtures verify gold conservation every simulation tick.

Independent review discovered that detached cargo retained for delayed recovery
was missing from the ledger/HUD totals. GoldEconomy now owns pending-cargo state;
the worker feature adopts it on reload, recovers it to safe floor and avoids
double counting/recovery on actor reinsertion. All new regressions pass.

`Godot --path . --script res://tests/worker_render_probe.gd` passed on the GPU.
It exercises the real composition root with test-only accelerated simulation and
captures `artifacts/workers-working.png`, `workers-hauling.png` and
`workers-treasury.png`. It observed actual digging/mining and carried cargo,
cleared the marked terrain, deposited exactly 400 gold and conserved supply every
tick. Lead and reviewer inspected the frames: roster/action, carried gold and
stored-gold displays agree with observed behavior. No gameplay speed control was added.

No remaining package blockers. Minor polish: depositing transfers instantly and
resets to idle, so its separate pose is not visible between frames. No audio or
native desktop automation verification is claimed. The user requested a stop for
status/next-step discussion after this package; further features are pending.

## Default excavation and glow — earlier baseline

The user's clarification supersedes the intermediate Hand/Dig split. Default
keeper click/drag toggles authoritative excavation marks on stone, gold and gem
terrain. There is no generic ground selection or separate mode. Future room
construction will have its own floor-placement action. Marks persist until
unmarked/cleared or until their terrain becomes non-excavatable.

Current check command validates 28 scripts. The full test command passes core 38,
targeting 49, input 31 and integration 10: 128 checks, zero failures. This covers
gem solidity/targeting, default toggle, mixed areas, ground/landmark exclusion,
modifier press/release behavior, UI isolation, automatic mark pruning and immediate
preview invalidation when hovered terrain changes without pointer motion.

The GPU selection render probe passed with seven additions and two removals and
captured `artifacts/selection-preview.png`. It also captured persistent glow in
`artifacts/excavation-glow-top.png` and `artifacts/excavation-glow-side.png`.
Lead and independent reviewer inspected all three. The amber additive shell is
visible on block tops and exposed sides; green plus/red X previews remain distinct.
The shader pulse uses GPU TIME; no per-tile CPU animation is needed. This is a
lightweight visible glow treatment in Compatibility rendering, not a full bloom
or physical light simulation.

Independent review approved the updated marking and glow, and identified the
stationary terrain-change preview gap. Lead fixed that gap and added regression
checks; the full suite passed again. Native mouse/keyboard automation remains
unavailable as documented below. Workers do not execute these marks yet.

The original acceptance baseline and timing sample below predate this follow-up.

## Environment and reproducible checks

- Godot `4.7.2.stable.official.ed1daf0bf`, Standard/GDScript.
- Windows desktop, Intel Core i5-13400F, NVIDIA GeForce RTX 4060.
- Renderer: OpenGL Compatibility; game viewport 1280x800.
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev.ps1 check`
  passed: 26 scripts, zero failures.
- `powershell -NoProfile -ExecutionPolicy Bypass -File tools/dev.ps1 test`
  passed: core 32, surface targeting 37, selection 14, scene integration 10;
  93 checks total, zero failures.
- The check wrapper was also tested with a deliberately malformed unattached
  script: returned exit 1. After removing that temporary fixture and its generated
  UID, validation returned exit 0. This catches errors editor import alone misses.

Core coverage includes module extension with a new creature, room definition and
feature, duplicate rejection and atomic rollback, invalid references/values,
connected starting terrain, 3600 wandering ticks and selection operations.
The fixture module does not modify core dispatch to add its definitions/feature.

Input coverage routes synthetic mouse/key events through the actual Godot
Viewport and HUD. It covers click toggle, inclusive rectangle toggle twice to
clear, preservation outside a rectangle, add/remove modifiers, persistent rings,
Escape, UI-to-world/world-to-UI cancellation and recovery. Camera tests project
rock/gold/floor surfaces through multiple yaw angles/distances and check nearest
terrain hits. Scene integration covers active camera, wheel, Home, world selection,
HUD isolation and feature ticking.

## Rendered inspection and timing sample

`Godot --path . --script res://tests/render_probe.gd` launched on the GPU,
captured overview and close perspective views, then exited successfully.
Generated evidence: `artifacts/overview.png`, `artifacts/close.png`.
`tools/dev.ps1 capture` also produces `artifacts/foundation.png`.
Artifacts are local ignored outputs, not required runtime content.

Lead inspected both camera distances; independent review inspected the overview.
Heart, portal, gold and imps read distinctly, and the desktop HUD is legible.
The original custom mesh winding defect was caught visually and corrected.
The latest close capture includes the updated multi-selection count/footer.
Procedural low-poly assets are foundation placeholders, not final art.

A 180-frame sample after 60 warm-up frames reported 3.003 seconds, about 60 FPS
with VSync at 1280x800, on the small 28x28 map with three actors. This is a short
smoke sample, not a stress test or a performance claim for larger populations.
No broad performance gate is declared passed for later milestones.

## Independent review and limitations

Reviewer found two actionable issues: floor-only picking missed raised terrain,
and editor import could return success despite script errors. Both were fixed and
rechecked. Reviewer independently ran all four suites before final test-file
organization; lead reran them after moving probes under `tests/`.

Native desktop automation could not initialize: both available entry points
reported `failed to write kernel assets ... os error 3`. No native mouse/keyboard
automation pass is claimed. Engine event routing and rendered output are verified;
physical input feel remains subject to manual playtesting. The user identified the
initial single-selection limitation during live play, and requested toggle drag
selection, which is now implemented and covered by the input suite.

Export templates are not installed. Running via Godot is verified; no standalone
Windows export was produced. No audio, wall fading, final hand model or hot-loading
of modules exists yet. Terrain changes currently rebuild small-map batches;
scaling to larger maps belongs to later profiling. Room definitions establish the
data boundary; room mechanics have not been implemented.
