class_name ScenarioWorld
extends Node3D

## 3D lab veneer (ADR 0009 stages 1–4). Not ground truth.
## World Transform3D ≠ OTP belief (ADR 0004). Laptop pose is presentation-only.

const SESSION_PORT := 24567
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const CONSOLE_SCENE := preload("res://scenes/main.tscn")
const CONCRETE_MARK := preload("res://images/concrete_icon_200.png")
const SIT_RANGE := 2.4
const PICKUP_RANGE := 1.8
const GIVE_RANGE := 2.2
const LOCAL_AVATAR_BASE := 1000

## OTP is ground truth. Paper tray is set dressing this beat (docs/11): pickup
## does not onboard King. Keying is W0 genesis / login import on the console.

@onready var players_root: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var prompt_label: Label = %Prompt
@onready var inventory_label: Label = %Inventory
@onready var session_label: Label = %Session
@onready var seated_layer: Control = %SeatedLayer
@onready var subviewport: SubViewport = %ConsoleViewport
@onready var console_display: TextureRect = %ConsoleDisplay
@onready var hint_label: Label = %SeatedHint
@onready var persona_badge: Label = %PersonaBadge
@onready var persona_edge: VBoxContainer = %PersonaEdge
@onready var persona_layer: Control = %PersonaLayer
@onready var fullscreen_button: Button = %FullscreenButton

var join_address: String = ""
var playbook_path: String = ""
var scenario_path: String = ""
var scenario_stay: bool = false
var console_only: bool = false
var seated_peer_id: int = 0
var console: NodeConsole = null
var documents: Dictionary = {}
var laptop_pos: Vector3 = Vector3(3.0, 0.85, -4.0)
var _interact_cool: Dictionary = {}
var personas: Array = []
var active_persona_name: String = ""
var _paper_parent: Node3D = null
var _persona_list: VBoxContainer = null
var _persona_name_edit: LineEdit = null
var _persona_enter: Button = null


func _ready() -> void:
	add_to_group("world")
	_parse_args()
	if console_only:
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return
	spawner.add_spawnable_scene("res://scenes/player.tscn")
	_build_room()
	_setup_console()
	_setup_persona_hud()
	fullscreen_button.pressed.connect(_toggle_fullscreen)
	_sync_fullscreen_button()
	_setup_multiplayer()
	if not playbook_path.is_empty() or not scenario_path.is_empty() or OS.has_feature("headless"):
		_ensure_persona("Helen")
		_ensure_persona("Alice")
		_select_persona("Helen")
		_hide_persona_landing()
	else:
		_show_persona_landing()
	if not scenario_path.is_empty():
		var scenario := preload("res://scripts/scenario_runner.gd").new()
		scenario.world = self
		scenario.stay = scenario_stay
		add_child(scenario)
	elif not playbook_path.is_empty():
		var runner := preload("res://scripts/playbook_runner.gd").new()
		runner.world = self
		add_child(runner)


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := args[i]
		if a == "--join" and i + 1 < args.size():
			join_address = args[i + 1]
			i += 2
		elif a.begins_with("--join="):
			join_address = a.get_slice("=", 1)
			i += 1
		elif a == "--playbook" and i + 1 < args.size():
			playbook_path = args[i + 1]
			i += 2
		elif a.begins_with("--playbook="):
			playbook_path = a.get_slice("=", 1)
			i += 1
		elif a == "--scenario" and i + 1 < args.size():
			scenario_path = args[i + 1]
			i += 2
		elif a.begins_with("--scenario="):
			scenario_path = a.get_slice("=", 1)
			i += 1
		elif a == "--stay":
			scenario_stay = true
			i += 1
		elif a == "--console-only":
			console_only = true
			i += 1
		else:
			i += 1


func _setup_console() -> void:
	console = CONSOLE_SCENE.instantiate() as NodeConsole
	console.use_session_actor = true
	console.session_changed.connect(_on_console_session)
	subviewport.add_child(console)
	subviewport.handle_input_locally = false
	console_display.texture = subviewport.get_texture()
	console_display.mouse_filter = Control.MOUSE_FILTER_STOP
	console_display.focus_mode = Control.FOCUS_CLICK
	console_display.gui_input.connect(_on_console_display_input)
	if not console_display.resized.is_connected(_fit_console_viewport):
		console_display.resized.connect(_fit_console_viewport)
	if not get_window().size_changed.is_connected(_fit_console_viewport):
		get_window().size_changed.connect(_fit_console_viewport)
	seated_layer.visible = false
	call_deferred("_fit_console_viewport")


func _console_device_scale() -> float:
	var scale := 1.0
	var screen := DisplayServer.window_get_current_screen()
	var screen_scale := DisplayServer.screen_get_scale(screen)
	if screen_scale > scale:
		scale = screen_scale
	var content := get_window().content_scale_factor
	if content > scale:
		scale = content
	var logical := get_viewport().get_visible_rect().size
	var window_px := Vector2(DisplayServer.window_get_size())
	if logical.x > 1.0 and logical.y > 1.0:
		var ratio := minf(window_px.x / logical.x, window_px.y / logical.y)
		if ratio > scale:
			scale = ratio
	return maxf(scale, 1.0)


func _console_logical_size() -> Vector2:
	var logical := console_display.size
	if logical.x >= 2.0 and logical.y >= 2.0:
		return logical
	var root := get_viewport().get_visible_rect().size
	return Vector2(
		root.x - console_display.offset_left + console_display.offset_right,
		root.y - console_display.offset_top + console_display.offset_bottom
	)


func _fit_console_viewport() -> void:
	if subviewport == null or console_display == null:
		return
	var logical := _console_logical_size()
	if logical.x < 2.0 or logical.y < 2.0:
		return
	var scale := _console_device_scale()
	var px := Vector2i(ceili(logical.x * scale), ceili(logical.y * scale))
	var layout := Vector2i(maxi(1, roundi(logical.x)), maxi(1, roundi(logical.y)))
	if subviewport.size == px and subviewport.size_2d_override == layout:
		return
	subviewport.size_2d_override = layout
	subviewport.size_2d_override_stretch = true
	subviewport.size = px
	print("console viewport %s layout %s scale %.3f" % [px, layout, scale])


func _on_console_display_input(event: InputEvent) -> void:
	var outgoing := event
	if event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		outgoing = event.duplicate()
		var scale := _console_device_scale()
		outgoing.position *= scale
		if outgoing is InputEventMouse:
			outgoing.global_position *= scale
	if event is InputEventMouseButton and event.pressed:
		console_display.grab_focus()
	subviewport.push_input(outgoing)
	console_display.accept_event()


func _setup_multiplayer() -> void:
	var peer := ENetMultiplayerPeer.new()
	if join_address.is_empty():
		var err := peer.create_server(SESSION_PORT)
		if err != OK:
			push_error("Listen-server failed on %s: %s" % [SESSION_PORT, err])
			session_label.text = "Host failed on port %s" % SESSION_PORT
			return
		multiplayer.multiplayer_peer = peer
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		_add_player(1)
		session_label.text = "Host · listen :%s · E interact · G give paper · Esc unsit" % SESSION_PORT
		if not OS.has_feature("headless") and not persona_landing_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		var host := "127.0.0.1"
		var port := SESSION_PORT
		if ":" in join_address:
			var parts := join_address.rsplit(":", false, 1)
			host = parts[0]
			port = int(parts[1])
		else:
			host = join_address
		var err := peer.create_client(host, port)
		if err != OK:
			push_error("Join failed %s:%s" % [host, port])
			session_label.text = "Join failed"
			return
		multiplayer.multiplayer_peer = peer
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		session_label.text = "Joining %s:%s…" % [host, port]


func _on_connected() -> void:
	session_label.text = "Joined · peer %s" % multiplayer.get_unique_id()
	if not OS.has_feature("headless") and not persona_landing_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_connection_failed() -> void:
	session_label.text = "Connection failed"
	printerr("CONCRETE session: connection failed")


func _on_server_disconnected() -> void:
	session_label.text = "Host disconnected"


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_add_player(id)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if seated_peer_id == id:
		seated_peer_id = 0
		seat_changed.rpc(0)
	var path := NodePath(str(id))
	if players_root.has_node(path):
		players_root.get_node(path).queue_free()


func _add_player(id: int) -> void:
	if players_root.has_node(str(id)):
		return
	var p: CharacterBody3D = PLAYER_SCENE.instantiate()
	p.name = str(id)
	p.position = Vector3(-2.0 + float((id - 1) % 4) * 1.3, 0.05, 3.6)
	players_root.add_child(p, true)
	if p is Player and id == multiplayer.get_unique_id():
		(p as Player).set_controlled(true)


func local_player() -> Player:
	var id := multiplayer.get_unique_id()
	if players_root.has_node(str(id)):
		return players_root.get_node(str(id)) as Player
	return null


func controlled_player() -> Player:
	var named := _player_for_persona(active_persona_name)
	if named != null:
		return named
	return local_player()


func _player_by_peer(peer_id: int) -> Player:
	if players_root.has_node(str(peer_id)):
		return players_root.get_node(str(peer_id)) as Player
	return null


func _player_for_persona(name: String) -> Player:
	if name.is_empty():
		return null
	for child in players_root.get_children():
		if child is Player and str(child.persona_name) == name:
			return child
	return null


func _process(_delta: float) -> void:
	_fit_console_viewport()
	_update_hud()
	if not multiplayer.is_server():
		return
	for child in players_root.get_children():
		if child is Player and child.intent_interact:
			var pid: int = child.peer_id
			var now_ms := Time.get_ticks_msec()
			if int(_interact_cool.get(pid, 0)) + 350 > now_ms:
				child.intent_interact = false
				continue
			_interact_cool[pid] = now_ms
			child.intent_interact = false
			_server_try_interact(child)


func _console_text_focused() -> bool:
	if subviewport == null:
		return false
	return subviewport.gui_get_focus_owner() is LineEdit


func _forward_console_key(event: InputEvent) -> bool:
	# The console is a texture. Mouse clicks are pushed from the display;
	# keystrokes stay on this window unless they are pushed too. Without
	# that, the W0 PIN field (and every other console field) cannot be typed
	# into, including after a fullscreen toggle moves window focus.
	if not seated_layer.visible or persona_landing_open() or subviewport == null:
		return false
	if not (event is InputEventKey or event is InputEventShortcut):
		return false
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		return false
	if event is InputEventKey and event.keycode == KEY_G and event.pressed and not event.echo and not _console_text_focused():
		return false
	subviewport.push_input(event.duplicate(), true)
	get_viewport().set_input_as_handled()
	return true


func _input(event: InputEvent) -> void:
	if _forward_console_key(event):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if persona_landing_open():
			if not active_persona_name.is_empty():
				_hide_persona_landing()
			get_viewport().set_input_as_handled()
			return
		var c := controlled_player()
		if c != null and c.seated:
			_request_unsit_controlled()
			get_viewport().set_input_as_handled()
			return
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G:
		if not persona_landing_open():
			_try_give()
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and not _local_is_seated() and not persona_landing_open():
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if get_viewport().gui_get_hovered_control() == fullscreen_button:
				return
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _local_is_seated() -> bool:
	var p := controlled_player()
	return p != null and p.seated


func _toggle_fullscreen() -> void:
	var win := get_window()
	var full := win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
	win.mode = Window.MODE_WINDOWED if full else Window.MODE_FULLSCREEN
	_sync_fullscreen_button()
	_fit_console_viewport()


func _sync_fullscreen_button() -> void:
	if fullscreen_button == null:
		return
	var mode := get_window().mode
	var full := mode == Window.MODE_FULLSCREEN or mode == Window.MODE_EXCLUSIVE_FULLSCREEN
	fullscreen_button.text = "Exit full screen" if full else "Enter full screen"


func _update_hud() -> void:
	_sync_fullscreen_button()
	_refresh_persona_badge()
	var p := controlled_player()
	if persona_landing_open():
		prompt_label.text = ""
		return
	if p == null:
		prompt_label.text = ""
		inventory_label.text = "Inventory: —"
		return
	if p.inventory.size() == 0:
		inventory_label.text = "Inventory: (empty)"
	else:
		var names: PackedStringArray = PackedStringArray()
		for id in p.inventory:
			names.append(_paper_label(str(id)))
		inventory_label.text = "Inventory: %s" % ", ".join(names)
	if p.seated:
		prompt_label.text = ""
		return
	var near_doc := _nearest_free_document(p.global_position)
	var d_lap := _xz_dist(p.global_position, laptop_pos)
	var give_to := _nearest_give_target(p)
	if near_doc != "" and _xz_dist(p.global_position, documents[near_doc].position) < PICKUP_RANGE:
		prompt_label.text = "E · pick up paper"
	elif give_to != null:
		var who := str(give_to.persona_name)
		if who.is_empty():
			who = "the other person"
		prompt_label.text = "G · give %s to %s" % [_paper_label(_give_doc_id(p)), who]
	elif d_lap < SIT_RANGE:
		if seated_peer_id != 0 and seated_peer_id != p.peer_id:
			prompt_label.text = "Laptop occupied (one seater)"
		else:
			prompt_label.text = "E · sit at node-1 console"
	else:
		prompt_label.text = ""


func _nearest_give_target(giver: Player) -> Player:
	if giver == null or giver.inventory.size() == 0:
		return null
	var best: Player = null
	var best_d := GIVE_RANGE
	for child in players_root.get_children():
		if not (child is Player) or child == giver:
			continue
		var d := _xz_dist(giver.global_position, child.global_position)
		if d < best_d:
			best_d = d
			best = child
	return best


func _try_give() -> void:
	var giver := controlled_player()
	if giver == null or giver.seated:
		return
	if multiplayer.is_server():
		_server_give(giver.peer_id)
	else:
		request_give.rpc()


@rpc("any_peer", "reliable")
func request_give() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	_server_give(sender)


func _server_give(giver_id: int) -> void:
	var giver := _player_by_peer(giver_id)
	if giver == null or giver.inventory.size() == 0:
		return
	var target := _nearest_give_target(giver)
	if target == null:
		return
	var doc_id := _give_doc_id(giver)
	if doc_id.is_empty():
		return
	var items := giver.inventory.duplicate()
	var idx := -1
	for i in range(items.size()):
		if str(items[i]) == doc_id:
			idx = i
			break
	if idx < 0:
		return
	items.remove_at(idx)
	giver.apply_bind(giver.principal_id, items)
	var theirs := target.inventory.duplicate()
	if not theirs.has(doc_id):
		theirs.append(doc_id)
	target.apply_bind(target.principal_id, theirs)
	if documents.has(doc_id):
		documents[doc_id].taken = true
		documents[doc_id].taken_by = target.peer_id
	replicate_bind.rpc(giver.peer_id, giver.principal_id, items)
	replicate_bind.rpc(target.peer_id, target.principal_id, theirs)


func _give_doc_id(giver: Player) -> String:
	if giver == null or giver.inventory.size() == 0:
		return ""
	var own_slip := ""
	var any_slip := ""
	for i in range(giver.inventory.size()):
		var doc_id := str(giver.inventory[i])
		var doc: Variant = documents.get(doc_id)
		if typeof(doc) != TYPE_DICTIONARY:
			continue
		if str(doc.get("kind", "")) != "public_slip":
			continue
		any_slip = doc_id
		if str(doc.get("holder_name", "")) == str(giver.persona_name):
			own_slip = doc_id
	if not own_slip.is_empty():
		return own_slip
	if not any_slip.is_empty():
		return any_slip
	return str(giver.inventory[giver.inventory.size() - 1])


func _request_unsit_controlled() -> void:
	var c := controlled_player()
	if c == null or not c.seated:
		return
	if multiplayer.is_server():
		_server_unsit(c.peer_id)
	else:
		request_unsit.rpc()


func _xz_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _nearest_free_document(from: Vector3) -> String:
	var best := ""
	var best_d := 999.0
	for id in documents.keys():
		var rec: Dictionary = documents[id]
		if rec.get("taken", false):
			continue
		var d := _xz_dist(from, rec.position)
		if d < best_d:
			best_d = d
			best = id
	return best


func _server_try_interact(player: Player) -> void:
	if player.seated:
		return
	var doc_id := _nearest_free_document(player.global_position)
	if doc_id != "" and _xz_dist(player.global_position, documents[doc_id].position) <= PICKUP_RANGE:
		_server_pickup(player.peer_id, doc_id)
		return
	if _xz_dist(player.global_position, laptop_pos) <= SIT_RANGE:
		_server_sit(player.peer_id)


func _server_pickup(peer_id: int, doc_id: String) -> void:
	if not documents.has(doc_id) or documents[doc_id].taken:
		return
	documents[doc_id].taken = true
	documents[doc_id].taken_by = peer_id
	var mesh: Node3D = documents[doc_id].mesh
	if mesh:
		mesh.visible = false
	apply_pickup.rpc(doc_id, peer_id)


@rpc("authority", "reliable", "call_local")
func apply_pickup(doc_id: String, by_peer: int) -> void:
	if documents.has(doc_id):
		documents[doc_id].taken = true
		documents[doc_id].taken_by = by_peer
		var mesh: Node3D = documents[doc_id].mesh
		if mesh:
			mesh.visible = false
	var p := _player_by_peer(by_peer)
	if p == null:
		return
	var items := p.inventory.duplicate()
	if not items.has(doc_id):
		items.append(doc_id)
	p.apply_bind(p.principal_id, items)
	if multiplayer.is_server():
		_server_store_bind(by_peer, p.principal_id, items)


@rpc("any_peer", "reliable")
func report_bind(principal: String, items: PackedStringArray) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	_server_store_bind(sender, principal, items)


func _server_store_bind(peer_id: int, principal: String, items: PackedStringArray) -> void:
	if not players_root.has_node(str(peer_id)):
		return
	var p: Player = players_root.get_node(str(peer_id))
	p.apply_bind(principal, items)
	replicate_bind.rpc(peer_id, principal, items)


@rpc("authority", "reliable", "call_remote")
func replicate_bind(peer_id: int, principal: String, items: PackedStringArray) -> void:
	if not players_root.has_node(str(peer_id)):
		return
	var p: Player = players_root.get_node(str(peer_id))
	p.apply_bind(principal, items)


func _server_sit(peer_id: int) -> void:
	if seated_peer_id != 0:
		return
	if not players_root.has_node(str(peer_id)):
		return
	var p: Player = players_root.get_node(str(peer_id))
	if _xz_dist(p.global_position, laptop_pos) > SIT_RANGE:
		return
	seated_peer_id = peer_id
	p.seated = true
	p.velocity = Vector3.ZERO
	seat_changed.rpc(peer_id)


func _server_unsit(peer_id: int) -> void:
	if seated_peer_id != peer_id:
		return
	var p := _player_by_peer(peer_id)
	if p:
		p.seated = false
	seated_peer_id = 0
	seat_changed.rpc(0)


@rpc("any_peer", "reliable", "call_local")
func request_unsit() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if seated_peer_id == sender:
		_server_unsit(sender)


@rpc("authority", "reliable", "call_local")
func seat_changed(peer_id: int) -> void:
	seated_peer_id = peer_id
	for child in players_root.get_children():
		if child is Player:
			child.seated = child.peer_id == peer_id and peer_id != 0
	_sync_console_visibility()


func _sync_console_visibility() -> void:
	var c := controlled_player()
	if c != null and c.seated:
		_enter_console()
	else:
		_leave_console()
	_refresh_persona_badge()


func _on_console_session(principal_id: String, username: String) -> void:
	var p := controlled_player()
	if p == null:
		return
	p.apply_bind(principal_id, p.inventory)
	if not username.is_empty():
		p.set_meta("session_username", username)


func _enter_console() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	seated_layer.visible = true
	_fit_console_viewport()
	if console:
		console.bind_actor("", false)
	hint_label.text = "Esc · stand up (session remains)  ·  Exit to menu leaves the workspace  ·  Exit session logs out"


func _leave_console() -> void:
	seated_layer.visible = false
	if controlled_player() != null and not OS.has_feature("headless") and not persona_landing_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _box(parent: Node, pos: Vector3, size: Vector3, color: Color, collision: bool = true) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	b.use_collision = collision
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	b.material = mat
	parent.add_child(b)
	return b


func _build_room() -> void:
	var room := Node3D.new()
	room.name = "Room"
	add_child(room)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.52, 0.62)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.65, 0.66, 0.7)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = false
	add_child(sun)

	_box(room, Vector3(0, -0.2, 0), Vector3(20, 0.4, 16), Color(0.28, 0.29, 0.31))
	_box(room, Vector3(0, 2.4, -8.0), Vector3(20, 5.0, 0.3), Color(0.72, 0.68, 0.62))
	_box(room, Vector3(0, 2.4, 8.0), Vector3(20, 5.0, 0.3), Color(0.72, 0.68, 0.62))
	_box(room, Vector3(-10.0, 2.4, 0), Vector3(0.3, 5.0, 16), Color(0.7, 0.66, 0.6))
	_box(room, Vector3(10.0, 2.4, 0), Vector3(0.3, 5.0, 16), Color(0.7, 0.66, 0.6))

	_box(room, Vector3(3.0, 0.55, -4.0), Vector3(2.6, 0.12, 1.3), Color(0.42, 0.28, 0.16))
	_box(room, Vector3(2.1, 0.25, -4.45), Vector3(0.12, 0.5, 0.12), Color(0.32, 0.2, 0.12))
	_box(room, Vector3(3.9, 0.25, -4.45), Vector3(0.12, 0.5, 0.12), Color(0.32, 0.2, 0.12))
	_box(room, Vector3(2.1, 0.25, -3.55), Vector3(0.12, 0.5, 0.12), Color(0.32, 0.2, 0.12))
	_box(room, Vector3(3.9, 0.25, -3.55), Vector3(0.12, 0.5, 0.12), Color(0.32, 0.2, 0.12))

	var laptop := _box(room, Vector3(3.0, 0.72, -3.85), Vector3(0.42, 0.04, 0.3), Color(0.12, 0.13, 0.15))
	laptop.name = "LaptopBase"
	var screen := _box(room, Vector3(3.0, 0.92, -4.02), Vector3(0.42, 0.32, 0.02), Color(0.15, 0.45, 0.55), false)
	screen.rotation_degrees = Vector3(-18, 0, 0)
	laptop_pos = Vector3(3.0, 0.0, -2.85)

	_box(room, Vector3(-3.2, 0.52, -4.0), Vector3(1.8, 0.08, 1.1), Color(0.48, 0.38, 0.26))
	_box(room, Vector3(-3.85, 0.22, -4.4), Vector3(0.1, 0.44, 0.1), Color(0.32, 0.22, 0.14))
	_box(room, Vector3(-2.55, 0.22, -4.4), Vector3(0.1, 0.44, 0.1), Color(0.32, 0.22, 0.14))
	_box(room, Vector3(-3.85, 0.22, -3.6), Vector3(0.1, 0.44, 0.1), Color(0.32, 0.22, 0.14))
	_box(room, Vector3(-2.55, 0.22, -3.6), Vector3(0.1, 0.44, 0.1), Color(0.32, 0.22, 0.14))
	_paper_parent = room

	var tray_tag := Label3D.new()
	tray_tag.text = "Collect identities here"
	tray_tag.position = Vector3(-3.2, 1.25, -4.0)
	tray_tag.font_size = 28
	tray_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	room.add_child(tray_tag)
	var tray_sub := Label3D.new()
	tray_sub.text = "papers appear when you generate a persona"
	tray_sub.position = Vector3(-3.2, 1.05, -4.0)
	tray_sub.font_size = 16
	tray_sub.modulate = Color(0.9, 0.86, 0.78)
	tray_sub.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	room.add_child(tray_sub)

	var node_tag := Label3D.new()
	node_tag.text = "node-1  :4000"
	node_tag.position = Vector3(3.0, 1.25, -3.7)
	node_tag.font_size = 32
	node_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	room.add_child(node_tag)


func persona_landing_open() -> bool:
	return persona_layer != null and persona_layer.visible


func credentials_from_active_persona() -> Dictionary:
	var rec := _persona_named(active_persona_name)
	if rec.is_empty():
		return {}
	return {
		"source": "persona",
		"paper_id": str(rec.get("paper_id", "")),
		"holder_name": str(rec.get("name", "")),
		"public_key": str(rec.get("public_key", "")),
		"private_key": str(rec.get("private_key", "")),
	}


func w1_admittee_credentials() -> Dictionary:
	var operator := _w1_operator()
	var skip := _w1_skip_names(operator)
	var slip: Dictionary = {}
	var other: Dictionary = {}
	for rec_any in _papers_from_player(operator):
		if typeof(rec_any) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = rec_any
		var holder := str(rec.get("holder_name", ""))
		if holder.is_empty() or skip.has(holder):
			continue
		if str(rec.get("kind", "")) == "public_slip":
			slip = rec
		else:
			other = rec
	var picked: Dictionary = slip if not slip.is_empty() else other
	if not picked.is_empty():
		return {
			"source": "inventory",
			"paper_id": str(picked.get("paper_id", "")),
			"holder_name": str(picked.get("holder_name", "")),
			"public_key": str(picked.get("public_key", "")),
			"private_key": "",
		}
	var fallback: Dictionary = {}
	for rec_any in personas:
		var rec: Dictionary = rec_any
		var name := str(rec.get("name", ""))
		if name.is_empty() or skip.has(name):
			continue
		fallback = rec
	if fallback.is_empty():
		return {}
	return {
		"source": "persona",
		"paper_id": str(fallback.get("paper_id", "")),
		"holder_name": str(fallback.get("name", "")),
		"public_key": str(fallback.get("public_key", "")),
		"private_key": "",
	}


func _w1_operator() -> Player:
	if seated_peer_id != 0:
		var seated := _player_by_peer(seated_peer_id)
		if seated != null:
			return seated
	return controlled_player()


func _w1_skip_names(operator: Player) -> Dictionary:
	var skip := {}
	if operator != null and not str(operator.persona_name).is_empty():
		skip[str(operator.persona_name)] = true
	return skip


func _setup_persona_hud() -> void:
	_build_persona_landing()
	_rebuild_persona_edge()
	_refresh_persona_badge()


func _build_persona_landing() -> void:
	for c in persona_layer.get_children():
		persona_layer.remove_child(c)
		c.queue_free()
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.05, 0.07, 0.82)
	persona_layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 480)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -280.0
	panel.offset_top = -240.0
	panel.offset_right = 280.0
	panel.offset_bottom = 240.0
	persona_layer.add_child(panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	panel.add_child(inner)
	var mark_row := CenterContainer.new()
	inner.add_child(mark_row)
	var mark := TextureRect.new()
	mark.custom_minimum_size = Vector2(72, 72)
	mark.texture = CONCRETE_MARK
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark_row.add_child(mark)
	var title := Label.new()
	title.text = "Personas"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	inner.add_child(title)
	var blurb := Label.new()
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.text = "Each generated name is a separate body in the room (colour only, for now). Switch who you walk. OTP login stays with the seated body — Alice will not see Helen's console. Collect papers at the identity desk and G-give them to another avatar."
	inner.add_child(blurb)
	_persona_list = VBoxContainer.new()
	_persona_list.add_theme_constant_override("separation", 6)
	inner.add_child(_persona_list)
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 8)
	_persona_name_edit = LineEdit.new()
	_persona_name_edit.placeholder_text = "Name (Helen, Alice, …)"
	_persona_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_persona_name_edit.text_submitted.connect(func(t: String) -> void: _on_generate_persona(t))
	add_row.add_child(_persona_name_edit)
	var gen := Button.new()
	gen.text = "Generate"
	gen.pressed.connect(func() -> void: _on_generate_persona(_persona_name_edit.text))
	add_row.add_child(gen)
	inner.add_child(add_row)
	_persona_enter = Button.new()
	_persona_enter.text = "Enter world"
	_persona_enter.pressed.connect(_hide_persona_landing)
	inner.add_child(_persona_enter)
	_refresh_persona_list()


func _refresh_persona_list() -> void:
	if _persona_list == null:
		return
	for c in _persona_list.get_children():
		_persona_list.remove_child(c)
		c.queue_free()
	if personas.is_empty():
		var empty := Label.new()
		empty.text = "No personas yet."
		_persona_list.add_child(empty)
	for rec_any in personas:
		var rec: Dictionary = rec_any
		var name := str(rec.get("name", ""))
		var row := HBoxContainer.new()
		var lab := Label.new()
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.text = name
		if name == active_persona_name:
			lab.text = "%s  (controlling)" % name
		row.add_child(lab)
		var sw := Button.new()
		sw.text = "Switch"
		sw.pressed.connect(_select_persona.bind(name))
		row.add_child(sw)
		_persona_list.add_child(row)
	if _persona_enter:
		_persona_enter.disabled = active_persona_name.is_empty()
		if active_persona_name.is_empty():
			_persona_enter.text = "Enter world"
		else:
			_persona_enter.text = "Enter world as %s" % active_persona_name


func _rebuild_persona_edge() -> void:
	for c in persona_edge.get_children():
		persona_edge.remove_child(c)
		c.queue_free()
	var head := Label.new()
	head.text = "Switch"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	persona_edge.add_child(head)
	for rec_any in personas:
		var rec: Dictionary = rec_any
		var name := str(rec.get("name", ""))
		var b := Button.new()
		b.text = name
		b.toggle_mode = true
		b.button_pressed = name == active_persona_name
		b.pressed.connect(_select_persona.bind(name))
		persona_edge.add_child(b)
	var roster := Button.new()
	roster.text = "Personas…"
	roster.pressed.connect(_show_persona_landing)
	persona_edge.add_child(roster)


func _refresh_persona_badge() -> void:
	if persona_badge == null:
		return
	if active_persona_name.is_empty():
		persona_badge.text = "Controlling: —"
		return
	var line := "Controlling: %s" % active_persona_name
	var you := controlled_player()
	if you != null and you.seated:
		line += " — at node-1"
	elif seated_peer_id != 0:
		var seater := _player_by_peer(seated_peer_id)
		if seater != null:
			var who := str(seater.persona_name)
			if who.is_empty():
				who = Player.display_name_for_peer(seater.peer_id)
			line += "  ·  %s at node-1" % who
	persona_badge.text = line


func _show_persona_landing() -> void:
	persona_layer.visible = true
	_refresh_persona_list()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _hide_persona_landing() -> void:
	if active_persona_name.is_empty():
		return
	persona_layer.visible = false
	if not _local_is_seated() and not OS.has_feature("headless"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_generate_persona(raw: String) -> void:
	var name := raw.strip_edges()
	if name.is_empty():
		return
	_ensure_persona(name)
	_select_persona(name)
	if _persona_name_edit:
		_persona_name_edit.text = ""


func _ensure_persona(name: String) -> void:
	if not _persona_named(name).is_empty():
		return
	var slug := _persona_slug(name)
	var rec := {
		"name": name,
		"public_key": "mldsa87:paper-%s" % slug,
		"private_key": "paper-%s-sk" % slug,
		"paper_id": "paper-%s" % slug,
	}
	personas.append(rec)
	_spawn_persona_paper(rec)
	_spawn_persona_public_slip(rec)
	_bind_or_spawn_avatar(rec, personas.size() - 1)
	_rebuild_persona_edge()
	_refresh_persona_list()


func _select_persona(name: String) -> void:
	if _persona_named(name).is_empty():
		return
	active_persona_name = name
	_apply_control()
	_refresh_persona_badge()
	_rebuild_persona_edge()
	_refresh_persona_list()
	_sync_console_visibility()


func _apply_control() -> void:
	for child in players_root.get_children():
		if child is Player:
			var on := str(child.persona_name) == active_persona_name and not active_persona_name.is_empty()
			child.set_controlled(on)
			child._refresh_nametag()


func _bind_or_spawn_avatar(rec: Dictionary, index: int) -> void:
	var name := str(rec.get("name", ""))
	if _player_for_persona(name) != null:
		return
	if index == 0:
		var host_body := local_player()
		if host_body:
			_apply_persona_to_player(host_body, rec, index)
		return
	var id := LOCAL_AVATAR_BASE + index
	if players_root.has_node(str(id)):
		_apply_persona_to_player(_player_by_peer(id), rec, index)
		return
	var p: CharacterBody3D = PLAYER_SCENE.instantiate()
	p.name = str(id)
	p.position = Vector3(-3.4, 0.05, -2.15)
	players_root.add_child(p, true)
	_apply_persona_to_player(p as Player, rec, index)
	if multiplayer.is_server():
		spawn_local_avatar.rpc(id, p.position, name, index)


@rpc("authority", "reliable", "call_remote")
func spawn_local_avatar(id: int, pos: Vector3, persona: String, color_idx: int) -> void:
	if players_root.has_node(str(id)):
		return
	var p: CharacterBody3D = PLAYER_SCENE.instantiate()
	p.name = str(id)
	p.position = pos
	players_root.add_child(p, true)
	var rec := _persona_named(persona)
	if rec.is_empty():
		rec = {"name": persona}
	_apply_persona_to_player(p as Player, rec, color_idx)


func _apply_persona_to_player(p: Player, rec: Dictionary, index: int) -> void:
	if p == null:
		return
	p.persona_name = str(rec.get("name", ""))
	p.body_color = Player.color_for_peer(index + 1)
	p._apply_color()
	p._refresh_nametag()


func _persona_named(name: String) -> Dictionary:
	for rec_any in personas:
		var rec: Dictionary = rec_any
		if str(rec.get("name", "")) == name:
			return rec
	return {}


func _persona_slug(name: String) -> String:
	var s := name.strip_edges().to_lower()
	var out := ""
	for i in s.length():
		var ch := s.substr(i, 1)
		var code := ch.unicode_at(0)
		var ok := (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		if ok:
			out += ch
		elif not out.is_empty() and not out.ends_with("-"):
			out += "-"
	if out.is_empty():
		return "persona"
	return out.trim_suffix("-")


func _spawn_persona_paper(rec: Dictionary) -> void:
	if _paper_parent == null:
		return
	var doc_id := str(rec.get("paper_id", ""))
	if documents.has(doc_id):
		return
	var i := documents.size()
	var pos := Vector3(-3.45 + float(i) * 0.38, 0.62, -4.05)
	var tint := Color(0.93, 0.91, 0.82).darkened(0.04 * float(i % 3))
	_spawn_document(_paper_parent, doc_id, pos, tint, {
		"holder_name": str(rec.get("name", "")),
		"public_key": str(rec.get("public_key", "")),
		"private_key": str(rec.get("private_key", "")),
		"kind": "keys",
	})


func _spawn_persona_public_slip(rec: Dictionary) -> void:
	if _paper_parent == null:
		return
	var doc_id := "%s-pub" % str(rec.get("paper_id", ""))
	if documents.has(doc_id):
		return
	var i := documents.size()
	var pos := Vector3(-3.45 + float(i) * 0.38, 0.62, -3.62)
	var tint := Color(0.78, 0.86, 0.92)
	_spawn_document(_paper_parent, doc_id, pos, tint, {
		"holder_name": str(rec.get("name", "")),
		"public_key": str(rec.get("public_key", "")),
		"private_key": "",
		"kind": "public_slip",
	})


func credentials_from_local_inventory() -> Dictionary:
	var papers := papers_from_local_inventory()
	if papers.is_empty():
		return {}
	var rec: Dictionary = papers[papers.size() - 1]
	return {
		"paper_id": str(rec.get("paper_id", "")),
		"holder_name": str(rec.get("holder_name", "")),
		"public_key": str(rec.get("public_key", "")),
		"private_key": str(rec.get("private_key", "")),
		"kind": str(rec.get("kind", "keys")),
		"source": "inventory",
	}


func papers_from_local_inventory() -> Array:
	return _papers_from_player(controlled_player())


func _papers_from_player(p: Player) -> Array:
	var out: Array = []
	if p == null:
		return out
	for i in range(p.inventory.size()):
		var doc_id := str(p.inventory[i])
		var doc: Variant = documents.get(doc_id)
		if typeof(doc) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = doc
		if str(rec.get("public_key", "")).is_empty():
			continue
		out.append({
			"paper_id": doc_id,
			"holder_name": str(rec.get("holder_name", doc_id)),
			"public_key": str(rec.get("public_key", "")),
			"private_key": str(rec.get("private_key", "")),
			"kind": str(rec.get("kind", "keys")),
		})
	return out


func _paper_label(doc_id: String) -> String:
	var doc: Variant = documents.get(doc_id)
	if typeof(doc) == TYPE_DICTIONARY:
		var who := str(doc.get("holder_name", ""))
		if str(doc.get("kind", "")) == "public_slip":
			return "%s public key" % who if not who.is_empty() else "public key"
		if not who.is_empty():
			return "%s keys" % who
	return doc_id


func _spawn_document(parent: Node, doc_id: String, pos: Vector3, color: Color, creds: Dictionary = {}) -> void:
	var mesh := _box(parent, pos, Vector3(0.28, 0.02, 0.36), color, false)
	mesh.name = doc_id
	var tag := Label3D.new()
	var who := str(creds.get("holder_name", "ISSUANCE"))
	var kind := str(creds.get("kind", "keys"))
	if kind == "public_slip":
		tag.text = "%s\npublic key\n(hand this)" % who
	else:
		tag.text = "%s\npaper keys" % who
	tag.position = Vector3(0, 0.12, 0)
	tag.font_size = 14
	tag.pixel_size = 0.004
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.add_child(tag)
	documents[doc_id] = {
		"position": pos,
		"taken": false,
		"taken_by": 0,
		"mesh": mesh,
		"holder_name": str(creds.get("holder_name", "")),
		"public_key": str(creds.get("public_key", "")),
		"private_key": str(creds.get("private_key", "")),
		"kind": str(creds.get("kind", "keys")),
	}
