extends GutTest

## Every character the game DISPLAYS must be one the font can draw.
##
## A grep gate, in the spirit of `test_world_clock`: the bug it catches is invisible
## on the machine you wrote it on and obvious to everybody else.
##
## Godot's default theme font is a subset of Open Sans, and on a desktop it quietly
## falls back to a SYSTEM font for anything the subset lacks. So an arrow, a play
## triangle or a star renders perfectly on a Linux box with DejaVu installed — and
## comes out as an empty box in the **web export**, where there is no system font to
## fall back to. That is how `▶ Play (⏎)`, `★ GOAL reached! ★` and five other strings
## shipped looking correct to everyone who wrote them.
##
## `has_char` reports the font's OWN coverage and ignores the system fallback, which
## is exactly the question the web build asks.
##
## What is safe: ASCII, and the Latin-1 punctuation this project already leans on —
## `·`, `—`, `•`, `×`. What is not: arrows, geometric shapes, dingbats. **If a glyph
## is not in the font, spell the word.**

## Comments are not displayed, so they may say `→` all they like. Only string
## literals are scanned.
const ROOTS := ["res://scripts", "res://scenes"]
const SKIP := ["res://scripts/tests"]


func test_every_displayed_character_can_be_drawn():
	var font: Font = ThemeDB.fallback_font
	assert_not_null(font, "there is a fallback font to ask")
	var bad: Array = []
	for path in _sources():
		var text := FileAccess.get_file_as_string(path)
		var line_no := 0
		for line in text.split("\n"):
			line_no += 1
			for literal in _quoted(String(line)):
				for i in range(literal.length()):
					var code: int = literal.unicode_at(i)
					if code > 127 and not font.has_char(code):
						bad.append("%s:%d  U+%04X '%s'  in \"%s\""
							% [path, line_no, code, literal[i], literal.substr(0, 60)])
	assert_eq(bad, [], "no string the game shows contains a glyph the font cannot draw:\n%s"
		% "\n".join(bad))


## The double-quoted spans of a line, stopping at a comment.
##
## Character by character rather than by regex because `"#"` is a real string in this
## project — it is the wall tile — and anything that treats the first `#` as a comment
## marker would truncate the line that paints walls.
func _quoted(line: String) -> Array:
	var out: Array = []
	var inside := false
	var buffer := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if inside and c == "\\":
			i += 2                     # an escape, whatever it escapes
			continue
		if c == "\"":
			if inside:
				out.append(buffer)
				buffer = ""
			inside = not inside
		elif inside:
			buffer += c
		elif c == "#":
			break                      # a # outside a string starts a comment
		i += 1
	return out


func _sources() -> Array:
	var found: Array = []
	var pending := ROOTS.duplicate()
	while not pending.is_empty():
		var dir_path := String(pending.pop_back())
		if SKIP.has(dir_path):
			continue
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			var full := "%s/%s" % [dir_path, entry]
			if dir.current_is_dir():
				pending.append(full)
			elif entry.ends_with(".gd") or entry.ends_with(".tscn"):
				found.append(full)
			entry = dir.get_next()
		dir.list_dir_end()
	return found
