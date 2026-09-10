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
	_apply_color()
	_refresh_nametag()
	camera.current = _is_local()
	set_multiplayer_authority(1)


static func color_for_peer(id: int) -> Color:
	return COLORS[maxi(id - 1, 0) % COLORS.size()]


static func display_name_for_peer(id: int) -> String:
	return COLOR_NAMES[maxi(id - 1, 0) % COLOR_NAMES.size()]


func _is_local() -> bool:
	return multiplayer.get_unique_id() == peer_id


func _apply_color() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mesh.set_surface_override_material(0, mat)


func _refresh_nametag() -> void:
	var who := display_name_for_peer(peer_id)
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
	if not _is_local() or seated:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_delta += event.relative


func _physics_process(delta: float) -> void:
	if _is_local() and not seated:
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
