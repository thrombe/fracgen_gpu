
/// import ./src/main.wgsl
/// import ./src/vertex.wgsl
/// import ./src/rng.wgsl


let min_iterations = 0u;
let max_iterations = 1000u;
let ignore_n_starting_iterations = 0u;
let ignore_n_ending_iterations = 0u;
let mandlebrot_early_bailout = false;
let samples_per_pix = 10u;
let windowless_samples_per_pix = 50u; // screen will freeze until this is done. so be careful with this

let scale_factor = 0.01;
let look_offset = v2f(-0.74571890570893210, 0.11765642707064532);
// let look_offset = v2f(-0.25, 0.0);

let julia = false;
let j = v2f(-0.74571890570893210, -0.11624642707064532);
let e_to_ix = false;

// think before touching these!!
let max_iterations_per_frame = 256u;
// let max_iterations_per_frame = 512u;
// let max_iterations_per_frame = 1536u;

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

fn get_color(hits: u32) -> v3f {
    // var map_factor = log2(f32(max_iterations));
    // map_factor = map_factor*17.25;

    // let hits = sqrt(f32(hits)/map_factor);
    // let hits = log2(f32(hits)/map_factor);
    // let hits = f32(hits)/map_factor;

    // let hits = hits*(1.0+0.01*stuff.scroll);
    // return v3f(hits)*v3f(0.0, 1.0, 0.0);

    if (hits == 0u) {
        return v3f(0.0);
    }

    let map_factor = 69.0/f32(max_iterations) * PI/2.0;
    let hits = f32(hits)*map_factor*(1.0 + 0.0*stuff.scroll);
    var tmp: f32;
    tmp = cos(hits-PI*(0.5+0.1666666667));
    if (tmp < 0.0) {tmp = 0.0;}
    let r = tmp;

    tmp = cos(hits);
    if (tmp < 0.0) {tmp = 0.0;}
    let g = tmp;
    
    tmp = cos(hits+PI*(0.5+0.1666666667));
    if (tmp < 0.0) {tmp = 0.0;}
    let b = tmp;

    let col = v3f(r, g, b);
    return col*col;
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

fn random_z(id: u32, random_helper: u32) -> v2f {
    let r = v2f(
        hash_rng(id + (random_helper+1u)*bitcast<u32>(stuff.time + stuff.cursor_x)) - 0.5,
        hash_rng(id + (random_helper+1u)*bitcast<u32>(stuff.time*PHI + stuff.cursor_y)) - 0.5
        );
    
    return r; // -0.5 to 0.5
}

fn reset_ele_at(screen_coords: vec2<u32>, index: u32, random_helper: u32) {
    compute_buffer.buff[index].iter = 0u;
    compute_buffer.buff[index].b = samples_per_pix;
    compute_buffer.buff[index].c = get_pos(screen_coords) + random_z(index, random_helper)*(scale_factor/f32(stuff.render_height));
    compute_buffer.buff[index].z = compute_buffer.buff[index].c;
}

// returns if a is completed calculating
fn mandlebrot_iterations(screen_coords: vec2<u32>, index: u32) -> bool {
    var ele = compute_buffer.buff[index];
    var z = ele.z;
    let c = ele.c;
    var max_iterations_per_frame = max_iterations_per_frame;
    if (stuff.windowless == 1u) {
        max_iterations_per_frame = max_iterations;
    }

    if (ele.iter == 0u && mandlebrot_early_bailout && !julia && !e_to_ix) {
        let x = c.x - 0.25;
        let q = x*x + c.y*c.y;
        if (((q + x/2.0)*(q + x/2.0)-q/4.0 < 0.0) || (q - 0.0625 < 0.0)) {
            compute_buffer.buff[index].b = compute_buffer.buff[index].b - 1u;
            buf.buf[index] = 0u;
            return true;
        }
    }

    for (var i=0u; i<max_iterations_per_frame; i=i+1u) {
        z = f(z, c);
        ele.iter = ele.iter + 1u;
        if (escape_func(z)) {
            if (ele.iter > min_iterations && ele.iter < max_iterations) {
                buf.buf[index] = ele.iter;
                ele.b = ele.b - 1u;

                ele.z = z;
                compute_buffer.buff[index] = ele;
                return true;
            }
        }
        if (ele.iter > max_iterations) {
            compute_buffer.buff[index].b = compute_buffer.buff[index].b - 1u;
            buf.buf[index] = 0u;
            return true;
        }
    }

    ele.z = z;
    compute_buffer.buff[index] = ele;
    return false;
}

[[stage(fragment)]]
fn main_fragment([[builtin(position)]] pos: vec4<f32>) -> [[location(0)]] vec4<f32> {
    let render_to_display_ratio = f32(stuff.render_height)/f32(stuff.display_height);
    let i = vec2<u32>(u32(pos.x*render_to_display_ratio), u32(pos.y*render_to_display_ratio));
    if (i.x >= stuff.render_width) {return v4f(0.0);};
    let index = i.x + i.y*stuff.render_width;

    if (compute_buffer.buff[index].c.x == 0.0 && compute_buffer.buff[index].c.y == 0.0) {
        reset_ele_at(i, index, 0u);
    }

    if (stuff.windowless == 1u) {
        var c = v4f(0.0);
        for (var j=0u; j<windowless_samples_per_pix; j=j+1u) {
            if (mandlebrot_iterations(i, index)) {
                reset_ele_at(i, index, j);
                let col = v4f(get_color(buf.buf[index]), 1.0);
                c = c+col;
            }    
        }
        c = c/f32(windowless_samples_per_pix);
        textureStore(compute_texture, vec2<i32>(i32(i.x), i32(i.y)), c);
    } else if (compute_buffer.buff[index].b > 0u) {
        if (mandlebrot_iterations(i, index)) {
            let b = compute_buffer.buff[index].b;
            reset_ele_at(i, index, 0u);
            compute_buffer.buff[index].b = b;

            let col = v4f(get_color(buf.buf[index]), 1.0);
            let c2 = textureLoad(compute_texture, vec2<i32>(i32(i.x), i32(i.y)));
            textureStore(compute_texture, vec2<i32>(i32(i.x), i32(i.y)), c2+col);
            if (compute_buffer.buff[index].b == 0u) {
                var c = textureLoad(compute_texture, vec2<i32>(i32(i.x), i32(i.y)));
                c = c/f32(samples_per_pix);
                textureStore(compute_texture, vec2<i32>(i32(i.x), i32(i.y)), c);
            }
        }
    }

    // reset compute_buffer by pressing mouse middle click
    if (stuff.mouse_middle == 1u) {
        reset_ele_at(i, index, 0u);
    }

    var col = textureLoad(compute_texture, vec2<i32>(i32(i.x), i32(i.y))).xyz;
    return v4f(col, 1.0);
}
