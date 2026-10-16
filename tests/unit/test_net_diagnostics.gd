extends GutTest
## NetDiagnostics (online test 16.10.2026): rates per second and peaks, frame hitches, averages
## between two marks, the static snapshot for bug reports and the last disconnect; plus the two
## smoothing helpers of that package: the own player's position history (NetPlayerState, no rubber
## band while the host's position only lags); the puppets' interpolation: test_net_interpolator.gd.

const Diagnostics = preload("res://online/net_diagnostics.gd")


func before_each() -> void:
	Diagnostics.reset_static()


func after_all() -> void:
	Diagnostics.reset_static()


func test_rates_roll_every_second_and_keep_the_peak() -> void:
	var d := Diagnostics.new(0)
	d.note_poll(0, 1)
	for i in 30:
		d.note_sent(100)
	d.note_received(50, 4, true)
	d.note_poll(1000, 1_000_000)
	assert_eq(d.rate.frames_out, 30)
	assert_eq(d.rate.bytes_out, 3000)
	assert_eq(d.rate.packets_in, 4)
	assert_eq(d.totals.bundles_in, 1)
	d.note_sent(10)
	d.note_poll(2000, 2_000_000)
	assert_eq(d.rate.bytes_out, 10)
	assert_eq(d.peak.bytes_out, 3000, "the busiest second stays")


func test_a_long_frame_counts_as_hitch_and_spreads_its_bucket() -> void:
	var d := Diagnostics.new(0)
	d.note_poll(0, 1)
	d.note_poll(16, 16_000)
	assert_eq(d.totals.hitches, 0)
	for i in 60:
		d.note_sent(100)
	assert_eq(d.note_poll(3016, 3_016_000), 3000)
	assert_eq(d.totals.hitches, 1)
	assert_eq(d.longest_hitch_msec, 3000)
	assert_eq(d.rate.frames_out, 20, "60 frames over 3 s, not a fake peak of 60/s")
	d.reset_poll_clock()
	assert_eq(d.note_poll(9000, 9_000_000), 0, "no hitch after a deliberate pause")


func test_averages_between_marks() -> void:
	var d := Diagnostics.new(0)
	var start := d.mark(1000)
	for i in 40:
		d.note_sent(250, 2)
	d.note_dropped(true, 3)
	var avg := d.since(start, 3000)
	assert_eq(avg.seconds, 2.0)
	assert_eq(avg.frames_out_per_s, 20.0)
	assert_eq(avg.packets_out_per_s, 40.0)
	assert_eq(avg.bytes_out_per_s, 5000.0)
	assert_eq(avg.dropped_out, 3)


func test_snapshot_without_and_with_a_connection() -> void:
	var offline := Diagnostics.snapshot()
	assert_false(offline.online)
	assert_false(offline.has("last_disconnect"))
	assert_eq(Diagnostics.describe_last_disconnect(), "")
	var d := Diagnostics.new()
	d.role = "client"
	d.room_code = "ABCD23"
	d.note_rtt(80)
	d.note_rtt(40)
	d.note_relay_error("rate_limited")
	d.make_current()
	var online := Diagnostics.snapshot()
	assert_true(online.online)
	assert_eq(online.connection.role, "client")
	assert_eq(online.connection.rtt_ms.min, 40)
	assert_eq(online.connection.rtt_ms.max, 80)
	assert_eq(online.connection.relay_errors, {"rate_limited": 1})
	assert_true(JSON.stringify(online).length() < 2000, "compact enough for a bug report")


func test_last_disconnect_outlives_the_connection() -> void:
	var d := Diagnostics.new()
	d.role = "client"
	d.room_code = "ABCD23"
	d.make_current()
	d.note_rtt(85)
	d.note_disconnect(4010, "slow consumer", "slow_consumer", 0.2)
	d = null
	var shot := Diagnostics.snapshot()
	assert_false(shot.online, "the connection is gone")
	assert_eq(shot.last_disconnect.code, 4010)
	assert_eq(shot.last_disconnect.end_reason, "slow_consumer")
	var line := Diagnostics.describe_last_disconnect()
	assert_string_contains(line, "slow_consumer")
	assert_string_contains(line, "4010")
	assert_string_contains(line, "rtt 85 ms")


func test_own_player_ignores_a_host_position_it_just_passed() -> void:
	var state := NetPlayerState.new()
	autofree(state)
	# Dash to the right at 450 px/s, 60 frames per second.
	var at := Vector2.ZERO
	for frame in 30:
		at = Vector2(frame * 7.5, 0)
		state._remember_position(frame * 16, at)
	var lagging := Vector2(100, 0)
	assert_true(at.distance_to(lagging) > NetPlayerState.SNAP_DISTANCE, "behind by more than the snap distance")
	assert_true(state.was_recently_at(lagging), "but the own path went through it: no rubber band")
	assert_false(state.was_recently_at(Vector2(100, 200)), "a position off the path is a real disagreement")
	state._remember_position(30 * 16 + int(NetPlayerState.HISTORY_SECONDS * 1000.0) + 100, at)
	assert_false(state.was_recently_at(lagging), "older than HISTORY_SECONDS is forgotten")
