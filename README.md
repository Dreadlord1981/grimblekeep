# Grimblekeep

A real-time 3D dungeon game about building a home for unpleasant little creatures.
Godot 4.7.2 Standard / GDScript. Current slice: excavation, mining, hauling and modular Treasury construction.

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

Open floor is immediately buildable after excavation; there is no claiming step.
Choose **Treasury** in the footer and click/drag to build for 50 stored gold per
tile. Existing rooms are skipped, never toggled off. Choose **Sell rooms** to
click/drag built tiles for a 50% refund (rounded down per tile). Gold held on sold
tiles becomes loose gold; refunds fill remaining storage or drop onto the floor
if no space remains. Escape/Done exits construction without clearing dig orders.

Each Treasury tile holds 500 gold. Workers spread deliveries across less-filled
tiles. Actual tile stock displays a coin pile below 35%, a small chest from 35%
and a large chest from 75%. Adjacent room tiles merge; selling a bridge splits
the room and recalculates capacity. Room cost, storage and appearance are data.

`check` imports resources and checks scripts; the wrapper detects logged script/errors
as well as the process exit code. `test` runs core, navigation, economy, targeting,
input, worker and room integration checks and exits nonzero on failures.
`capture` requires a graphics-capable desktop and writes
`artifacts/foundation.png`, then exits. Export templates are not needed to run locally.

This is an early construction sandbox, not the complete pet dungeon. Lair/food
mechanics, needs, portal attraction, work-based leveling and saves remain later packages.
See `PLAN.md` for progress,
`AGENTS.md` for agent instructions and `docs/ARCHITECTURE.md` for extension contracts.
