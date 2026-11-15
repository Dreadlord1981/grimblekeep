# Grimblekeep verification — 2026-11-15

Foundation and worker digging/mining/hauling implemented locally with independent
review. Room construction, needs, attraction, leveling and saving remain pending.

## A* diagonals and shared-side mining — current verification

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
