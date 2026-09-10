extends Node

## Honest playbook actor = this Godot process as a body (ADR 0009 option C).
## Curl POST is not the user. Same-process puppets are not this path.

var world: ScenarioWorld

var _result: Dictionary = {
	"ok": false,
	"principal_id": "",
	"did": "",
	"seated": false,
	"error": "",
}


func _ready() -> void:
	await get_tree().process_frame
	await _run()


func _run() -> void:
	var spec := _load_spec(world.playbook_path)
	if spec.is_empty():
		_fail("bad_playbook")
		return
	var steps: Array = spec.get("steps", [])
	for step_any in steps:
		var step := str(step_any)
		printerr("playbook step: ", step)
		var err := await _do_step(step)
		if not err.is_empty():
			_fail(err)
			return
	var p: Player = world.local_player()
	_result["ok"] = true
	_result["principal_id"] = p.principal_id if p else ""
	_result["did"] = world.console.current_did if world.console else ""
	_result["seated"] = world.seated_peer_id == multiplayer.get_unique_id()
	_result.erase("error")
	_emit_and_quit(0)


func _do_step(step: String) -> String:
	match step:
		"join":
			return await _step_join()
		"pickup_nearest_document":
			return await _step_pickup()
		"sit_laptop":
			return await _step_sit()
		"wait_console_ready":
			return await _step_console_ready()
		"create_plaque":
			return await _step_create()
		"eve_deny":
			return await _step_eve_deny()
		_:
			return "unknown_step:%s" % step


func _step_join() -> String:
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if world.local_player() != null:
			return ""
		await get_tree().create_timer(0.1).timeout
	return "join_timeout"


func _step_pickup() -> String:
	var p: Player = world.local_player()
	if p == null:
		return "no_body"
	var doc_id: String = world._nearest_free_document(p.global_position)
	if doc_id.is_empty():
		# Walk toward tray even if we don't know yet; papers start free.
		doc_id = "paper-1"
	var target: Vector3 = world.documents[doc_id].position if world.documents.has(doc_id) else Vector3(-3.2, 0.6, -4.0)
	var err := await _steer_to(target, 1.35, 25000)
	if not err.is_empty():
		return err
	p.bot_interact = true
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		p = world.local_player()
		if p and p.keyed:
			p.bot_move = Vector3.ZERO
			return ""
		p.bot_interact = true
		await get_tree().create_timer(0.2).timeout
	return "pickup_timeout"


func _step_sit() -> String:
	var p: Player = world.local_player()
	if p == null:
		return "no_body"
	var err := await _steer_to(world.laptop_pos, 2.05, 25000)
	if not err.is_empty():
		return err
	if world.seated_peer_id != 0 and world.seated_peer_id != p.peer_id:
		return "laptop_occupied"
	p.bot_interact = true
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		p = world.local_player()
		if p and p.seated:
			p.bot_move = Vector3.ZERO
			return ""
		p.bot_interact = true
		await get_tree().create_timer(0.2).timeout
	return "sit_timeout"


func _step_console_ready() -> String:
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if world.console and world.console.console_idle():
			return ""
		await get_tree().create_timer(0.2).timeout
	return "console_timeout"


func _step_create() -> String:
	if world.console == null:
		return "no_console"
	world.console.playbook_create()
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		if world.console.last_tag == "create" and world.console.console_idle():
			if world.console.last_code >= 400:
				return "create_http_%s" % world.console.last_code
			_result["did"] = world.console.current_did
			return ""
		await get_tree().create_timer(0.2).timeout
	return "create_timeout"


func _step_eve_deny() -> String:
	if world.console == null:
		return "no_console"
	world.console.playbook_eve_deny()
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		if world.console.last_tag == "advance_eve" and world.console.console_idle():
			if world.console.last_code == 403:
				return ""
			return "eve_expected_403_got_%s" % world.console.last_code
		await get_tree().create_timer(0.2).timeout
	return "eve_deny_timeout"


func _steer_to(target: Vector3, stop_dist: float, timeout_ms: int) -> String:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var p: Player = world.local_player()
		if p == null:
			return "no_body"
		var to: Vector3 = target - p.global_position
		to.y = 0.0
		if to.length() <= stop_dist:
			p.bot_move = Vector3.ZERO
			return ""
		p.bot_move = to.normalized()
		await get_tree().create_timer(0.05).timeout
	return "steer_timeout"


func _load_spec(path: String) -> Dictionary:
	var resolved := path
	if resolved.is_empty():
		resolved = "res://playbooks/first-login.json"
	elif not resolved.begins_with("res://") and not resolved.begins_with("/"):
		var named := "res://playbooks/%s.json" % resolved
		if FileAccess.file_exists(named):
			resolved = named
		elif FileAccess.file_exists("res://playbooks/%s" % resolved):
			resolved = "res://playbooks/%s" % resolved
	if not FileAccess.file_exists(resolved):
		printerr("playbook missing: ", resolved)
		return {}
	var f := FileAccess.open(resolved, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _fail(reason: String) -> void:
	_result["ok"] = false
	_result["error"] = reason
	var p: Player = world.local_player()
	if p:
		_result["principal_id"] = p.principal_id
		_result["seated"] = p.seated
	if world.console:
		_result["did"] = world.console.current_did
	_emit_and_quit(1)


func _emit_and_quit(code: int) -> void:
	print(JSON.stringify(_result))
	get_tree().quit(code)
