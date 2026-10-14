class_name HealthComponent
extends Node
## HP in 0.5 steps. Emits died exactly once.

signal health_changed(current: float, maximum: float)
signal died

@export var max_health := 6.0

var _current := 0.0
var _is_dead := false
var _initialized := false


func _ready() -> void:
	if not _initialized:
		reset(max_health)


## Sets a new maximum and refills HP. Used on spawn and for enemy scaling.
func reset(new_max_health: float) -> void:
	max_health = new_max_health
	_current = new_max_health
	_is_dead = false
	_initialized = true
	health_changed.emit(_current, max_health)


func get_health() -> float:
	return _current


func get_max_health() -> float:
	return max_health


func is_dead() -> bool:
	return _is_dead


## Returns the HP actually removed.
func take_damage(amount: float) -> float:
	if _is_dead or amount <= 0.0:
		return 0.0
	var applied := minf(amount, _current)
	_current -= applied
	health_changed.emit(_current, max_health)
	if _current <= 0.0:
		_is_dead = true
		died.emit()
	return applied


## Heals up to max_health. Returns the HP actually restored.
func heal(amount: float) -> float:
	if _is_dead or amount <= 0.0:
		return 0.0
	var applied := minf(amount, max_health - _current)
	if applied <= 0.0:
		return 0.0
	_current += applied
	health_changed.emit(_current, max_health)
	return applied
