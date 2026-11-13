shader_type canvas_item;

// pixel_lit
//
// Ambient + point lights for the folded world's tiles, evaluated at ART-PIXEL
// resolution so the lighting stays as chunky as the tiles it falls on.
//
// Three things make this read as pixel lighting rather than a soft 2D glow:
//
//   1. Both the shaded point and every light position are SNAPPED to the
//      art-pixel grid before the distance is taken, so a light's falloff moves
//      in whole pixels and its edge is a staircase, not a gradient.
//   2. The accumulated intensity is QUANTIZED into `light_steps` steps, so
//      light arrives as discrete rings the way a hand-painted sprite would.
//   3. The step edges are ORDERED-DITHERED with a 4x4 Bayer threshold computed
//      in art-pixel space, so the rings break up into a checker rather than a
//      hard contour.
//
// Ambient is deliberately generous: unlit ground must stay readable and
// navigable. Lighting here is style, not a fog-of-war mechanic.
//
// There is no occlusion. Lights pass through walls. That is a deliberate limit
// while the fold seam stays a hard cut — shadow casters would have to be
// re-derived per fold and would want to blur the seam, which is exactly what
// we do not want yet.
//
// INK is the other half, and it is what gives the sheet edges. Every vertex carries
// (in COLOR, which `vertex()` takes and then clears) which of its base tile's four
// neighbours matter and where in that tile it sits. From that the fragment draws,
// per art pixel:
//
//   - on what stops you: a dark RIM along every face that met open space;
//   - on what you move through: a dithered CONTACT SHADOW where something solid
//     stood against it — under an overhang, beside a wall, along a floor.
//
// And rock DARKENS away from its surface: the tile that faces air is drawn as painted,
// the one behind it dimmer, and by `TileBatch.MAX_DEPTH` in it is `rock_shade` of
// itself. So a room reads as shapes with faces, not as a field of brick.
//
// All three are BASE-space facts (`TileBatch` reads them off the base grid), so
// a tile keeps its rim and its shadow however it is folded, ridden or cut, and a
// crease cuts them exactly as it cuts the art. That is the same rule the wall's lit
// cap has always followed, extended to the other three sides; it is why a seam shows
// two rims meeting, and stays a hard line.
//
// Ink multiplies the texel BEFORE the light, so a rim under a lamp is a lit rim.
//
// Water MOVES: alternate pixel rows slide a texel either way. On `world_time`, which
// the rig feeds from `WorldClock` — never TIME — so held water holds still.

const int MAX_LIGHTS = 12;

// Position (world units) of each live light.
uniform vec2 light_pos[MAX_LIGHTS];
// Linear RGB of each live light.
uniform vec3 light_color[MAX_LIGHTS];
// x = radius in world units, y = energy multiplier.
uniform vec2 light_falloff[MAX_LIGHTS];
uniform int light_count = 0;

// Base illumination where no light reaches. Never near zero: see above.
uniform vec3 ambient = vec3(0.55, 0.58, 0.72);
// How strongly THIS surface answers light. Background paper takes less than
// foreground solids, which is what separates the two planes.
uniform float light_gain = 1.0;
// Flat multiplier for the whole surface (the subspace's hue shift).
uniform vec3 tint = vec3(1.0);

// World units per art pixel — the snapping quantum.
uniform float pixel_size = 4.0;
// Number of discrete brightness steps between dark and fully lit.
uniform int light_steps = 5;
// 0 = hard steps, 1 = fully dithered step edges.
uniform float dither = 0.85;
// Ceiling on accumulated light, so overlapping lamps bloom instead of blowing out.
uniform float max_light = 1.75;

// True for the material that draws what stops you. It decides what the neighbour
// mask MEANS: open faces to rim, or solid neighbours to cast a contact shadow.
uniform bool solid = false;
// The tileset's shape, so a fragment can tell which kind it is drawing and stay
// inside its own tile when it slides a texel.
uniform float atlas_kinds = 12.0;
uniform float atlas_variants = 4.0;
uniform float tile_px = 16.0;
// How bright the deepest rock is drawn, as a fraction of its painted colour.
uniform float rock_shade : hint_range(0.0, 1.0) = 0.46;
// The row of the tileset that is water.
uniform float water_kind = 3.0;
// Seconds of WORLD time (`WorldClock`). Stops when the world does.
uniform float world_time = 0.0;

varying vec2 world_pos;
// r: neighbour mask / 15 (1 up, 2 right, 4 down, 8 left).  g: depth in solid mass,
// 0..1.  b, a: where in its base cell this vertex sits, 0..1.
varying vec4 tile;

// 4x4 ordered-dither threshold in [0,1), computed arithmetically so the shader
// needs no constant array.
float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x / 2.0 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

vec2 snap_px(vec2 p) {
	return floor(p / pixel_size) * pixel_size;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	// The vertex colour is DATA here, not a colour: take it and hand the fragment
	// plain white, so the texel arrives untinted.
	tile = COLOR;
	COLOR = vec4(1.0);
}

bool bit(float mask, float value) {
	return mod(floor(mask / value), 2.0) >= 1.0;
}

// How much ink this art pixel takes, 1 = none.
float ink_at(vec2 lp, float mask, float threshold) {
	bool up = bit(mask, 1.0);
	bool right = bit(mask, 2.0);
	bool down = bit(mask, 4.0);
	bool left = bit(mask, 8.0);
	float ink = 1.0;
	float last = tile_px - 1.0;
	if (solid) {
		// The rim. One pixel on the sides, two underneath: the underside of a thing
		// is the part that is in its own shadow. The top is left to the tileset,
		// which paints the sky-facing cap.
		if (left && lp.x < 1.0) ink = min(ink, 0.58);
		if (right && lp.x >= last) ink = min(ink, 0.58);
		if (down && lp.y >= last) ink = min(ink, 0.46);
		else if (down && lp.y >= last - 1.0) ink = min(ink, 0.74);
		if (up && lp.y < 1.0 && (left && lp.x < 1.0 || right && lp.x >= last)) ink = 0.58;
	} else {
		// The contact shadow: solid above reaches furthest (an overhang), a wall
		// beside reaches a little, a floor below is a single grounding line. Each
		// thins out through the same ordered dither the light steps use.
		if (up && 1.0 - lp.y / 6.0 > threshold) ink = min(ink, 0.70);
		if (left && 1.0 - lp.x / 3.0 > threshold) ink = min(ink, 0.78);
		if (right && 1.0 - (last - lp.x) / 3.0 > threshold) ink = min(ink, 0.78);
		if (down && lp.y >= last) ink = min(ink, 0.82);
	}
	return ink;
}

void fragment() {
	// Which art pixel this is, in the world and within its own tile. Both take a
	// quarter-pixel nudge before the floor: when the target has an odd size (it does,
	// mid-zoom) pixel centres land exactly ON art-pixel boundaries, and a bare floor
	// would drop a one-pixel rim from some tiles and double it on others. Centres sit
	// on a boundary or in the middle, never anywhere else, and a quarter clears both.
	vec2 art = floor(world_pos / pixel_size + 0.25);
	float threshold = bayer4(art);

	// The texel. Water slides alternate rows a texel either way, wrapped inside its
	// own tile so it can never read a neighbouring variant.
	vec2 uv = UV;
	if (abs(floor(UV.y * atlas_kinds) - water_kind) < 0.5) {
		float row = art.y;
		float slide = floor(sin(world_time * 1.7 + row * 0.8) * 1.49 + 0.5);
		float column = floor(UV.x * atlas_variants);
		float u = fract(fract(UV.x * atlas_variants) + slide / tile_px);
		uv.x = (column + u) / atlas_variants;
	}
	vec4 texel = texture(TEXTURE, uv);
	vec2 lp = clamp(floor(tile.ba * tile_px + 0.25), vec2(0.0), vec2(tile_px - 1.0));
	texel.rgb *= ink_at(lp, floor(tile.r * 15.0 + 0.5), threshold);
	texel.rgb *= mix(1.0, rock_shade, clamp(tile.g, 0.0, 1.0));
	COLOR = texel;

	vec2 p = snap_px(world_pos);
	vec3 acc = vec3(0.0);
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= light_count) {
			break;
		}
		float radius = light_falloff[i].x;
		if (radius <= 0.0) {
			continue;
		}
		float d = distance(p, snap_px(light_pos[i]));
		float a = clamp(1.0 - d / radius, 0.0, 1.0);
		// Squared falloff: a small bright core with a long, quiet tail.
		acc += light_color[i] * (a * a * light_falloff[i].y);
	}

	// Quantize the accumulated INTENSITY, not each channel, so overlapping
	// lights of different colours blend together instead of separating into
	// per-channel contours.
	float m = max(acc.r, max(acc.g, acc.b));
	if (m > 0.0001) {
		float steps = float(light_steps);
		float q = floor(m * steps + mix(0.5, threshold, dither)) / steps;
		acc *= q / m;
	}

	vec3 lit = clamp(ambient + acc * light_gain, vec3(0.0), vec3(max_light));
	COLOR.rgb *= tint * lit;
}
