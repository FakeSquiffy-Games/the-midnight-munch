shader_type canvas_item;

void fragment() {
    float distance_to_center = distance(UV, vec2(0.5));
    if (distance_to_center > 0.5) {
        discard;
    }
}