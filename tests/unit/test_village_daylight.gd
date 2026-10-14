extends GutTest
## Village time of day: bright by day, smooth dusk and dawn, dark night, lamps get light sources.


func test_day_is_bright() -> void:
	for hour in [7.0, 12.0, 17.0]:
		assert_eq(VillageDaylight.darkness_for_hour(hour), 0.0, "%.1f o'clock is bright" % hour)


func test_night_is_dark() -> void:
	for hour in [20.0, 23.5, 0.0, 3.0, 4.9]:
		assert_almost_eq(VillageDaylight.darkness_for_hour(hour), VillageDaylight.NIGHT_DARKNESS, 0.001, "%.1f o'clock is night" % hour)


func test_dusk_and_dawn_are_in_between_and_monotonic() -> void:
	var previous := 0.0
	for step in 11:
		var hour := lerpf(VillageDaylight.DUSK_START, VillageDaylight.NIGHT_START, step / 10.0)
		var darkness := VillageDaylight.darkness_for_hour(hour)
		assert_true(darkness >= previous, "dusk gets darker at %.2f" % hour)
		previous = darkness
	var dawn := VillageDaylight.darkness_for_hour(6.0)
	assert_true(dawn > 0.0 and dawn < VillageDaylight.NIGHT_DARKNESS, "dawn is in between")


func test_night_colour_is_blue_and_dusk_violet() -> void:
	assert_true(VillageDaylight.dark_color_for_hour(1.0).is_equal_approx(VillageDaylight.NIGHT_COLOR), "night is blue")
	assert_true(VillageDaylight.dark_color_for_hour(18.0).is_equal_approx(VillageDaylight.DUSK_COLOR), "dusk is violet")


func test_lamps_get_one_light_each() -> void:
	var props := Node2D.new()
	add_child_autofree(props)
	for prop_name in ["Lamp1", "Lamp2", "Well"]:
		var prop := Node2D.new()
		prop.name = prop_name
		props.add_child(prop)
	VillageDaylight.add_lamp_lights(props)
	VillageDaylight.add_lamp_lights(props)
	assert_not_null(props.get_node("Lamp1/LampLight"))
	assert_not_null(props.get_node("Lamp2/LampLight"))
	assert_null(props.get_node_or_null("Well/LampLight"))
	assert_eq(props.get_node("Lamp1").get_child_count(), 1, "no duplicate light on a second call")
