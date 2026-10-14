class_name EnemyScaling
extends RefCounted
## Room-based difficulty scaling (D-011, retuned D-074), k(room) = floor((room - 1) / 5):
##   HP       = base * 1.18^k * (champion factor)
##   damage   = base * 1.14^k * (champion factor)
##   cooldown = base * max(0.55, 1 - 0.03 k), telegraph * max(0.7, 1 - 0.015 k)
##   speed    = base * min(1.5, 1 + 0.03 k)
## The same formula continues endlessly (D-063).

const ROOMS_PER_BLOCK := 5
const HEALTH_FACTOR_PER_BLOCK := 1.18
const DAMAGE_FACTOR_PER_BLOCK := 1.14
## Minibosses are champions: tougher than a plain enemy (D-077).
const MINIBOSS_HEALTH_FACTOR := 3.0
const MINIBOSS_DAMAGE_FACTOR := 1.5
const COOLDOWN_REDUCTION_PER_BLOCK := 0.03
const MIN_COOLDOWN_FACTOR := 0.55
const TELEGRAPH_REDUCTION_PER_BLOCK := 0.015
const MIN_TELEGRAPH_FACTOR := 0.7
const SPEED_GAIN_PER_BLOCK := 0.03
const MAX_SPEED_FACTOR := 1.5


static func get_block(room_index: int) -> int:
	return maxi(0, floori(float(room_index - 1) / ROOMS_PER_BLOCK))


static func health_multiplier(room_index: int, is_miniboss: bool) -> float:
	var factor := MINIBOSS_HEALTH_FACTOR if is_miniboss else 1.0
	return pow(HEALTH_FACTOR_PER_BLOCK, get_block(room_index)) * factor


static func damage_multiplier(room_index: int, is_miniboss: bool) -> float:
	var factor := MINIBOSS_DAMAGE_FACTOR if is_miniboss else 1.0
	return pow(DAMAGE_FACTOR_PER_BLOCK, get_block(room_index)) * factor


static func cooldown_multiplier(room_index: int) -> float:
	return maxf(MIN_COOLDOWN_FACTOR, 1.0 - COOLDOWN_REDUCTION_PER_BLOCK * get_block(room_index))


static func telegraph_multiplier(room_index: int) -> float:
	return maxf(MIN_TELEGRAPH_FACTOR, 1.0 - TELEGRAPH_REDUCTION_PER_BLOCK * get_block(room_index))


static func speed_multiplier(room_index: int) -> float:
	return minf(MAX_SPEED_FACTOR, 1.0 + SPEED_GAIN_PER_BLOCK * get_block(room_index))
