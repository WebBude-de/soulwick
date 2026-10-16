extends GutTest
## NetInterpolator (online test 16.10.2026, "Mobs springen/ruckeln"): drawn a fixed delay in the
## host's past between two snapshots; delta snapshots (left-out entity stands), teleports, a late
## stream. The jitter comparison runs one enemy at 120 px/s through 15 snapshots/s (10/s for the
## side view) that arrive 80 ms +- 30 ms late in TCP order and measures how evenly it moves on a
## 60 fps client: the old pull towards the newest snapshot against the interpolation.

const Interpolator = preload("res://online/net_interpolator.gd")
const SPEED := 120.0
const FRAME_MSEC := 1000.0 / 60.0


func test_draws_between_two_samples_with_the_delay() -> void:
	var interp := Interpolator.new()
	interp.begin_snapshot(1000.0, 5000.0)
	interp.push(1, 1000.0, Vector2(0, 0))
	interp.begin_snapshot(1100.0, 5100.0)
	interp.push(1, 1100.0, Vector2(100, 0))
	# Local 5150 = host 1150, drawn at host 1050: halfway.
	assert_almost_eq(interp.position_at(1, 5150.0).x, 50.0, 0.01)
	assert_eq(interp.position_at(1, 4000.0), Vector2(0, 0), "before the oldest sample")
	assert_eq(interp.position_at(2, 5150.0), Vector2.INF, "unknown id")


func test_left_out_entity_stands_and_does_not_glide_through_the_pause() -> void:
	var interp := Interpolator.new()
	for i in 4:
		var t := 1000.0 + i * 100.0
		interp.begin_snapshot(t, t + 4000.0)
		if i == 0:
			interp.push(1, t, Vector2(0, 0))
	# Moves again at host 1400 (left out at 1100-1300 = it stood at 0).
	interp.begin_snapshot(1400.0, 5400.0)
	interp.push(1, 1400.0, Vector2(40, 0))
	assert_eq(interp.position_at(1, 5300.0 + Interpolator.DELAY_MSEC), Vector2(0, 0), "still standing at host 1300")
	assert_almost_eq(interp.position_at(1, 5350.0 + Interpolator.DELAY_MSEC).x, 20.0, 0.01, "moves only between 1300 and 1400")
	# Past its newest sample while newer snapshots leave it out: held, not extrapolated.
	interp.begin_snapshot(1500.0, 5500.0)
	assert_eq(interp.position_at(1, 5600.0 + Interpolator.DELAY_MSEC), Vector2(40, 0))


func test_teleports_are_not_blended() -> void:
	var interp := Interpolator.new()
	interp.begin_snapshot(1000.0, 1000.0)
	interp.push(1, 1000.0, Vector2(0, 0))
	interp.begin_snapshot(1100.0, 1100.0)
	interp.push(1, 1100.0, Vector2(500, 0))
	assert_eq(interp.position_at(1, 1150.0), Vector2(0, 0), "until the jump")
	assert_eq(interp.position_at(1, 1200.0), Vector2(500, 0), "then at once")


func test_a_late_stream_is_led_for_a_short_time_only() -> void:
	var interp := Interpolator.new()
	interp.begin_snapshot(1000.0, 1000.0)
	interp.push(1, 1000.0, Vector2(0, 0))
	interp.begin_snapshot(1100.0, 1100.0)
	interp.push(1, 1100.0, Vector2(10, 0))
	# Nothing new for a while: drawn time passes the newest sample.
	assert_almost_eq(interp.position_at(1, 1250.0).x, 15.0, 0.01, "50 ms past: led by the last velocity")
	assert_almost_eq(interp.position_at(1, 2000.0).x, 10.0 + 10.0 * Interpolator.MAX_EXTRAPOLATE_MSEC / 100.0, 0.01, "capped")


func test_old_history_is_dropped() -> void:
	var interp := Interpolator.new()
	for i in 100:
		interp.begin_snapshot(i * 66.0, i * 66.0)
		interp.push(1, i * 66.0, Vector2(i, 0))
	var kept: Array = interp._samples[1]
	assert_true(kept.size() <= int(Interpolator.KEEP_MSEC / 66.0) + 3, "about KEEP_MSEC of samples (%d)" % kept.size())


func test_jitter_comparison_top_down_and_side_view() -> void:
	for setup: Array in [["top-down 15/s", 15.0, 14.0, 120.0], ["side view 10/s", 10.0, 12.0, 96.0]]:
		var old := _run(setup[1], false, setup[2], setup[3])
		var new := _run(setup[1], true, setup[2], setup[3])
		gut.p("%s, 80 +- 30 ms: speed per frame old max %.0f px/s off (sd %.0f, %d jumps), interpolated max %.0f px/s off (sd %.0f, %d jumps)" % [
			setup[0], old.max_off, old.sd, old.jumps, new.max_off, new.sd, new.jumps])
		assert_true(new.max_off < old.max_off * 0.5, "%s: at least half as uneven" % setup[0])
		assert_eq(new.jumps, 0, "%s: no jumps" % setup[0])


## One enemy walking at SPEED for 6 s; snapshots at rate, 80 +- 30 ms late in order. Returns how far
## the per-frame speed is off SPEED (max and standard deviation, after a warm-up) and the jumps.
func _run(rate: float, interpolated: bool, follow_rate: float, snap_distance: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1607
	var interp := Interpolator.new()
	var arrivals: Array = []
	var last_arrival := 0.0
	var interval := 1000.0 / rate
	var t := 0.0
	while t < 6000.0:
		var arrival := maxf(last_arrival, t + 80.0 + rng.randf_range(-30.0, 30.0))
		last_arrival = arrival
		arrivals.append([arrival, t, Vector2(SPEED * t / 1000.0, 0)])
		t += interval
	var drawn := Vector2.ZERO
	var target := Vector2.ZERO
	var next := 0
	var previous := Vector2.ZERO
	var offs: Array[float] = []
	var jumps := 0
	var now := 0.0
	while now < 6000.0:
		while next < arrivals.size() and float(arrivals[next][0]) <= now:
			var item: Array = arrivals[next]
			interp.begin_snapshot(item[1], now)
			interp.push(1, item[1], item[2])
			target = item[2]
			next += 1
		if interpolated:
			var at := interp.position_at(1, now)
			if at != Vector2.INF:
				drawn = at
		else:
			var error := target - drawn
			if error.length() > snap_distance:
				drawn = target
				jumps += 1
			else:
				drawn += error * minf(1.0, follow_rate * FRAME_MSEC / 1000.0)
		if now > 1000.0:
			var speed := (drawn.x - previous.x) / (FRAME_MSEC / 1000.0)
			offs.append(absf(speed - SPEED))
			if absf(drawn.x - previous.x) > snap_distance * 0.5:
				jumps += 1 if interpolated else 0
		previous = drawn
		now += FRAME_MSEC
	var total := 0.0
	var largest := 0.0
	for off in offs:
		total += off * off
		largest = maxf(largest, off)
	return {"max_off": largest, "sd": sqrt(total / maxf(1.0, offs.size())), "jumps": jumps}
