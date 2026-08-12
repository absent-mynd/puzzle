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

varying vec2 world_pos;

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
}

void fragment() {
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
		float threshold = mix(0.5, bayer4(world_pos / pixel_size), dither);
		float steps = float(light_steps);
		float q = floor(m * steps + threshold) / steps;
		acc *= q / m;
	}

	vec3 lit = clamp(ambient + acc * light_gain, vec3(0.0), vec3(max_light));
	COLOR.rgb *= tint * lit;
}
