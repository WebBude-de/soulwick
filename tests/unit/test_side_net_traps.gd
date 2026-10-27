extends GutTest
## Turrets and spike traps of a side segment in a group game (M5 round 3, NetSide): the host's
## turrets and traps report every charge, shot, death and phase change; a client's are
## remote_controlled and play exactly what arrives - also events that came before its own segment
## was built. Without a network: the RPC handlers are called like the relay would.

const PLAN := [
	"####################",
	"#..................#",
	"#..................#",
	"#..................#",
	"#S.....T....^^....D#",
	"####################",
]
const SLOT := 5

var _old_save_path: String


func before_all() -> void:
	_old_save_path = SaveManager.save_path
	SaveManager.save_path = "user://test_side_net_traps_save.cfg"


func after_all() -> void:
	SaveManager.save_path = _old_save_path


func _side(host: bool) -> NetSide:
	var side := NetSide.new()
	side.name = NetSide.NODE_NAME
	add_child_autofree(side)
	side.is_host = host
	side.set_physics_process(false)
	return side


func _layout() -> SideLayout:
	var layout := SideLayout.parse(PackedStringArray(PLAN), &"net_traps")
	layout.biome_id = &"crypt"
	return layout


## A segment of slot, announced to side before it enters the tree (as NetDungeon does).
func _segment(side: NetSide, slot: int) -> SideSegment:
	side._segment_slot = slot
	var segment := SideSegment.new()
	segment.setup(_layout(), 1, null, 21)
	side.on_node_added(segment)
	add_child_autofree(segment)
	segment.global_position = Vector2(0, 11000)
	return segment


func test_client_traps_follow_the_host() -> void:
	var side := _side(false)
	var segment := _segment(side, SLOT)
	var turret := segment.get_turrets()[0]
	var spikes := segment.get_spikes()
	assert_true(turret.remote_controlled, "a client's turret waits for the host")
	for trap in spikes:
		assert_true(trap.remote_controlled, "a client's spikes wait for the host")
	side.side_turret_net(SLOT, 0, NetSide.TurretEvent.CHARGE, Vector2.LEFT)
	assert_true(turret.is_charging(), "the host's charge shows")
	side.side_turret_net(SLOT, 0, NetSide.TurretEvent.FIRE, Vector2.LEFT)
	assert_false(turret.is_charging())
	side.side_spikes_net(SLOT, 1, SideSpikes.Phase.WARN)
	assert_eq(spikes[1].phase, SideSpikes.Phase.WARN, "the host's spike phase")
	assert_eq(spikes[0].phase, SideSpikes.Phase.IDLE, "only the trap it names")
	side.side_turret_net(SLOT, 0, NetSide.TurretEvent.DIED, Vector2.ZERO)
	assert_true(turret.is_dead(), "destroyed with the host's")
	side.side_turret_net(SLOT, 7, NetSide.TurretEvent.DIED, Vector2.ZERO)
	side.side_turret_net(SLOT + 3, 0, NetSide.TurretEvent.CHARGE, Vector2.LEFT)
	assert_eq(side.turret_events, 3, "unknown turrets and other segments change nothing here")
	assert_eq(side.turret_shots, 1)
	assert_eq(side.turret_deaths, 1)
	assert_eq(side.spike_events, 1)


func test_client_keeps_events_until_its_segment_is_built() -> void:
	var side := _side(false)
	side._segment_slot = SLOT - 1
	side.side_spikes_net(SLOT, 0, SideSpikes.Phase.ACTIVE)
	side.side_turret_net(SLOT, 0, NetSide.TurretEvent.CHARGE, Vector2.RIGHT)
	var segment := _segment(side, SLOT)
	assert_true(segment.get_spikes()[0].is_active(), "the early spike event played on the build")
	assert_true(segment.get_turrets()[0].is_charging(), "the early charge too")
	assert_eq(segment.get_turrets()[0].rules.aim, Vector2.RIGHT)


func test_host_watches_every_turret_and_trap() -> void:
	var side := _side(true)
	var segment := _segment(side, SLOT)
	var turret := segment.get_turrets()[0]
	assert_false(turret.remote_controlled, "the host's turret decides")
	assert_gt(turret.charge_started.get_connections().size(), 0, "charges go out")
	assert_gt(turret.fired.get_connections().size(), 0, "shots go out")
	assert_gt(turret.died.get_connections().size(), 0, "the death goes out")
	for trap in segment.get_spikes():
		assert_false(trap.remote_controlled)
		assert_gt(trap.phase_changed.get_connections().size(), 0, "spike phases go out")


func test_detached_client_decides_alone_again() -> void:
	var side := _side(false)
	var segment := _segment(side, SLOT)
	side.detach()
	assert_false(segment.get_turrets()[0].remote_controlled)
	for trap in segment.get_spikes():
		assert_false(trap.remote_controlled)


func test_a_client_obstacle_run_builds_its_slopes_without_rush_events() -> void:
	var side := _side(false)
	side._segment_slot = SLOT
	var segment := SideSegment.new()
	segment.setup(ObstacleRunPlans.build(&"crypt_run_lift"), 1, null, 21)
	side.on_node_added(segment)
	add_child_autofree(segment)
	segment.global_position = Vector2(0, 11000)
	assert_not_null(segment.get_node_or_null(^"Slopes"), "the two-way piece's slopes on the client too")
	for gone: StringName in [&"side_rush_crown_net", &"side_rush_combo_net", &"side_rush_result_net"]:
		assert_false(side.has_method(gone), "%s: no crown, combo or result any more (D-216)" % gone)

