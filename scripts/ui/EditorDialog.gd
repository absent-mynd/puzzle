class_name EditorDialog extends Control

## EditorDialog
##
## One reusable modal dialog for the level editor, replacing the five near-duplicate
## keyboard handlers that used to hijack the status label as a fake text field. It's a
## themed Control overlay (dim background + centered PanelContainer) — NOT a Window — so
## it inherits the project theme and is fully testable headlessly.
##
## Async API (each shows the dialog and `await`s the user's choice):
##   var name = await dialog.prompt_text("Save as", current)      # String, or null
##   var meta = await dialog.prompt_form("Metadata", fields)      # Dictionary, or null
##   var idx  = await dialog.prompt_choice("Open level", names)   # int index, or -1
##
## Confirm = OK button or ENTER; cancel = Cancel button or ESC.

## Emitted internally when the user confirms/cancels; carries the result. `await`ed by
## the prompt_* methods.
signal _closed(result)

var _title_label: Label
var _content: VBoxContainer
var _ok_button: Button
var _cancel_button: Button

## Per-prompt content nodes (set while a prompt is active).
var _text_input: LineEdit = null
var _field_inputs: Dictionary = {}   # key -> LineEdit
var _field_kinds: Dictionary = {}    # key -> "text" | "int" | "float"
var _item_list: ItemList = null

## "text" | "form" | "choice" — which prompt is active (governs how a result is built).
var _mode: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # block clicks to the editor behind
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = UIPalette.OVERLAY_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UIConstants.SPACING_MD)
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.theme_type_variation = &"HeadingLabel"
	vbox.add_child(_title_label)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", UIConstants.SPACING_SM)
	vbox.add_child(_content)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", UIConstants.SPACING_SM)
	vbox.add_child(buttons)

	_cancel_button = Button.new()
	_cancel_button.text = "Cancel"
	_cancel_button.custom_minimum_size = UIConstants.DIALOG_BUTTON
	_cancel_button.pressed.connect(_on_cancel)
	buttons.add_child(_cancel_button)

	_ok_button = Button.new()
	_ok_button.text = "OK"
	_ok_button.theme_type_variation = &"PrimaryButton"
	_ok_button.custom_minimum_size = UIConstants.DIALOG_BUTTON
	_ok_button.pressed.connect(_on_ok)
	buttons.add_child(_ok_button)


## Prompt for a single line of text. Returns the entered String, or null on cancel.
func prompt_text(title: String, initial: String = "") -> Variant:
	_reset_content()
	_mode = "text"
	_title_label.text = title
	_text_input = LineEdit.new()
	_text_input.text = initial
	_text_input.custom_minimum_size = Vector2(360, 0)
	_content.add_child(_text_input)
	_show()
	_text_input.grab_focus()
	_text_input.select_all()
	return await _closed


## Prompt for several fields at once. `fields` is an Array of
## {"key","label","value", "kind": "text"|"int"|"float"}. Returns a Dictionary of
## key -> typed value, or null on cancel.
func prompt_form(title: String, fields: Array) -> Variant:
	_reset_content()
	_mode = "form"
	_title_label.text = title
	for f in fields:
		var key: String = f["key"]
		var kind: String = f.get("kind", "text")
		_field_kinds[key] = kind

		var row := VBoxContainer.new()
		var label := Label.new()
		label.theme_type_variation = &"StatusLabel"
		label.text = f.get("label", key)
		row.add_child(label)

		var input := LineEdit.new()
		input.text = str(f.get("value", ""))
		input.custom_minimum_size = Vector2(360, 0)
		row.add_child(input)

		_content.add_child(row)
		_field_inputs[key] = input
	_show()
	if not _field_inputs.is_empty():
		_field_inputs.values()[0].grab_focus()
	return await _closed


## Prompt to pick one of `items` (Array of String). Returns the chosen index, or -1.
func prompt_choice(title: String, items: Array) -> Variant:
	_reset_content()
	_mode = "choice"
	_title_label.text = title
	_item_list = ItemList.new()
	_item_list.custom_minimum_size = Vector2(360, 220)
	for it in items:
		_item_list.add_item(str(it))
	if items.size() > 0:
		_item_list.select(0)
	_item_list.item_activated.connect(func(_i): _on_ok())  # double-click confirms
	_content.add_child(_item_list)
	_show()
	_item_list.grab_focus()
	return await _closed


func _reset_content() -> void:
	for c in _content.get_children():
		c.queue_free()
	_text_input = null
	_field_inputs = {}
	_field_kinds = {}
	_item_list = null


func _show() -> void:
	visible = true


## Build the result from the active prompt's inputs.
func _collect_result() -> Variant:
	match _mode:
		"text":
			return _text_input.text if _text_input else ""
		"form":
			var out := {}
			for key in _field_inputs:
				out[key] = _coerce(_field_inputs[key].text, _field_kinds.get(key, "text"))
			return out
		"choice":
			return _item_list.get_selected_items()[0] if (_item_list and _item_list.get_selected_items().size() > 0) else -1
		_:
			return null


## Coerce a raw string to the field's kind (invalid numbers pass through as the string
## so the caller can decide; callers here validate before writing).
func _coerce(text: String, kind: String) -> Variant:
	match kind:
		"int":
			return int(text) if text.is_valid_int() else text
		"float":
			return float(text) if text.is_valid_float() else text
		_:
			return text


func _cancel_result() -> Variant:
	return -1 if _mode == "choice" else null


func _on_ok() -> void:
	var result: Variant = _collect_result()
	visible = false
	# Deferred so the awaiting caller resumes OUTSIDE the button/input call stack (avoids
	# "locked object" if the caller frees or rebuilds nodes on resume).
	_closed.emit.call_deferred(result)


func _on_cancel() -> void:
	visible = false
	_closed.emit.call_deferred(_cancel_result())


## ENTER confirms, ESC cancels while the dialog is open. Marked handled so the editor's
## own _input (guarded by its dialog flag anyway) never sees these.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and _mode != "form":
		# In a multi-field form, ENTER shouldn't submit while tabbing between fields.
		_on_ok()
		get_viewport().set_input_as_handled()


## True while a prompt is on screen (the editor uses this to ignore its own input).
func is_open() -> bool:
	return visible
