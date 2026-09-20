extends GcityTest

const PROPERTY_CASES: int = 10_000
const SEED_ORDER: int = 20260921
const SEED_REMOVE: int = 20260922
const SEED_BASES: int = 20260923
const SEED_CACHE: int = 20260924

const STATS: Array[StringName] = [&"damage", &"recoil", &"sway"]
const ENTITY_ACTOR: int = 1
const ENTITY_PISTOL: int = 2
const ENTITY_CROWBAR: int = 3


func _resolver() -> StatResolver:
	var r := StatResolver.new()
	for stat: StringName in STATS:
		assert_eq(r.register_stat(stat, 1000), OK, "register %s" % stat)
	return r


func _mod(stat: StringName, cls: StringName, value: int, tags: Array[StringName] = []) -> Dictionary:
	return {"stat": stat, "class": cls, "value": value, "source": &"test.src", "tags": tags}


# ---------------------------------------------------------------- units

func test_registration_and_defaults() -> void:
	var r := StatResolver.new()
	assert_eq(r.class_ids(), [&"add", &"mul"] as Array[StringName], "built-in classes in fold order")
	assert_eq(r.register_stat(&"damage", 34500), OK, "register")
	assert_eq(r.register_stat(&"damage", 1), ERR_ALREADY_EXISTS, "duplicate")
	assert_eq(r.register_stat(&"Bad Id", 1), ERR_INVALID_PARAMETER, "id format")
	assert_true(r.has_stat(&"damage"), "has")
	assert_eq(r.resolve(7, &"damage"), 34500, "default base resolves for any entity")
	assert_eq(r.resolve(7, &"unknown"), 0, "unregistered stat resolves to 0 (and logs)")
	assert_eq(r.get_base(7, &"damage"), 34500, "default base")
	assert_eq(r.set_base(7, &"damage", 40000), OK, "set base")
	assert_eq(r.get_base(7, &"damage"), 40000, "base read back")
	assert_eq(r.get_base(8, &"damage"), 34500, "other entities keep the default")
	assert_eq(r.set_base(7, &"unknown", 1), ERR_DOES_NOT_EXIST, "set base on unknown stat")


func test_arithmetic_is_exact_and_truncates_once() -> void:
	var r := _resolver()
	assert_eq(r.set_base(ENTITY_PISTOL, &"damage", 34500), OK, "base 34.5")
	var h_add: int = r.add_modifier(ENTITY_PISTOL, _mod(&"damage", &"add", 500))
	var h_mul: int = r.add_modifier(ENTITY_PISTOL, _mod(&"damage", &"mul", 1000))
	assert_true(h_add >= 1 and h_mul >= 1 and h_add != h_mul, "handles issued")
	assert_eq(r.resolve(ENTITY_PISTOL, &"damage"), 38500, "(34500 + 500) * 11000 / 10000")
	var h_mul2: int = r.add_modifier(ENTITY_PISTOL, _mod(&"damage", &"mul", 1000))
	assert_eq(r.resolve(ENTITY_PISTOL, &"damage"), 42000, "multipliers sum within the class: 35000 * 12000 / 10000")
	assert_eq(r.remove_modifier(h_mul2), OK, "remove")
	var h_odd: int = r.add_modifier(ENTITY_PISTOL, _mod(&"damage", &"add", 1))
	assert_eq(r.resolve(ENTITY_PISTOL, &"damage"), 38501, "35001 * 11000 / 10000 = 38501.1 truncated once")
	assert_eq(r.remove_modifier(h_odd), OK, "remove odd")
	var h_neg: int = r.add_modifier(ENTITY_PISTOL, _mod(&"damage", &"mul", -20000))
	assert_eq(r.resolve(ENTITY_PISTOL, &"damage"), 0, "multiplier sum below -10000 clamps to 0")
	assert_eq(r.remove_modifier(h_neg), OK, "remove neg")
	assert_eq(r.resolve(ENTITY_PISTOL, &"damage"), 38500, "back to the prior value")


func test_modifier_validation() -> void:
	var r := _resolver()
	assert_eq(r.add_modifier(1, {"stat": &"nope", "class": &"add", "value": 1, "source": &"s"}), -1, "unknown stat")
	assert_eq(r.add_modifier(1, {"stat": &"damage", "class": &"pow", "value": 1, "source": &"s"}), -1, "unknown class")
	assert_eq(r.add_modifier(1, {"stat": &"damage", "class": &"add", "value": 1.5, "source": &"s"}), -1, "float value")
	assert_eq(r.add_modifier(1, {"stat": &"damage", "class": &"add", "value": 1}), -1, "missing source")
	assert_eq(r.add_modifier(1, {"stat": &"damage", "class": &"add", "value": 1, "source": "s"}), -1, "source must be StringName")
	assert_eq(r.add_modifier(1, {"stat": &"damage", "class": &"add", "value": 1, "source": &"s", "tags": "x"}), -1, "tags must be array")
	assert_eq(r.add_modifier(1, {"stat": &"damage", "class": &"add", "value": 1, "source": &"s", "tags": [&"Bad Tag"]}), -1, "tag format")
	assert_eq(r.add_modifier(1, {"stat": &"damage", "class": &"add", "value": 1, "source": &"s", "extra": 1}), -1, "unexpected key")
	assert_eq(r.modifier_count(), 0, "nothing landed")
	assert_eq(r.remove_modifier(42), ERR_DOES_NOT_EXIST, "remove unknown handle")
	assert_eq(r.resolve(1, &"damage"), 1000, "value untouched by rejected modifiers")


func test_wielded_items_inherit_by_tag() -> void:
	var r := _resolver()
	assert_eq(r.set_tags(ENTITY_PISTOL, [&"weapon_class.handgun", &"weapon"]), OK, "pistol tags")
	assert_eq(r.set_tags(ENTITY_CROWBAR, [&"weapon"]), OK, "crowbar tags")
	assert_eq(r.set_inherits(ENTITY_PISTOL, ENTITY_ACTOR), OK, "pistol wielded")
	assert_eq(r.set_inherits(ENTITY_CROWBAR, ENTITY_ACTOR), OK, "crowbar wielded")
	var perk: int = r.add_modifier(ENTITY_ACTOR, _mod(&"damage", &"mul", 1000, [&"weapon_class.handgun"]))
	assert_true(perk >= 1, "perk added")
	assert_eq(r.resolve(ENTITY_PISTOL, &"damage"), 1100, "handgun perk reaches the pistol")
	assert_eq(r.resolve(ENTITY_CROWBAR, &"damage"), 1000, "and not the crowbar")
	assert_eq(r.resolve(ENTITY_ACTOR, &"damage"), 1100, "the actor's own resolution includes its own modifiers")
	var untagged: int = r.add_modifier(ENTITY_ACTOR, _mod(&"damage", &"add", 50))
	assert_true(untagged >= 1, "untagged added")
	assert_eq(r.resolve(ENTITY_ACTOR, &"damage"), 1155, "untagged applies to the actor: (1000+50)*1.1")
	assert_eq(r.resolve(ENTITY_PISTOL, &"damage"), 1100, "untagged modifiers do not reach wielded items")
	assert_eq(r.remove_modifier(perk), OK, "perk removed")
	assert_eq(r.resolve(ENTITY_PISTOL, &"damage"), 1000, "cache invalidated through inheritance")
	assert_eq(r.set_inherits(ENTITY_PISTOL, -1), OK, "unwield")
	var perk2: int = r.add_modifier(ENTITY_ACTOR, _mod(&"damage", &"mul", 1000, [&"weapon"]))
	assert_true(perk2 >= 1, "perk2")
	assert_eq(r.resolve(ENTITY_PISTOL, &"damage"), 1000, "unwielded item inherits nothing")
	assert_eq(r.resolve(ENTITY_CROWBAR, &"damage"), 1100, "still-wielded crowbar matches the weapon tag")
	assert_eq(r.set_inherits(ENTITY_ACTOR, ENTITY_CROWBAR), ERR_INVALID_PARAMETER, "cycle rejected")
	assert_eq(r.set_inherits(ENTITY_ACTOR, ENTITY_ACTOR), ERR_INVALID_PARAMETER, "self rejected")
	assert_eq(r.set_tags(ENTITY_PISTOL, [&"Bad Tag"]), ERR_INVALID_PARAMETER, "tag format")
	assert_eq(r.get_tags(ENTITY_CROWBAR), [&"weapon"] as Array[StringName], "tags read back")
	assert_eq(r.get_inherits(ENTITY_CROWBAR), ENTITY_ACTOR, "inherits read back")


func test_extension_a_new_class_is_a_registration_call() -> void:
	var r := _resolver()
	var floor_fold: Callable = func(acc: int, sum: int) -> int: return maxi(acc, sum)
	assert_eq(r.register_modifier_class(&"floor", 200, floor_fold), OK, "register a class that folds after mul")
	assert_eq(r.register_modifier_class(&"floor", 200, floor_fold), ERR_ALREADY_EXISTS, "duplicate class")
	assert_eq(r.class_ids(), [&"add", &"mul", &"floor"] as Array[StringName], "fold order by (order, id)")
	var h: int = r.add_modifier(1, _mod(&"damage", &"floor", 5000))
	assert_true(h >= 1, "floor modifier")
	assert_eq(r.resolve(1, &"damage"), 5000, "floor lifts 1000 to 5000")
	var snap: Dictionary = r.snapshot()
	var classes: Dictionary = snap["classes"]
	assert_eq(classes[&"floor"], 200, "class order is in the snapshot")


func test_snapshot_is_hashable_state_and_cache_is_not() -> void:
	var a := _resolver()
	var b := _resolver()
	assert_eq(StateHash.of(a.snapshot()), StateHash.of(b.snapshot()), "identically built resolvers hash equal")
	assert_eq(a.set_base(1, &"damage", 5), OK, "base")
	assert_ne(StateHash.of(a.snapshot()), StateHash.of(b.snapshot()), "a base change changes the hash")
	assert_eq(b.set_base(1, &"damage", 5), OK, "base b")
	var h: int = a.add_modifier(1, _mod(&"damage", &"add", 1, [&"t"]))
	var hb: int = b.add_modifier(1, _mod(&"damage", &"add", 1, [&"t"]))
	assert_eq(h, hb, "handles are deterministic")
	assert_eq(StateHash.of(a.snapshot()), StateHash.of(b.snapshot()), "same operations, same hash")
	var before: String = StateHash.of(a.snapshot())
	assert_eq(a.resolve(1, &"damage"), 6, "resolve populates the cache")
	assert_eq(StateHash.of(a.snapshot()), before, "resolving (caching) does not change state")
	assert_eq(a.remove_modifier(h), OK, "remove")
	assert_eq(b.remove_modifier(hb), OK, "remove b")
	assert_eq(StateHash.of(a.snapshot()), StateHash.of(b.snapshot()), "still equal after removal")
	assert_ne(StateHash.of(a.snapshot()), before, "removal changed the hash (next_handle advanced, modifier gone)")


# ---------------------------------------------------------------- properties (claim 3)

## Random modifier for a random stat. Values keep the arithmetic well inside int64.
func _random_mod(rng: RandomNumberGenerator, tags: Array[StringName] = []) -> Dictionary:
	var stat: StringName = STATS[rng.randi_range(0, STATS.size() - 1)]
	var cls: StringName = &"add" if rng.randf() < 0.6 else &"mul"
	var value: int = rng.randi_range(-3000, 3000) if cls == &"add" else rng.randi_range(-4000, 4000)
	return _mod(stat, cls, value, tags)


## Half the time the tag that entity 2 carries, else no tags. Built explicitly: a
## typed-array literal inside a ternary is not inferred as typed at runtime.
func _maybe_tag(rng: RandomNumberGenerator) -> Array[StringName]:
	var tags: Array[StringName] = []
	if rng.randf() < 0.5:
		tags.append(&"t")
	return tags


## (a) Applying the same modifiers in any order resolves to the same value.
func test_property_resolution_is_order_independent() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_ORDER
	var failures: int = 0
	for case: int in range(PROPERTY_CASES):
		var mods: Array[Dictionary] = []
		for i: int in range(rng.randi_range(1, 8)):
			mods.append(_random_mod(rng))
		var base: int = rng.randi_range(-50_000, 50_000)
		var a := _resolver()
		var b := _resolver()
		for stat: StringName in STATS:
			a.set_base(1, stat, base)
			b.set_base(1, stat, base)
		for m: Dictionary in mods:
			a.add_modifier(1, m)
		var shuffled: Array[Dictionary] = mods.duplicate()
		for i: int in range(shuffled.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp: Dictionary = shuffled[i]
			shuffled[i] = shuffled[j]
			shuffled[j] = tmp
		for m: Dictionary in shuffled:
			b.add_modifier(1, m)
		for stat: StringName in STATS:
			if a.resolve(1, stat) != b.resolve(1, stat):
				failures += 1
				if failures <= 3:
					fail("case %d: order changed %s: %d vs %d" % [case, stat, a.resolve(1, stat), b.resolve(1, stat)])
	assert_eq(failures, 0, "order-independent in all %d cases" % PROPERTY_CASES)


## (b) Adding then removing a modifier restores the exact prior value, for every stat.
func test_property_remove_restores_prior_value() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_REMOVE
	var failures: int = 0
	for case: int in range(PROPERTY_CASES):
		var r := _resolver()
		r.set_tags(2, [&"t"])
		r.set_inherits(2, 1)
		var entity: int = rng.randi_range(1, 2)
		for i: int in range(rng.randi_range(0, 6)):
			r.add_modifier(rng.randi_range(1, 2), _random_mod(rng, _maybe_tag(rng)))
		var before: Dictionary = {}
		for stat: StringName in STATS:
			before[stat] = r.resolve(entity, stat)
		var h: int = r.add_modifier(rng.randi_range(1, 2), _random_mod(rng, _maybe_tag(rng)))
		for stat: StringName in STATS:
			r.resolve(entity, stat)  # populate the cache with the modified value
		if r.remove_modifier(h) != OK:
			failures += 1
			continue
		for stat: StringName in STATS:
			if r.resolve(entity, stat) != before[stat]:
				failures += 1
				if failures <= 3:
					fail("case %d: %s was %d, after add+remove %d" % [case, stat, before[stat], r.resolve(entity, stat)])
	assert_eq(failures, 0, "add+remove restores in all %d cases" % PROPERTY_CASES)


## (c) No sequence of modifier operations mutates a base.
func test_property_bases_are_never_mutated() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_BASES
	var failures: int = 0
	for case: int in range(PROPERTY_CASES):
		var r := _resolver()
		var bases: Dictionary = {}
		for stat: StringName in STATS:
			if rng.randf() < 0.7:
				var b: int = rng.randi_range(-100_000, 100_000)
				r.set_base(1, stat, b)
				bases[stat] = b
			else:
				bases[stat] = 1000
		var handles: Array[int] = []
		for i: int in range(rng.randi_range(1, 10)):
			var op: float = rng.randf()
			if op < 0.7 or handles.is_empty():
				handles.append(r.add_modifier(1, _random_mod(rng)))
			else:
				var idx: int = rng.randi_range(0, handles.size() - 1)
				r.remove_modifier(handles[idx])
				handles.remove_at(idx)
			r.resolve(1, STATS[rng.randi_range(0, STATS.size() - 1)])
		for stat: StringName in STATS:
			if r.get_base(1, stat) != bases[stat]:
				failures += 1
				if failures <= 3:
					fail("case %d: base of %s drifted to %d" % [case, stat, r.get_base(1, stat)])
	assert_eq(failures, 0, "bases intact in all %d cases" % PROPERTY_CASES)


## (d) A cached value never differs from a fresh resolution of the same state: replay
## the same operation log into a second resolver that has never cached, and compare.
func test_property_cache_matches_fresh_resolution() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_CACHE
	var failures: int = 0
	for case: int in range(PROPERTY_CASES):
		var live := _resolver()
		live.set_tags(2, [&"t"])
		live.set_inherits(2, 1)
		var log: Array[Dictionary] = []
		var handles: Array[int] = []
		for i: int in range(rng.randi_range(1, 12)):
			var op: float = rng.randf()
			var entity: int = rng.randi_range(1, 2)
			if op < 0.5 or handles.is_empty():
				var m: Dictionary = _random_mod(rng, _maybe_tag(rng))
				handles.append(live.add_modifier(entity, m))
				log.append({"op": "add", "entity": entity, "mod": m})
			elif op < 0.7:
				var idx: int = rng.randi_range(0, handles.size() - 1)
				live.remove_modifier(handles[idx])
				log.append({"op": "remove", "handle": handles[idx]})
				handles.remove_at(idx)
			elif op < 0.85:
				var stat: StringName = STATS[rng.randi_range(0, STATS.size() - 1)]
				var b: int = rng.randi_range(-50_000, 50_000)
				live.set_base(entity, stat, b)
				log.append({"op": "base", "entity": entity, "stat": stat, "value": b})
			else:
				var parent: int = 1 if rng.randf() < 0.7 else -1
				live.set_inherits(2, parent)
				log.append({"op": "inherit", "parent": parent})
			# read through the cache after every operation
			live.resolve(1, STATS[rng.randi_range(0, STATS.size() - 1)])
			live.resolve(2, STATS[rng.randi_range(0, STATS.size() - 1)])
		var fresh := _resolver()
		fresh.set_tags(2, [&"t"])
		fresh.set_inherits(2, 1)
		for entry: Dictionary in log:
			var op: String = entry["op"]
			match op:
				"add":
					var e_entity: int = entry["entity"]
					var e_mod: Dictionary = entry["mod"]
					fresh.add_modifier(e_entity, e_mod)
				"remove":
					var e_handle: int = entry["handle"]
					fresh.remove_modifier(e_handle)
				"base":
					var b_entity: int = entry["entity"]
					var b_stat: StringName = entry["stat"]
					var b_value: int = entry["value"]
					fresh.set_base(b_entity, b_stat, b_value)
				"inherit":
					var parent: int = entry["parent"]
					fresh.set_inherits(2, parent)
		for entity: int in [1, 2]:
			for stat: StringName in STATS:
				if live.resolve(entity, stat) != fresh.resolve(entity, stat):
					failures += 1
					if failures <= 3:
						fail("case %d: cached %d vs fresh %d for entity %d %s" % [case, live.resolve(entity, stat), fresh.resolve(entity, stat), entity, stat])
		if StateHash.of(live.snapshot()) != StateHash.of(fresh.snapshot()):
			failures += 1
			if failures <= 3:
				fail("case %d: snapshots differ between cached and fresh resolvers" % case)
	assert_eq(failures, 0, "cache consistent in all %d cases" % PROPERTY_CASES)


# ---------------------------------------------------------------- restore

func test_restore_round_trips_and_rejects_hostile_input() -> void:
	var a := _resolver()
	assert_eq(a.set_base(1, &"damage", 5), OK, "base")
	assert_eq(a.set_tags(2, [&"t", &"a"]), OK, "tags")
	assert_eq(a.set_inherits(2, 1), OK, "inherit")
	var h1: int = a.add_modifier(1, _mod(&"damage", &"mul", 1000, [&"t"]))
	var h2: int = a.add_modifier(2, _mod(&"recoil", &"add", -7))
	assert_eq(a.remove_modifier(h1), OK, "remove one so next_handle is ahead of the live handles")
	assert_true(h2 >= 1, "h2")
	var snap: Dictionary = a.snapshot()
	var b := _resolver()
	assert_eq(b.restore(snap), OK, "restore")
	assert_eq(StateHash.of(b.snapshot()), StateHash.of(snap), "identical snapshot after restore")
	for entity: int in [1, 2]:
		for stat: StringName in STATS:
			assert_eq(b.resolve(entity, stat), a.resolve(entity, stat), "resolve %d %s" % [entity, stat])
	var h3a: int = a.add_modifier(1, _mod(&"sway", &"add", 1))
	var h3b: int = b.add_modifier(1, _mod(&"sway", &"add", 1))
	assert_eq(h3a, h3b, "handles continue identically")
	# string keys (as a JSON round trip would produce) are accepted
	var stringy: Dictionary = snap.duplicate(true)
	var stats_s: Dictionary = {}
	var stats_in: Dictionary = stringy["stats"]
	for key: StringName in stats_in:
		stats_s[String(key)] = stats_in[key]
	stringy["stats"] = stats_s
	var c := _resolver()
	assert_eq(c.restore(stringy), OK, "String keys accepted")
	assert_eq(StateHash.of(c.snapshot()), StateHash.of(snap), "and canonicalised back")
	var hostile: Array[Dictionary] = []
	var d: Dictionary
	d = snap.duplicate(true)
	d.erase("tags")
	hostile.append(d)
	d = snap.duplicate(true)
	d["next_handle"] = 1
	hostile.append(d)
	d = snap.duplicate(true)
	_sub(d, "stats")[&"damage"] = 999
	hostile.append(d)
	d = snap.duplicate(true)
	_sub(d, "classes")[&"pow"] = 5
	hostile.append(d)
	d = snap.duplicate(true)
	_sub(d, "bases")[1] = {&"nope": 1}
	hostile.append(d)
	d = snap.duplicate(true)
	_sub(d, "modifiers")[h2] = {"entity": 2, "stat": &"recoil", "class": &"add", "value": 1.5, "source": &"s", "tags": []}
	hostile.append(d)
	d = snap.duplicate(true)
	_sub(d, "modifiers")[h2] = {"entity": 2, "stat": &"recoil", "class": &"add", "value": 1, "source": &"s", "tags": ["b", "a"]}
	hostile.append(d)
	d = snap.duplicate(true)
	_sub(d, "tags")[2] = ["t", "a"]
	hostile.append(d)
	d = snap.duplicate(true)
	_sub(d, "inherits")[1] = 2
	hostile.append(d)
	d = snap.duplicate(true)
	_sub(d, "inherits")[3] = 3
	hostile.append(d)
	var i: int = 0
	for bad: Dictionary in hostile:
		var e := _resolver()
		assert_eq(e.restore(bad), ERR_INVALID_DATA, "hostile %d rejected" % i)
		assert_eq(StateHash.of(e.snapshot()), StateHash.of(_resolver().snapshot()), "hostile %d left it pristine" % i)
		i += 1


static func _sub(dict: Dictionary, key: String) -> Dictionary:
	var out: Dictionary = dict[key]
	return out
