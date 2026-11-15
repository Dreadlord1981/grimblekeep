extends GameFeature
## Test-only extension: proves optional behavior receives session events/context.

var tick_count: int = 0


func tick(_delta: float) -> void:
	tick_count += 1
