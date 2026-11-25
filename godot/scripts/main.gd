class_name NodeConsole
extends Control

## Node-1 console veneer. Durable mutates go to OTP HTTP only (ADR 0004).
## Helen → Alice play: empty CoT, W0 genesis, W1, Exit, Alice login, discovery, W2.

const BASE := "http://127.0.0.1:4000"
const WIRE_COLOR := Color(0.62, 0.66, 0.72)
const GRAPH_FONT := 16
## Layout x/y were written for the smaller blocks. 1.5 leaves a gap without
## the spread of 2×. Applied on every workspace.
const GRAPH_SCALE := 1.5
const GRAPH_ZOOM := 1.0
const KIND_COLORS := {
	"text_in": Color(0.22, 0.38, 0.52),
	"text_out": Color(0.22, 0.38, 0.52),
	"user_picker": Color(0.22, 0.38, 0.52),
	"people_picker": Color(0.22, 0.38, 0.52),
	"person": Color(0.28, 0.36, 0.48),
	"run": Color(0.58, 0.28, 0.46),
	"commit": Color(0.22, 0.52, 0.36),
	"populate": Color(0.2, 0.42, 0.48),
	"data": Color(0.62, 0.46, 0.18),
	"info": Color(0.18, 0.5, 0.4),
	"process": Color(0.36, 0.3, 0.56),
	"note": Color(0.3, 0.32, 0.36),
}

signal session_changed(principal_id: String, username: String)

@onready var status_label: Label = %Status
@onready var session_label: Label = %SessionLabel
@onready var screen_host: Control = %ScreenHost

var http: HTTPRequest
var _pending: String = ""
var last_tag: String = ""
var last_code: int = 0
var current_did: String = ""

var use_session_actor: bool = false
var session_principal_id: String = ""
var session_username: String = ""
var session_keyed: bool = false

var _lab: Dictionary = {}
var _session: Dictionary = {}
var _workspace_id: String = ""
var _graph_inputs: Dictionary = {}
var _usernames: Array = []
var _shown_pin: String = ""
var _screen: String = ""
var _discovery: DiscoveryView = null
var _info_panel: PanelContainer = null
var _info_title: Label = null
var _info_body: Label = null
var _w0_tabs: TabContainer = null
var _graph_nodes: Dictionary = {}
var _graph_kinds: Dictionary = {}
var _commit_btn: Button = null
var _populate_btn: Button = null
var _busy: bool = false
var _busy_timer: Timer = null
var _busy_pulse: bool = false


func _ready() -> void:
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_http_completed)
	_refresh()


func bind_actor(_principal_id: String, _keyed: bool) -> void:
	_refresh()


func console_idle() -> bool:
	return _pending.is_empty()


func playbook_create() -> void:
	status_label.text = "Plaque playbook superseded — run W2 from the launcher."


func playbook_eve_deny() -> void:
	status_label.text = "Eve-deny playbook superseded — Alice has no bootstrap cap."


## Leave a workspace or discovery view for the console menu.
## Pre-genesis that menu is the empty-CoT Overview. After login it is Home / launcher.
## Does not log out and does not stand the body up.
func _return_to_menu() -> void:
	if _screen == "w0_tabs" and _w0_tabs != null and is_instance_valid(_w0_tabs):
		_w0_tabs.current_tab = 0
		status_label.text = "Empty Circle of Trust."
		return
	if not bool(_lab.get("genesis_complete", false)):
		_open_w0()
		return
	if session_principal_id.is_empty() and not bool(_session.get("logged_in", false)):
		_show_login()
		return
	status_label.text = "Menu."
	_http_get("/v1/workspaces?principal_id=%s" % _actor().uri_encode(), "workspaces")


func _refresh() -> void:
	status_label.text = "Refreshing from OTP…"
	_http_get("/v1/lab", "lab")


func _actor() -> String:
	if session_principal_id.is_empty():
		return "unkeyed"
	return session_principal_id


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
	last_tag = tag
	last_code = code

	if code == 0:
		if _busy:
			_end_busy(false)
			_show_status("Write dropped before OTP answered (chain publish timed out). OTP is still up — press Go / Commit again.")
			return
		_show_status("OTP unreachable at %s — run ./scripts/node-up.sh." % BASE)
		_show_unreachable()
		return

	var parsed: Variant = null
	if not text.is_empty():
		parsed = JSON.parse_string(text)

	match tag:
		"lab":
			if typeof(parsed) != TYPE_DICTIONARY:
				status_label.text = "Bad lab (%s)" % code
				return
			_lab = parsed
			if not bool(_lab.get("powered", false)):
				status_label.text = "Node powered off."
				_show_off()
				return
			if not bool(_lab.get("genesis_complete", false)):
				_hide_status()
				_workspace_id = "w0"
				_http_get("/v1/workspace?id=w0&principal_id=unkeyed", "workspace")
				return
			_http_get("/v1/session", "session")
		"session":
			if typeof(parsed) == TYPE_DICTIONARY:
				_apply_session(parsed)
			if bool(_session.get("logged_in", false)):
				status_label.text = "Launcher."
				_http_get("/v1/workspaces?principal_id=%s" % _actor().uri_encode(), "workspaces")
			else:
				status_label.text = "Login required."
				_show_login()
		"workspaces":
			var list: Array = []
			if typeof(parsed) == TYPE_DICTIONARY:
				list = parsed.get("workspaces", [])
			_show_launcher(list)
		"workspace":
			if code >= 400:
				status_label.text = "Workspace failed (%s): %s" % [code, text]
				return
			if typeof(parsed) == TYPE_DICTIONARY:
				_show_workspace(parsed)
		"genesis":
			if code == 409:
				_end_busy(false)
				_show_status("Genesis replay denied — zeroise first.")
				return
			if code >= 400:
				_end_busy(false)
				_show_status("Genesis failed (%s): %s" % [code, text])
				return
			_end_busy(true)
			_hide_status()
			status_label.text = "Genesis ok — King minted. Not signed HTTP."
			if typeof(parsed) == TYPE_DICTIONARY:
				session_principal_id = str(parsed.get("principal", {}).get("id", ""))
				session_username = str(parsed.get("principal", {}).get("display_name", "Helen"))
				session_keyed = not session_principal_id.is_empty()
				current_did = str(parsed.get("g_did", ""))
				_emit_session()
			_refresh()
		"login":
			if code == 409:
				status_label.text = "Session occupied — Exit session first."
				return
			if code >= 400:
				status_label.text = "Login failed (%s): %s" % [code, text]
				return
			if typeof(parsed) == TYPE_DICTIONARY:
				var p: Dictionary = parsed.get("principal", {})
				session_principal_id = str(p.get("id", ""))
				session_username = str(p.get("display_name", ""))
				session_keyed = not session_principal_id.is_empty()
				_emit_session()
			status_label.text = "Logged in. Vault imported (volatile)."
			_refresh()
		"logout":
			session_principal_id = ""
			session_username = ""
			session_keyed = false
			_emit_session()
			status_label.text = "Exited session."
			_refresh()
		"power":
			_refresh()
		"zeroise":
			session_principal_id = ""
			session_username = ""
			session_keyed = false
			_emit_session()
			status_label.text = "Zeroised — King-making re-opened (chain wipe is stubbed)."
			_refresh()
		"run_w1":
			if code == 403:
				_end_busy(false)
				status_label.text = "W1 denied — no covering capability (Helen's any cap covers this)."
				return
			if code >= 400:
				_end_busy(false)
				status_label.text = "W1 failed (%s): %s" % [code, text]
				return
			_end_busy(true)
			if typeof(parsed) == TYPE_DICTIONARY:
				_shown_pin = str(parsed.get("pin", ""))
				status_label.text = "Alice admitted. PIN (show once): %s" % _shown_pin
				_set_graph_out("pin", _shown_pin)
			else:
				status_label.text = "W1 ok."
		"run_w2":
			if code == 403:
				_end_busy(false)
				status_label.text = "W2 denied — no covering cap, or vault unusable."
				return
			if code >= 400:
				_end_busy(false)
				status_label.text = "W2 failed (%s): %s" % [code, text]
				return
			_end_busy(true)
			status_label.text = "Wrote information."
			if typeof(parsed) == TYPE_DICTIONARY:
				current_did = str(parsed.get("did", ""))
				status_label.text = "Wrote %s" % current_did
		"discovery":
			if code == 403:
				status_label.text = "Discovery denied."
				return
			if typeof(parsed) == TYPE_DICTIONARY:
				_show_discovery(parsed)
			status_label.text = "Discovery (data = markers; unread info omitted). Click an info node to read it."
		"info_object":
			_fill_info_panel(code, parsed, text)
		"save_graph":
			if code == 403:
				status_label.text = "Denied — GraphEdit cannot widen authority."
			else:
				status_label.text = "Save layout: %s %s" % [code, text]


func _apply_session(parsed: Dictionary) -> void:
	_session = parsed
	if bool(parsed.get("logged_in", false)):
		session_principal_id = str(parsed.get("principal_id", ""))
		session_username = str(parsed.get("username", ""))
		session_keyed = not session_principal_id.is_empty()
	else:
		session_principal_id = ""
		session_username = ""
		session_keyed = false
	_emit_session()


func _show_status(text: String) -> void:
	status_label.text = text
	status_label.visible = true


func _hide_status() -> void:
	status_label.visible = false


func _on_populate_graph() -> void:
	_apply_inventory_to_graph(true)


func _emit_session() -> void:
	if session_username.is_empty():
		session_label.text = "Session: none (Esc unsits; Exit logs out)"
	else:
		session_label.text = "Session: %s  %s" % [session_username, _short_principal(session_principal_id)]
	session_changed.emit(session_principal_id, session_username)


func _clear_screen() -> void:
	for c in screen_host.get_children():
		screen_host.remove_child(c)
		c.queue_free()
	_graph_inputs.clear()
	_graph_nodes.clear()
	_graph_kinds.clear()
	_commit_btn = null
	_populate_btn = null
	_discovery = null
	_info_panel = null
	_info_title = null
	_info_body = null
	_w0_tabs = null
	_screen = ""
	_stop_busy_timer()
	_busy = false


func _vbox() -> VBoxContainer:
	# ScreenHost is a VBox so the graph can take leftover height.
	if screen_host is VBoxContainer:
		var host := screen_host as VBoxContainer
		host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		host.size_flags_vertical = Control.SIZE_EXPAND_FILL
		host.add_theme_constant_override("separation", 8)
		return host
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	screen_host.add_child(box)
	return box


func _btn(label: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.pressed.connect(cb)
	return b


func _show_unreachable() -> void:
	_clear_screen()
	var box := _vbox()
	box.add_child(_note("OTP is down. Start ./scripts/node-up.sh then Refresh."))
	box.add_child(_btn("Refresh", _refresh))


func _show_off() -> void:
	_clear_screen()
	_screen = "off"
	var box := _vbox()
	box.add_child(_note("Laptop is powered off. Product HTTP refuses. Lab harness can power on."))
	box.add_child(_btn("Power on", func() -> void: _http_post("/v1/lab/power", {"on": true}, "power")))


func _show_chooser() -> void:
	_workspace_id = "w0"
	_http_get("/v1/workspace?id=w0&principal_id=unkeyed", "workspace")


func _show_login() -> void:
	_clear_screen()
	_screen = "login"
	var box := _vbox()
	box.add_child(_heading("Identity process"))
	box.add_child(_note("Username + PIN. Paper private key is imported into this user's vault. Stub αβω pass granted caps. Not signed sessions."))
	box.add_child(_paper_status_label())
	var creds := _inventory_credentials()
	var user := LineEdit.new()
	user.placeholder_text = "Username"
	user.name = "LoginUser"
	if not creds.is_empty():
		user.text = str(creds.get("holder_name", ""))
	box.add_child(user)
	box.add_child(_pin_prompt_label())
	var pin := LineEdit.new()
	pin.name = "LoginPin"
	pin.secret = true
	_wire_pin_edit(pin)
	box.add_child(pin)
	var sk := LineEdit.new()
	sk.placeholder_text = "Paper private key"
	sk.secret = true
	sk.name = "LoginKey"
	if not creds.is_empty():
		sk.text = str(creds.get("private_key", ""))
	box.add_child(sk)
	box.add_child(_btn("Login", func() -> void:
		if not _pin_ok(pin.text):
			_show_status("PIN must be exactly 5 digits (0–9).")
			return
		_http_post("/v1/session/login", {
			"username": user.text,
			"pin": pin.text,
			"private_key": sk.text,
		}, "login")
	))
	box.add_child(_btn("Power off", func() -> void: _http_post("/v1/lab/power", {"on": false}, "power")))
	box.add_child(_btn("Refresh", _refresh))


func _show_launcher(workspaces: Array) -> void:
	_clear_screen()
	_screen = "launcher"
	var box := _vbox()
	box.add_child(_heading("Home / launcher"))
	if workspaces.is_empty():
		box.add_child(_note("No workspaces listed for this principal."))
	for w_any in workspaces:
		if typeof(w_any) != TYPE_DICTIONARY:
			continue
		var w: Dictionary = w_any
		var id := str(w.get("id", ""))
		box.add_child(_btn("Run %s" % _workspace_menu_label(id), _open_workspace.bind(id)))
	box.add_child(_btn("Discovery", _open_discovery))
	box.add_child(_btn("Exit session", func() -> void:
		_http_post("/v1/session/logout", {"principal_id": _actor()}, "logout")
	))
	box.add_child(_btn("Power off", func() -> void: _http_post("/v1/lab/power", {"on": false}, "power")))
	box.add_child(_btn("Refresh", _refresh))
	if not _shown_pin.is_empty():
		box.add_child(_note("Last generated PIN (paper, show once): %s" % _shown_pin))


func _workspace_menu_label(id: String) -> String:
	match id:
		"w0":
			return "w0 — first user"
		"w1":
			return "w1 — add user"
		"w2":
			return "w2 — write info"
		_:
			return id


func _open_w0() -> void:
	_workspace_id = "w0"
	_http_get("/v1/workspace?id=w0&principal_id=unkeyed", "workspace")


func _open_workspace(id: String) -> void:
	_workspace_id = id
	_http_get("/v1/workspace?id=%s&principal_id=%s" % [id.uri_encode(), _actor().uri_encode()], "workspace")


func _open_discovery() -> void:
	_http_get("/v1/discovery?principal_id=%s" % _actor().uri_encode(), "discovery")


func _show_workspace(ws: Dictionary) -> void:
	_clear_screen()
	_screen = "workspace"
	var layout: Dictionary = ws.get("layout", {})
	if layout.is_empty() and _workspace_id == "w0":
		layout = {"workspace_id": "w0", "nodes": [], "wires": []}
	_usernames = ws.get("usernames", [])
	if _workspace_id == "w0" and not bool(_lab.get("genesis_complete", false)):
		_show_w0_tabs(ws, layout)
		return
	var box := _vbox()
	var title := "Workspace %s" % _workspace_menu_label(str(ws.get("id", _workspace_id)))
	if bool(ws.get("locked", false)) or bool(layout.get("locked", false)):
		title += " — GraphEdit cannot widen authority"
	if bool(ws.get("system", false)):
		title += " — system (no prior cap)"
	box.add_child(_heading(title))
	box.add_child(_paper_status_label())
	var row := HBoxContainer.new()
	row.add_child(_btn("Exit to menu", _return_to_menu))
	row.add_child(_btn("Try save layout (expect deny — cannot mint verbs)", func() -> void:
		_http_post("/v1/workspaces/save", {
			"principal_id": _actor(),
			"id": _workspace_id,
			"layout": {"grants": [{"verb": "bootstrap"}]},
		}, "save_graph")
	))
	box.add_child(row)
	_build_graph(box, layout)
	var g_did := str(ws.get("g_did", ""))
	if _graph_inputs.has("link") and _graph_inputs["link"] is LineEdit and not g_did.is_empty():
		(_graph_inputs["link"] as LineEdit).text = g_did


func _show_w0_tabs(_ws: Dictionary, layout: Dictionary) -> void:
	_screen = "w0_tabs"
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen_host.add_child(tabs)

	var overview := VBoxContainer.new()
	overview.name = "Overview"
	overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overview.add_theme_constant_override("separation", 10)
	overview.add_child(_heading("Empty Circle of Trust"))
	overview.add_child(_note("This node is not linked to a Circle of Trust. It is a new box: no King, no G, no D1–D5."))
	overview.add_child(_note("You can wait to connect later (sign this node's EK, join someone else's G — not this beat). Or start genesis: open W0 — first user, fill the fields, then Go / Commit."))
	overview.add_child(_heading("Colour key"))
	overview.add_child(_color_key())
	overview.add_child(_note("Wires are locked (one grey). GraphEdit cannot mint or widen authority."))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.add_child(_btn("Open W0 — first user", func() -> void: tabs.current_tab = 1))
	actions.add_child(_btn("Power off", func() -> void: _http_post("/v1/lab/power", {"on": false}, "power")))
	actions.add_child(_btn("Zeroise", func() -> void: _http_post("/v1/lab/zeroise", {}, "zeroise")))
	actions.add_child(_btn("Refresh", _refresh))
	overview.add_child(actions)
	tabs.add_child(overview)
	tabs.set_tab_title(0, "Overview")

	var genesis := VBoxContainer.new()
	genesis.name = "W0Genesis"
	genesis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	genesis.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(genesis)
	tabs.set_tab_title(1, "W0 — first user")
	tabs.current_tab = 0
	_w0_tabs = tabs
	var leave := HBoxContainer.new()
	leave.add_theme_constant_override("separation", 8)
	leave.add_child(_btn("Exit to menu", _return_to_menu))
	genesis.add_child(leave)
	_build_graph(genesis, layout)


func _wire_shader() -> Shader:
	# GraphEdit draws every connection as (thickness + 4) pixels and paints
	# the outer band in the rim colour. A small thickness is therefore still
	# a wide stroke. This keeps a one-pixel core and fades the padding out.
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
render_mode blend_mix;
uniform vec4 rim_color : source_color;
uniform int from_type;
uniform int to_type;
uniform float line_width;
void fragment() {
	float dist = abs(UV.y - 0.5);
	float width = max(line_width, 1.0);
	float core = 0.5 / width;
	float aa = 0.6 / width;
	float alpha = 1.0 - smoothstep(core, core + aa, dist);
	COLOR = vec4(COLOR.rgb, COLOR.a * alpha);
}
"""
	return shader


func _color_key() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var rows := [
		["Input", KIND_COLORS["text_in"]],
		["Populate", KIND_COLORS["populate"]],
		["Go / Commit", KIND_COLORS["commit"]],
		["Data", KIND_COLORS["data"]],
		["Info", KIND_COLORS["info"]],
		["Process", KIND_COLORS["process"]],
		["Locked wire", WIRE_COLOR],
	]
	for row_any in rows:
		var row: Array = row_any
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(22, 16)
		swatch.color = row[1]
		line.add_child(swatch)
		var lab := Label.new()
		lab.text = str(row[0])
		line.add_child(lab)
		box.add_child(line)
	return box


func _build_graph(parent: Control, layout: Dictionary) -> void:
	var graph := GraphEdit.new()
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.size_flags_stretch_ratio = 1.0
	graph.custom_minimum_size = Vector2(0, 0)
	graph.right_disconnects = false
	graph.minimap_enabled = true
	graph.show_grid = true
	graph.zoom = GRAPH_ZOOM
	graph.snapping_distance = 24
	graph.connection_lines_thickness = 0.0
	graph.connection_lines_antialiased = false
	graph.set_meta("wire_shader", _wire_shader())
	graph.add_theme_font_size_override("title_font_size", GRAPH_FONT)
	graph.connection_request.connect(_on_graph_connection_request)
	graph.disconnection_request.connect(_on_graph_disconnection_request)
	graph.delete_nodes_request.connect(_on_graph_delete_nodes)
	parent.add_child(graph)
	_graph_inputs.clear()
	_graph_nodes.clear()
	_graph_kinds.clear()
	_commit_btn = null
	_populate_btn = null
	var nodes: Array = layout.get("nodes", [])
	for n_any in nodes:
		if typeof(n_any) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = n_any
		var gn := GraphNode.new()
		var nid := str(n.get("id", "n"))
		gn.name = nid
		gn.title = str(n.get("title", nid))
		gn.position_offset = Vector2(float(n.get("x", 40)), float(n.get("y", 40))) * GRAPH_SCALE
		gn.add_theme_font_size_override("title_font_size", GRAPH_FONT)
		var typ := str(n.get("type", "text_in"))
		gn.custom_minimum_size = _node_min_size(typ, n)
		_style_graph_node(gn, typ)
		_graph_nodes[nid] = gn
		_graph_kinds[nid] = typ
		match typ:
			"text_out":
				_add_subtitle(gn, n)
				var out := LineEdit.new()
				out.editable = false
				out.placeholder_text = "(output)"
				out.add_theme_font_size_override("font_size", GRAPH_FONT)
				gn.add_child(out)
				_graph_inputs[nid] = out
				_set_io_slot(gn, 0, true, true)
			"user_picker":
				_add_subtitle(gn, n)
				var item := ItemList.new()
				item.select_mode = ItemList.SELECT_MULTI
				item.custom_minimum_size = Vector2(110, 48)
				item.add_theme_font_size_override("font_size", GRAPH_FONT)
				for u_any in _usernames:
					if typeof(u_any) == TYPE_DICTIONARY:
						item.add_item(str(u_any.get("username", "")))
				gn.add_child(item)
				_graph_inputs[nid] = item
				_set_io_slot(gn, 0, true, true)
			"person":
				_add_subtitle(gn, n)
				_set_io_slot(gn, 0, false, true)
			"people_picker":
				_build_people_picker(gn, n)
				_graph_inputs[nid] = gn
			"populate":
				_add_subtitle(gn, n)
				var pb := Button.new()
				pb.text = "Populate"
				pb.add_theme_font_size_override("font_size", GRAPH_FONT)
				pb.pressed.connect(_on_populate_graph)
				gn.add_child(pb)
				_populate_btn = pb
				_set_io_slot(gn, 0, false, true)
			"commit":
				_fill_commit_node(gn, n)
			"run":
				_add_subtitle(gn, n)
				var rb := Button.new()
				rb.text = gn.title
				rb.add_theme_font_size_override("font_size", GRAPH_FONT)
				rb.pressed.connect(_on_run_graph)
				gn.add_child(rb)
				_commit_btn = rb
				_set_io_slot(gn, 0, true, true)
			"data", "info", "process", "note":
				_add_subtitle(gn, n)
				var wired := nid != "prompt"
				_set_io_slot(gn, 0, wired, wired)
			_:
				_add_subtitle(gn, n)
				if nid == "pin":
					_add_pin_prompt(gn)
					gn.custom_minimum_size = Vector2(150, 64) * (float(GRAPH_FONT) / 8.0)
				var le := LineEdit.new()
				le.placeholder_text = "5 digits" if nid == "pin" else gn.title
				le.add_theme_font_size_override("font_size", GRAPH_FONT)
				if nid == "pin":
					_wire_pin_edit(le)
				gn.add_child(le)
				_graph_inputs[nid] = le
				_set_io_slot(gn, 0, true, true)
		graph.add_child(gn)
	for w_any in layout.get("wires", []):
		var spec := _wire_spec(w_any)
		if spec.is_empty():
			continue
		graph.connect_node(str(spec["from"]), int(spec["from_port"]), str(spec["to"]), int(spec["to_port"]))
	_thin_graph_wires(graph)


func _thin_graph_wires(graph: GraphEdit) -> void:
	var layer := graph.get_node_or_null("_connection_layer")
	if layer == null:
		return
	var shader: Shader = graph.get_meta("wire_shader")
	for child in layer.get_children():
		if not child is Line2D:
			continue
		var line := child as Line2D
		var mat := ShaderMaterial.new()
		mat.shader = shader
		line.material = mat
		line.width = 1.0
		line.antialiased = false


func _add_subtitle(gn: GraphNode, n: Dictionary) -> void:
	var subtitle := str(n.get("subtitle", ""))
	if subtitle.is_empty():
		return
	var sub := Label.new()
	sub.text = subtitle
	var typ := str(n.get("type", ""))
	if typ == "note":
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.custom_minimum_size = Vector2(120, 0)
	else:
		sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub.add_theme_font_size_override("font_size", GRAPH_FONT)
	sub.add_theme_color_override("font_color", Color(0.88, 0.9, 0.93))
	gn.add_child(sub)
	gn.set_meta("base_subtitle", subtitle)


func _add_pin_prompt(host: Control) -> void:
	host.add_child(_pin_prompt_label())


func _pin_prompt_label() -> Label:
	var hint := Label.new()
	hint.text = "Enter a 5-digit numeric PIN"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", GRAPH_FONT)
	hint.add_theme_color_override("font_color", Color(0.9, 0.86, 0.7))
	return hint


func _wire_pin_edit(le: LineEdit) -> void:
	le.max_length = 5
	le.placeholder_text = "5-digit PIN"
	le.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	le.text_changed.connect(func(t: String) -> void: _filter_pin_edit(le, t))
	_paint_pin_edit(le)


func _filter_pin_edit(le: LineEdit, t: String) -> void:
	var out := ""
	for i in t.length():
		var ch := t.substr(i, 1)
		if ch >= "0" and ch <= "9":
			out += ch
		if out.length() >= 5:
			break
	if out != t:
		var col := le.caret_column
		le.text = out
		le.caret_column = mini(col, out.length())
	_paint_pin_edit(le)


func _paint_pin_edit(le: LineEdit) -> void:
	if _pin_ok(le.text):
		le.modulate = Color.WHITE
	else:
		le.modulate = Color(1.0, 0.88, 0.72)


func _pin_ok(s: String) -> bool:
	if s.length() != 5:
		return false
	for i in s.length():
		var ch := s.substr(i, 1)
		if ch < "0" or ch > "9":
			return false
	return true


func _fill_commit_node(gn: GraphNode, n: Dictionary) -> void:
	var ports: Array = n.get("ports", [])
	for p_any in ports:
		if typeof(p_any) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = p_any
		var row := Label.new()
		row.text = str(p.get("label", p.get("id", "pass-through")))
		row.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_theme_font_size_override("font_size", GRAPH_FONT)
		gn.add_child(row)
	var b := Button.new()
	b.text = "Go / Commit"
	b.add_theme_font_size_override("font_size", GRAPH_FONT)
	b.pressed.connect(_on_run_graph)
	gn.add_child(b)
	_commit_btn = b
	var i := 0
	for p_any2 in ports:
		if typeof(p_any2) != TYPE_DICTIONARY:
			continue
		var p2: Dictionary = p_any2
		var enable_in := bool(p2.get("in", true))
		var enable_out := bool(p2.get("out", true))
		_set_io_slot(gn, i, enable_in, enable_out)
		i += 1
	_set_io_slot(gn, i, false, false)


func _set_io_slot(gn: GraphNode, idx: int, enable_in: bool, enable_out: bool) -> void:
	gn.set_slot(idx, enable_in, 0, WIRE_COLOR, enable_out, 0, WIRE_COLOR)


func _wire_spec(w_any: Variant) -> Dictionary:
	if typeof(w_any) == TYPE_DICTIONARY:
		var w: Dictionary = w_any
		return {
			"from": str(w.get("from", "")),
			"from_port": int(w.get("from_port", 0)),
			"to": str(w.get("to", "")),
			"to_port": int(w.get("to_port", 0)),
		}
	if typeof(w_any) == TYPE_ARRAY and w_any.size() >= 2:
		if w_any.size() >= 4:
			return {
				"from": str(w_any[0]),
				"from_port": int(w_any[1]),
				"to": str(w_any[2]),
				"to_port": int(w_any[3]),
			}
		return {"from": str(w_any[0]), "from_port": 0, "to": str(w_any[1]), "to_port": 0}
	return {}


func _node_min_size(typ: String, n: Dictionary = {}) -> Vector2:
	var s := float(GRAPH_FONT) / 8.0
	match typ:
		"process":
			return Vector2(140, 32) * s
		"data", "info":
			return Vector2(140, 36) * s
		"populate":
			return Vector2(140, 40) * s
		"commit":
			var ports: Array = n.get("ports", [])
			return Vector2(190, 44 + float(ports.size()) * 18.0) * s
		"note":
			return Vector2(160, 48) * s
		"person":
			return Vector2(120, 36) * s
		"people_picker":
			var people: Array = n.get("people", [])
			return Vector2(280, 96 + float(people.size()) * 36.0) * s
		_:
			return Vector2(150, 48) * s


func _style_graph_node(gn: GraphNode, typ: String, override_col: Color = Color(0, 0, 0, 0)) -> void:
	var col: Color = Color(0.3, 0.32, 0.36)
	if override_col.a > 0.01:
		col = override_col
	elif KIND_COLORS.has(typ):
		col = KIND_COLORS[typ]
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	gn.add_theme_stylebox_override("titlebar", sb)
	gn.add_theme_stylebox_override("titlebar_selected", sb)
	var panel := StyleBoxFlat.new()
	panel.bg_color = col.darkened(0.35)
	panel.set_corner_radius_all(4)
	panel.content_margin_left = 10
	panel.content_margin_right = 10
	panel.content_margin_top = 8
	panel.content_margin_bottom = 10
	gn.add_theme_stylebox_override("panel", panel)
	gn.add_theme_constant_override("separation", 10)
	gn.add_theme_constant_override("port_offset", 6)


func _on_graph_connection_request(_from: StringName, _from_port: int, _to: StringName, _to_port: int) -> void:
	pass


func _on_graph_disconnection_request(_from: StringName, _from_port: int, _to: StringName, _to_port: int) -> void:
	pass


func _on_graph_delete_nodes(_nodes: Array) -> void:
	pass


func _inventory_credentials() -> Dictionary:
	var worlds := get_tree().get_nodes_in_group("world")
	if worlds.is_empty():
		return {}
	var w := worlds[0] as Node
	if w != null and w.has_method("credentials_from_active_persona"):
		var persona: Variant = w.call("credentials_from_active_persona")
		if typeof(persona) == TYPE_DICTIONARY and not (persona as Dictionary).is_empty():
			return persona
	if w != null and w.has_method("credentials_from_local_inventory"):
		var creds: Variant = w.call("credentials_from_local_inventory")
		if typeof(creds) == TYPE_DICTIONARY:
			return creds
	return {}


func _paper_status_label() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _workspace_id == "w1":
		l.text = "W1 adds a user before their first login. Switch to the new persona, pick up their public-key slip, G-give it to the seated user, switch back, then Populate. Populate never copies the seater's own keys."
	elif _workspace_id == "w0":
		l.text = "Fields stay empty until you press Populate (persona or inventory keys). PIN is typed."
	else:
		l.text = "Paper keys stay in inventory / persona until you press Populate."
	l.add_theme_color_override("font_color", Color(0.72, 0.76, 0.8))
	return l


func refresh_persona_fields() -> void:
	if _screen == "login":
		_show_login()


func _apply_inventory_to_graph(force: bool = false) -> void:
	var creds := _populate_source()
	if creds.is_empty():
		if _workspace_id == "w1":
			_show_status("W1 needs the new user's public key (not the seater's). Generate them, G-give their public-key slip to the seater, then Populate.")
		else:
			_show_status("Nothing to populate — generate a persona or pick up paper.")
		return
	if _graph_inputs.has("public_key") and _graph_inputs["public_key"] is LineEdit:
		var pk := _graph_inputs["public_key"] as LineEdit
		if force or pk.text.is_empty():
			pk.text = str(creds.get("public_key", ""))
	if _workspace_id != "w1" and _graph_inputs.has("private_key") and _graph_inputs["private_key"] is LineEdit:
		var sk := _graph_inputs["private_key"] as LineEdit
		if force or sk.text.is_empty():
			sk.text = str(creds.get("private_key", ""))
	if _graph_inputs.has("username") and _graph_inputs["username"] is LineEdit:
		var un := _graph_inputs["username"] as LineEdit
		if force or un.text.is_empty():
			un.text = str(creds.get("holder_name", ""))


func _populate_source() -> Dictionary:
	if _workspace_id == "w1":
		return _w1_credential_source()
	return _inventory_credentials()


func _w1_credential_source() -> Dictionary:
	var worlds := get_tree().get_nodes_in_group("world")
	if worlds.is_empty():
		return {}
	var w := worlds[0] as Node
	if w != null and w.has_method("w1_admittee_credentials"):
		var rec: Variant = w.call("w1_admittee_credentials")
		if typeof(rec) == TYPE_DICTIONARY and not (rec as Dictionary).is_empty():
			return rec
	return {}


func _graph_text(id: String) -> String:
	var c: Variant = _graph_inputs.get(id)
	if c is LineEdit:
		return (c as LineEdit).text
	return ""


func _build_people_picker(gn: GraphNode, n: Dictionary) -> void:
	var people: Array = n.get("people", [])
	var from_d3 := Label.new()
	from_d3.text = "from D3"
	from_d3.add_theme_font_size_override("font_size", GRAPH_FONT)
	gn.add_child(from_d3)
	_set_io_slot(gn, 0, true, false)
	var slot := 1
	for p_any in people:
		if typeof(p_any) != TYPE_DICTIONARY:
			continue
		var p: Dictionary = p_any
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name := Label.new()
		name.text = str(p.get("username", ""))
		name.custom_minimum_size = Vector2(72, 0)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.add_theme_font_size_override("font_size", GRAPH_FONT)
		var read_box := CheckBox.new()
		read_box.text = "Read"
		var write_box := CheckBox.new()
		write_box.text = "Write"
		read_box.add_theme_font_size_override("font_size", GRAPH_FONT)
		write_box.add_theme_font_size_override("font_size", GRAPH_FONT)
		var is_self := bool(p.get("self", false))
		if not is_self and str(p.get("public_key", "")) == session_principal_id and not session_principal_id.is_empty():
			is_self = true
		if not is_self and str(p.get("username", "")) == session_username and not session_username.is_empty():
			is_self = true
		read_box.button_pressed = is_self
		write_box.button_pressed = is_self
		row.add_child(name)
		row.add_child(read_box)
		row.add_child(write_box)
		row.set_meta("username", str(p.get("username", "")))
		row.set_meta("read", read_box)
		row.set_meta("write", write_box)
		gn.add_child(row)
		_set_io_slot(gn, slot, false, false)
		slot += 1
	var read_out := Label.new()
	read_out.text = "read list"
	read_out.add_theme_font_size_override("font_size", GRAPH_FONT)
	gn.add_child(read_out)
	_set_io_slot(gn, slot, false, true)
	slot += 1
	var write_out := Label.new()
	write_out.text = "write list"
	write_out.add_theme_font_size_override("font_size", GRAPH_FONT)
	gn.add_child(write_out)
	_set_io_slot(gn, slot, false, true)


func _graph_access(which: String) -> Array:
	var gn: Variant = _graph_inputs.get("access")
	var names: Array = []
	if not (gn is GraphNode):
		return names
	for c in (gn as GraphNode).get_children():
		if not c.has_meta("username"):
			continue
		var box: Variant = c.get_meta(which)
		if box is CheckBox and (box as CheckBox).button_pressed:
			names.append(str(c.get_meta("username")))
	return names


func _graph_picked(id: String) -> Array:
	var c: Variant = _graph_inputs.get(id)
	var names: Array = []
	if c is ItemList:
		var item := c as ItemList
		for i in item.get_selected_items():
			names.append(item.get_item_text(i))
	return names


func _set_graph_out(id: String, value: String) -> void:
	var c: Variant = _graph_inputs.get(id)
	if c is LineEdit:
		(c as LineEdit).text = value


func _on_run_graph() -> void:
	if _busy:
		return
	if _workspace_id == "w0" and not _pin_ok(_graph_text("pin")):
		_show_status("PIN must be exactly 5 digits (0–9).")
		return
	_begin_busy()
	match _workspace_id:
		"w0":
			_http_post("/v1/genesis", {
				"username": _graph_text("username"),
				"public_key": _graph_text("public_key"),
				"private_key": _graph_text("private_key"),
				"pin": _graph_text("pin"),
			}, "genesis")
		"w1":
			_http_post("/v1/workspaces/run", {
				"principal_id": _actor(),
				"id": "w1",
				"username": _graph_text("username"),
				"public_key": _graph_text("public_key"),
			}, "run_w1")
		"w2":
			_http_post("/v1/workspaces/run", {
				"principal_id": _actor(),
				"id": "w2",
				"text": _graph_text("text"),
				"readers": _graph_access("read"),
				"writers": _graph_access("write"),
				"link_did": _graph_text("link"),
			}, "run_w2")
		_:
			_end_busy(false)
			status_label.text = "Unknown workspace %s" % _workspace_id


func _begin_busy() -> void:
	_busy = true
	_busy_pulse = false
	if _commit_btn:
		_commit_btn.disabled = true
		_commit_btn.text = "Working… ⏳"
	if _populate_btn:
		_populate_btn.disabled = true
	_paint_commit_working(true)
	_paint_previews("writing…", true)
	_show_status("Working — writing names (this can take a while)…")
	if _busy_timer == null:
		_busy_timer = Timer.new()
		_busy_timer.wait_time = 0.45
		_busy_timer.timeout.connect(_on_busy_pulse)
		add_child(_busy_timer)
	_busy_timer.start()


func _end_busy(ok: bool) -> void:
	_stop_busy_timer()
	_busy = false
	if _populate_btn:
		_populate_btn.disabled = false
	if _commit_btn:
		_commit_btn.disabled = false
		_commit_btn.text = "Go / Commit" if not ok else "Go / Commit"
	_paint_commit_working(false)
	if ok:
		_paint_previews("wrote", false, true)
	else:
		_paint_previews("", false, false)


func _stop_busy_timer() -> void:
	if _busy_timer:
		_busy_timer.stop()


func _on_busy_pulse() -> void:
	if not _busy:
		return
	_busy_pulse = not _busy_pulse
	_paint_previews("writing…", true)


func _paint_commit_working(working: bool) -> void:
	if not _graph_nodes.has("run"):
		return
	var gn: GraphNode = _graph_nodes["run"]
	if working:
		_style_graph_node(gn, "commit", Color(0.78, 0.55, 0.16))
	else:
		_style_graph_node(gn, "commit")


func _paint_previews(label: String, working: bool, wrote: bool = false) -> void:
	for id in _graph_kinds.keys():
		var typ := str(_graph_kinds[id])
		if typ != "data" and typ != "info" and typ != "process":
			continue
		var gn: GraphNode = _graph_nodes[id]
		var col: Color = KIND_COLORS[typ]
		if wrote:
			col = col.lightened(0.12)
		elif working:
			col = Color(0.78, 0.52, 0.14) if _busy_pulse else Color(0.58, 0.4, 0.12)
		_style_graph_node(gn, typ, col)
		if gn.get_child_count() == 0 or not (gn.get_child(0) is Label):
			continue
		var sub := gn.get_child(0) as Label
		var base := str(gn.get_meta("base_subtitle", sub.text))
		if wrote:
			sub.text = "wrote — " + base
		elif working and not label.is_empty():
			sub.text = "%s — %s" % [label, base]
		else:
			sub.text = base


func _show_discovery(graph: Dictionary) -> void:
	_clear_screen()
	_screen = "discovery"
	var box := _vbox()
	box.add_child(_heading("Discovery"))
	box.add_child(_note("Walk from D5[user]. The layout settles. Click an info node to read it. Data = markers (no D4 bytes)."))
	box.add_child(_btn("Exit to menu", _return_to_menu))
	var split := HBoxContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 12)
	_discovery = DiscoveryView.new()
	_discovery.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_discovery.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_discovery.custom_minimum_size = Vector2(0, 360)
	_discovery.open_info.connect(_on_open_info)
	_discovery.setup(graph)
	split.add_child(_discovery)
	_info_panel = _make_info_panel()
	split.add_child(_info_panel)
	box.add_child(split)


func _make_info_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.visible = false
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	panel.add_child(inner)
	var head := HBoxContainer.new()
	_info_title = Label.new()
	_info_title.text = "Information"
	_info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_title.add_theme_font_size_override("font_size", 16)
	head.add_child(_info_title)
	head.add_child(_btn("Close", _close_info_panel))
	inner.add_child(head)
	_info_body = Label.new()
	_info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info_body.add_theme_font_size_override("font_size", 14)
	inner.add_child(_info_body)
	return panel


func _on_open_info(did: String) -> void:
	if _info_panel == null or not is_instance_valid(_info_panel):
		return
	_info_panel.visible = true
	if _info_title:
		_info_title.text = "Information"
	if _info_body:
		_info_body.text = "Reading…"
	_http_get("/v1/info_object?principal_id=%s&did=%s" % [_actor().uri_encode(), did.uri_encode()], "info_object")


func _close_info_panel() -> void:
	if _info_panel and is_instance_valid(_info_panel):
		_info_panel.visible = false


func _fill_info_panel(code: int, parsed: Variant, _raw: String) -> void:
	if _screen != "discovery" or _info_body == null or not is_instance_valid(_info_body):
		return
	if _info_panel:
		_info_panel.visible = true
	if code >= 400 or typeof(parsed) != TYPE_DICTIONARY:
		_info_body.text = "Could not read this object (%s)." % code
		return
	var obj: Dictionary = parsed
	if _info_title:
		_info_title.text = str(obj.get("label", "Information"))
	_info_body.text = "%s\n\nDID\n%s\n\nRead\n%s\n\nWrite\n%s" % [
		str(obj.get("content", "")),
		str(obj.get("did", "")),
		_join_ids(obj.get("read_list", [])),
		_join_ids(obj.get("write_list", [])),
	]


func _join_ids(items: Variant) -> String:
	if typeof(items) != TYPE_ARRAY or (items as Array).is_empty():
		return "—"
	var parts := PackedStringArray()
	for item in items:
		parts.append(str(item))
	return ", ".join(parts)


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	return l


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	return l


func _short_principal(id: String) -> String:
	if id.length() <= 24:
		return id
	return "%s…%s" % [id.substr(0, 12), id.substr(id.length() - 8, 8)]


class DiscoveryView extends Control:
	signal open_info(did: String)

	var nodes: Array = []
	var edges: Array = []
	var _pos: Dictionary = {}
	var _vel: Dictionary = {}
	var _temperature := 1.0
	var _settled := false

	func setup(graph: Dictionary) -> void:
		nodes = graph.get("nodes", [])
		edges = graph.get("edges", [])
		mouse_filter = Control.MOUSE_FILTER_STOP
		var i := 0
		for n_any in nodes:
			if typeof(n_any) != TYPE_DICTIONARY:
				continue
			var n: Dictionary = n_any
			var did := str(n.get("did", i))
			var ang := TAU * float(i) / maxf(float(nodes.size()), 1.0)
			_pos[did] = Vector2(420, 200) + Vector2(cos(ang), sin(ang)) * 220.0
			_vel[did] = Vector2.ZERO
			i += 1
		queue_redraw()
		set_process(nodes.size() > 1)

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton):
			return
		var click := event as InputEventMouseButton
		if not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
			return
		for i in range(nodes.size() - 1, -1, -1):
			var n_any: Variant = nodes[i]
			if typeof(n_any) != TYPE_DICTIONARY:
				continue
			var n: Dictionary = n_any
			if str(n.get("kind", "")) != "info":
				continue
			var did := str(n.get("did", ""))
			var p: Vector2 = _pos.get(did, Vector2.ZERO)
			var title := _node_title(n)
			if click.position.distance_to(p) <= 18.0 or _label_rect(p, title).has_point(click.position):
				open_info.emit(did)
				accept_event()
				return

	func _process(delta: float) -> void:
		if _settled or nodes.size() <= 1:
			_settled = true
			set_process(false)
			return
		var energy := 0.0
		for a_any in nodes:
			if typeof(a_any) != TYPE_DICTIONARY:
				continue
			var a: Dictionary = a_any
			var aid := str(a.get("did", ""))
			var pa: Vector2 = _pos.get(aid, Vector2.ZERO)
			var force := (Vector2(420, 200) - pa) * 0.008
			var title_a := _node_title(a)
			var ra := _label_rect(pa, title_a)
			for b_any in nodes:
				if typeof(b_any) != TYPE_DICTIONARY:
					continue
				var b: Dictionary = b_any
				var bid := str(b.get("did", ""))
				if aid == bid:
					continue
				var pb: Vector2 = _pos.get(bid, Vector2.ZERO)
				var d: Vector2 = pa - pb
				var L := maxf(d.length(), 28.0)
				force += d.normalized() * (6400.0 / (L * L))
				force += _label_push(ra, _label_rect(pb, _node_title(b)))
			for e_any in edges:
				if typeof(e_any) != TYPE_DICTIONARY:
					continue
				var e: Dictionary = e_any
				if str(e.get("from", "")) == aid:
					force += _spring(_pos.get(str(e.get("to", "")), pa) - pa)
				elif str(e.get("to", "")) == aid:
					force += _spring(_pos.get(str(e.get("from", "")), pa) - pa)
			var v: Vector2 = _vel.get(aid, Vector2.ZERO)
			v = (v + force * _temperature) * lerpf(0.28, 0.82, _temperature)
			if v.length() > 14.0:
				v = v.limit_length(14.0)
			if v.length() < 0.2:
				v = Vector2.ZERO
			_vel[aid] = v
			_pos[aid] = pa + v * delta * 60.0
			energy += v.length_squared()
		_temperature *= pow(0.982, delta * 60.0)
		if _temperature < 0.05 or (_temperature < 0.45 and energy < 0.35):
			_freeze()
			return
		queue_redraw()

	func _freeze() -> void:
		_settled = true
		for key in _vel.keys():
			_vel[key] = Vector2.ZERO
		set_process(false)
		queue_redraw()

	func _node_title(n: Dictionary) -> String:
		var did := str(n.get("did", ""))
		return "%s  %s" % [str(n.get("title", str(n.get("kind", "")))), did.substr(0, mini(did.length(), 28))]

	func _draw() -> void:
		for e_any in edges:
			if typeof(e_any) != TYPE_DICTIONARY:
				continue
			var e: Dictionary = e_any
			var a: Vector2 = _pos.get(str(e.get("from", "")), Vector2.ZERO)
			var b: Vector2 = _pos.get(str(e.get("to", "")), Vector2.ZERO)
			draw_line(a, b, Color(0.45, 0.5, 0.58), 1.5)
		for n_any in nodes:
			if typeof(n_any) != TYPE_DICTIONARY:
				continue
			var n: Dictionary = n_any
			var did := str(n.get("did", ""))
			var p: Vector2 = _pos.get(did, Vector2.ZERO)
			var kind := str(n.get("kind", "info"))
			var col := Color(0.35, 0.72, 0.55) if kind == "info" else Color(0.75, 0.62, 0.32)
			draw_circle(p, 14.0, col)
			var title := "%s  %s" % [str(n.get("title", kind)), did.substr(0, mini(did.length(), 28))]
			draw_string(ThemeDB.fallback_font, p + Vector2(18, 4), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.92, 0.93, 0.95))

	func _label_rect(p: Vector2, title: String) -> Rect2:
		var width := ThemeDB.fallback_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		return Rect2(p + Vector2(16, -10), Vector2(width + 8.0, 22.0))

	func _label_push(a: Rect2, b: Rect2) -> Vector2:
		var pad := 10.0
		var ax := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
		var ay := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
		if ax + pad <= 0.0 or ay + pad <= 0.0:
			return Vector2.ZERO
		var push := Vector2.ZERO
		var sep := a.get_center() - b.get_center()
		if ax < ay:
			push.x = signf(sep.x if absf(sep.x) > 0.5 else 1.0) * (ax + pad) * 0.55
		else:
			push.y = signf(sep.y if absf(sep.y) > 0.5 else 1.0) * (ay + pad) * 0.9
		return push

	func _spring(toward: Vector2) -> Vector2:
		var dist := toward.length()
		if dist < 1.0:
			return Vector2.ZERO
		return toward.normalized() * (dist - 190.0) * 0.012
