
/// import ./src/main.wgsl
/// import ./src/vertex.wgsl
/// import ./src/rng.wgsl


let min_iterations = 0u;
let max_iterations = 500u;
let ignore_n_starting_iterations = 0u;
let ignore_n_ending_iterations = 0u;
let mandlebrot_early_bailout = false;

let scale_factor = 2.0;
let look_offset = v2f(-0.25, 0.0);

let julia = false;
let j = v2f(-0.74571890570893210, -0.11624642707064532);
let e_to_ix = false;

// think before touching these!!
let max_iterations_per_frame = 56;
// let max_iterations_per_frame = 512;
// let max_iterations_per_frame = 1536;

fn f(z: v2f, c: v2f) -> v2f {
    var k = v2f(0.0);
    if (e_to_ix) {
        let p = -32.0;
        // convert to r*e^(i*theta)
        let r = sqrt(z.x*z.x+z.y*z.y);
        let t = atan2(z.y, z.x);
        // raise to pth power and convert back to x + i*y
        let r = pow(r, p);
        let t = p*t;
        k = v2f(r*cos(t), r*sin(t));
    } else {
        k = v2f(z.x*z.x-z.y*z.y, 2.0*z.x*z.y);
    }

    if (julia) {
        return k + j;
    } else {
        return k + c;
    }
}

fn escape_func(z: v2f) -> bool {
    return z.x*z.x + z.y*z.y > 4.0;
}

fn get_pos(render_coords: vec2<u32>) -> v2f {
    let scale = f32(stuff.render_height)/scale_factor;
    let curs = (
            v2f(f32(render_coords.x), f32(render_coords.y))
           -v2f(
                (f32(stuff.render_width))/2.0,
                f32(stuff.render_height)/2.0
            )
        )/scale + look_offset;
    return curs;
}

fn get_color(hits: u32) -> v3f {
   return v3f(f32(hits)/50.0);
}

fn reset_ele_at(screen_coords: vec2<u32>, index: u32) {
    compute_buffer.buff[index].iter = 0u;
    compute_buffer.buff[index].b = 0u;
    compute_buffer.buff[index].c = get_pos(screen_coords);
    compute_buffer.buff[index].z = compute_buffer.buff[index].c;
}

fn mandlebrot_iterations(screen_coords: vec2<u32>, index: u32) {
    var ele = compute_buffer.buff[index];
    var z = ele.z;
    let c = ele.c;

    if (ele.iter == 0u && mandlebrot_early_bailout && !julia && !e_to_ix) {
        let x = c.x - 0.25;
        let q = x*x + c.y*c.y;
        if (((q + x/2.0)*(q + x/2.0)-q/4.0 < 0.0) || (q - 0.0625 < 0.0)) {
            compute_buffer.buff[index].b = 1u;
            return;
        }
    }

    for (var i=0; i<max_iterations_per_frame; i=i+1) {
        z = f(z, c);
        ele.iter = ele.iter + 1u;
        if (escape_func(z)) {
            if (ele.iter > min_iterations && ele.iter < max_iterations) {
                buf.buf[index] = ele.iter;
                ele.b = 1u;
                break;
            }
        }
        if (ele.iter > max_iterations) {
            compute_buffer.buff[index].b = 1u;
            return;
        }
    }

    ele.z = z;
    compute_buffer.buff[index] = ele;
}

[[stage(fragment)]]
fn main_fragment([[builtin(position)]] pos: vec4<f32>) -> [[location(0)]] vec4<f32> {
    let render_to_display_ratio = f32(stuff.render_height)/f32(stuff.display_height);
    let i = vec2<u32>(u32(pos.x*render_to_display_ratio), u32(pos.y*render_to_display_ratio));
    let index = i.x + i.y*stuff.render_width;

    if (compute_buffer.buff[index].c.x == 0.0 && compute_buffer.buff[index].c.y == 0.0) {
        reset_ele_at(i, index);
    }

    if (compute_buffer.buff[index].b == 0u) {
        mandlebrot_iterations(i, index);
    }

    var col = buf.buf[index];

    // reset board by pressing mouse middle click
    if (stuff.mouse_middle == 1u) {
        reset_ele_at(i, index);
    }

    var col = get_color(col);
    return v4f(col, 1.0);
}