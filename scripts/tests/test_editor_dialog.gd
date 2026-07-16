## EditorDialog unit tests
##
## Drives the async prompt API: a fire-and-forget coroutine sets the inputs and clicks
## OK/Cancel a couple of frames after the prompt shows, while the test awaits the
## prompt's return value.

extends GutTest


## Let deferred signal emits / fire-and-forget confirm coroutines settle before GUT
## frees the autofreed dialog, so nothing is freed mid-emit at teardown.
func after_each() -> void:
	await wait_frames(1)


func _make() -> EditorDialog:
	var dlg := EditorDialog.new()
	add_child_autofree(dlg)
	await wait_frames(1)
	return dlg


# --- text ---

func _confirm_text_soon(dlg: EditorDialog, text: String) -> void:
	await wait_frames(2)
	dlg._text_input.text = text
	dlg._on_ok()


func test_prompt_text_confirm_returns_value() -> void:
	var dlg := await _make()
	_confirm_text_soon(dlg, "my_level")
	var result = await dlg.prompt_text("Save as", "initial")
	assert_eq(result, "my_level", "returns the typed text on OK")
	assert_false(dlg.visible, "dialog hides after confirm")


func _cancel_soon(dlg: EditorDialog) -> void:
	await wait_frames(2)
	dlg._on_cancel()


func test_prompt_text_cancel_returns_null() -> void:
	var dlg := await _make()
	_cancel_soon(dlg)
	var result = await dlg.prompt_text("Save as", "initial")
	assert_null(result, "returns null on cancel")


# --- form ---

func _confirm_form_soon(dlg: EditorDialog, values: Dictionary) -> void:
	await wait_frames(2)
	for key in values:
		dlg._field_inputs[key].text = str(values[key])
	dlg._on_ok()


func test_prompt_form_returns_typed_values() -> void:
	var dlg := await _make()
	var fields := [
		{"key": "name", "label": "Name", "value": "old", "kind": "text"},
		{"key": "par", "label": "Par", "value": "1", "kind": "int"},
	]
	_confirm_form_soon(dlg, {"name": "Chamber", "par": "4"})
	var result = await dlg.prompt_form("Metadata", fields)
	assert_eq(result["name"], "Chamber", "text field returned as string")
	assert_eq(result["par"], 4, "int field coerced to int")


func test_prompt_form_cancel_returns_null() -> void:
	var dlg := await _make()
	var fields := [{"key": "name", "label": "Name", "value": "x", "kind": "text"}]
	_cancel_soon(dlg)
	var result = await dlg.prompt_form("Metadata", fields)
	assert_null(result, "form returns null on cancel")


# --- choice ---

func _choose_soon(dlg: EditorDialog, index: int) -> void:
	await wait_frames(2)
	dlg._item_list.select(index)
	dlg._on_ok()


func test_prompt_choice_returns_index() -> void:
	var dlg := await _make()
	_choose_soon(dlg, 2)
	var result = await dlg.prompt_choice("Open", ["a", "b", "c"])
	assert_eq(result, 2, "returns the selected index")


func test_prompt_choice_cancel_returns_negative_one() -> void:
	var dlg := await _make()
	_cancel_soon(dlg)
	var result = await dlg.prompt_choice("Open", ["a", "b"])
	assert_eq(result, -1, "choice returns -1 on cancel")
