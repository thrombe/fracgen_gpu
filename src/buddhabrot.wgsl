
/// import ./src/main.wgsl
/// import ./src/vertex.wgsl
/// import ./src/rng.wgsl

fn conplex_div(a: v2f, b: v2f) -> v2f {
    let d = dot(b,b);
    return v2f( dot(a,b), a.y*b.x - a.x*b.y ) / d;
}

fn complex_mul(a: v2f, b: v2f) -> v2f {
    return v2f( a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x);
}

fn sdf_point(_z: v2f) -> f32 {
    let z = _z - v2f(0.0, 0.0);
    return sqrt(dot(z, z));
}

fn sdf_line(z: v2f, len: f32) -> f32 {
    let p1 = v2f(len, 0.0);
    let p2 = v2f(-len, 0.0);
    let dir = normalize(p2 - p1);
    
    let h = min(1.0, max(0.0, dot(dir, z - p1)/length(p1-p2))); //from 0.0 to 1.0 wich point is closer p1 or p2
    let d = length((z-p1)-h*(p2-p1));
    return d;
}

fn sdf_ninja_star(_z: v2f) -> f32 {
    let z = _z - v2f(4.0);
    let r = sqrt(length(z));
    let a = atan2(z.y, z.x);
    return r - 1.0 + sin(3.0*a+2.0*r*r)/2.0;
}

fn sdf_ninja_star_non_smooth(z: v2f) -> f32 {
    let h = v2f(0.001, 0.0);
    let d = sdf_ninja_star(z);
    let grad = v2f(
        sdf_ninja_star(z+h) - sdf_ninja_star(z-h),
        sdf_ninja_star(z+h.yx) - sdf_ninja_star(z-h.yx),
    )/(2.0*h.x);
    let de = abs(d)/length(grad);
    let e = 0.2;
    return smoothstep(1.0*e, 2.0*e, de);
}

fn sdf_sin(z: v2f) -> f32 {
    var s = 0.0;
    if (abs(z.y) < 5.0) {
        s = abs(sin(z.x - 200.0));
    } else {
        s = 1.0;
    }
    return s;
}

struct TrajectoryPoint {
    z: v2f,
    c: v2f,
    iter: u32,
    b: u32,
};
struct TrajectoryBuffer {
    buff: array<TrajectoryPoint>,
};
@group(0) @binding(1)
var<storage, read_write> compute_buffer: TrajectoryBuffer;

struct Buf {
    buf: array<u32>,
};
@group(0) @binding(2)
var<storage, read_write> buf: Buf;

@group(0) @binding(3)
var compute_texture: texture_storage_2d<rgba32float, read_write>;

const bg_frac_bright = 2.0;
const scroll_multiplier = 0.01;

// /// work_group_count 15000
// const min_iterations = 500u;
// const max_iterations = 10000u;
// const ignore_n_starting_iterations = 500u;

/// work_group_count 60000
const min_iterations = 0u;
const max_iterations = 30u;
const ignore_n_starting_iterations = 0u;

// const limit_new_points_to_cursor = false;
const limit_new_points_to_cursor = true;

const ignore_n_ending_iterations = 0u;
const mandlebrot_early_bailout = false;
const force_use_escape_func_b = false;

const mouse_sample_size = 2.0;
const mouse_sample_r_theta = true;

// const e_to_ix = false;
const e_to_ix = true;
const e_to_ix_pow = -2.0;
const scale_factor = 3.0;
const look_offset = v2f(-0.25, 0.0);

const anti = false; // !needs super low iteration count (both max_iteration and max_iter_per_frame)
const julia = false;
const j = v2f(-0.74571890570893210, -0.11624642707064532);

// think before touching these!!
const chill_compute = false; // skip compute, just return
// const max_iterations_per_frame = 64;
// const max_iterations_per_frame = 256;
// const max_iterations_per_frame = 512;
const max_iterations_per_frame = 1536;

fn mouse_radius_map(_r: f32) -> f32 {
    var r = _r;
    // r = sqrt(r);
    // r = pow(r*1.0, -1.0);
    r = pow((-r + 1.0), -0.1) - 1.0;
    r = sqrt(r);

    r = mouse_sample_size*r*0.5;
    return r;
}

fn f(z: v2f, c: v2f) -> v2f {
    var k = v2f(0.0);
    if (e_to_ix) {
        let p = e_to_ix_pow;
        // convert to r*e^(i*theta)
        var r = sqrt(z.x*z.x+z.y*z.y);
        var t = atan2(z.y, z.x);
        // raise to pth power and convert back to x + i*y
        r = pow(r, p);
        t = p*t;
        k = v2f(r*cos(t), r*sin(t));
    } else {
        k = v2f(z.x*z.x-z.y*z.y, 2.0*z.x*z.y);
        // k = v2f(z.x*z.x+z.y*z.y, 2.0*z.x*z.y); // gives square
        // k = v2f(z.x*z.x+z.y*z.y, -2.0*z.x*z.y); // gives bullet/droplet
    }

    if (julia) {
        return k + j;
    } else {
        return k + c;
    }
}

fn sdf(_z: v2f) -> f32 {
    var z = _z;
    // z = z.yx;
    z = z * 10.1;
    // z = z + v2f(0.0, 10.0);
    // z = z * v2f(0.1, 1.0);

    var d = 0.0;
    d = sdf_point(z);
    d += - 1.0;
    d = pow(d, 2.0);
    var e = min(sdf_line(z.yx, 5.0), sdf_line(z, 5.0)) - 0.01;
    e = pow(e, 1.5);
    e = abs(e);
    d = min(d, e) - 0.1;
    var s = sdf_ninja_star(z + 4.0 + v2f(0.0, 5.0)) - 0.01;
    d = min(s, d);

    // d = sdf_line(z);
    // d = min(sdf_point(z), sdf_line(z));
    // d = sdf_ninja_star(z);
    // d = sdf_ninja_star_non_smooth(z);
    // d = sdf_sin(z);

    d = d * 10.1;
    d = 1.0/d;

    return d;
}

fn escape_func_m(z: v2f) -> bool {
    // return z.x*z.x + z.y*z.y > 4.0;
    // return 0.02/z.x + z.y*z.y > 4.0; // make wierd root things
    // return 1.0/z.x - z.y*z.y > 4.0; // turns the background black
    // return 0.01/z.x - z.y*z.y > 4.0; // root things go smaller
    // return 0.01/(z.x * z.y) > 4.0;
    return sdf(z) > 4.0;
}

// OOF: why is this here again??
fn escape_func_b(z: v2f) -> bool {
    // return escape_func_m(z);
    return z.x*z.x + z.y*z.y > 4.0;
    // return 0.2/z.x + z.y*z.y > 4.0; // make wierd root things
    // return 1.0/z.x - z.y*z.y > 4.0; // turns the background black
    // return 0.2/z.x - z.x*z.x > 4.0; // root things go smaller
}

fn map_hit_count(_hits: f32) -> f32 {
    var hits = f32(_hits);
    var map_factor = log2(f32(max_iterations));
    map_factor = map_factor*17.25;

    hits = pow(hits, 0.45);

    hits = pow(hits/map_factor, 0.7);
    // hits = sqrt(hits/map_factor);
    // hits = log2(hits/map_factor);
    // hits = hits/map_factor;

    hits = hits*(1.0+scroll_multiplier*stuff.scroll);
    return hits;
}

fn get_color(_hits: u32) -> v3f {
    let hits = map_hit_count(f32(_hits));

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


fn get_screen_pos(c_: v2f) -> vec2<i32> {
    let scale = f32(stuff.render_height)/scale_factor;
    var c = c_ - look_offset;
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
        r = v2f(r.x, r.y*2.0*PI);
        r.x = mouse_radius_map(r.x);
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
    // compute_buffer.buff[id].z = random_z(u32(random_z(id).x));
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
            // let index = get_screen_index(v2f(z.x, c.x)); // https://superliminal.com/fractals/bgram/ZrZiOut.htm
            if (index != 0u && ele.iter > ignore_n_starting_iterations) {
                buf.buf[index] = buf.buf[index] + 1u; // maybe make this atomic
                // !
                // let i = get_screen_pos(z);
                // var c2 = textureLoad(compute_texture, i);
                // textureStore(compute_texture, i, c2);
            }
        }
    }

    ele.z = z;
    compute_buffer.buff[id] = ele;
}


// 1080*1920/64 = 32400
// work_group_count 6000
// work_group_count 15000
/// compute_enable
@compute @workgroup_size(64) // workgroup_size can take 3 arguments -> x*y*z executions (default x, 1, 1) // minimum opengl requirements are (1024, 1024, 64) but (x*y*z < 1024 (not too sure)) no info about wgsl rn
fn main_compute(@builtin(global_invocation_id) id: vec3<u32>) { // global_invocation_id = local_invocation_id*work_group_id
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


fn simple_mandlebrot(_c: v2f) -> v3f {
    var c = _c;
    var z = c;

    // early bailout
    // let x = c.x - 0.25;
    // let q = x*x + c.y*c.y;
    // if (((q + x/2.0)*(q + x/2.0)-q/4.0 < 0.0) || (q - 0.0625 < 0.0)) {
    //     return v3f(0.0);
    // }

    let max_iter = 40;
    var iter = 0;
    for (var i=0; i<max_iter; i=i+1) {
        z = f(z, c);
        iter = iter + 1;
        if (z.x*z.x + z.y*z.y > 4.0) {
            return v3f(f32(iter) * bg_frac_bright/3000.0);
        }
    }

    return v3f(0.0);
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

@fragment
fn main_fragment(@builtin(position) pos: vec4<f32>) -> @location(0) vec4<f32> {
    let render_to_display_ratio = f32(stuff.render_height)/f32(stuff.display_height);
    let i = vec2<u32>(u32(pos.x*render_to_display_ratio), u32(pos.y*render_to_display_ratio));
    if (i.x >= stuff.render_width) {return v4f(0.0);};
    let index = i.x + i.y*stuff.render_width;
    var col = buf.buf[index];

    let compute_buffer_size = 2560u*1600u;

    if (stuff.mouse_right == 1u && index < compute_buffer_size) {
        buf.buf[index] = 0u;
        // reset active trajectories by pressing mouse middle click
        // reset_ele_at(index);
    }

    // show trajectory buffer
    let i2 = u32(pos.x)+u32(pos.y)*stuff.display_width;
    if (stuff.mouse_middle == 1u && i2 < compute_buffer_size && compute_buffer.buff[i2].iter > min_iterations) {
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

    var col1 = simple_mandlebrot(get_pos(i));
    col1 += get_color(col);
    return v4f(col1, 1.0);
}
