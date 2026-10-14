extends GutTest
## Spawn draws: distinct markers without replacement, weighted enemy types (D-009, D-010).


func test_markers_are_distinct() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 200:
		var picked := EnemySpawner.pick_markers(5, 3, rng)
		assert_eq(picked.size(), 3)
		var unique := {}
		for marker in picked:
			assert_between(marker, 0, 4)
			unique[marker] = true
		assert_eq(unique.size(), 3, "no marker is used twice")


func test_marker_count_is_capped_by_available_markers() -> void:
	var rng := RandomNumberGenerator.new()
	assert_eq(EnemySpawner.pick_markers(2, 5, rng).size(), 2)


func test_weights_match_gdd_distribution() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var weights: Array[float] = [0.5, 0.35, 0.15]
	var counts := [0, 0, 0]
	var draws := 20000
	for i in draws:
		counts[EnemySpawner.pick_weighted(weights, rng)] += 1
	assert_almost_eq(counts[0] / float(draws), 0.5, 0.02, "Slime 50 %")
	assert_almost_eq(counts[1] / float(draws), 0.35, 0.02, "Skeleton 35 %")
	assert_almost_eq(counts[2] / float(draws), 0.15, 0.02, "Archer 15 %")


func test_invalid_marker_count_spawns_nothing() -> void:
	var spawner: EnemySpawner = autofree(EnemySpawner.new())
	spawner.enemy_types.assign([load("res://enemies/data/slime.tres")])
	spawner.spawn_weights.assign([1.0])
	var container: Node2D = autofree(Node2D.new())
	var context := DungeonContext.new()
	context.rng = RandomNumberGenerator.new()
	var markers: Array[Marker2D] = []
	var spawned := spawner.spawn_encounter(1, RoomSequence.RoomType.COMBAT, markers, Vector2.ZERO, container, context)
	assert_push_error("expected at least 5 spawn markers")
	assert_eq(spawned.size(), 0, "a broken template must not produce a (completable) encounter")
