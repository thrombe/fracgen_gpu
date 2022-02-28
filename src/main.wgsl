
// https://gpuweb.github.io/gpuweb/wgsl/#builtin-functions

struct Stuff {
    width: f32;
    height: f32;
    time: f32;
    cursor_x: f32;
    cursor_y: f32;

    scroll: f32;
    mouse_left: u32;
    mouse_right: u32;
    mouse_middle: u32;
};
[[group(0), binding(0)]]
var<uniform> stuff: Stuff;

let PI = 3.14159265359;
let PHI = 1.61803398874989484820459;
type v2f = vec2<f32>;
type v3f = vec3<f32>;
type v4f = vec4<f32>;


struct TrajectoryPoint {
    z: v2f;
    c: v2f;
    iter: u32;
    b: u32;
};
struct TrajectoryBuffer {
    // buff: [[stride(4)]] array<u32>; // stride is the length of the element in array in bytes
    buff: array<TrajectoryPoint>;
};
[[group(0), binding(1)]]
var<storage, read_write> compute_buffer: TrajectoryBuffer;



struct Buf {
    buf: array<u32>;
};
[[group(0), binding(2)]]
var<storage, read_write> buf: Buf;


// / import ./src/rng.wgsl

/// import ./src/vertex.wgsl
/// import ./src/compute.wgsl