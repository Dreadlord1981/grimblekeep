# Grimblekeep

A real-time 3D dungeon game about building a home for unpleasant little creatures.
Godot 4.7.2 Standard / GDScript. Current slice: excavation, mining, Treasury/Lair construction and a first living Grubbin.

## Run

Open `project.godot` in Godot and press F6 on `scenes/dungeon.tscn`, or F5 for the project.
In PowerShell with `GODOT_EXE` configured:

```powershell
.\tools\dev.ps1 check
.\tools\dev.ps1 test
.\tools\dev.ps1 run
.\tools\dev.ps1 capture
```

Controls: WASD/arrows or middle drag to pan, right drag or Q/E to orbit, wheel to
zoom, Home to return to the Heart. The keeper hand marks stone, gold and gem tiles
for excavation by default; no tool switch is needed. Click or drag an inclusive
rectangle to toggle marks, preserving marks outside it. Repeat to unmark. Ground,
the Heart and the portal are ignored. Shift marks only, Ctrl unmarks only, Escape
clears all marks, F3 toggles diagnostics.
Marked blocks retain a pulsing amber surface/edge glow on top and sides. Green plus
symbols preview added marks and red X symbols preview removals, with exact counts
in the footer before release. Workers automatically take reachable marked jobs.
Stone becomes walkable floor. Gold seams contain 200 gold; workers mine in small
strikes, carry up to 60 and deliver to the starting treasury. Gems remain in place
and generate gold more slowly. Deposited gold is spendable; loose and carried gold
are displayed separately. Sale refunds also use available Treasury space as
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
Choose **Treasury** in the footer and click/drag to build for 50 stored gold per
tile. Existing rooms are skipped, never toggled off. Choose **Sell rooms** to
click/drag built tiles for a 50% refund (rounded down per tile). Gold held on sold
tiles becomes loose gold; refunds fill remaining storage or drop onto the floor
if no space remains. Right-click, Escape or Done exits construction without clearing
dig orders. A canceled drag cannot place/sell tiles when the left button releases.
The bottom hub starts on **Creatures**, with one portrait per species and its
population overlaid. Switch to **Rooms** for chest/bed build icons, tile prices
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
Bed footprints, rest rates and future meal/wage requirements come from species
definitions; larger footprints must actually fit, without overlapping other beds.

Treasury floors/walls use brass inlays and coin seals; Lairs use patched rugs and
ragged skull hangings. Dressing updates after digging/selling. Marking decorated
rock temporarily reveals its amber excavation glow and unmarking restores the art.
The debug creature cards use portraits, action icons and energy/work bars; hover
for the current job and pending/established bed details.

`check` imports resources and checks scripts; the wrapper detects logged script/errors
as well as the process exit code. `test` runs core, navigation, economy, targeting,
input, worker and room integration checks and exits nonzero on failures.
`capture` requires a graphics-capable desktop and writes
`artifacts/foundation.png`, then exits. Export templates are not needed to run locally.

This is an early living-dungeon sandbox, not the complete pet dungeon. Food,
wages, cooking/crafting, combat, a second species, keeper pickup/drop, work-based
leveling and saves remain later packages. No food/wage simulation is implied by
the species requirement fields. See `LORE.md` for the accepted first-creature and
specialist-community direction.
See `PLAN.md` for progress,
`AGENTS.md` for agent instructions and `docs/ARCHITECTURE.md` for extension contracts.
