shader_type canvas_item;

// The cutting mat: what is under the sheet.
//
// Everything that is not sheet used to be one flat colour, which said "nothing is
// here" about the one place the game is most about — the space a fold takes away, the
// gap a strip leaves either side of itself, the edge a room ends on. A sheet that
// gets cut and folded is lying on something, and this is it: a dark mat ruled in
// cells, with every fourth line drawn solid.
//
// The ruling is the WORLD'S grid, at rest. That is the point of it: the sheet slides
// over the mat when it folds, and the mat does not move, so a fold is seen against
// something that stayed where it was.
//
// A function of world position and nothing else. No time, no light, no state — so it
// is the same image for as long as the camera is still, which is what a held world
// has to be.

// One art pixel and one cell, in world units.
uniform float pixel_size = 4.0;
uniform float cell = 64.0;
// The colour of the mat itself. The world sets it: it deepens as you fold in.
uniform vec3 ground = vec3(0.039, 0.043, 0.071);
// How far the ruling lifts off the ground, dotted and solid.
uniform float minor_lift = 0.03;
uniform float major_lift = 0.06;
// Every how many cells a line is drawn solid.
uniform float major_every = 4.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Which art pixel this is. The quarter-pixel nudge is not cosmetic: when the render
	// target has an odd size (it does, mid-zoom) the pixel centres land EXACTLY on
	// art-pixel boundaries, `floor` goes either way on the last bit of a float, and a
	// one-pixel line is skipped in some columns and doubled in others. Centres only
	// ever sit on a boundary or in the middle, and a quarter is clear of both.
	vec2 px = floor(world_pos / pixel_size + 0.25);
	float per = cell / pixel_size;
	vec2 in_cell = mod(px, per);
	vec2 id = floor(px / per);
	bool on_x = in_cell.x < 1.0;
	bool on_y = in_cell.y < 1.0;

	float lift = 0.0;
	// The ordinary ruling is dotted, so it reads as a guide and not as a wall.
	if ((on_x && mod(px.y, 2.0) < 1.0) || (on_y && mod(px.x, 2.0) < 1.0)) {
		lift = minor_lift;
	}
	if ((on_x && mod(id.x, major_every) < 0.5) || (on_y && mod(id.y, major_every) < 0.5)) {
		lift = major_lift;
	}
	// Lift along the ground's own hue, so the ruling deepens with it.
	vec3 hue = ground / max(max(ground.r, max(ground.g, ground.b)), 0.0001);
	COLOR = vec4(ground + hue * lift, 1.0);
}
