class_name InputHelp extends RefCounted

## InputHelp
##
## Builds the player-facing controls text from the LIVE InputMap, so the on-screen
## guidance can never drift from the actual key bindings again (the HUD's old
## instruction string was a hardcoded literal that no longer matched the controls).
## Also the single place a rebinding UI would read/label actions from.

## Human-readable key string for an action's first bound key ("?" if unbound).
static func key_for(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var code: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
			return OS.get_keycode_string(code)
	return "?"


## One-line gameplay controls summary for the HUD footer.
static func gameplay_summary() -> String:
	return "Arrows/WASD: Move  |  %s: Interact/Fold  |  %s: Confirm  |  %s: Undo  |  %s: Restart  |  %s: Pause  |  Click crease: Unfold" % [
		key_for("interact"),
		key_for("ui_accept"),
		key_for("ui_undo"),
		key_for("restart"),
		key_for("ui_cancel"),
	]


## Structured control rows (label -> keys) for a full help overlay / rebinding list.
static func control_rows() -> Array:
	return [
		{"label": "Move", "keys": "Arrows / WASD"},
		{"label": "Interact / place anchor (facing)", "keys": key_for("interact")},
		{"label": "Confirm fold (selected anchors)", "keys": key_for("ui_accept")},
		{"label": "Undo", "keys": key_for("ui_undo")},
		{"label": "Restart level", "keys": key_for("restart")},
		{"label": "Pause / cancel selection", "keys": key_for("ui_cancel")},
		{"label": "Unfold a crease", "keys": "Click the crease dot"},
	]
