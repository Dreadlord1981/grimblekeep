class_name KeeperHandItem
extends RefCounted
## Stable FIFO custody entry. Consumers read it; KeeperState owns membership.

var id: int
var kind: StringName
var actor: CreatureState
var gold_amount: int = 0
var origin := Vector2i(-1, -1)
