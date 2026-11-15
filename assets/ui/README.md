# Grimblekeep interface icons

Original SVG artwork authored in code for Grimblekeep. No stock art, external fonts or generated bitmap imagery is used. Earthy colors and simple silhouettes are intended for the desktop HUD at 20–56 logical pixels. Room icons and creature portraits are selected through content definitions; action icons represent shared gameplay states.

The Pig Pen room icon (`room_pig_pen.svg`) and eating action icon (`action_eat.svg`) are original SVG additions for the food loop. Their cave-pig silhouette and earthy palette match the corresponding in-game food.

Keeper pointing/gripping silhouettes are original code-drawn polygons in `ui/keeper_hand.gd`. The hand preview instances the held creature's original definition-provided model in an isolated viewport; gold uses original procedural sack/coin meshes in `ui/held_creature_preview.gd`. Bottom-hub details use standard Godot controls. Protected Heart storage uses original low coin piles, worn slabs, iron edging and coin stamps. No external artwork or Blender-authored model was introduced.

Related world assets are also original procedural geometry: `presentation/pig_view.gd` builds and animates the cave pig, instantiated by `scenes/food/cave_pig.tscn`; `presentation/food_view.gd` presents authoritative food quantities. Pig Pen mud, straw, troughs and timber rails are built in `presentation/room_view.gd`. These assets use Godot primitive meshes and code-defined materials, with no external models, textures or bitmap assets.
