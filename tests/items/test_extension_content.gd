extends GcityTest

## The G1 extension exercise (standards §11): a second weapon frame, its parts and a
## second ammo type exist as content only. This test knows no frame or ammo by name:
## it walks whatever content/ holds and runs the full chain on each combination.

const SEED: int = 20260920


func test_every_frame_fires_every_compatible_round_with_zero_sim_diff() -> void:
	var db := ContentDb.new()
	assert_eq(ContentLoader.load_all(db), OK, "content")
	var frames: Array[StringName] = db.ids(&"weapon_frame")
	var ammos: Array[StringName] = db.ids(&"ammo")
	assert_true(frames.size() >= 2, "at least two frames exist (%d)" % frames.size())
	assert_true(ammos.size() >= 2, "at least two ammo types exist (%d)" % ammos.size())
	var combinations: int = 0
	for frame: StringName in frames:
		var frame_t: Dictionary = db.get_entry(&"weapon_frame", frame)
		var magazine_template: StringName = &""
		for part: StringName in db.ids(&"weapon_part"):
			var part_t: Dictionary = db.get_entry(&"weapon_part", part)
			var fits: Array = part_t["fits"]
			if part_t.get("socket") == "magazine" and fits.has(String(frame)):
				magazine_template = part
				break
		assert_false(magazine_template.is_empty(), "frame %s has a magazine" % frame)
		for ammo: StringName in ammos:
			var ammo_t: Dictionary = db.get_entry(&"ammo", ammo)
			if ammo_t["calibre"] != frame_t["calibre"]:
				continue
			combinations += 1
			var sim: SimRoot = SimAssembly.build(SEED + combinations, db)
			var items: ItemSystem = SimAssembly.items_of(sim)
			var actors: ActorSystem = SimAssembly.actors_of(sim)
			var stats: StatResolver = SimAssembly.stats_of(sim)
			var combat: CombatSystem = SimAssembly.combat_of(sim)
			var player: int = actors.spawn(&"arcade", 0)
			var dummy: int = actors.spawn(&"range_dummy", 5)
			var inv: StringName = ItemSystem.inventory_of(player)
			var weapon: int = items.spawn(&"weapon_frame", frame, inv, 1)
			var magazine: int = items.spawn(&"weapon_part", magazine_template, inv, 2)
			var rounds: Array[int] = []
			for i: int in range(3):
				rounds.append(items.spawn(&"ammo", ammo, inv, 10 + i))
			var before: int = items.item_count()
			for r: int in rounds:
				assert_true(_do(sim, &"magazine.load", {"actor": player, "magazine": magazine, "round": r}), "%s/%s load" % [frame, ammo])
			assert_true(_do(sim, &"actor.wield", {"actor": player, "weapon": weapon}), "%s wield" % frame)
			assert_true(_do(sim, &"weapon.reload_tactical", {"actor": player, "weapon": weapon, "magazine": magazine}), "%s reload" % frame)
			sim.step_n(stats.resolve(weapon, &"reload_ticks") / 1000 + 1)
			var expected_damage: int = 0
			var ammo_stats: Array = ammo_t["stats"]
			for e: Variant in ammo_stats:
				var d: Dictionary = e
				if d["stat"] == "damage":
					expected_damage = d["value"]
			assert_eq(stats.resolve(items.chambered(weapon), &"damage"), expected_damage, "%s/%s round damage from the file" % [frame, ammo])
			var hits: int = 0
			for shot: int in range(3):
				assert_true(_do(sim, &"weapon.fire", {"actor": player, "target": dummy}), "%s/%s shot %d" % [frame, ammo, shot])
				var last: Dictionary = combat.last_shot()
				var hit: bool = last["hit"]
				if hit:
					hits += 1
					assert_eq(last["damage"], expected_damage, "%s/%s applied damage" % [frame, ammo])
				sim.step_n(stats.resolve(weapon, &"cycle_ticks") / 1000 + 1)
			assert_eq(items.item_count(), before - 3, "%s/%s three rounds consumed, nothing else" % [frame, ammo])
			assert_eq(actors.health_of(dummy)[&"body"], 100000000 - hits * expected_damage, "%s/%s dummy health reconciles" % [frame, ammo])
	assert_true(combinations >= 4, "two frames x two rounds ran (%d combinations)" % combinations)


func _do(sim: SimRoot, kind: StringName, payload: Dictionary) -> bool:
	var before: int = sim.dispatched_count()
	assert_eq(sim.submit(SimCommand.new(sim.get_tick() + 1, kind, payload)), OK, "submit %s" % kind)
	sim.step()
	return sim.dispatched_count() == before + 1
