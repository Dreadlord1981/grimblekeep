# Grimblekeep — shared development checklist

Status: unlimited mixed keeper-hand FIFO queue accepted, extending verified controls, hub and protected Heart storage (2026-11-15). Full pet-dungeon milestone remains open.
Updated: 2026-11-15

## How to use this plan

- User authorized keeper-hand pickup/drop and creature inspection, preserving creature jobs and gold/food. Also change Pig Pen minimum/density from 3x1 to 2x1 (or rotated), one pig per two tiles. Saving, wages, crafting, combat, XP, second species and cooking remain separate packages.
- Read this file and `AGENTS.md` before starting work.
- Work toward the current milestone. Keep the game playable as systems are added.
- Use `[ ]` for pending work and `[x]` only for work verified against its acceptance criteria.
- Record an active assignment below before parallel work begins. Give each assignment clear ownership, interfaces and a reviewer.
- Update this plan after accepted work. Record what was tested, remaining problems and the next action in the handoff.
- Keep new feature ideas in the backlog; do not silently expand the milestone.

## Agreed vision

- Original Dungeon Keeper-inspired real-time dungeon management game for desktop PC.
- Godot and GDScript; no Rust requirement.
- True perspective 3D, with camera rotation, pan and zoom. An elevated management view and closer inspection must both work.
- Fun, expressive creatures; gritty stone, worn materials, torchlight and eerie magic; dark, twisted humor.
- Begin with coherent retro 1990s-style low-poly graphics, small textures and simple animations. Upgrade presentation later.
- Restrained mouse-and-keyboard HUD with readable information and shortcuts.
- An animated keeper hand is the primary world cursor: it points out excavation targets and lets the player pick up and drop creatures to guide them. Give it an original design matching Grimblekeep's gritty cartoon style.
- Default click/drag on stone, gold or gem blocks toggles excavation marks directly; there is no separate generic selection or Hand/Dig/Inspect mode. Open ground is eligible for the explicit room construction action. Marks glow across block tops and exposed sides, with green plus/red X previews for additions/removals.
- Core loop: excavate, mine gold, build rooms on open floor, attract creatures through portals, meet their needs and expand. There is no separate claiming step.
- The Dungeon Heart anchors the keeper's presence and forms the dungeon's central landmark. Begin with its chamber, a few worker imps and nearby mineable gold.
- Keep the Heart separate from the portal: the Heart sustains the dungeon; the portal admits creatures. The Heart does not generate free gold or food.
- Heart art direction: an exaggerated beating heart suspended in rusty chains above a stone basin, surrounded by candles and pipes. Use gritty cartoon materials and dark humor, such as an imp mopping up an unpleasant leak.
- In the pet dungeon, the Heart provides atmosphere through its pulse, animation and sound. Later, it reacts urgently to threats and its destruction becomes the defeat condition when combat is introduced.
- Initial economic resources: gold and food. Gold is mined and hauled into a treasury; food exists in a producing room and is eaten by creatures.
- Stone is excavated terrain. Wood may appear in props. Neither is an inventory currency.
- No idle/mobile economy, premium currencies, reward popups, waiting timers or time acceleration controls. An ordinary pause/menu is fine.
- Creature arrival and production may use internal simulation timing; these are world behaviors, not player-facing countdowns.

## First playable scope: the pet dungeon

One small sandbox dungeon containing a central Dungeon Heart chamber, worker imps, two resident creature species, one separate portal, a treasury, a lair and a food room. Workers excavate and haul gold. Residents arrive when room requirements are met, explore, eat and sleep. The player can inspect creatures, guide them with the keeper hand and save/load the dungeon. The Heart beats and establishes atmosphere; attack, destruction and defeat mechanics wait until the combat milestone.

Combat, invading heroes, research, spells, traps, campaigns, multiplayer and elaborate manufacturing chains are outside this first scope.

## World and lore checkpoint — after the playable foundation

- [ ] Complete the world-building discussion with the user. First Grubbin/Lair and specialist-community direction agreed; keeper, Heart meaning and wider world remain open in `LORE.md`.
- [ ] Establish who the keeper is, what the Dungeon Heart means and why this dungeon exists.
- [ ] Decide where portals lead, why creatures choose to arrive and what life underground is like.
- [ ] Define the surface world and its view of dungeon inhabitants, including the motives of future invading heroes.
- [ ] Establish the balance of menace, affection and twisted humor, with examples that guide names, dialogue, props and creature behavior.
- [x] Capture the approved Grubbin/Lair and specialist-community direction in `LORE.md`, with open world questions separated. Later canon still needs discussion.

Until then, use provisional names and replaceable content. Foundation work can proceed once authorized; avoid inventing permanent lore or commissioning substantial narrative-dependent assets before this checkpoint. Lore should explain and enrich the agreed mechanics; any new gameplay scope needs a separate decision. Begin with a concise premise and world rules rather than a full campaign history.

### Creature lore structure — use for each species at the lore checkpoint

- [ ] Origins: what the creature is, how its kind came to exist, its homeland and natural habitat.
- [ ] Culture: beliefs, customs, social habits, rivalries and relationships with other species and the surface world.
- [ ] Motivation: why it leaves home, travels through a portal and chooses to live in the keeper's dungeon.
- [ ] Needs and talents: preferred food, sleeping arrangements, room conditions, useful abilities and sources of discomfort or trouble.
- [ ] Personality in play: how its background appears in its silhouette, movement, possessions, animations and everyday behavior; allow individual variation within a species.
- [ ] Humor: characteristic contradictions, anxieties or customs that produce Grimblekeep's dark humor naturally.
- [ ] Gameplay connections: identify which attraction rules, room preferences and existing behaviors express this background. Mark proposed mechanics as ideas until separately approved.
- [ ] World consistency: check connections to the shared world, Heart, portals and other species; distinguish agreed canon from provisional ideas in `LORE.md`.

Begin with worker imps and the two initial resident species. Make this small cast memorable before expanding it. Review each species for a clear origin, a believable reason to join the dungeon and observable personality. Lore descriptions do not mark unimplemented behavior complete or authorize additional simulation systems.

## Creature, job, behavior and progression systems

- [x] Initial creature system: stable species definitions, individual identities/state and capabilities. Future needs, levels and experience remain separate work.
- [x] Initial worker job system: discovers marked work, reserves workers/work positions, checks reachability, releases canceled/unreachable work and offers follow-up tasks as the dungeon changes.
- [x] Initial worker behavior system: executes walking, working, carrying, depositing and idle behavior using explicit state transitions; presentation reads this state rather than deciding gameplay. Generic resident needs/behaviors remain later work.
- [ ] Work progression follow-up: monsters earn experience from completed useful work and can level up. No experience for idling, failed/canceled actions or duplicated completion events.
- [ ] Define data-driven XP thresholds, level limits and modest work-related benefits; show level/XP/current job when implemented. Test exactly-once rewards, thresholds and interrupted work before accepting progression.

User sequencing: record these systems now, finish mining/digging first, then implement work-based progression as a focused package. Current workers need job and behavior separation; they do not need an XP system to begin excavating.

## Work and review flow

1. Lead defines a small work package: objective, owned files, interfaces, acceptance criteria and verification method.
2. Implementer completes the package and runs relevant checks.
3. A different agent reviews behavior, code or assets against the package and this vision. Findings have severity and concrete evidence.
4. Implementer resolves findings; reviewer verifies material fixes.
5. Lead integrates the result, checks the playable scenario and updates this checklist with evidence.

Use available agent slots for focused engineering, review and art tasks as needed. Do not require every role to run simultaneously. Avoid concurrent edits to the same files; agree on shared interfaces before parallel implementation. Agent approval is supporting evidence, not a replacement for running the game.

## AI development loops — required once implementation starts

These loops turn the vision into observable acceptance checks. They reduce errors and drift; they cannot guarantee fun, flawless art or a commercial-quality game. The user authorized foundation implementation on 2026-11-15. No background automation or additional service is enabled by this document.

### A. Work-package loop: define, build, verify, review, repair

1. Read the current milestone, relevant code, existing changes and latest handoff. Establish the starting behavior before changing it.
2. Define one small package using the template below. Identify dependencies and agree on interfaces before parallel work.
3. Implement the smallest complete behavior. Use placeholders where the milestone permits them.
4. Run focused tests and the relevant playable scenario. Inspect actual outputs; collect failures and enough evidence to reproduce them.
5. Have a different agent review the changes against the package, failure cases and agreed vision. Give the reviewer the requirements and evidence, not just the implementer's explanation.
6. Fix findings, rerun affected checks and have material fixes reviewed again. Return to implementation only for a concrete failure or unmet acceptance criterion.
7. Integrate only after the package gate passes. Record the result and evidence before marking its checklist item complete.

Package template:

- ID / milestone / objective:
- Implementer / independent reviewer / owned files:
- Dependencies / agreed interfaces:
- Acceptance checks: observable behavior, relevant failure cases and expected outcomes.
- Verification: commands, scenario, seed where useful, visual checks and performance limits where applicable.
- Effort boundary: small deliverable and repair/inspection budget agreed by the lead before starting.
- Evidence: tested revision or file state, command exit/results, scenario observations and artifact paths.
- Findings / fixes / remaining limits:
- Status: pending, active, in review, needs repair, accepted, or blocked with a concrete reason.

### B. Gameplay loop: prove the dungeon behaves correctly

- Start with a small reproducible scene; exercise the normal path and the highest-risk interruptions.
- Add meaningful regression checks for discovered bugs. Do not merely restate the implementation in a test.
- Use headless tests for rules and simulation, and graphical runs for targeting, controls and visual behavior.
- Inspect real player inputs as well as scripted scenarios. Internal API calls alone do not prove that a player can perform an action.
- Once focused checks pass, verify affected integrations. Broaden testing when a dependency, failure or unresolved risk warrants it.

Required scenarios as their systems become available:

| Scenario | Observable acceptance evidence |
| --- | --- |
| Starting dungeon | One central Heart chamber, a separate portal, workers and accessible gold; correct perspective camera and readable selection. |
| Dig, mine and build | Player marks terrain with the hand; workers excavate and haul; treasury receives deposits; construction spends exactly the intended stored gold. |
| Interrupt a worker | Pick up a carrying worker, block a route or remove a target; no duplicated/lost gold, stuck job or leaked reservation. Record any deliberately dropped cargo as world state. |
| Room attraction | A species stays ineligible until its room/capacity rules are met; eligible arrivals use the connected portal and do not exceed capacity. |
| Living residents | Observe repeated eating/sleeping cycles, competition for beds/food and recovery from target removal; needs and task displays agree with behavior. |
| Keeper hand | Hover, mark/cancel, pick up and valid/invalid drop work across camera views; UI clicks do not trigger world actions. |
| Save and resume | Save during active work and while a creature is held; loading preserves the Heart, rooms, resources and needs and restores sensible activity. |
| Extended operation | Seeded simulation and a graphical session show no accumulating errors, permanently stuck actors or unbounded growth; record population, map size and elapsed simulation time. |

For gold, account explicitly for unmined, carried, dropped, stored and spent amounts against the initial total, gem output and explicit sale refunds. Starting rooms also have salvage value. For food, account for production and consumption. The Heart and portal create no free economic resources. Verify these properties across interruption and save/load scenarios.

### C. Asset loop: brief, create, import, inspect, revise

1. Brief the asset against the agreed style, camera distance, world scale, silhouette, animation needs and technical budget. Reference approved visuals; generated screenshots are targets, not proof of attainable runtime quality.
2. Produce a small representative sample before expanding a creature family or room kit. Record provenance and import settings.
3. Import the asset into Godot and inspect it alongside existing content under actual dungeon lighting, at overview and close camera distances.
4. A different agent reviews shape, palette, material wear, scale, pivots, clipping, animation, readability and technical cost. Use rendered frames and motion evidence for animated assets; inspect sound in playback when audio tools permit.
5. Revise specific failures and recheck them. Accept only when the asset serves its gameplay role and fits the current milestone's fidelity.

Preserve the expressive gritty cartoon direction, even with retro graphics. Do not approve attractive isolated renders that become unreadable in play. Do not claim animation or audio was reviewed if the available tools could not inspect it; record the missing check.

### D. Integration and milestone loop: prove the complete experience

1. Lead integrates reviewed packages in dependency order and runs the milestone scenario through real game controls.
2. Inspect the current rendered game against the vision: perspective depth, readable rooms/creatures, restrained desktop HUD, physical gold/food, keeper hand and distinct Heart/portal.
3. Check relevant performance on a recorded machine and workload; record measurements rather than inferred speed. Define numerical budgets before claiming a performance gate has passed.
4. Classify defects and send actionable failures back to the responsible package loop. Preserve repro steps and evidence.
5. Accept the milestone only when its listed checks pass. For the final vertical slice, verify the exported Windows build as well as the editor run.

Blocking findings include crashes, data loss, duplicated resources/creatures, broken core progression, unusable controls, or material departures from the agreed vision. Minor polish findings may remain explicitly tracked if they do not prevent the milestone goal. Never weaken acceptance checks or move required work to the backlog just to declare completion.

### Repair limits, continuity and escalation

- After three unsuccessful repairs of the same issue, stop repeating the patch. Reproduce it in isolation, re-examine the design and obtain a fresh reviewer diagnosis before further changes.
- Work within the package effort boundary. If it is exceeded, record evidence and replan the smallest in-scope deliverable; leave the package incomplete if required checks remain unmet.
- Resolve routine implementation decisions autonomously within the agreed scope. Request user direction only when a missing choice, new authority or scope change prevents safe progress.
- A reviewer finding must identify a violated requirement, observable defect or concrete maintenance risk. Avoid endless subjective polishing once the agreed fidelity is met.
- At session or agent handoff, record current package, file/revision state, passed/failed checks, evidence locations, outstanding findings and the next executable action. Resume from this record.
- Keep test acceleration inside test tooling; it does not authorize player-facing speed controls. Creature AI remains local gameplay logic; these development loops introduce no runtime LLM dependency.

## Milestones and acceptance gates

### 0. Planning and tooling — complete for local development

- [x] Record vision, scope, milestones and review workflow.
- [x] Document AI development loops, package/evidence requirements, repair limits and milestone acceptance rules.
- [x] Verify installed Godot executable and usable local test commands from this project directory.
- [x] Confirm export-template availability and graphics-capable test execution: GPU run passes; templates are absent, so standalone export remains pending for Milestone 5.
- [x] Establish art budgets, camera scale and a small set of visual references before asset production (see `docs/ARCHITECTURE.md` and `docs/references/`).
- [x] Obtain the user's go-ahead to begin game implementation (2026-11-15).

Gate: agreed scope, working toolchain and explicit implementation authorization.

### 1. Playable foundation — verified locally

- [x] Create the Godot project, folder conventions and reproducible launch/check commands.
- [x] Build a small grid-based 3D dungeon with solid rock and open floor.
- [x] Establish the starting Heart chamber with a placeholder pulsing Dungeon Heart, a few workers and nearby gold; leave an accessible route for expansion.
- [x] Implement perspective camera pan, rotation, zoom and floor selection.
- [x] Add a placeholder keeper hand cursor with clear hover/pointing feedback on world targets; UI interaction must not trigger world actions.
- [x] Support rectangular tile drag selection, click toggling, additive/removal modifiers and clearing selection; HUD panels must not leak selection or leave a stuck drag. Default click/drag toggles every affected tile and preserves selection outside the area.
- [x] Default keeper-hand marking accepts stone, gold and gems and rejects open floor/landmarks, with no mode split. Green plus/red X hover/drag previews and footer counts show exact changes; persistent amber glow covers tops and exposed sides.
- [x] Show an animated placeholder creature at correct world scale.
- [x] Add a diagnostic scene and basic error logging (main scene, F3 overlay and validation/test runners).

Gate: project launches without script errors; camera and selection work at different angles and zoom levels; the Heart reads as the central landmark and is visually distinct from the portal; a rendered capture has been inspected.

Evidence: `docs/VERIFICATION.md`; 28 scripts validated and 128 checks passed after default excavation/glow follow-up. GPU captures inspected at overview and close distances, plus mixed preview and top/side glow views. Native desktop automation failed to initialize; physical input feel still needs manual observation, while Godot Viewport input routing is tested.

### 2. Workers and construction — verified locally

- [x] M2A: marked stone becomes walkable floor, finite gold is mined into physical cargo/piles and deposited in a small starting treasury. No room-building interface is required for this package.
- [x] Mark accessible rock for excavation; workers reach it and dig.
- [x] Use the keeper hand to mark/cancel excavation targets, with distinct valid, selected and blocked feedback at different camera angles.
- [x] Excavated floor is immediately walkable and eligible for rooms; no separate claiming job or ownership requirement (user simplification).
- [x] Mine finite gold seams and haul carried gold into treasury storage. Gold nodes hold 200; workers extract 20 per strike, carry up to 60 and deposit physically. Gem nodes yield gold more slowly and remain in place.
- [x] Use eight-direction A* with weighted distance costs, strict no-corner-cutting, revision-aware navigation and mid-route edge revalidation. Workers move at equal world speed; mining remains cardinal-adjacent.
- [x] Allow up to four miners per gold/gem node, one per reachable cardinal side, with shared yield accounting and individually releasable reservations. Stone and loose piles remain exclusive.
- [x] Build room tiles with clear drag preview, validity and exact cost. Existing tiles never toggle off; only explicit Sell mode removes them, with 50% refund shown before release.
- [x] Recognize connected rooms and handle merging/splitting and capacity changes.
- [x] Store gold per Treasury tile (500 each), balance worker deliveries, show pile/small/large chest stages and preserve local stock/refunds when selling or reducing capacity.
- [x] Handle unreachable jobs, blocked routes and interrupted worker excavation/hauling without duplicate rewards; regression coverage includes cargo recovery when actors disappear and treasury access changes.

Gate: a scripted scenario excavates a route, deposits gold and constructs a room; checks cover room changes, spending and job ownership.

Evidence: 48 scripts validate and 870 automated checks pass, including 42 room rules/end-to-end mining/building, 33 finite-storage worker checks, 40 construction input checks and 97 independent room/refund checks. GPU room probe passes all 11 flags; lead and independent reviewers inspected the room, gold-stage, build and Sell captures. Native physical input remains unverified as recorded in `docs/VERIFICATION.md`.

### 3. Living pet dungeon

- [x] M3A: one Grubbin can arrive through a reachable portal after a fitting personal Lair bed becomes available, explore, tire, sleep and wake repeatedly. Species data supports larger footprints; first Grubbin population is capped at one for this prototype.
- [x] Add recognizable room floor and rock-wall dressing, original procedural Grubbin/cots, icon-led room choices/creature cards and safe right-click Build/Sell cancellation. Preserve mineral readability and amber excavation top/side glow.
- [x] M3B: build Pig Pens; M3C user correction changes minimum to 2x1 (or rotated) and one pig per two connected tiles. Pigs grow, roam their fenced enclosure, meet hungry Grubbins locally and are consumed exactly once. Preserve food through room edits and verify repeated eat/rest cycles with independent code/visual review.
- [ ] Define rooms and species through data with explicit attraction requirements.
- [ ] Spawn residents through a connected portal only when requirements and capacity allow.
- [ ] Implement full hunger/energy/mood action choice. Hunger, energy, rest and work arbitration are verified; mood remains pending.
- [x] Complete target reservation across beds and food, including exact food identity, physical meeting, release and interruption recovery.
- [x] Complete basic food production, eating and sleeping for the first species, with repeated cycles and conserved stock. Cooking and richer needs remain separate work.
- [ ] Add two species with distinguishable silhouettes, preferences and behavior.
- [x] Inspect/name creatures and display their current action and supported needs/cargo/bed in a focused closable panel.
- [x] Pick up eligible friendly creatures with the keeper hand and drop them on valid accessible dungeon floor; invalid drops keep them held and show why.
- [x] Suspend movement/jobs/needs while held, release stale reservations and resume sensible behavior after dropping; prevent duplicate creatures and recover held-creature removal/cargo safely.
- [ ] Persistence follow-up: save/load held identity, names, cargo and safe resumption with the rest of the session in Milestone 4. No save behavior is claimed by M3C.

Gate: expanding the dungeon changes which species can arrive; residents repeatedly satisfy needs without starvation loops, reservation leaks or becoming stuck. Keeper-hand pickup/drop works across camera views, respects placement rules and leaves creature/job state consistent.

M3A evidence: 59 scripts validate and 1,039 checks pass (including 24 bed contracts, 89 resident behavior checks, 20 resident UI checks and 32 independent edge cases). GPU probe passes 20 boolean conditions plus two full sleep entries/wake/recovery, with Viewport construction and inspected walking/sleeping/awake/departure frames. M3B adds verified hunger/food and the funded start. M3C final evidence: 91 scripts, 1,783 headless checks, keeper GPU25/0 and updated food GPU31/0. Full Milestone 3 remains open: mood, second species and broader attraction are pending; persistence follows in Milestone 4.

### 4. Persistence and robustness

- [ ] Save/load terrain, rooms, stored/carried gold, food, creatures and needs.
- [ ] Preserve the Heart's location and its chamber through save/load without duplicating or losing the central landmark.
- [ ] Version the save format and handle invalid saves without overwriting a valid save.
- [ ] Verify a save round trip and resumption of sensible jobs after loading.
- [ ] Run a seeded extended simulation covering excavation, arrival, eating and sleeping.
- [ ] Measure frame time and simulation time against a recorded reference machine, map size and population.

Gate: test results and measured performance are recorded; no unresolved critical progression or data-loss defects.

### 5. Cohesive retro vertical slice

- [ ] Replace placeholders with consistent low-poly creatures, modular rooms and props.
- [ ] Add readable animation, lighting, sound and interaction feedback.
- [ ] Give the Dungeon Heart a distinctive pulse, restrained sound and gritty cartoon chamber dressing; verify its readability from overview and close inspection views.
- [ ] Polish keeper hand idle, pointing, grabbing and release animations; verify target visibility, cursor responsiveness and readable feedback at gameplay scale.
- [ ] Review assets together at actual gameplay distance and during movement.
- [ ] Polish desktop HUD, shortcuts, camera occlusion and a short introduction.
- [ ] Export a Windows build and run the exported build through the complete pet-dungeon scenario.
- [ ] Install the matching export templates before producing the standalone Windows build (not required for editor/local runs).
- [ ] Complete independent code and visual reviews, fix release-blocking findings and record known issues.

Gate: exported build supports the complete loop with cohesive presentation, reliable saves and recorded test evidence. This is a vertical slice, not a claim of commercial release readiness.

## Quality rules

- Keep simulation state separate from rendering; assets should be replaceable without rewriting game rules.
- Organize code by responsibility: core state/contracts, content definitions/features, presentation, interaction, UI and tests. Document dependency direction and extension examples in `docs/ARCHITECTURE.md`.
- Add creatures and rooms through stable-ID data definitions and optional scenes. Add mechanics through explicit feature modules with lifecycle/context/events, without editing core dispatch switches for each new species or room.
- Avoid a monolithic controller, hard-coded node paths between unrelated systems and speculative framework machinery. Shared interfaces belong to the lead; changes require dependency review.
- Review new definitions for duplicate IDs, invalid values and missing references. Prove extension boundaries with a small test module, not only architecture prose.
- Code review must check module boundaries, readable names, small focused functions, deterministic testability, error handling and preservation of existing behavior. New mechanics may extend contracts deliberately when needed; do not promise that core will never evolve.
- Maintain one clear source of truth for room membership, gold, needs, capacity and reservations.
- Tool eligibility belongs in authoritative selection/command rules. Preview symbols and counts must match the operation committed on release, including mixed toggles and modifier changes; do not rely on color alone for removal feedback.
- Prefer simple systems with explicit responsibilities. Profile before introducing complex optimizations.
- Use tests for consequential rules and failure cases; inspect rendered output for visual correctness. Headless success alone does not verify graphics or controls.
- Assets must pass silhouette, scale, palette, texture, animation and import checks. Record their source/license or generation provenance.
- Reject visible generation artifacts, unreadable creatures, inconsistent materials and mobile-style interface elements.
- Report observed results honestly. Separate measured performance and tested behavior from estimates and untested assumptions.

## Active assignments

- M3C-queue accepted: lead implemented stable KeeperHandItem entries, ordered KeeperState, per-entry pickup origins and partial aggregate gold transfers; input agent enabled appending world/G pickups and FIFO right drops; UI agent added virtualized queue cards/pinned next summary and front-entry model binding; behavior reviewer independently exercised mixed FIFO and recovery. No gameplay count cap or same-type restriction. Invalid drops retain all order; duplicate physical actors cannot be queued twice. Queued creatures freeze/resume individually; gold remains in the ledger and each right-click debits only its own batch. Current core queue21, independent queue32, input104, UI40 and gold27/review40 all pass, including140 mixed entries, removal of head/middle/tail, reloads, resumed209 gold/3 meals, distinct gold batches and Heart-less origins. UI renders at most10 cards while scrolling all authoritative entries; a 40-entry GPU fixture proves later entries remain accessible. Actual queue-card inspection preserves order/model; card disposal safely detaches then queue-frees. Final check101 scripts/0, full test2,010/0, queue GPU18/0 plus keeper33/food31/Heart-gold20 all independently rerun by lead. Independent core/input/visual reviews approved. Existing creatures/gold only; no new economy, food/landmark pickup or saves.

- M3C-gold accepted: root implemented gold custody in the ledger, protected-capacity merging, room protection and Heart bootstrap; input agent added gold mouse controls; UI agent added the gold sack/amount and protected-floor art; behavior reviewer verified worker competition, storage edits, startup and conservation. Fresh games have eight protected 500-capacity floor cells around the Heart, 3,000 initial gold and no prebuilt Treasury. Loose/stored gold shares the single hand with creature custody; storage drops fill available capacity and retain overflow loose. Heart cells cannot be sold/built over, and player Treasury expansion/sales preserve them. Final check 96 scripts/0, full test 1,927/0; core gold 25, independent gold 40, updated startup 25, all zero failures. Actual default bootstrap/gold GPU 20/0 proves pickup, UI/terrain rejection, deposits, loose drops and worker recovery. No wages or food pickup implemented.

- M3C-controls accepted, superseding initial gestures/layout: left-click picks up immediately, left release never drops, right-click drops. Empty-hand RMB orbit/Build cancellation remain. Shared valid floor includes other creatures/beds without changing their identities or ownership. Individual details are inside the bottom hub; species portraits cycle members for inspection, with I on a hovered creature as an alternative. The isolated 3D hand preview follows the held actor's exact identity/name/cargo even while another actor is inspected, and switches cleanly between species and gold. Core 44, input 90, UI 26 and independent shared-drop 32 checks pass. Keeper GPU 33/0 demonstrates distinct named workers and Grubbin models, inline details and safe task resumption. Independent code/visual reviews approved; top-edge label overlap was repaired and verified. One custody object at a time; no save implementation.

- M3C accepted: lead implemented KeeperState/actor contracts, drop validation, core42 checks, sample-module compliance and density correction; simulation agent implemented synchronous suspension/fresh resumption with91 checks; input agent separated geometry/gesture helpers with59 Viewport checks; UI/presentation agent implemented the focused inspector/held view with20 UI checks and25 GPU checks. Final91 scripts/0, full1,783 checks/0. Updated food GPU31/0 proves2x1 minimum,6tiles/3pigs and continuing growth/roam/eat/rest. Click inspects, drag picks/releases, G/button lifts for click-to-drop. Actor identity/cargo/established bed survive; active jobs/meals/pending claims release; held behavior/needs freeze. Invalid, UI and canceled drops retain custody. Independent core/input/behavior/visual reviews approved. Repaired raw held-removal cargo loss and excavation preview disappearing over creatures, with regression evidence. GPU hauled all400 seam gold after relocating a60-gold carrier and interrupted actual sleeping/eating safely. No new assets beyond original code-drawn UI; Blender remains available for future work. Scope respected: one held creature, existing species, no saving, combat or new production chain.

- M3B accepted: lead implemented food definitions, ledger, stable units/age, source pools, production and schema/docs; behavior agent implemented hunger/local-meal arbitration; presentation agent implemented confined authoritative pig roaming, growth views, perimeter fences and GPU evidence; HUD/reviewer agent implemented food status/icons and independent tests. Minimum 3x1 or rotated 1x3 before births, one pig per three connected tiles, one birth per 12 seconds until full. Piglets grow over 30 simulation seconds and roam their connected enclosure; a reserved pig and eater must meet before timed eating. Stock and exact identities survive selling/shrinking, feature/view reloads and blocked routes. Food/work/rest priorities and alternate food/producer extensions pass review. Final 82 scripts and 1,571 headless checks pass; GPU31/0 includes all six pen cells visited, newborn/juvenile/adult views, three meals/two trips and rest/wake. Independent code/visual reviews approved, including repaired meal reachability and food-type component-cache bugs. User's later 3,000-gold request is accepted: finite bank in six Treasury tiles, 17 startup/conservation/mining checks, default GPU capture inspected. Blender user environment and background Python verified. Effort boundary respected: no cooking, mood penalties, wages, combat or complex chain. Growth changes appearance, not nutrition. User corrected the temporary 3x3 minimum to 3x1; latest instruction prevails.

- Bedrock accepted: lead added solid terrain classification and scenario border/pattern helpers; presentation agent implemented distinct layered bedrock with matching raised picking surface; independent reviewer ran 73 rule/Viewport checks; UI agent replaced the gem-like Lair icon with a clear bed. Full suite1,249/0, scripts64/0; bedrock GPU15/0 and icon capture pass. Core/visual reviews approved marking/building protection, worker cancellation/conservation, A*, portal/bed access, atomic authoring helpers and unchanged starting routes/resources. Effort boundary respected: terrain/helpers and icon correction, no map editor or new systems.

- Full-Treasury follow-up accepted: worker agent gated mineral-job discovery and active strikes on reachable free storage, retained orders/cargo and verified automatic spending/expansion resumption; stone digging continues. 60 focused checks pass, including hybrid rest/home-making while storage is full. Missing-storage and shared-workplace fixture expectations were updated to the user rule. Lead independently reviewed code and executed the integrated suite; no blockers remain.

- M3A-local-bed/hub accepted: lead added pending/established bed contract and authoritative proximity enforcement; simulation agent implemented immediate home travel and local claiming; presentation agent hides pending beds and verified actual formation; UI agent supplied a focused tabbed hub, count overlays and F3-only details. Bed contracts31/0, resident118/0, UI41/0, construction input47/0, independent resident review49/0. GPU26flags true plus two sleep entries. Pending space is exclusive but invisible, healthy creatures visit it first, remote/displaced/stale claims fail, and established rest/worker priority survives. Creatures is default; Rooms counts connected groups with actual tile/gold/bed tooltips. Old sidebar/footer text removed. Independent reviews and lead visual inspection approved. Effort boundary respected: requested corrections only.

- M3A accepted: lead implemented bed contracts, content/profile extensions, work/rest priority, lore/reference and docs; simulation agent implemented resident arrival/rest with 89 checks; UI agent implemented original SVG icons, compact cards, right-click cancellation and 20 UI/44 room-input checks; presentation agent implemented Grubbin/cots/room art and 32 independent edge checks. Full suite 1,039/0, scripts 59/0. GPU 20 flags true plus two sleep entries. Independent code and visual reviews approved; repaired wall-art occlusion of excavation glow and sleeping/waking cot alignment. One species/rest loop only; active food/wages/crafting not started.

- M2C multi-side mining — accepted: side reservations for up to four gold/gem miners, 52 focused checks and four-miner GPU capture verified. Independent review approved shared yield, reachable faces, cancellation, depletion, replacement and global workplace conflicts.
- M2B A* and diagonal movement — accepted: native octile A*, strict corner rules, weak revision cache, movement edge validation and weighted job choices. Independent Dijkstra/worker regression suite passes 366 checks. Full suite 658/0, scripts 40/0; GPU worker scenario confirms diagonal travel and 400 gold deposited without loss. Independent review approved.
- M2A worker excavation/mining — accepted: core path/economy contracts, separate job board/behavior module, worker animation/cargo, loose gold/treasury and real HUD complete. Independent review approved; 240 checks pass and 37 scripts validate. GPU scenario dug stone and deposited exactly 400 finite gold with conservation checked every tick. Leveling remains follow-up per user sequencing.
- F1 core/tooling — accepted: lead implemented explicit contracts, validated module registry, replaceable scenario/feature, test runners and architecture docs; core 32 checks pass.
- F2 world presentation — accepted: world-view agent implemented procedural batched terrain and landmarks/actors; GPU captures inspected and mesh winding repaired.
- F3 interaction/UI — accepted: interaction agent implemented camera, accurate targeting, hand/HUD and user-requested multi-tile toggling; targeting 37, selection 14 and full-scene integration 10 checks pass.
- F4 independent review — accepted for M1: separate reviewer ran the suites, checked architecture/visuals and rechecked fixes to picking and script-validation failures; no code blockers remain. Native automation limitation is documented.
- F5 tool split — superseded by the user's clarification: remove separate Hand/Dig modes and generic ground selection. Keep the add/remove preview work.
- F6 default excavation and glow — accepted: authoritative marks on stone/gold/gem, mode UI removed, terrain-change cleanup, amber glow on tops and sides. Core 38, targeting 49, input 31, integration 10 pass (128 total). Lead and independent reviewer inspected mixed preview and top/side glow captures. Reviewer-noted stationary terrain-change preview gap fixed with regression checks. Worker execution remains Milestone 2.
- M2D accepted: lead implemented core room state/registry, physical capacity and spending/refunds, scenario and docs; input agent implemented Build/Sell controls and 40 Viewport checks; worker agent implemented balanced finite hauling with 33 checks; presentation agent implemented generic rooms and per-tile gold stages, plus 97 independent rule checks. Independent reviews approved core, controls, worker behavior and rendered output. Full suite 870/0, scripts 48/0; GPU all 11 flags true. The user's removal of claiming and explicit Sell-only/50% decisions are implemented. Effort boundary respected: Treasury only; Lair/food are future roles.

### Starter room direction (provisional)

- Treasury: build now; costs stored gold and supplies finite storage capacity.
- Each Treasury tile has its own gold stock and capacity. Workers spread deliveries across tiles with space. Configurable fullness thresholds display coin piles, small chests and large chests. Selling storage spills its contents as recoverable loose gold. The user chose a 50% construction-cost refund per tile, including starting room tiles; refund fills remaining storage or becomes loose gold if capacity is unavailable. Sale refunds are an explicit economy source in conservation checks.
- Lair: approved for M3A; residents establish personal nests, with species-defined bed footprints rather than a universal one-bed-per-tile rule.
- Pig Pen: selected for M3B basic physical food production. Dining Hall/cooks remain a later upgrade using shared food definitions and inventory/reservation APIs.
- Approved direction: basic Hatchery/Pig Pen food can be eaten directly; a later Dining Hall combines cooking stations and tables for prepared meals with better hunger value/mood. Creatures need cooking capabilities. Other specialists can craft doors and room machinery in later packages; no wood/stone currencies are added.
- Approved creature requirements: bed size, meal amount and desired gold wages vary by species. Only bed/rest behavior is active in M3A; food production/consumption and wage payment require dedicated verified packages.
- Rooms need recognizable floor and wall art, supplied by definitions and updated with terrain/room edits. Keep diggable gold/gems recognizable and navigation independent of decorative meshes.
- User approved a dungeon community of specialists: some creatures work, others fight, with overlapping capabilities possible. Preserve keeper/Heart/portal identity; active cooking/crafting/combat belong to later packages.
- User requested icon-led build choices and creature overview, with details in tooltips, and right-click cancellation back to the default keeper action. M3A includes these controls without changing default excavation.
- Follow-up: a tabbed hub replaces the verbose footer/right sidebar. Creatures is the default tab; one species portrait carries its population count. Rooms shows one icon per type with the number of connected rooms; tile totals/capacity remain in tooltips. Debug/control text belongs to the F3 window.
- Follow-up: personal bed reservations only hold space for capacity. The creature walks to the reserved footprint and claims it locally before the bed appears. Existing open terrain still needs no claiming.
- Later rooms should follow gameplay needs after the pet-dungeon loop works. These roles do not authorize implementing additional rooms in M2D.

For each future package record: ID, objective, implementer, reviewer, owned files, dependencies, acceptance checks and status.

## Latest handoff

- Completed: unlimited mixed keeper-hand queue. Left-click appends creatures/gold, each right-click drops the oldest entry, and invalid drops preserve order. An ordered scrollable strip shows entries and a pinned next summary; the actual next model/name/amount stays correct even while inspecting another actor. Individual info remains in the bottom hub. Protected Heart storage (3,000/4,000, no prebuilt Treasury), shared-floor drops, food/rest and the two-tile Pig Pen rule remain verified.
- Verification: check101 scripts/0, full test2,010/0. Queue core21/review32, input104, UI40, gold27/review40 plus existing suites pass. Lead independently reran queue GPU18/0, keeper33/0, food31/0 and Heart/gold20/0 (102 graphical checks). Independent core/input/behavior/visual reviews approved.140 mixed entries,40-item scrolling, exact FIFO identities/amounts, removals, reloads and resumed jobs/food conserve quantities. See `docs/VERIFICATION.md`.
- Known limits: no artificial hand count limit, but only currently eligible creatures/gold are pickable; no food/landmark pickup. One Grubbin portal cap remains. No save/load, starvation damage, mood, wages, cooking/crafting, combat or XP. Queued needs freeze; interrupted tasks replan. No broad large-world performance, native OS input or export gate is claimed. Current assets remain procedural. The user playtested and approved this checkpoint for commit/push; refer to Git history for its revision.
- Next action: discuss current progress and the next focused package after this Git checkpoint. Save/load should preserve the full ordered queue, origins, names and per-batch gold; a second species/attraction and needs consequences are also pending. User requested future hand polish with actual creatures dangling from the keeper's hand. Record that direction without starting it or another system until authorized.

## Later backlog

- Training, research, traps, doors, spells and creature progression.
- Combat, invading heroes, defenses and campaign objectives.
- Dungeon Heart threat reactions, attack/damage behavior and destruction as the defeat condition; introduce and test these alongside combat.
- Richer creature relationships, humor and room interactions.
- Improved models, textures, animation, accessibility, audio and wider playtesting.
- Keeper-hand visual refinement: show the actual held creature dangling and moving from the hand, replacing portrait-like held presentation. Preserve exact next-item identity and readable mixed queue/drop feedback. This is future presentation polish, not a new custody mechanic.
