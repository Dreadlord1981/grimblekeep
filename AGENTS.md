# Grimblekeep agent instructions

Read `PLAN.md` in full before working. It defines the agreed game, current scope, milestone gates and review flow.

- The user authorized foundation implementation and then digging/mining on 2026-11-15. Current scope is Milestone 2 worker excavation, finite gold mining and basic hauling. Creature/job/behavior separation and work-based leveling are required design directions; leveling is planned follow-up, not required to finish digging/mining.
- Work in `C:\Users\Akpen\projects\godot\Grimblekeep`.
- Keep the approved vision: real-time perspective 3D dungeon management, gold and food, expressive gritty cartoon art and a desktop interface.
- Include the animated keeper hand for excavation targeting and picking up/dropping friendly creatures, following the interaction and review checks in `PLAN.md`.
- Default click/drag on stone, gold or gem terrain toggles authoritative excavation marks. Do not add a separate Hand/Dig/Inspect mode. Ground marking belongs to future context-specific actions such as room construction. Marked blocks glow on tops and exposed sides; green plus/red X previews show additions/removals.
- Include the central Dungeon Heart and its starting chamber, distinct from the creature portal. Its initial role is atmosphere and identity; damage/destruction and defeat belong to later combat work. It produces no free gold or food.
- Use focused agents for implementation and independent review when authorized work benefits from delegation. Assign clear file ownership and acceptance criteria; avoid overlapping edits.
- Follow the required AI development loops in `PLAN.md`: define a small package, implement, execute relevant checks, obtain independent review, repair and integrate with evidence. Review approval alone does not establish correctness.
- Apply the gameplay scenarios and asset review criteria as systems become available. Verify real controls and rendered output where required; record checks that could not be performed.
- After three unsuccessful repairs of the same issue, isolate it and obtain a fresh diagnosis. Respect package effort boundaries and leave unmet gates open; never relax acceptance criteria to report success.
- Before implementation, read applicable directory instructions and existing changes. Preserve unrelated user work.
- Keep contributions within the current milestone. Record acceptance evidence and material unresolved issues in `PLAN.md` before handing off.
- Do not mark unchecked work complete based on code inspection alone when execution or visual verification is required.
- Maintain runnable milestones and replaceable presentation assets. Do not add resources, production chains or gameplay systems beyond the agreed scope without user direction.
- Keep code in sensible areas: `core/` for state/contracts, `content/` for definitions and feature modules, `presentation/` for 3D views, `interaction/` for input/camera, `ui/` for interface, and `tests/` for verification. Follow `docs/ARCHITECTURE.md` once present.
- New creatures and rooms should use stable-ID definitions; optional mechanics should use explicit feature modules and documented context/events. Prefer composition over species/room switches in core code. Keep views and input out of simulation state. Review an extension test before accepting the module boundary.
- Navigation uses eight-direction A* with straight/diagonal distance costs and no corner cutting (both flank cells open). Worker routes must revalidate diagonal edges after terrain edits; mining still uses cardinal-adjacent workplaces. Gold/gem nodes support one miner per reachable side, up to four, sharing one authoritative supply balance.
