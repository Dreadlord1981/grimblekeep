# Grimblekeep

A real-time 3D dungeon game about building a home for unpleasant little creatures.
Godot 4.7.2 Standard / GDScript. Current slice: excavation, mining, Treasury/Lair/Pig Pen construction and a Grubbin that eats and sleeps.

## Run

Open `project.godot` in Godot and press F6 on `scenes/dungeon.tscn`, or F5 for the project.
In PowerShell with `GODOT_EXE` configured:

```powershell
.\tools\dev.ps1 check
.\tools\dev.ps1 test
.\tools\dev.ps1 run
.\tools\dev.ps1 capture
```

Blender 5.3 is available for model/animation authoring. User `BLENDER_EXE` points
to its executable and the installation folder is on user PATH; new terminals can
run `blender --version`. Already-open terminals may need reopening. Scripts can
read `[Environment]::GetEnvironmentVariable('BLENDER_EXE', 'User')` directly.
Background Python automation was verified without opening a window or saving a
file. Existing game assets are still original procedural meshes and SVGs.

Fresh playtests start with **3,000 stored gold** in a six-tile Treasury, so rooms
can be tested immediately. This is a finite starting bank; each tile still holds
500 gold. Mining pauses while storage is full and resumes after construction
spends some of it. The scene's `starting_gold` property can be set to zero for
mining-only test fixtures.

Controls: WASD/arrows or middle drag to pan, right drag or Q/E to orbit, wheel to
zoom, Home to return to the Heart. The keeper hand marks stone, gold and gem tiles
for excavation by default; no tool switch is needed. Click or drag an inclusive
rectangle to toggle marks, preserving marks outside it. Repeat to unmark. Ground,
the Heart and the portal are ignored. Shift marks only, Ctrl unmarks only, Escape
clears all marks, F3 toggles diagnostics.
Marked blocks retain a pulsing amber surface/edge glow on top and sides. Green plus
symbols preview added marks and red X symbols preview removals, with exact counts
in contextual feedback before release. Workers automatically take reachable marked jobs.
Stone becomes walkable floor. Gold seams contain 200 gold; workers mine in small
strikes, carry up to 60 and deliver to the starting treasury. Gems remain in place
and generate gold more slowly. Deposited gold is spendable; loose and carried gold
are detailed in the gold tooltip. Sale refunds also use available Treasury space as
described below. Cancel marks to stop further work.
Workers use eight-direction A* routes with safe diagonals and constant world speed.
Gold and gem seams allow one miner on each reachable cardinal side, up to four;
multiple miners share the same node supply. Dig around a seam to expose more faces.
Gold/gem mining pauses when no reachable Treasury has free space; orders remain
marked and resume after spending or adding storage. Stone digging still works.

Dark blue-charcoal **bedrock**, with flat tops and horizontal bands, is
indestructible: it blocks movement and cannot be marked, mined or built on.
The starting map uses it around the edge and in a small internal pattern.
Scenario authors can use `foundation_layout.gd` helpers `add_bedrock_border()`
and `paint_bedrock()` for different border thicknesses and arbitrary cell patterns.

Open floor is immediately buildable after excavation; there is no claiming step.
Choose **Treasury** in the Rooms tab and click/drag to build for 50 stored gold per
tile. Existing rooms are skipped, never toggled off. Choose **Sell rooms** to
click/drag built tiles for a 50% refund (rounded down per tile). Gold held on sold
tiles becomes loose gold; refunds fill remaining storage or drop onto the floor
if no space remains. Right-click, Escape or Done exits construction without clearing
dig orders. A canceled drag cannot place/sell tiles when the left button releases.
The bottom hub starts on **Creatures**, with one portrait per species and its
population overlaid. Switch to **Rooms** for chest/bed/pig build icons, tile prices
and connected-room counts. Hover for names, total tiles and capacity. F3 opens
the debug window with individual actions/needs and controls; there is no fixed
right sidebar or verbose footer. Construction feedback follows the cursor.

Each Treasury tile holds 500 gold. Workers spread deliveries across less-filled
tiles. Actual tile stock displays a coin pile below 35%, a small chest from 35%
and a large chest from 75%. Adjacent room tiles merge; selling a bridge splits
the room and recalculates capacity. Room cost, storage and appearance are data.

Choose the Lair bed icon to build for 50 gold per tile. A reachable free bed space
attracts the first Grubbin through the portal (one Grubbin in this prototype).
It walks to its reserved space and claims it locally before its cot appears,
then explores, gets tired, returns to sleep and recovers. Space reserved for
arrival remains bare until the owner reaches it; remote bed creation is rejected.
Selling any part of a bed releases it and the resident seeks another fitting space.
Bed footprints, rest rates, appetite and future wage requirements come from species
definitions; larger footprints must actually fit, without overlapping other beds.

Build a **Pig Pen** using the pig icon in Rooms for 75 gold per tile. A connected
pen needs a 3x1 (or rotated 1x3) footprint before pigs appear. Every three tiles
provide capacity for one pig, rounded down. Each pen produces one pig every 12
seconds until full. Pigs start small, grow over 30 simulation seconds and wander
their connected fenced enclosure. Hungry Grubbins reserve a pig, meet it locally
and eat, then return to their routine. Larger species appetites require more food.
The header shows actual food stock; F3 adds individual satiety and eating progress.
Selling pen space stops the affected production but preserves existing food.
Food is not yet required for portal recruitment, and missing food has no health
or mood penalty in this package. Imps currently have no hunger requirement.

Treasury floors/walls use brass inlays and coin seals; Lairs use patched rugs and
ragged skull hangings; Pig Pens have mud, straw, troughs and perimeter fencing.
Dressing updates after digging/selling. Marking decorated
rock temporarily reveals its amber excavation glow and unmarking restores the art.
The debug creature cards use portraits, action icons and energy/satiety/work bars; hover
for the current job and pending/established bed details.

`check` imports resources and checks scripts; the wrapper detects logged script/errors
as well as the process exit code. `test` runs core, navigation, economy, targeting,
input, worker and room integration checks and exits nonzero on failures.
`capture` requires a graphics-capable desktop and writes
`artifacts/foundation.png`, then exits. Export templates are not needed to run locally.

This is an early living-dungeon sandbox, not the complete pet dungeon. Mood,
wages, cooking/crafting, combat, a second species, keeper pickup/drop, work-based
leveling and saves remain later packages. Food definitions, producer rooms and
meal reservations support later extensions; no cooking or wage payment exists yet.
See `LORE.md` for the accepted first-creature and
specialist-community direction.
See `PLAN.md` for progress,
`AGENTS.md` for agent instructions and `docs/ARCHITECTURE.md` for extension contracts.
