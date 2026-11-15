shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.46, 0.07, 1.0);
varying vec3 local_vertex;
varying vec3 local_normal;

void vertex() {
	// The shared unit box is scaled by its node. Coordinates stay -1..1 per face.
	local_vertex = VERTEX * 2.0;
	local_normal = NORMAL;
}

void fragment() {
	vec2 face_position = local_vertex.xy;
	if (abs(local_normal.y) > 0.5) {
		face_position = local_vertex.xz;
	} else if (abs(local_normal.x) > 0.5) {
		face_position = local_vertex.zy;
	}
	float distance_to_edge = max(abs(face_position.x), abs(face_position.y));
	float edge_halo = exp(-pow((distance_to_edge - 0.94) * 11.0, 2.0));
	float pulse = 0.83 + 0.17 * sin(TIME * 2.3);
	ALBEDO = glow_color.rgb;
	ALPHA = (0.12 + edge_halo * 0.38) * pulse;
}
