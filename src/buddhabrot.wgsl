
/// import ./src/main.wgsl
/// import ./src/vertex.wgsl
/// import ./src/rng.wgsl

struct TrajectoryPoint {
    z: v2f;
    c: v2f;
    iter: u32;
    b: u32;
};
struct TrajectoryBuffer {
    buff: array<TrajectoryPoint>;
};
[[group(0), binding(1)]]
var<storage, read_write> compute_buffer: TrajectoryBuffer;

struct Buf {
    buf: array<u32>;
};
[[group(0), binding(2)]]
var<storage, read_write> buf: Buf;


let min_iterations = 5000u;
let max_iterations = 100000u;
let ignore_n_starting_iterations = 5000u;
let ignore_n_ending_iterations = 0u;
let limit_new_points_to_cursor = false;
let mandlebrot_early_bailout = false;
let force_use_escape_func_b = false;

let mouse_sample_size = 2.0;
let mouse_sample_r_theta = true;
let scale_factor = 2.0;
let look_offset = v2f(-0.25, 0.0);

let anti = false; // !needs super low iteration count (both max_iteration and max_iter_per_frame)
let julia = false;
let j = v2f(-0.74571890570893210, -0.11624642707064532);
let e_to_ix = false;

// think before touching these!!
let chill_compute = false; // skip compute, just return
// let max_iterations_per_frame = 64;
let max_iterations_per_frame = 256;
// let max_iterations_per_frame = 512;
// let max_iterations_per_frame = 1536;

fn f(z: v2f, c: v2f) -> v2f {
    var k = v2f(0.0);
    if (e_to_ix) {
        let p = 3.0;
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

fn escape_func_m(z: v2f) -> bool {
    return z.x*z.x + z.y*z.y > 4.0;
}

fn escape_func_b(z: v2f) -> bool {
    return escape_func_m(z);
    // return z.x*z.x + z.y*z.y > 4.0;
}

fn get_color(hits: u32) -> v3f {
    var map_factor = log2(f32(max_iterations));
    map_factor = map_factor*17.25;

    let hits = sqrt(f32(hits)/map_factor);
    // let hits = log2(f32(hits)/map_factor);
    // let hits = f32(hits)/map_factor;

    let hits = hits*(1.0+0.001*stuff.scroll);

    let version = 0;
    let color_method_mod_off = v3f(0.0588, 0.188, 0.247);
    var color = v3f(hits);

    if (version == 0) { // overflow version
        color.x = hits;
        if (hits > 0.99) {color.y = hits - 0.99;} else {color.y = 0.0;}
        if (hits > 1.99) {color.z = hits - 0.99;} else {color.z = 0.0;}
    } else if (version == 1) { // mod version
        color.x = f32(u32((hits + color_method_mod_off.x)*255.0)%255u)/255.0;
        color.y = f32((u32((hits + color_method_mod_off.y)*255.0)%511u)/2u)/255.0;
        color.z = f32((u32((hits + color_method_mod_off.z)*255.0)%1023u)/4u)/255.0;
    } else if (version == 2) { // lerp version
        // why can't it be done with a vector + dynamic indexing?
        var t = hits;
        var intervals = 5;
        t = t*f32(intervals);
        var index = i32(floor(t));
        t = fract(t);
        let v0 = v3f(0.0, 0.0, 0.0); // background
        let v1 = v3f(0.5, 0.1, 0.3);
        let v2 = v3f(0.9, 0.3, 0.4);
        let v3 = v3f(0.4, 0.9, 0.8);
        let v4 = v3f(0.2, 0.4, 0.6);
        let v5 = v3f(0.2, 0.4, 0.2);
        let v6 = v3f(0.0, 0.0, 0.0);
        if (index <= 0) {
            color = v0;
        } else if (index == 1) {
            color = v2*t + (1.0-t)*v1;
        } else if (index == 2) {
            color = v3*t + (1.0-t)*v2;
        } else if (index == 3) {
            color = v4*t + (1.0-t)*v3;
        } else if (index == 4) {
            color = v5*t + (1.0-t)*v4;
        } else if (index == 5) {
            color = v6*t + (1.0-t)*v5;
        } else if (index > 5) {
            color = v6;
        }
        // if (t > 0.6) {return v3f(1.0);}
    }

    return color;
    // return color.rbg;
    // return color.gbr;
    // return color.brg;
}


fn get_screen_pos(c: v2f) -> vec2<i32> {
    let scale = f32(stuff.render_height)/scale_factor;
    var c = c - look_offset;
    c = c*scale + v2f(f32(stuff.render_width)/2.0, f32(stuff.render_height)/2.0);
    var index = vec2<i32>(i32(c.x), i32(c.y));
    if (index.x < 0 || index.x >= i32(stuff.render_width) || index.y < 0 || index.y >= i32(stuff.render_height)) {
        return vec2<i32>(0);
    }
    return index;
}

fn get_screen_index(c: v2f) -> u32 {
    let i = get_screen_pos(c);
    return u32(i.x + i.y*i32(stuff.render_width));
}

fn random_z(id: u32) -> v2f {
    var r = v2f(
        hash_rng(id + bitcast<u32>(stuff.time + stuff.cursor_x)),
        hash_rng(id + bitcast<u32>(stuff.time*PHI + stuff.cursor_y)),
    );
    if (mouse_sample_r_theta) {
        r = v2f(mouse_sample_size*r.x*0.5, r.y*2.0*PI);
        r = r.x*v2f(cos(r.y), sin(r.y));
    } else {
        r = r - 0.5;
        r = r*mouse_sample_size;
    }
    if (stuff.mouse_left == 1u) {
        // get this by inverting the get_screen_pos func
        let scale = f32(stuff.display_height)/scale_factor;
        let curs = (v2f(stuff.cursor_x, stuff.cursor_y) - v2f((f32(stuff.render_width*stuff.display_height)/f32(stuff.render_height))/2.0, f32(stuff.display_height)/2.0))/scale + look_offset;
        return curs + 0.09*r;
    }
    
    // both should be in range -2 to 2
    return r*4.0;
}

fn reset_ele_at(id: u32) {
    compute_buffer.buff[id].iter = 0u;
    compute_buffer.buff[id].b = 0u;
    compute_buffer.buff[id].c = random_z(id);
    compute_buffer.buff[id].z = compute_buffer.buff[id].c;
}

fn mandlebrot_iterations(id: u32) {
    var ele = compute_buffer.buff[id];
    var z = ele.z;
    let c = ele.c;

    if (ele.iter == 0u && mandlebrot_early_bailout && !julia && !e_to_ix) {
        let x = c.x - 0.25;
        let q = x*x + c.y*c.y;
        if (((q + x/2.0)*(q + x/2.0)-q/4.0 < 0.0) || (q - 0.0625 < 0.0)) {
            if (anti) {
                ele.iter = 0u;
                ele.b = max_iterations+1u;
                compute_buffer.buff[id] = ele;
            } else {
                reset_ele_at(id);
            }
            return;
        }
    }

    for (var i=0; i<max_iterations_per_frame; i=i+1) {
        z = f(z, c);
        ele.iter = ele.iter + 1u;
        if (escape_func_m(z)) {
            if (anti) {
                reset_ele_at(id);
                return;
            }
            if (ele.iter > min_iterations && ele.iter < max_iterations) {
                ele.b = ele.iter+1u;
                ele.iter = 0u;

                ele.z = c;
                compute_buffer.buff[id] = ele;
                return;
            }
        }
        if (ele.iter > max_iterations) {
            if (anti) {
                ele.b = ele.iter+1u;
                ele.iter = 0u;
                ele.z = c;
                compute_buffer.buff[id] = ele;
            } else {
                reset_ele_at(id);
            }
            return;
        }
    }

    ele.z = z;
    compute_buffer.buff[id] = ele;
}

fn buddhabrot_iterations(id: u32) {
    var ele = compute_buffer.buff[id];
    var z = ele.z;
    let c = ele.c;

    for (var i=0; i<max_iterations_per_frame; i=i+1) {
        z = f(z, c);
        ele.b = ele.b - 1u;
        if (
            (force_use_escape_func_b && escape_func_b(z)) ||
            (!force_use_escape_func_b && ele.b == 0u) ||
            ele.iter > max_iterations - ignore_n_ending_iterations) {
            reset_ele_at(id);
            return;
        } else {
            ele.iter = ele.iter + 1u;
            let index = get_screen_index(z);
            if (index != 0u && ele.iter > ignore_n_starting_iterations) {
                buf.buf[index] = buf.buf[index] + 1u; // maybe make this atomic
            }
        }
    }

    ele.z = z;
    compute_buffer.buff[id] = ele;
}


// 1080*1920/64 = 32400
/// work_group_count 6000
/// compute_enable
[[stage(compute), workgroup_size(64)]] // workgroup_size can take 3 arguments -> x*y*z executions (default x, 1, 1) // minimum opengl requirements are (1024, 1024, 64) but (x*y*z < 1024 (not too sure)) no info about wgsl rn
fn main_compute([[builtin(global_invocation_id)]] id: vec3<u32>) { // global_invocation_id = local_invocation_id*work_group_id
    if (chill_compute) {return;}
    if (stuff.windowless == 1u) {return;}
    if (limit_new_points_to_cursor && stuff.mouse_left != 1u) {return;}
    let ele = compute_buffer.buff[id.x];

    if (ele.b == 0u) {
        mandlebrot_iterations(id.x);
    } else {
        buddhabrot_iterations(id.x);
    }
}

[[stage(fragment)]]
fn main_fragment([[builtin(position)]] pos: vec4<f32>) -> [[location(0)]] vec4<f32> {
    let render_to_display_ratio = f32(stuff.render_height)/f32(stuff.display_height);
    let i = vec2<u32>(u32(pos.x*render_to_display_ratio), u32(pos.y*render_to_display_ratio));
    if (i.x >= stuff.render_width) {return v4f(0.0);};
    let index = i.x + i.y*stuff.render_width;
    var col = buf.buf[index];

    let compute_buffer_size = 1920u*1080u;

    // reset active trajectories by pressing mouse middle click
    if (stuff.mouse_middle == 1u && index < compute_buffer_size) {
        // buf.buf[index] = 0u;
        reset_ele_at(index);
    }

    // show trajectory buffer
    let i2 = u32(pos.x)+u32(pos.y)*stuff.display_width;
    if (stuff.mouse_right == 1u && i2 < compute_buffer_size && compute_buffer.buff[i2].iter > min_iterations) {
        return v4f(0.8);
    }

    // color selected pixel
    if (stuff.mouse_left == 1u) {
        let j = random_z(index);
        let i = get_screen_index(j);
        if (i == index) {
            return v4f(1.0);
        }
    }

    var col = get_color(col);
    return v4f(col, 1.0);
}
