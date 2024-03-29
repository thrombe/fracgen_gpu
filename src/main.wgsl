
struct Stuff {
    render_width: u32,
    render_height: u32,
    display_width: u32,
    display_height: u32,
    windowless: u32,

    time: f32,
    cursor_x: f32,
    cursor_y: f32,

    scroll: f32,
    mouse_left: u32,
    mouse_right: u32,
    mouse_middle: u32,
};

@group(0) @binding(0)
var<uniform> stuff: Stuff;

const PI: f32 = 3.14159265359;
const PHI: f32 = 1.61803398874989484820459;
alias v2f = vec2<f32>;
alias v3f = vec3<f32>;
alias v4f = vec4<f32>;
