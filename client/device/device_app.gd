## An app on the device (design doc §12.2; M5 spec claims 3–4): a pane that reads the
## sim every refresh and submits commands through the shell, and holds nothing of the
## sim's between frames (the fitness function on `client/device/` enforces it): view
## state only, such as a cursor. `refresh` returns whether what it shows changed, so
## the shell redraws only then (§12.4).
class_name DeviceApp extends Control

## The shell's submit: `func(kind: StringName, payload: Dictionary) -> void`.
var _submit: Callable = Callable()
## The shell's note line: `func(text: String) -> void`.
var _note: Callable = Callable()
var _last_text: String = ""


func bind(submit: Callable, note: Callable) -> void:
	_submit = submit
	_note = note


## Reads the sim and rebuilds the pane. Returns true when the pane changed.
func refresh(_sim: SimRoot, _player: int) -> bool:
	return false


## One of the device actions (`device_up`, `device_down`, `device_left`,
## `device_right`, `device_select`, `device_secondary`, `device_back`). Returns true
## when the app used it.
func handle(_action: StringName, _sim: SimRoot, _player: int) -> bool:
	return false


## The prompt line the shell shows under the pane for this app.
func prompts(_glyphs: InputGlyphs) -> String:
	return ""


## Sets the pane's text and reports whether it changed: the redraw-on-change signal
## for the text panes.
func _set_text(label: RichTextLabel, text: String) -> bool:
	if text == _last_text:
		return false
	_last_text = text
	label.text = text
	return true


func submit(kind: StringName, payload: Dictionary) -> void:
	if _submit.is_valid():
		_submit.call(kind, payload)


func note(text: String) -> void:
	if _note.is_valid():
		_note.call(text)
