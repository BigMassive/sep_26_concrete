class_name ScenarioWorld
extends Node3D

## 3D lab veneer (ADR 0009 stages 1–4). Not ground truth.
## World Transform3D ≠ OTP belief (ADR 0004). Laptop pose is presentation-only.

const SESSION_PORT := 24567
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const CONSOLE_SCENE := preload("res://scenes/main.tscn")
const OTP_BASE := "http://127.0.0.1:4000"
const SIT_RANGE := 2.4
const PICKUP_RANGE := 1.8

## OTP already onboards King at node-up (Bootstrap.fresh_bootstrap! / sidecar vault).
## Chronology gate is Godot-side: unkeyed bodies must not use that principal_id.
## First paper binds this body to the existing King key — we do not POST a second King.
## Later papers POST /v1/principals (Eve, colour-named users). Custody stays CONCRETE_VAULT_DIR.

@onready var players_root: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var prompt_label: Label = %Prompt
@onready var inventory_label: Label = %Inventory
@onready var session_label: Label = %Session
@onready var seated_layer: Control = %SeatedLayer
@onready var subviewport: SubViewport = %ConsoleViewport
@onready var hint_label: Label = %SeatedHint

var join_address: String = ""
var playbook_path: String = ""
var console_only: bool = false
var seated_peer_id: int = 0
var king_paper_claimed: bool = false
var console: NodeConsole = null
var documents: Dictionary = {}
var laptop_pos: Vector3 = Vector3(3.0, 0.85, -4.0)
var _interact_cool: Dictionary = {}


func _ready() -> void:
	add_to_group("world")
	_parse_args()
	if console_only:
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return
	spawner.add_spawnable_scene("res://scenes/player.tscn")
	_build_room()
	_setup_console()
	_setup_multiplayer()
	if not playbook_path.is_empty():
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
		elif a == "--console-only":
			console_only = true
			i += 1
		else:
			i += 1


func _setup_console() -> void:
	console = CONSOLE_SCENE.instantiate() as NodeConsole
	console.use_session_actor = true
	subviewport.add_child(console)
	seated_layer.visible = false


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
		session_label.text = "Host · listen :%s · E interact · Esc unsit" % SESSION_PORT
		if not OS.has_feature("headless"):
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
	if not OS.has_feature("headless"):
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


func local_player() -> Player:
	var id := multiplayer.get_unique_id()
	if players_root.has_node(str(id)):
		return players_root.get_node(str(id)) as Player
	return null


func _process(_delta: float) -> void:
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


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _local_is_seated() or seated_peer_id == multiplayer.get_unique_id():
			request_unsit.rpc()
			get_viewport().set_input_as_handled()
			return
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and not _local_is_seated():
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _local_is_seated() -> bool:
	var p := local_player()
	return p != null and p.seated


func _update_hud() -> void:
	var p := local_player()
	if p == null:
		prompt_label.text = ""
		inventory_label.text = "Inventory: —"
		return
	var items := ", ".join(p.inventory) if p.inventory.size() > 0 else "(empty)"
	inventory_label.text = "Inventory: %s" % items
	if p.seated:
		prompt_label.text = ""
		return
	var near_doc := _nearest_free_document(p.global_position)
	var d_lap := _xz_dist(p.global_position, laptop_pos)
	if near_doc != "" and _xz_dist(p.global_position, documents[near_doc].position) < PICKUP_RANGE:
		prompt_label.text = "E · pick up issuance document"
	elif d_lap < SIT_RANGE:
		if seated_peer_id != 0 and seated_peer_id != p.peer_id:
			prompt_label.text = "Laptop occupied (one seater)"
		else:
			prompt_label.text = "E · sit at node-1 console"
	else:
		prompt_label.text = ""


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
	var first_king := not king_paper_claimed
	if first_king:
		king_paper_claimed = true
	documents[doc_id].taken = true
	documents[doc_id].taken_by = peer_id
	var mesh: Node3D = documents[doc_id].mesh
	if mesh:
		mesh.visible = false
	apply_pickup.rpc(doc_id, peer_id, first_king, Player.display_name_for_peer(peer_id))


@rpc("authority", "reliable", "call_local")
func apply_pickup(doc_id: String, by_peer: int, first_king: bool, display_name: String) -> void:
	if documents.has(doc_id):
		documents[doc_id].taken = true
		documents[doc_id].taken_by = by_peer
		var mesh: Node3D = documents[doc_id].mesh
		if mesh:
			mesh.visible = false
	if by_peer != multiplayer.get_unique_id():
		return
	_bind_after_pickup(doc_id, first_king, display_name)


func _bind_after_pickup(doc_id: String, first_king: bool, display_name: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var principal := ""
	if first_king:
		http.request(OTP_BASE + "/v1/bootstrap")
		var completed: Array = await http.request_completed
		var code: int = completed[1]
		var body: PackedByteArray = completed[3]
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if code == 200 and typeof(parsed) == TYPE_DICTIONARY:
			principal = str(parsed.get("king", {}).get("id", ""))
		else:
			printerr("Issuance bind (King) failed: OTP %s" % code)
	else:
		var payload := JSON.stringify({"display_name": display_name})
		http.request(
			OTP_BASE + "/v1/principals",
			PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_POST,
			payload
		)
		var completed: Array = await http.request_completed
		var code: int = completed[1]
		var body: PackedByteArray = completed[3]
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if code < 400 and typeof(parsed) == TYPE_DICTIONARY:
			principal = str(parsed.get("principal", {}).get("id", ""))
		else:
			printerr("Issuance onboard failed: OTP %s" % code)
	http.queue_free()
	var p := local_player()
	if p == null:
		return
	var items := p.inventory.duplicate()
	if not items.has(doc_id):
		items.append(doc_id)
	p.apply_bind(principal, items)
	if multiplayer.is_server():
		_server_store_bind(multiplayer.get_unique_id(), principal, items)
	else:
		report_bind.rpc_id(1, principal, items)


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


@rpc("any_peer", "reliable", "call_local")
func request_unsit() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if seated_peer_id != sender:
		return
	if players_root.has_node(str(sender)):
		players_root.get_node(str(sender)).seated = false
	seated_peer_id = 0
	seat_changed.rpc(0)


@rpc("authority", "reliable", "call_local")
func seat_changed(peer_id: int) -> void:
	seated_peer_id = peer_id
	for child in players_root.get_children():
		if child is Player:
			child.seated = child.peer_id == peer_id and peer_id != 0
	if peer_id == multiplayer.get_unique_id():
		_enter_console()
	else:
		_leave_console()


func _enter_console() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	seated_layer.visible = true
	var p := local_player()
	if p and console:
		console.bind_actor(p.principal_id, p.keyed)
	hint_label.text = "Esc · stand up  ·  mouse/keyboard drive node-1"


func _leave_console() -> void:
	seated_layer.visible = false
	if local_player() != null and not OS.has_feature("headless"):
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

	_box(room, Vector3(-3.2, 0.52, -4.0), Vector3(1.1, 0.06, 0.7), Color(0.55, 0.45, 0.32))
	_spawn_document(room, "paper-1", Vector3(-3.45, 0.62, -4.05), Color(0.93, 0.91, 0.82))
	_spawn_document(room, "paper-2", Vector3(-2.95, 0.62, -3.95), Color(0.9, 0.88, 0.78))

	var tray_tag := Label3D.new()
	tray_tag.text = "Issuance tray\n(pick up — vault stays sidecar)"
	tray_tag.position = Vector3(-3.2, 1.15, -4.0)
	tray_tag.font_size = 28
	tray_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	room.add_child(tray_tag)

	var node_tag := Label3D.new()
	node_tag.text = "node-1  :4000"
	node_tag.position = Vector3(3.0, 1.25, -3.7)
	node_tag.font_size = 32
	node_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	room.add_child(node_tag)


func _spawn_document(parent: Node, doc_id: String, pos: Vector3, color: Color) -> void:
	var mesh := _box(parent, pos, Vector3(0.28, 0.02, 0.36), color, false)
	mesh.name = doc_id
	var tag := Label3D.new()
	tag.text = "ISSUANCE\n(public identity)"
	tag.position = Vector3(0, 0.12, 0)
	tag.font_size = 14
	tag.pixel_size = 0.004
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.add_child(tag)
	documents[doc_id] = {"position": pos, "taken": false, "taken_by": 0, "mesh": mesh}
