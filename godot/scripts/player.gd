class_name Player
extends CharacterBody3D

## Session body. Pose is ephemeral (ADR 0004). Colour is not cryptographic identity.

const SPEED := 4.8
const GRAVITY := 28.0
const LOOK_SENS := 0.0024

const COLOR_NAMES := ["Orange", "Teal", "Violet", "Lime", "Amber", "Rose"]
const COLORS := [
	Color(0.92, 0.38, 0.18),
	Color(0.18, 0.68, 0.78),
	Color(0.62, 0.38, 0.88),
	Color(0.45, 0.82, 0.28),
	Color(0.95, 0.72, 0.22),
	Color(0.88, 0.32, 0.52),
]

var peer_id: int = 0
var body_color: Color = Color.WHITE
var principal_id: String = ""
var keyed: bool = false
var inventory: PackedStringArray = PackedStringArray()
var seated: bool = false
var persona_name: String = ""
var locally_controlled: bool = false
var _body_meshes: Array = []

var intent_dir: Vector3 = Vector3.ZERO
var intent_yaw: float = 0.0
var intent_pitch: float = 0.0
var intent_interact: bool = false

## Headless playbook steers in world XZ; not a skip-to-keyed back door.
var bot_move: Vector3 = Vector3.ZERO
var bot_interact: bool = false

var _mouse_delta: Vector2 = Vector2.ZERO

@onready var camera: Camera3D = $Camera3D
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var nametag: Label3D = $Nametag


func _ready() -> void:
	peer_id = int(String(name))
	body_color = color_for_peer(peer_id)
	_build_humanoid()
	_apply_color()
	_refresh_nametag()
	_apply_first_person()
	camera.current = is_controlled()
	set_multiplayer_authority(1)


func is_controlled() -> bool:
	if locally_controlled:
		return true
	if not persona_name.is_empty():
		return false
	return multiplayer.get_unique_id() == peer_id


func set_controlled(on: bool) -> void:
	locally_controlled = on
	if camera:
		camera.current = on
	_apply_first_person()


static func color_for_peer(id: int) -> Color:
	return COLORS[maxi(id - 1, 0) % COLORS.size()]


static func display_name_for_peer(id: int) -> String:
	return COLOR_NAMES[maxi(id - 1, 0) % COLOR_NAMES.size()]


func _is_local() -> bool:
	return multiplayer.get_unique_id() == peer_id


func _persona_gate() -> bool:
	var worlds := get_tree().get_nodes_in_group("world")
	if worlds.is_empty():
		return false
	var w := worlds[0] as Node
	return w != null and w.has_method("persona_landing_open") and bool(w.call("persona_landing_open"))


func _apply_color() -> void:
	if _body_meshes.is_empty() and mesh:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = body_color
		mesh.set_surface_override_material(0, mat)
		return
	var skin := body_color.lerp(Color(0.91, 0.74, 0.62), 0.62)
	var cloth := body_color
	var pants := body_color.darkened(0.28)
	var hair := body_color.darkened(0.42).lerp(Color(0.18, 0.12, 0.08), 0.35)
	var shoes := body_color.darkened(0.55)
	for part_any in _body_meshes:
		var part: MeshInstance3D = part_any
		var kind := str(part.get_meta("part", "cloth"))
		var col := cloth
		match kind:
			"skin":
				col = skin
			"pants":
				col = pants
			"hair":
				col = hair
			"shoes":
				col = shoes
			"eye_white":
				col = Color(0.96, 0.96, 0.97)
			"eye_iris":
				col = Color(0.12, 0.1, 0.09)
			_:
				col = cloth
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.roughness = 0.72
		part.set_surface_override_material(0, mat)


func _build_humanoid() -> void:
	if mesh:
		mesh.visible = false
	_body_meshes.clear()
	# KidsCanCode / GDQuest-style dummy: capsule torso, sphere head, hinged arms.
	_add_sphere(Vector3(-0.09, 0.07, 0.03), 0.07, "shoes")
	_add_sphere(Vector3(0.09, 0.07, 0.03), 0.07, "shoes")
	_add_cylinder(Vector3(-0.09, 0.28, 0.0), 0.055, 0.32, "pants")
	_add_cylinder(Vector3(0.09, 0.28, 0.0), 0.055, 0.32, "pants")
	_add_cylinder(Vector3(-0.09, 0.62, 0.0), 0.07, 0.34, "pants")
	_add_cylinder(Vector3(0.09, 0.62, 0.0), 0.07, 0.34, "pants")
	_add_sphere(Vector3(0.0, 0.84, 0.0), 0.13, "pants", Vector3(1.35, 0.55, 1.1))
	_add_capsule(Vector3(0.0, 1.16, 0.0), 0.15, 0.52, "cloth")
	_add_arm(-1.0)
	_add_arm(1.0)
	_add_cylinder(Vector3(0.0, 1.42, 0.0), 0.045, 0.08, "skin", Vector3.ZERO, "head")
	_add_sphere(Vector3(0.0, 1.56, 0.0), 0.13, "skin", Vector3.ONE, "head")
	_add_sphere(Vector3(0.0, 1.64, -0.01), 0.135, "hair", Vector3(1.08, 0.52, 1.02), "head")
	_add_sphere(Vector3(-0.045, 1.57, -0.11), 0.028, "eye_white", Vector3.ONE, "head")
	_add_sphere(Vector3(0.045, 1.57, -0.11), 0.028, "eye_white", Vector3.ONE, "head")
	_add_sphere(Vector3(-0.045, 1.57, -0.132), 0.014, "eye_iris", Vector3.ONE, "head")
	_add_sphere(Vector3(0.045, 1.57, -0.132), 0.014, "eye_iris", Vector3.ONE, "head")
	_add_sphere(Vector3(0.0, 1.545, -0.125), 0.02, "skin", Vector3.ONE, "head")
	if camera:
		camera.position = Vector3(0.0, 1.58, -0.02)
	if nametag:
		nametag.position = Vector3(0.0, 1.95, 0.0)


func _add_arm(side: float) -> void:
	# Pivot chain: shoulder → upper → elbow → forearm/hand so segments meet.
	var upper_len := 0.28
	var fore_len := 0.26
	var shoulder := Node3D.new()
	shoulder.position = Vector3(side * 0.20, 1.34, 0.04)
	shoulder.rotation_degrees = Vector3(16.0, 0.0, side * 12.0)
	add_child(shoulder)
	var upper := _mesh_cylinder(0.045, upper_len, "cloth")
	upper.position = Vector3(0.0, -upper_len * 0.5, 0.0)
	shoulder.add_child(upper)
	var elbow := Node3D.new()
	elbow.position = Vector3(0.0, -upper_len, 0.0)
	elbow.rotation_degrees = Vector3(10.0, 0.0, side * 6.0)
	shoulder.add_child(elbow)
	var forearm := _mesh_cylinder(0.04, fore_len, "skin")
	forearm.position = Vector3(0.0, -fore_len * 0.5, 0.0)
	elbow.add_child(forearm)
	var hand := _mesh_sphere(0.045, "skin")
	hand.position = Vector3(0.0, -fore_len, 0.0)
	elbow.add_child(hand)


func _apply_first_person() -> void:
	var hide_head := is_controlled()
	for part_any in _body_meshes:
		var part: MeshInstance3D = part_any
		if str(part.get_meta("view", "body")) == "head":
			part.visible = not hide_head
	if nametag:
		nametag.visible = not hide_head


func _add_capsule(pos: Vector3, radius: float, height: float, part: String, view := "body") -> void:
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = height
	_add_part(cap, pos, part, Vector3.ZERO, Vector3.ONE, view)


func _add_sphere(pos: Vector3, radius: float, part: String, scale := Vector3.ONE, view := "body") -> void:
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	_add_part(sph, pos, part, Vector3.ZERO, scale, view)


func _add_cylinder(pos: Vector3, radius: float, height: float, part: String, rot := Vector3.ZERO, view := "body") -> void:
	var mi := _mesh_cylinder(radius, height, part, view)
	mi.position = pos
	mi.rotation = rot
	add_child(mi)


func _mesh_cylinder(radius: float, height: float, part: String, view := "body") -> MeshInstance3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	return _make_part(cyl, part, view)


func _mesh_sphere(radius: float, part: String, view := "body") -> MeshInstance3D:
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	return _make_part(sph, part, view)


func _make_part(mesh: Mesh, part: String, view := "body") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_meta("part", part)
	mi.set_meta("view", view)
	_body_meshes.append(mi)
	return mi


func _add_part(mesh: Mesh, pos: Vector3, part: String, rot := Vector3.ZERO, scale := Vector3.ONE, view := "body") -> void:
	var mi := _make_part(mesh, part, view)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scale
	add_child(mi)


func _refresh_nametag() -> void:
	var who := display_name_for_peer(peer_id)
	if not persona_name.is_empty():
		who = persona_name
	if keyed and not principal_id.is_empty():
		nametag.text = "%s\n%s" % [who, _short_principal(principal_id)]
	else:
		nametag.text = "%s\nunkeyed" % who
	nametag.modulate = body_color


func _short_principal(id: String) -> String:
	if id.length() <= 24:
		return id
	return "%s…%s" % [id.substr(0, 12), id.substr(id.length() - 8, 8)]


func _unhandled_input(event: InputEvent) -> void:
	if not is_controlled() or seated or _persona_gate():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_delta += event.relative


func _physics_process(delta: float) -> void:
	if is_controlled() and not seated and not _persona_gate():
		_update_local_look()
		_collect_and_send_intent()
	if multiplayer.is_server() and not seated:
		_simulate(delta)
	elif multiplayer.is_server() and seated:
		velocity = Vector3.ZERO


func _update_local_look() -> void:
	intent_yaw -= _mouse_delta.x * LOOK_SENS
	intent_pitch = clampf(intent_pitch - _mouse_delta.y * LOOK_SENS, -1.15, 1.15)
	_mouse_delta = Vector2.ZERO
	rotation.y = intent_yaw
	camera.rotation.x = intent_pitch


func _collect_and_send_intent() -> void:
	var dir := Vector3.ZERO
	if bot_move.length_squared() > 0.0001:
		dir = bot_move
		dir.y = 0.0
		if dir.length() > 1.0:
			dir = dir.normalized()
	else:
		var input := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_W):
			input.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S):
			input.y += 1.0
		if Input.is_physical_key_pressed(KEY_A):
			input.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D):
			input.x += 1.0
		dir = (transform.basis * Vector3(input.x, 0.0, input.y))
		dir.y = 0.0
		if dir.length() > 1.0:
			dir = dir.normalized()
	var interact := bot_interact
	if not bot_move.length_squared() > 0.0001:
		interact = interact or Input.is_physical_key_pressed(KEY_E)
	bot_interact = false
	if multiplayer.is_server():
		intent_dir = dir
		intent_interact = interact
	else:
		receive_intent.rpc_id(1, dir, intent_yaw, intent_pitch, interact)


@rpc("any_peer", "unreliable")
func receive_intent(dir: Vector3, yaw: float, pitch: float, interact: bool) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	intent_dir = dir
	intent_yaw = yaw
	intent_pitch = pitch
	intent_interact = interact


func _simulate(delta: float) -> void:
	rotation.y = intent_yaw
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	velocity.x = intent_dir.x * SPEED
	velocity.z = intent_dir.z * SPEED
	move_and_slide()
	sync_pose.rpc(global_position, intent_yaw, intent_pitch, seated)


@rpc("any_peer", "unreliable", "call_remote")
func sync_pose(pos: Vector3, yaw: float, pitch: float, is_seated: bool) -> void:
	if multiplayer.is_server():
		return
	global_position = pos
	rotation.y = yaw
	seated = is_seated
	if _is_local():
		camera.rotation.x = pitch
		intent_yaw = yaw
		intent_pitch = pitch


func apply_bind(p_id: String, items: PackedStringArray) -> void:
	principal_id = p_id
	keyed = not p_id.is_empty()
	inventory = items
	_refresh_nametag()
