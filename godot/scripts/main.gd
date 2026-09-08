extends Control

## Thin veneer — all durable state from OTP HTTP (ADR 0004).

const BASE := "http://127.0.0.1:4000"

@onready var status_label: Label = %Status
@onready var king_label: Label = %KingLabel
@onready var content_input: LineEdit = %ContentInput
@onready var plaque: RichTextLabel = %Plaque

var http: HTTPRequest
var king_id: String = ""
var eve_id: String = ""
var current_did: String = ""
var _pending: String = ""


func _ready() -> void:
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_http_completed)
	$Margin/VBox/ActorRow/RefreshBtn.pressed.connect(_refresh_all)
	$Margin/VBox/CreateBtn.pressed.connect(_on_create)
	$Margin/VBox/AdvanceBtn.pressed.connect(_on_advance_king)
	$Margin/VBox/DenyBtn.pressed.connect(_on_advance_eve)
	_refresh_all()


func _refresh_all() -> void:
	status_label.text = "Refreshing from backend…"
	_http_get("/health", "health")


func _on_create() -> void:
	if king_id.is_empty():
		status_label.text = "No King principal yet — is OTP up?"
		return
	var body := {
		"principal_id": king_id,
		"content": content_input.text,
		"label": "plaque"
	}
	_http_post("/v1/info_objects", body, "create")


func _on_advance_king() -> void:
	_advance_as(king_id, "advance_king")


func _on_advance_eve() -> void:
	if eve_id.is_empty():
		_http_post("/v1/principals", {"display_name": "Eve"}, "ensure_eve_then_advance")
	else:
		_advance_as(eve_id, "advance_eve")


func _advance_as(principal_id: String, tag: String) -> void:
	if current_did.is_empty():
		status_label.text = "Create an info object first."
		return
	var body := {
		"principal_id": principal_id,
		"did": current_did,
		"content": content_input.text,
		"message": "advance from Godot"
	}
	_http_post("/v1/info_objects/advance", body, tag)


func _http_get(path: String, tag: String) -> void:
	_pending = tag
	var err := http.request(BASE + path)
	if err != OK:
		status_label.text = "HTTPRequest error: %s" % err


func _http_post(path: String, data: Dictionary, tag: String) -> void:
	_pending = tag
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := http.request(BASE + path, headers, HTTPClient.METHOD_POST, JSON.stringify(data))
	if err != OK:
		status_label.text = "HTTPRequest error: %s" % err


func _on_http_completed(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text := body.get_string_from_utf8()
	var tag := _pending
	_pending = ""

	if code == 0:
		status_label.text = "OTP unreachable at %s — run ./scripts/node-up.sh (and lab-up for IPFS)." % BASE
		return

	var parsed: Variant = JSON.parse_string(text)

	match tag:
		"health":
			if typeof(parsed) != TYPE_DICTIONARY:
				status_label.text = "Bad health response (%s)" % code
				return
			var h: Dictionary = parsed
			status_label.text = "OTP ok · IPFS=%s · IOTA=%s" % [str(h.get("ipfs", false)), str(h.get("iota", false))]
			_http_get("/v1/bootstrap", "bootstrap")
		"bootstrap":
			if typeof(parsed) != TYPE_DICTIONARY:
				status_label.text = "Bad bootstrap (%s)" % code
				return
			var b: Dictionary = parsed
			var king: Dictionary = b.get("king", {})
			king_id = str(king.get("id", ""))
			king_label.text = "King: %s (%s)" % [str(king.get("display_name", "?")), king_id]
			_http_get("/v1/info_objects", "list")
		"list":
			if typeof(parsed) != TYPE_DICTIONARY:
				return
			var objs: Array = parsed.get("objects", [])
			if objs.size() > 0:
				current_did = str(objs[0].get("did", ""))
				_http_get("/v1/info_object?did=%s" % current_did.uri_encode(), "plaque")
			else:
				plaque.text = "[i]No info objects yet — create one.[/i]"
		"create":
			if code == 403:
				status_label.text = "Create denied (capability)."
				return
			if code >= 400:
				status_label.text = "Create failed (%s): %s" % [code, text]
				return
			status_label.text = "Created."
			_apply_plaque(parsed)
		"advance_king":
			if code >= 400:
				status_label.text = "Advance failed (%s): %s" % [code, text]
				return
			status_label.text = "Advanced (King)."
			_apply_plaque(parsed)
		"ensure_eve_then_advance":
			if typeof(parsed) == TYPE_DICTIONARY:
				eve_id = str(parsed.get("principal", {}).get("id", ""))
			_advance_as(eve_id, "advance_eve")
		"advance_eve":
			if code == 403:
				status_label.text = "Eve denied (fail closed) — plaque unchanged."
				_reload_plaque()
				return
			status_label.text = "Unexpected Eve result (%s): %s" % [code, text]
		"plaque":
			_apply_plaque(parsed)


func _reload_plaque() -> void:
	if current_did.is_empty():
		return
	_http_get("/v1/info_object?did=%s" % current_did.uri_encode(), "plaque")


func _apply_plaque(data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		plaque.text = str(data)
		return
	var d: Dictionary = data
	current_did = str(d.get("did", current_did))
	plaque.text = "[b]DID[/b] %s\n[b]head[/b] %s\n[b]content[/b] %s\n[b]iota checkpoint[/b] %s\n[b]updated[/b] %s" % [
		current_did,
		str(d.get("head_cid", "")),
		str(d.get("content", "")),
		str(d.get("iota_checkpoint", "")),
		str(d.get("updated_at", ""))
	]
