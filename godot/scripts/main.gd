class_name NodeConsole
extends Control

## Node-1 console veneer. Durable mutates go to OTP HTTP only (ADR 0004).
## Helen → Alice play: empty CoT, W0 genesis, W1, Exit, Alice login, discovery, W2.

const BASE := "http://127.0.0.1:4000"

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
		status_label.text = "OTP unreachable at %s — run ./scripts/node-up.sh." % BASE
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
				status_label.text = "Empty CoT — chooser."
				_show_chooser()
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
				status_label.text = "Genesis replay denied — zeroise first."
				return
			if code >= 400:
				status_label.text = "Genesis failed (%s): %s" % [code, text]
				return
			status_label.text = "Genesis ok — Helen is King. Not signed HTTP."
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
				status_label.text = "W1 denied (cap or locked graph)."
				return
			if code >= 400:
				status_label.text = "W1 failed (%s): %s" % [code, text]
				return
			if typeof(parsed) == TYPE_DICTIONARY:
				_shown_pin = str(parsed.get("pin", ""))
				status_label.text = "Alice admitted. PIN (show once): %s" % _shown_pin
				_set_graph_out("pin", _shown_pin)
			else:
				status_label.text = "W1 ok."
		"run_w2":
			if code == 403:
				status_label.text = "W2 denied (no cap, vault, or locked graph)."
				return
			if code >= 400:
				status_label.text = "W2 failed (%s): %s" % [code, text]
				return
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
			status_label.text = "Discovery (data = markers; unread info omitted)."
		"save_graph":
			if code == 403:
				status_label.text = "Graph locked — GraphEdit cannot widen authority."
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


func _emit_session() -> void:
	if session_username.is_empty():
		session_label.text = "Session: none (Esc unsits; Exit logs out)"
	else:
		session_label.text = "Session: %s  %s" % [session_username, _short_principal(session_principal_id)]
	session_changed.emit(session_principal_id, session_username)


func _clear_screen() -> void:
	for c in screen_host.get_children():
		c.queue_free()
	_graph_inputs.clear()
	_discovery = null
	_screen = ""


func _vbox() -> VBoxContainer:
	var box := VBoxContainer.new()
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
	_clear_screen()
	_screen = "chooser"
	var box := _vbox()
	box.add_child(_heading("Boot chooser"))
	box.add_child(_note("This box has no CoT yet. Network join (sign EK, D2, resolve G) is later."))
	box.add_child(_btn("King-making (W0 genesis)", _open_w0))
	box.add_child(_btn("Power off", func() -> void: _http_post("/v1/lab/power", {"on": false}, "power")))
	box.add_child(_btn("Zeroise (re-open King-making; chain wipe stubbed)", func() -> void: _http_post("/v1/lab/zeroise", {}, "zeroise")))
	box.add_child(_btn("Refresh", _refresh))


func _show_login() -> void:
	_clear_screen()
	_screen = "login"
	var box := _vbox()
	box.add_child(_heading("Identity process"))
	box.add_child(_note("Username + PIN. Paper private key is imported into this user's vault. Stub αβω pass granted caps. Not signed sessions."))
	var user := LineEdit.new()
	user.placeholder_text = "Username"
	user.name = "LoginUser"
	box.add_child(user)
	var pin := LineEdit.new()
	pin.placeholder_text = "PIN"
	pin.secret = true
	pin.name = "LoginPin"
	box.add_child(pin)
	var sk := LineEdit.new()
	sk.placeholder_text = "Paper private key"
	sk.secret = true
	sk.name = "LoginKey"
	box.add_child(sk)
	box.add_child(_btn("Login", func() -> void:
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
	box.add_child(_note("Runnable workspaces are OTP caps, not GraphEdit pictures."))
	if workspaces.is_empty():
		box.add_child(_note("No workspaces listed for this principal."))
	for w_any in workspaces:
		if typeof(w_any) != TYPE_DICTIONARY:
			continue
		var w: Dictionary = w_any
		var id := str(w.get("id", ""))
		var locked := bool(w.get("locked", false))
		var label := "%s%s" % [id, " (locked)" if locked else ""]
		box.add_child(_btn("Run %s" % label, _open_workspace.bind(id)))
	box.add_child(_btn("Discovery", _open_discovery))
	box.add_child(_btn("Exit session", func() -> void:
		_http_post("/v1/session/logout", {"principal_id": _actor()}, "logout")
	))
	box.add_child(_btn("Power off", func() -> void: _http_post("/v1/lab/power", {"on": false}, "power")))
	box.add_child(_btn("Refresh", _refresh))
	if not _shown_pin.is_empty():
		box.add_child(_note("Last generated PIN (paper, show once): %s" % _shown_pin))


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
		layout = {
			"workspace_id": "w0",
			"nodes": [
				{"id": "username", "title": "Username", "x": 40, "y": 40, "type": "text_in"},
				{"id": "public_key", "title": "Public key", "x": 40, "y": 140, "type": "text_in"},
				{"id": "private_key", "title": "Private key (paper)", "x": 40, "y": 240, "type": "text_in"},
				{"id": "pin", "title": "PIN", "x": 380, "y": 40, "type": "text_in"},
				{"id": "run", "title": "Run genesis", "x": 380, "y": 180, "type": "run"},
			],
			"wires": [["username", "run"], ["public_key", "run"], ["private_key", "run"], ["pin", "run"]],
		}
	_usernames = ws.get("usernames", [])
	var box := _vbox()
	var title := "Workspace %s" % str(ws.get("id", _workspace_id))
	if bool(ws.get("locked", false)) or bool(layout.get("locked", false)):
		title += " — locked (server denies GraphEdit widen)"
	if bool(ws.get("system", false)):
		title += " — system (no prior cap)"
	box.add_child(_heading(title))
	var row := HBoxContainer.new()
	row.add_child(_btn("Back", _refresh))
	row.add_child(_btn("Try save layout (expect deny if locked)", func() -> void:
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


func _build_graph(parent: Control, layout: Dictionary) -> void:
	var graph := GraphEdit.new()
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.custom_minimum_size = Vector2(0, 380)
	graph.right_disconnects = false
	parent.add_child(graph)
	_graph_inputs.clear()
	var nodes: Array = layout.get("nodes", [])
	for n_any in nodes:
		if typeof(n_any) != TYPE_DICTIONARY:
			continue
		var n: Dictionary = n_any
		var gn := GraphNode.new()
		var nid := str(n.get("id", "n"))
		gn.name = nid
		gn.title = str(n.get("title", nid))
		gn.position_offset = Vector2(float(n.get("x", 40)), float(n.get("y", 40)))
		gn.custom_minimum_size = Vector2(220, 80)
		var typ := str(n.get("type", "text_in"))
		match typ:
			"text_out":
				var out := LineEdit.new()
				out.editable = false
				out.placeholder_text = "(output)"
				gn.add_child(out)
				_graph_inputs[nid] = out
			"user_picker":
				var item := ItemList.new()
				item.select_mode = ItemList.SELECT_MULTI
				item.custom_minimum_size = Vector2(200, 88)
				for u_any in _usernames:
					if typeof(u_any) == TYPE_DICTIONARY:
						item.add_item(str(u_any.get("username", "")))
				gn.add_child(item)
				_graph_inputs[nid] = item
			"run":
				var b := Button.new()
				b.text = gn.title
				b.pressed.connect(_on_run_graph)
				gn.add_child(b)
			_:
				var le := LineEdit.new()
				le.placeholder_text = gn.title
				gn.add_child(le)
				_graph_inputs[nid] = le
		gn.set_slot(0, true, 0, Color(0.55, 0.75, 0.9), true, 0, Color(0.55, 0.75, 0.9))
		graph.add_child(gn)
	for w_any in layout.get("wires", []):
		if typeof(w_any) == TYPE_ARRAY and w_any.size() >= 2:
			graph.connect_node(str(w_any[0]), 0, str(w_any[1]), 0)


func _graph_text(id: String) -> String:
	var c: Variant = _graph_inputs.get(id)
	if c is LineEdit:
		return (c as LineEdit).text
	return ""


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
				"readers": _graph_picked("readers"),
				"writers": _graph_picked("writers"),
				"link_did": _graph_text("link"),
			}, "run_w2")
		_:
			status_label.text = "Unknown workspace %s" % _workspace_id


func _show_discovery(graph: Dictionary) -> void:
	_clear_screen()
	_screen = "discovery"
	var box := _vbox()
	box.add_child(_heading("Discovery"))
	box.add_child(_note("Walk from D5[user]. Info filtered by read list. Data = markers (no D4 bytes)."))
	box.add_child(_btn("Back", _refresh))
	_discovery = DiscoveryView.new()
	_discovery.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_discovery.custom_minimum_size = Vector2(0, 360)
	_discovery.setup(graph)
	box.add_child(_discovery)


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
	var nodes: Array = []
	var edges: Array = []
	var _pos: Dictionary = {}
	var _vel: Dictionary = {}

	func setup(graph: Dictionary) -> void:
		nodes = graph.get("nodes", [])
		edges = graph.get("edges", [])
		var i := 0
		for n_any in nodes:
			if typeof(n_any) != TYPE_DICTIONARY:
				continue
			var n: Dictionary = n_any
			var did := str(n.get("did", i))
			var ang := TAU * float(i) / maxf(float(nodes.size()), 1.0)
			_pos[did] = Vector2(420, 200) + Vector2(cos(ang), sin(ang)) * 140.0
			_vel[did] = Vector2.ZERO
			i += 1
		queue_redraw()
		set_process(true)

	func _process(delta: float) -> void:
		if nodes.is_empty():
			return
		for a_any in nodes:
			if typeof(a_any) != TYPE_DICTIONARY:
				continue
			var a: Dictionary = a_any
			var aid := str(a.get("did", ""))
			var pa: Vector2 = _pos.get(aid, Vector2.ZERO)
			var force := (Vector2(420, 200) - pa) * 0.02
			for b_any in nodes:
				if typeof(b_any) != TYPE_DICTIONARY:
					continue
				var b: Dictionary = b_any
				var bid := str(b.get("did", ""))
				if aid == bid:
					continue
				var pb: Vector2 = _pos.get(bid, Vector2.ZERO)
				var d: Vector2 = pa - pb
				var L := maxf(d.length(), 8.0)
				force += d.normalized() * (1800.0 / (L * L))
			for e_any in edges:
				if typeof(e_any) != TYPE_DICTIONARY:
					continue
				var e: Dictionary = e_any
				if str(e.get("from", "")) == aid:
					var other: Vector2 = _pos.get(str(e.get("to", "")), pa)
					force += (other - pa) * 0.015
				elif str(e.get("to", "")) == aid:
					var other2: Vector2 = _pos.get(str(e.get("from", "")), pa)
					force += (other2 - pa) * 0.015
			var v: Vector2 = _vel.get(aid, Vector2.ZERO)
			v = (v + force) * 0.85
			_vel[aid] = v
			_pos[aid] = pa + v * delta * 60.0
		queue_redraw()

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
