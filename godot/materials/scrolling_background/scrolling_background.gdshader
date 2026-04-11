shader_type canvas_item;

uniform sampler2D text_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float scroll_speed : hint_range(0.0, 5.0) = 0.3;
uniform float row_height : hint_range(0.01, 1.0) = 0.1;
uniform float texture_aspect_ratio : hint_range(0.1, 50.0) = 10.0;
uniform float rotation : hint_range(-3.14159, 3.14159) = 0.0;
uniform float uv_scale : hint_range(0.1, 10.0) = 1.0;

uniform vec3 background_color : source_color = vec3(1.0, 0.0, 0.0);
uniform vec4 text_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
    // Rotate UV around the center
    vec2 centered = (UV - vec2(0.5)) * uv_scale;
    float s = sin(rotation);
    float c = cos(rotation);
    vec2 rotated = vec2(
        centered.x * c - centered.y * s,
        centered.x * s + centered.y * c
    ) + vec2(0.5);

    // Everything below is identical to before, just using rotated instead of UV
    float row = floor(rotated.y / row_height);
    float tile_v = fract(rotated.y / row_height);

    float direction = mod(row, 2.0) < 1.0 ? 1.0 : -1.0;
    float row_offset = fract(sin(row * 127.1 + 311.7) * 43758.5453);
    float offset = TIME * scroll_speed * direction + row_offset;

    float u_scale = row_height * texture_aspect_ratio;
    float tile_u = (rotated.x / u_scale) + offset;

    float texture_read = texture(text_texture, vec2(tile_u, tile_v)).a;
    vec3 out_color = mix(background_color, text_color.rgb, texture_read * text_color.a);
    COLOR = vec4(out_color, 1.0);
}