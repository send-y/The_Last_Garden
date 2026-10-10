extends SceneTree

const CATALOG_PATH := "res://src/characters/npc_generation_catalog.gd"
const GENERATOR_PATH := "res://src/characters/npc_profile_generator.gd"
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	check(FileAccess.file_exists(CATALOG_PATH) and FileAccess.file_exists(GENERATOR_PATH), "Missing NPC generator/catalog implementation")
	if failures > 0:
		quit(1)
		return
	var catalog = load(CATALOG_PATH).new()
	var generator = load(GENERATOR_PATH).new()
	check(catalog.validate().is_empty(), "Shipped generator content validates")
	var first: Dictionary = generator.generate(94, "core:test_person", catalog.data)
	check(bool(first.ok), "Compatible person is generated")
	check(first == generator.generate(94, "core:test_person", catalog.data), "Generation is deterministic")
	var profiles: Dictionary = {}
	for seed_value: int in range(80):
		var result: Dictionary = generator.generate(seed_value, "core:test_person", catalog.data)
		check(bool(result.ok), "All tested seeds produce a compatible profile")
		if not bool(result.ok): continue
		check(generator.validate_profile(result.profile, catalog.data).is_empty(), "Complete profile obeys lore and component restrictions")
		var fingerprint: Dictionary = {}
		for field: String in ["community_id","childhood_id","experience_id","aspiration_id","value_ids","heritage_ids"]: fingerprint[field] = result.profile[field]
		profiles[JSON.stringify(fingerprint)] = true
	check(profiles.size() > 20, "Seed sample includes distinct profiles")
	var impossible: Dictionary = catalog.data.duplicate(true)
	impossible.experiences = []
	check(not bool(generator.generate(94, "core:test_person", impossible).ok), "Impossible catalogue fails finitely")
	impossible = catalog.data.duplicate(true)
	for experience: Dictionary in impossible.experiences: experience.min_age = 101
	check(not generator.generate(94,"core:test_person",impossible).ok,"Nonempty impossible catalogue stops after bounded retries")
	var forbidden: Dictionary = catalog.data.duplicate(true)
	var child_id: String = first.profile.childhood_id
	for child: Dictionary in forbidden.childhoods:
		if String(child.id) == child_id: child.excludes = [first.profile.heritage_ids[0]]
	check(not generator.validate_profile(first.profile,forbidden).is_empty(),"Cross-group exclusion sees plural heritage IDs")
	var dependent: Dictionary = catalog.data.duplicate(true)
	for child: Dictionary in dependent.childhoods:
		child["requires"] = child.get("requires",{})
		child.requires["heritage_ids"] = [dependent.heritages[0].id]
	dependent.heritages = [dependent.heritages[0]]
	check(generator.generate(94,"core:test_person",dependent).ok,"Childhood can depend on previously selected family heritage")
	var wrong: Dictionary = first.profile.duplicate(true)
	wrong.age_years = 28
	wrong.history_facts.append({"id":"core:old_war", "kind":"personal", "years_ago":50, "minimum_age":8})
	check(not generator.validate_profile(wrong, catalog.data).is_empty(), "Young person cannot remember old collapse firsthand")
	wrong.history_facts[-1].kind = "family_account"
	check(generator.validate_profile(wrong, catalog.data).is_empty(), "Inherited account is not a personal memory")
	wrong.history_facts[-1] = {"id":"core:undated_collapse", "kind":"personal", "historical":true}
	check(not generator.validate_profile(wrong, catalog.data).is_empty(), "Undated historical event cannot become certain personal memory")
	wrong = first.profile.duplicate(true)
	wrong.age_years = 5
	check(not generator.validate_profile(wrong, catalog.data).is_empty(), "Training cannot exceed a person's eligible lifetime")
	wrong = first.profile.duplicate(true)
	wrong.technology = "space"
	check(not generator.validate_profile(wrong, catalog.data).is_empty(), "Unsupported technology is rejected")
	if failures == 0: print("PASS: procedural NPC content, deterministic generation and lore constraints")
	quit(0 if failures == 0 else 1)
