# Grimblekeep verification — 2026-11-15

Foundation, workers, Treasury Build/Sell and the first Grubbin/Lair rest loop are
verified locally with independent review. M3B adds verified Pig Pen production,
growth, roaming and eating, plus a 3,000-gold playtest start. M3C keeper pickup/drop
and creature inspection are verified below. Mood/wages, a second species,
leveling remain pending; M4A manual save/load is verified below. Earlier sections below
the current checkpoint retain their historical counts and scope.

## Room corners and lighter excavation highlights — current verification

Final check: **133 scripts, zero failures**. Full headless runner:
**2,501 checks, zero failures**, exit0 (`artifacts/room-corners-full-tests.log`).
New independent room-corner32/0; wall58/room42/food28 independently rerun.

Actual Compatibility graphical room probe: **20/0**, independently run by lead and
presentation implementer. Inspected `artifacts/room-corners-pigpen-3x3.png`,
`room-corners-pigpen-5x5.png` and `room-corners-loaded.png`: all supported corner
lamps face inward, floor and pigs remain readable, darkness outside is retained,
and there are no floor poles. Verified growth/split/merge, no duplicate fixtures,
real wall support, floor/bed coexistence, saved exact mount faces, missing old
corner catch-up, mixed custody and resource conservation. Source and visuals
approved by independent reviewer. No global lighting or lamp cost change.

Excavation overlay uses alpha mixing with bounded face opacity.035/edge.24 rather
than the stronger additive face fill. Lead pixel/render regression **20/0** samples
a dense4x4 marked area over three pulse phases: dark-rock red channel beforeselection
.02-.04, new selectedcenters.05-.07; former centers were.13-.16. Strong outlines and
top/side glow remain. Independent graphical diagnostic **4/0** proves alpha works
in Compatibility and repeated refreshes keep one shell per cell. Exact solid-orange
user screenshot was not reproduced in a fresh runtime; the change reduces/bounds
fill safely, without claiming an unverified driver/ignored-alpha bug.

Independent review approved. No live game was restarted or saved automatically;
prior Windows window-control initialization failure still applies. User can F5 save,
restart and F9 load to apply corner fixtures and the new overlay. User playtested and approved this checkpoint for commit/push; refer to Git history.

## Immediate wall sconces — prior checkpoint

Final `check`: **129 scripts, zero failures**. Full headless runner:
**2,469 checks, zero failures**, exit0 (`artifacts/wall-lamps-full-tests.log`).
New independent wall suite58/0, updated infrastructure46/0 and exploration76/0.
Lead, presentation implementer and independent reviewer each ran the actual
`wall_lamp_render_probe.gd`: **36/0**, Compatibility/RTX4060 at1280x800.

Inspected `artifacts/wall-lamp-close.png`, `wall-lamp-excavation.png`,
`wall-lamps-start.png`, `wall-lamps-room.png`, `wall-lamps-living-room.png`,
`wall-lamps-room-fixtures.png` and `wall-lamps-loaded.png`. Wall plates/brackets
attach to real supporting faces; all mesh bounds remain above0.85 and the local
shadow light is at1.65, below ordinary wall height. There is no floor post or
unsupported interior fallback. Rooms and established beds use the same access
floor without losing their wall fixture. Opposite faces of a shared wall persist.

Excavation removes invalid supports and fits sparse replacement sconces immediately,
before another feature tick. Tests verify idempotence, coverage spacing, continued
mining/cargo/custody, room fixtures and exact service/support save restoration.
Old floor and unfinished lamp saves convert to supported sconces where walls exist;
malformed new mount references reject before live mutation. Portal claiming and
optional worker-provider extension remain tested. Timed lamp-job expectations were
replaced to follow the user's direct-installation instruction.

Code/behavior/visual reviews approved. Current user game was left running unchanged:
both native window-control entry points failed to initialise with kernel-assets
path-not-found (os error3), so no save/reload action could be performed. User should
F5 save and restart to apply; no live progress or existing save was overwritten.

## Fog planning and wall visibility correction — prior checkpoint

`tools/dev.ps1 check`: **127 scripts, zero failures**. New independent
`fog_planning_tests.gd`: **52/0**; updated exploration review **76/0**. Revised
fixtures keep the unknown portal outside the final wall-plus-four-row boundary.
Final full headless runner: **2,410 checks, zero failures**, exit0; log at
`artifacts/fog-plan-full-tests.log`. Updated game launched without errors in
`artifacts/playtest-fog-plan.log`; no running user game was closed or overwritten.

Lead and independent reviewer each ran graphical `fog_planning_render_probe.gd`:
**22/0**. Lead also reran exploration graphical probe **34/0**. Inspected captures:
`artifacts/fog-planned-room.png`, `fog-plan-removal.png`, `fog-plan-discovered.png`,
`fog-plan-excavated.png` and `exploration-four-row-band.png`.

Actual Viewport4x7 drag queues28 cells through fog. Identical amber/top-side geometry
and ray height conceal unknown floor, bedrock, gold and portal contents. Repeat drag,
Shiftadd, Ctrlremove, red-X previews, UI/stale release cancellation remain correct.
Unknown marks persist through hidden terrain edits and JSON round trips. Discovery
clears only non-diggable marks; known rock/gold/gems remain until dug/cancelled.
Workers progressively complete the plan and never mine unknown mineral targets;
resource ledgers balance. Existing build/Sell/keeper visibility guards stay active.

The exposed wall plus four further rows is revealed around reachable dungeon space
(five cells from the adjacent open-floor boundary). Knowledge persists as walls move.
Revealed rock/bedrock has a faint dark material base for legible planning silhouettes;
ambient remains0.055 and all actual environmental light comes from local fixtures.
Unknown contents remain hidden. Current saves preserve planned unknown obstacles;
older v2 saves without a radius validate their original one-tile frontier first,
then expand knowledge and prune only newly revealed invalid plans. Malformed marks
on originally known non-diggable tiles reject instead of being silently repaired.

Independent core/input/overlay/save and visual review approved. Prior unseen-planning
rejection checks were superseded by the user's explicit correction; hidden resource
interaction and undiscovered work rejection continue to be tested. No other feature,
price, art overhaul or Kitchen work was introduced.

## M4B compact start, exploration and infrastructure — prior checkpoint

`tools/dev.ps1 check`: **125 scripts, zero failures**. Full headless runner:
**2,358 checks, zero failures**, including new infrastructure workers45 and
independent exploration76. Worker/resident/keeper/room/food/save regressions all pass.
Existing large-map scene probes explicitly select the development layout; actual
starting-gold and new exploration tests exercise the compact player start.

New graphical `tests/exploration_render_probe.gd`: **34/0**, run independently by
presentation implementer and lead on RTX4060/Compatibility at1280x800. Lead and
independent reviewer inspected all five artifacts:

- `artifacts/exploration-dark-start.png`:24 Heart-chamber floor cells, three imps,
  finite protected3,000gold, two initial lamps, black unknown space and remote beacon.
- `artifacts/exploration-frontier-dig.png`:real Viewport marking and worker digging
  reveal successive frontier blocks; unseen rock cannot be blindly designated.
- `artifacts/exploration-claimed-lamps.png`:six dug corridor blocks lead to local
  portal claiming and additional physical imp-installed lamps, with warm light pools.
- `artifacts/exploration-lit-rooms.png`:built Lair/PigPen, claimed-portal Grubbin arrival,
  local bed establishment and physical food; room floors remain readable in local light.
- `artifacts/exploration-loaded.png`:app replacement preserves exact revealed footprint,
  installed lamps, portal ownership and ordered worker/gold custody without resource loss.

Independent checks cover never-seen resources/rooms/actors, direct API and input
eligibility, hidden UI population cards, fog persistence after resealing passages,
local/capability/held/needs guards, unreachable work, partial progress, safe resumption,
claimed recruitment, corrupt new payloads, and validv1 ->v2 disk replacement with
exact oldbytes inbackup. Found/fixed version preflight that rejected parsed JSON
float2.0 through strict array membership; shared numeric envelope validation now
accepts supported integer-valued versions and still rejects malformed versions.
Worker tests prove provider extension, shared reservations/routes, cargo conservation,
rest arbitration and optional lamp preemption within0.25seconds.

Presentation source reviewed: no global DirectionalLight in dungeon view, small
ambient baseline, local shadowed lights, opaque homogeneous fog and explicit
hiding for tall actors/labels/food/rooms/beds/gold. Spatial terrain batches address
Compatibility per-mesh light limits. No gameplay state is created by rendering.

Version2 uses separate exploration/infrastructure state; version1 preserves old
known terrain, active portals, identities, mixed custody and economy. Existing
saved dungeons are not resized. Current game launched successfully; only the Godot
editor was running beforehand, so no user game/save was closed or overwritten.

Remaining scope: ever-explored knowledge only, no enemy line-of-sight/fog contest,
no new currency or economy balance, no Kitchen/second species/model overhaul.
Extended simulation/profiling, native OS input and exported-build gates remain open.
The user subsequently playtested and authorized commit/push of the integrated checkpoint.

## M4A manual save/load — prior checkpoint

Population-only creature overview follow-up: resident UI **45/0**, independent
keeper UI **40/0** and save integration **28/0**, no blockers in review. Future
species portraits are hidden until their first arrival; last-member removal hides
the card, while held actors remain counted. Fresh-game GPU capture
`artifacts/foundation.png` inspected: only the three-worker species card is shown,
with no zero-population Grubbin portrait. Room choices remain available. This adds
four checks to the preceding2,233 coverage (current total2,237). Focused UI and
save integration suites were rerun for this presentation follow-up.

`tools/dev.ps1 check`: **114 scripts, zero failures**. Full headless runner:
**2,232 checks, zero failures**; afterward one extra app backup-recovery assertion
passed in focused integration, bringing current coverage to **2,233 checks**.
New suites: state53, independent review106, UI22, feature-extension14, integration28.
Lead reran final state/review suites independently (53/106, zero failures).

Final GPU `tests/save_integration_tests.gd -- --render-save`: **28/0**, NVIDIA
RTX4060, Compatibility OpenGL,1280x800. Lead and independent UI reviewer inspected
`artifacts/save-loaded-queue.png`. Real Viewport F5/F9 restore a played dungeon
with Unicode names, saved camera, one Heart/portal, rooms, food, beds, excavation
orders, protected starting storage and four ordered hand entries (worker carrying23,
31gold, Grubbin,47gold). App replacement binds new views/input/HUD to the new
context, reports success and preserves frozen custody. FIFO drops and resumed
jobs/meals conserve all gold/food. A fresh app can load disk without another gold grant.
Independent UI tests exercise actual Save/Load buttons, UI isolation, suppressed
repeats/modifiers/text-edit shortcuts and bounded error/status tooltips.

Independent review covers48 entries, identity counters after removals/consumption,
repeated JSON round trips, unfinished mining strike plus loaded carrier, established
and invisible pending beds, sleepers in the hysteresis band, partial meals and
unmet hunger after food depletion, orphaned37gold, blocked food after source sale,
food pose/age/producer phase, and conservation on every continuation tick.
The unmet-hunger test exposed private appetite intent lost at load; persistent
`CreatureState.hunger_intent` now preserves it without claiming movement ownership.

Adversarial checks reject missing/unknown/malformed/duplicate IDs, versions,
terrain, room/bed/producer profiles, nonfinite values, mismatched custody/stock
and unbalanced ledgers. Validation constructs detached candidates before live
replacement. Stateful test-only mechanics round-trip through stable feature hooks;
missing/unavailable/duplicate features and invalid camera data reject clearly.
Disk tests verify exact previous bytes survive rejected writes, retained .bak,
missing-primary recovery after an interrupted rename, corrupt-primary protection,
malformed JSON, missing files and path/directory errors. App reports backup recovery.
A corrupt existing primary is preserved and must be repaired/moved before saving
over it; no automatic fallback to an older save on explicit corruption is claimed.

No autosave/cloud/multiple-slot browser, format migration, crash/power-loss durability,
large-population performance or complete Milestone4 acceptance is claimed. Temporary
routes, jobs and timed bites/strikes replan rather than resuming exact partial timing.
Native OS input/export gates remain as recorded below; engine input routing and
actual rendered state are verified. User authorized commit/push of this checkpoint;
refer to Git history for its revision.

## Unlimited mixed keeper queue — prior checkpoint

`tools/dev.ps1 check`: **101 scripts, zero failures**. Full
`tools/dev.ps1 test`: **2,010 checks, zero failures**, independently executed by
the lead. Updated suites: keeper input 104, UI 40, gold 27; new primary queue 21
and independent queue 32. All existing rule/integration checks pass.

The hand now stores an uncapped mixed FIFO array of stable custody entries.
Left-click appends eligible creatures and separate gold batches; right-click
drops exactly the oldest entry. Invalid targets retain the complete order. The
front model/amount stays unchanged when later entries are appended or another
actor is inspected. The aggregate gold ledger includes every queued batch once;
partial storage and overflow affect only the batch being dropped.

Independent scenarios queue 140 mixed entries, preserve 70 held hybrids across
feature reloads, then resume 209 gold delivery and three real meals. Head/middle/
tail deletion, raw actor-array removal, cargo recovery, per-entry Heart-less
origins, repeated same-kind batches, invalid drops and shared floor all preserve
survivor order and quantities. Original single-item rejection assertions were
updated to the user's new semantics, while duplicate-actor rejection remains.

Viewport input checks cover 21 mixed pickups and exact per-click FIFO drops with
UI/focus/stale-release protection. UI checks cover 80 entries with at most 10 rendered
cards, far scrolling, front-model stability and actual queued-card inspection
without reordering. The virtual canvas represents all entries; the draw bound is
not a gameplay capacity limit. Card rebuilds detach and queue-free controls so
the emitting GUI object can finish handling its click safely.

New GPU queue probe **18/0** and existing keeper **33/0**, Heart/gold **20/0** and
food **31/0** passed for implementer and lead (**102 graphical checks** total).
The actual Viewport queues Muck, 450 gold, Grimble, 500 gold and Grout; each drop
advances to the correct model/amount while all 950 gold remains accounted for.
A 40-actor UI fixture scrolls to entries 33–39 while retaining the first item's
pinned Next summary. Lead and independent reviewers inspected
`keeper-mixed-queue.png`, `keeper-queue-gold-next.png`,
`keeper-queue-grubbin-next.png`, `keeper-queue-second-gold.png` and
`keeper-queue-scrolled.png`. Latest target, hand and textual validity cues agree.

Independent code/behavior/input/visual reviews found no remaining blockers.
There is no count cap or same-type restriction for eligible creatures/gold; this
does not add food/landmark pickup, saving or new economy mechanics. No broad
large-world performance or native OS/export gate is claimed. The full ordered
queue and individual origins/amounts remain required future persistence state.

## Click pickup, right drop, bottom hub and Heart gold — earlier baseline

Final `tools/dev.ps1 check`: **96 scripts, zero failures**. Full
`tools/dev.ps1 test`: **1,927 checks, zero failures**. Updated suites include
startup25, keeper core44, behavior91, UI26, input90, shared-drop review32,
gold core25 and independent gold review40. Lead independently executed the full
suite and all three GPU scenarios: keeper **33/0**, food **31/0**, Heart/gold
**20/0** (84 graphical checks). Separate core, behavior, input and visual reviews
approved the final state with no remaining blockers.

The user superseded the original gestures and floating inspector: left-click
must pick up immediately, left release must not drop, and right-click drops the
held creature. Its actual model/name must identify what will be dropped. Individual
details belong inside the bottom hub. Valid connected FLOOR may be shared with
another creature or personal bed; ownership and ledger state remain unchanged.

Core drop policy changes remove occupancy restrictions. Primary core44/0 and
independent shared-drop32/0 pass, including repeated stacks of three distinct
named carriers retaining120 gold, original occupied pickup-cell drops, another
owner's established bed, two eaters sharing a service tile without duplicate
consumption, and invalid terrain/connectivity still retaining custody. Existing
keeper behavior91/0 also passes independently. The earlier gesture counts below
are historical; final correction evidence follows.

Input90 verifies immediate left-button pickup, no left-release/extra-left drop,
right-button drop and motion suppression until release, empty-hand orbit, UI and
terrain rejection, gold/creature hand exclusion, source priority and storage
overflow. Bottom-hub UI26 proves individual cycling/naming, layout at1280x800,
no floating inspector, shared-floor drop and an unchanged held model when the
inspected actor changes. Actual preview scenes read held state without modifying
it and detach old models immediately; empty hands disable the studio viewport.

Keeper GPU33 captures the exact Muck#3/60-gold model while inspecting Grout#2,
then Grout's model and the named Grubbin, with readable bottom-hub details. The
existing worker mining/haul and resident sleep/eat interruptions remain verified.
Reviewed artifacts include `keeper-held-a-inspecting-b.png`,
`keeper-held-worker-b.png`, and the updated `keeper-holding-valid.png`,
`keeper-grubbin-held.png` and resident inspection frames.

The new default dungeon has no prebuilt Treasury. Eight protected500-capacity
floor cells around the Heart hold the finite3,000 starting bank. Startup25 checks
worker mining/delivery before a Treasury, full4,000-capacity pause/spend/resume,
Treasury expansion and sale without losing protected storage, and one-time supply.
Gold core25/review40 verify loose/stored pickup, exact hand accounting, full and
partial-storage overflow, worker reservation races/reloads, source blockage,
configuration rollback, shared-hand exclusion and protected-cell build/Sell refusal.
One review test initially failed to wait for a worker's bounded retry before
claiming a reserved haul; its corrected oracle waits for a real live job and
still requires zero worker cargo before keeper pickup.

Heart/gold GPU20 uses the actual fresh-game configuration, observes3000/4000
with no Treasury, lifts500 gold, rejects invalid/UI drops, stores it again,
leaves it loose and lets an imp return it. Lead and independent reviewers inspected
`heart-storage-bootstrap.png`, `keeper-gold-held.png`, `keeper-gold-invalid.png`,
`heart-storage-deposited.png`, `keeper-gold-loose.png` and
`heart-storage-worker-return.png`. Low coin piles and worn iron/coin floor markers
keep the Heart readable. The hand shows a procedural sack/coins and exact amount.
An edge-position label/hint overlap was fixed and independently verified. All
art remains original procedural/code presentation; no new external asset was used.

Gold carried by the keeper is physical, non-spendable custody until stored. A
storage drop accepts free capacity and leaves overflow loose; ordinary valid floor
gets a loose pile. No wages/payment, food pickup or recurring Heart income exists.
Legacy fixed-Treasury probes explicitly opt out of the new bootstrap; they do not
describe the actual start. No native OS input, export, save or stress/performance
gate is claimed by this checkpoint.

## Keeper custody, inspection and two-tile Pig Pens — earlier baseline

Final `tools/dev.ps1 check`: **91 scripts, zero failures**. Full
`tools/dev.ps1 test`: **1,783 checks, zero failures** (earlier1,571 plus core42,
keeper behavior91, input59 and UI20). The lead executed the integrated suite.
GPU keeper probe **25/0** and updated food probe **31/0** independently passed
for implementer and lead. Separate core, behavior, input and UI/visual reviews
found no remaining blocking issues.

The package adds one held creature and a conditional inspection panel, without
replacing the actor or removing its gold from the ledger. Pickup/drop synchronously
release old behavior paths/jobs. Established beds survive; pending claims and
meal reservations are released. Held needs, movement and work freeze, and dropping
creates fresh behavior from the validated new position. Food cannot be consumed
by a held creature or disappear as an interrupted meal is canceled.

Primary core checks cover live IDs, eligibility, bounded naming, single custody,
floor/Heart/portal/boundary/connectivity rules, other actors/beds, revalidation after
terrain changes, established/pending home ownership and actor removal. A separate
ambient feature also proves the custody contract works outside worker/resident
modules. Independent review found raw removal of a held carrier could lose its
untracked cargo; KeeperState.prune now retains it idempotently in the recovery
ledger, with passing raw-removal and repeated-cleanup regressions.

Behavior scenarios interrupt stone/gold/gem strikes, hauling, local eating, sleep
and pending home claims. They exercise repeated handoffs, hybrid workers,
feature reloads, unavailable food/routes and held-actor despawn. Worker recovery
adopts pending cargo even when pickup removed the actor's previous behavior.
Inspector tests send actual Viewport events to edit names, press Pick Up, close
details while holding and attempt invalid/valid drops without leaking into terrain.
Input checks also cover sixteen awake/sleeping camera combinations, nearer actors,
wall occlusion, stationary actor/terrain updates, six-pixel pickup threshold,
focused G text entry, tool refusal while held, UI/focus/orbit/tool cancellation
and stale press IDs. Review found actor hover could suppress an existing terrain
drag preview; the helper now suppresses only idle actor hover, and two Viewport
regressions verify rectangle preview and commit across a creature.

Actual GPU gameplay mined a carrier's60 gold, inspected/renamed it, lifted it,
rejected a solid-tile drop and restored its original visible model on valid floor.
The workers then delivered all400 gold from the two marked seams. A resident
arrived, claimed a bed, slept and ate; pickup froze needs, retained its established
bed and released an interrupted exact meal without a debit. Removing the held
resident cleared custody/inspection. Gold/food were accounted throughout.

Lead and independent reviewers inspected `keeper-worker-inspection.png`,
`keeper-holding-valid.png`, `keeper-holding-invalid.png`,
`keeper-worker-dropped.png`, `keeper-resident-inspection.png`,
`keeper-grubbin-held.png`, `keeper-eating-interrupted.png` and
`keeper-held-removed.png` in local ignored `artifacts/`. The focused panel is
closable and capability-aware, the gripping portrait matches the hidden actor,
and green/red drop cues have explicit text. No permanent sidebar was restored.
Assets remain original code-drawn/procedural presentation, not final hand art.

The user's Pig Pen change supersedes the earlier 3x1 rule: current minimum is
2x1 or rotated 1x2, with one pig per two connected tiles. Actual manifest tests
and Viewport build/tooltip checks verify the new rule; independent producer tests
retain other minimum sizes to exercise configurable extension behavior.
The updated food GPU probe builds `pig-pen-minimum-2x1.png`, extends to six tiles
with capacity3, observes one pig visit all six cells, repeated meals/rest and
conservation (five produced, four consumed, one remaining in the recorded run).
The game still starts with3,000 stored gold; mining-only GPU fixtures opt out.

No native OS input, save/load, audio, export, new performance/stress gate or
Blender asset authoring is claimed by this package. Held needs freeze, and
interrupted tasks replan with reset progress. A single hand/first Grubbin remains
the prototype limit; mood, broader attraction and a second species are still open.

## Pig Pen food loop and funded playtest start — earlier baseline

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
