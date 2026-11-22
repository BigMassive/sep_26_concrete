extends Node

## Host test setup. One Godot process switches personas and presses the same
## console controls a seated person uses. This is not the option-C peer playbook
## (ADR 0009): a joining process does not own both bodies or this console.
## Chain writes still wait on OTP. Bodies teleport; they do not walk the room.

var world: ScenarioWorld
var stay: bool = false

var _pin := "13579"
var _alice_pin := ""
var _result := {
	"ok": false,
	"name": "",
	"helen_pin": "",
	"alice_pin": "",
	"session": "",
	"principal_id": "",
	"error": "",
}


func _ready() -> void:
	await get_tree().process_frame
	await _run()


func _run() -> void:
	if not world.join_address.is_empty():
		_fail("scenario_is_host_only")
		return
	var spec := _load_spec(world.scenario_path)
	if spec.is_empty():
		_fail("bad_scenario")
		return
	_result["name"] = str(spec.get("name", ""))
	var spec_pin := str(spec.get("pin", "")).strip_edges()
	if spec_pin.length() == 5:
		_pin = spec_pin
	_result["helen_pin"] = _pin
	if bool(spec.get("stay", false)):
		stay = true
	var steps: Array = spec.get("steps", [])
	for step_any in steps:
		var step := str(step_any)
		printerr("scenario step: ", step)
		var err := await _do_step(step)
		if not err.is_empty():
			_fail(err)
			return
	var console: NodeConsole = world.console
	_result["ok"] = true
	_result["alice_pin"] = _alice_pin
	_result["session"] = str(console.session_username) if console else ""
	_result["principal_id"] = str(console.session_principal_id) if console else ""
	_result.erase("error")
	_finish(0)


func _do_step(step: String) -> String:
	match step:
		"helen_pickup_keys":
			return await _pickup_named("Helen", "paper-helen")
		"helen_sit":
			return await _sit_named("Helen")
		"helen_genesis":
			return await _helen_genesis()
		"alice_give_slip":
			return await _alice_give_slip()
		"helen_w1":
			return await _helen_w1()
		"helen_logout":
			return await _helen_logout()
		"alice_pickup_keys":
			return await _pickup_named("Alice", "paper-alice")
		"alice_login":
			return await _alice_login()
		_:
			return "unknown_step:%s" % step


func _helen_genesis() -> String:
	var err := await _sit_named("Helen")
	if not err.is_empty():
		return err
	err = await _wait_idle(20000)
	if not err.is_empty():
		return err
	var console: NodeConsole = world.console
	if bool(console._lab.get("genesis_complete", false)):
		return "genesis_already_done"
	if console._screen != "w0_tabs" or console._w0_tabs == null:
		return "w0_not_open"
	console._w0_tabs.current_tab = 1
	console._on_populate_graph()
	var pin_edit: Variant = console._graph_inputs.get("pin")
	if not (pin_edit is LineEdit):
		return "pin_field_missing"
	var user := str(console._graph_text("username"))
	var pk := str(console._graph_text("public_key"))
	if user != "Helen" or pk != "mldsa87:paper-helen":
		return "populate_not_helen"
	(pin_edit as LineEdit).text = _pin
	(pin_edit as LineEdit).text_changed.emit(_pin)
	console._on_run_graph()
	return await _wait_genesis()


func _wait_genesis() -> String:
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		var console: NodeConsole = world.console
		if console._pending.is_empty() and not console._busy:
			if console.session_username == "Helen" and bool(console._lab.get("genesis_complete", false)):
				return ""
			var status := str(console.status_label.text)
			if status.contains("failed") or status.contains("denied") or status.contains("dropped") or status.contains("unreachable"):
				return status
		await get_tree().create_timer(0.2).timeout
	return "genesis_timeout"


func _alice_give_slip() -> String:
	var err := await _pickup_named("Alice", "paper-alice-pub")
	if not err.is_empty():
		return err
	var alice := world.controlled_player()
	var helen := world._player_for_persona("Helen")
	if alice == null or helen == null:
		return "give_nobody"
	if not helen.seated:
		return "helen_not_seated"
	alice.global_position = helen.global_position + Vector3(-1.4, 0.0, 0.0)
	alice.velocity = Vector3.ZERO
	alice.bot_move = Vector3.ZERO
	await get_tree().physics_frame
	world._try_give()
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if helen.inventory.has("paper-alice-pub"):
			return ""
		await get_tree().process_frame
	return "give_timeout"


func _helen_w1() -> String:
	world._select_persona("Helen")
	var err := await _wait_idle(20000)
	if not err.is_empty():
		return err
	var console: NodeConsole = world.console
	console._open_workspace("w1")
	err = await _wait_workspace("w1")
	if not err.is_empty():
		return err
	console._on_populate_graph()
	if console._graph_text("username") != "Alice":
		return "populate_not_alice"
	if console._graph_text("public_key") != "mldsa87:paper-alice":
		return "populate_not_alice_key"
	console._on_run_graph()
	return await _wait_w1()


func _wait_workspace(id: String) -> String:
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		var console: NodeConsole = world.console
		if console._pending.is_empty() and console._workspace_id == id and console._screen == "workspace" and console._graph_inputs.has("username"):
			return ""
		var status := str(console.status_label.text)
		if status.begins_with("HTTPRequest error") or status.begins_with("Workspace failed"):
			return status
		await get_tree().create_timer(0.2).timeout
	return "workspace_timeout"


func _wait_w1() -> String:
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		var console: NodeConsole = world.console
		if console._pending.is_empty() and not console._busy:
			var pin := str(console._shown_pin)
			if pin.length() == 5:
				_alice_pin = pin
				_result["alice_pin"] = pin
				return ""
			var status := str(console.status_label.text)
			if status.contains("failed") or status.contains("denied") or status.contains("dropped"):
				return status
		await get_tree().create_timer(0.2).timeout
	return "w1_timeout"


func _helen_logout() -> String:
	world._select_persona("Helen")
	var err := await _wait_idle(20000)
	if not err.is_empty():
		return err
	var console: NodeConsole = world.console
	console._return_to_menu()
	err = await _wait_screen("launcher", 20000)
	if not err.is_empty():
		return err
	if not _press("Exit session"):
		return "exit_session_missing"
	err = await _wait_screen("login", 20000)
	if not err.is_empty():
		return err
	if not str(console.session_username).is_empty():
		return "still_logged_in"
	world._request_unsit_controlled()
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if world.seated_peer_id == 0:
			return ""
		await get_tree().process_frame
	return "unsit_timeout"


func _alice_login() -> String:
	if _alice_pin.length() != 5:
		return "alice_pin_missing"
	var err := await _sit_named("Alice")
	if not err.is_empty():
		return err
	var console: NodeConsole = world.console
	console._show_login()
	var fields := _line_edits()
	var user := fields.get("LoginUser") as LineEdit
	var key := fields.get("LoginKey") as LineEdit
	var pin := fields.get("LoginPin") as LineEdit
	if user == null or key == null or pin == null:
		return "login_fields_missing"
	if user.text != "Alice" or key.text != "paper-alice-sk":
		return "login_not_alice"
	pin.text = _alice_pin
	pin.text_changed.emit(_alice_pin)
	if not _press("Login"):
		return "login_button_missing"
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if console._pending.is_empty() and console.session_username == "Alice" and console._screen == "launcher":
			return ""
		var status := str(console.status_label.text)
		if status.begins_with("Login failed") or status.contains("occupied"):
			return status
		await get_tree().create_timer(0.2).timeout
	return "login_timeout"


func _pickup_named(persona: String, doc_id: String) -> String:
	world._select_persona(persona)
	var p := world.controlled_player()
	if p == null:
		return "no_body"
	if p.seated:
		return "seated_cannot_pickup"
	if not world.documents.has(doc_id):
		return "missing_%s" % doc_id
	var at: Vector3 = world.documents[doc_id].position
	p.global_position = Vector3(at.x, 0.05, at.z)
	p.velocity = Vector3.ZERO
	p.bot_move = Vector3.ZERO
	await get_tree().physics_frame
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if p.inventory.has(doc_id):
			return ""
		p.bot_interact = true
		await get_tree().create_timer(0.2).timeout
	return "pickup_timeout:%s" % doc_id


func _sit_named(persona: String) -> String:
	world._select_persona(persona)
	var p := world.controlled_player()
	if p == null:
		return "no_body"
	if p.seated:
		return ""
	if world.seated_peer_id != 0:
		return "laptop_occupied"
	p.global_position = world.laptop_pos
	p.velocity = Vector3.ZERO
	p.bot_move = Vector3.ZERO
	await get_tree().physics_frame
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if p.seated:
			p.bot_move = Vector3.ZERO
			return ""
		p.bot_interact = true
		await get_tree().create_timer(0.2).timeout
	return "sit_timeout"


func _wait_idle(timeout_ms: int) -> String:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var console: NodeConsole = world.console
		if console and console._pending.is_empty() and not console._busy:
			return ""
		await get_tree().create_timer(0.2).timeout
	return "console_busy"


func _wait_screen(screen: String, timeout_ms: int) -> String:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var console: NodeConsole = world.console
		if console._pending.is_empty() and str(console._screen) == screen:
			return ""
		await get_tree().create_timer(0.2).timeout
	return "screen_timeout:%s" % screen


func _press(label: String) -> bool:
	var console: NodeConsole = world.console
	if console == null:
		return false
	var stack: Array = [console.screen_host]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text == label:
			(n as Button).pressed.emit()
			return true
		for ch in n.get_children():
			stack.append(ch)
	return false


func _line_edits() -> Dictionary:
	var out := {}
	var console: NodeConsole = world.console
	var stack: Array = [console.screen_host]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is LineEdit and not str(n.name).is_empty():
			out[str(n.name)] = n
		for ch in n.get_children():
			stack.append(ch)
	return out


func _load_spec(path: String) -> Dictionary:
	var resolved := path
	if resolved.is_empty():
		return {}
	if not resolved.begins_with("res://") and not resolved.begins_with("/"):
		var named := "res://scenarios/%s.json" % resolved
		if FileAccess.file_exists(named):
			resolved = named
		elif FileAccess.file_exists("res://scenarios/%s" % resolved):
			resolved = "res://scenarios/%s" % resolved
	if not FileAccess.file_exists(resolved):
		printerr("scenario missing: ", resolved)
		return {}
	var f := FileAccess.open(resolved, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _fail(reason: String) -> void:
	_result["ok"] = false
	_result["error"] = reason
	_result["alice_pin"] = _alice_pin
	var console: NodeConsole = world.console
	if console:
		_result["session"] = str(console.session_username)
		_result["principal_id"] = str(console.session_principal_id)
	_finish(1)


func _finish(code: int) -> void:
	print(JSON.stringify(_result))
	if stay:
		return
	get_tree().quit(code)
