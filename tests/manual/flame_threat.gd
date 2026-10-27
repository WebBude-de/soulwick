extends SceneTree
## How threatened is the soul flame of "Flamme hüten" (playtest 23.10.2026 #56d68b40, "die Flamme
## bekommt nie Schaden")? Plays the flame plan rooms headless with real biome enemies and one
## inattentive player: he stands far from the flame and does nothing (invulnerable, so only the
## flame counts). Prints per run the flame's lowest health share, whether it went out and when, and
## how many enemies went for it.
## Usage: godot --headless --audio-driver Dummy --fixed-fps 60 --path . -s tests/manual/flame_threat.gd -- [runs=3] [room=6] [template=flamme_schrein_crypt] [players=1]

const RUNNER := "res://tests/manual/flame_threat_runner.gd"


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


## Autoloads exist from the first frame on: the typed body runs as a node then.
func _start() -> void:
	var runner := (load(RUNNER) as GDScript).new() as Node
	root.add_child(runner)
