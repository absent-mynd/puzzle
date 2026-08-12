shader_type canvas_item;

// held
//
// What a stopped world looks like.
//
// Raising a hand stops time (see `FoldWorld.placing()`), and the world says so by
// not moving — which is a problem, because a world that is not moving looks exactly
// like a world you are not moving IN. Standing still and time being held are the same
// picture. So the screen takes on a look of its own for as long as the hold lasts.
//
// This runs on the TextureRect that composites the low-resolution render target, so
// it is the last thing to touch the world and the only thing that can speak for all
// of it at once. The HUD is on its own layer above and is untouched: the readout that
// says PLACING must not be dimmed by the effect it is describing.
//
// Three decisions, and the first two are the same one the lighting pass makes:
//
//   1. **Everything happens on the ART-PIXEL grid**, recovered from
//      `TEXTURE_PIXEL_SIZE` — the render target is the art, so its texels ARE art
//      pixels at every zoom. A dither computed in screen pixels would be four times
//      too fine and would read as video noise laid over the game rather than as
//      something the game is made of.
//   2. **The threshold is the same 4x4 ordered Bayer** as `pixel_lit.gdshader`, by
//      the same arithmetic trick. This game already says "a value between two values"
//      with that exact checker; a second dither pattern would be a second dialect.
//   3. **The hold DISSOLVES in rather than crossfading.** Each art pixel flips the
//      instant the ease passes its own threshold, so the stop spreads across the
//      frame as a growing checker in about a tenth of a second. A smooth fade would
//      be a continuous animation announcing that continuous animation has stopped.
//
// The held look itself is a desaturation toward a cold tint plus a slight darkening —
// the colour drains out of the world and it cools. On top of that the dither STAYS,
// as a fixed screen-door over the held frame: every other art pixel a shade deeper,
// so the still frame has a visible texture and cannot be mistaken for the game having
// simply stopped drawing.
//
// Nothing here animates on its own. That is the entire point: with `held` steady the
// output is a fixed function of the input, so a stopped world is one unchanging image.

// How far into the held look the screen is. `FoldWorld` eases this in real time —
// the effect announces the stop, so it is not itself stopped by it.
uniform float held : hint_range(0.0, 1.0) = 0.0;

// What the world's colour drains toward. Cold and slightly blue: the game already
// spends warm amber on the things you carry and act with, so cooling is the cheapest
// way to say "not now" without touching those hues' meaning.
uniform vec3 hold_tint = vec3(0.72, 0.80, 1.05);

// How much of the colour goes. Deliberately restrained, and this is the one number
// here with a rule behind it rather than a taste: the overlay draws INSIDE the render
// target, so this effect reaches the markers too, and those are drawn unlit precisely
// so that what you navigate and fold by never dims. Drain hard enough to grey them
// out and the cursor stops saying which KIND of hand is about to be spent — which is
// the decision the pause exists to let you make. The world cools; it does not go
// monochrome.
uniform float drain : hint_range(0.0, 1.0) = 0.34;

// How far the held frame sits below the running one. Enough to read as a step down,
// not so much that a dark corner becomes unreadable.
uniform float dim : hint_range(0.0, 1.0) = 0.18;

// Depth of the screen-door left behind once a pixel has flipped. This carries most of
// the message, since the colour shift is kept light — the texture is the tell.
uniform float screen_door : hint_range(0.0, 1.0) = 0.26;

// 4x4 ordered-dither threshold in [0,1), computed arithmetically so the shader needs
// no constant array. Identical to `pixel_lit.gdshader` — same pattern, same phase, so
// the two never beat against each other.
float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x / 2.0 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

void fragment() {
	// Texel coordinates of the render target = art pixels, at any zoom.
	float threshold = bayer4(UV / TEXTURE_PIXEL_SIZE);
	// The dissolve, and the whole of the on/off test: `bayer4` is never negative, so
	// at `held == 0` no pixel qualifies and the running world passes through
	// untouched; its ceiling is 15/16, so by `held == 1` every pixel has flipped.
	// (Written as one branch rather than an early-out because Godot's shader language
	// does not allow `return` in `fragment`.)
	if (threshold < held) {
		float lum = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
		vec3 frozen = mix(COLOR.rgb, lum * hold_tint, drain) * (1.0 - dim);
		COLOR.rgb = frozen * (1.0 - screen_door * threshold);
	}
}
