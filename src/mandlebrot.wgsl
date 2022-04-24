
/// import ./src/main.wgsl
/// import ./src/vertex.wgsl
/// import ./src/rng.wgsl

struct TrajectoryPoint {
    z: v2f;
    c: v2f;
    dz: v2f;
    iter: u32;
    samples: u32;
    orbit_trap_dist: f32;
    place_holder: u32; // struct size increases by multiples of 64bits for some reason?
};
struct TrajectoryBuffer {
    buff: array<TrajectoryPoint>;
};
[[group(0), binding(1)]]
var<storage, read_write> compute_buffer: TrajectoryBuffer;

struct Buf {
    buf: array<f32>;
};
[[group(0), binding(2)]]
var<storage, read_write> buf: Buf;

[[group(0), binding(3)]]
var compute_texture: texture_storage_2d<rgba32float, read_write>;


// helper functions

fn conplex_div(a: v2f, b: v2f) -> v2f {
    let d = dot(b,b);
    return v2f( dot(a,b), a.y*b.x - a.x*b.y ) / d;
}

fn complex_mul(a: v2f, b: v2f) -> v2f {
    return v2f( a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x );
}

fn sdf_point(z: v2f) -> f32 {
    let z = z - v2f(10.0, 2.0);
    return sqrt(dot(z, z));
}

fn sdf_line(z: v2f) -> f32 {
    let z = v2f(min(z.x, 10.0), z.y - 0.5);
    let z = z - v2f(10.0+stuff.scroll, 2.0);
    return sqrt(dot(z, z)) - 0.1;
}

fn sdf_ninja_star(z: v2f) -> f32 {
    let z = z - v2f(4.0);
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
    return smoothStep(1.0*e, 2.0*e, de);
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




let min_iterations = 0u;
let max_iterations = 1000u;
let ignore_n_starting_iterations = 0u;
let ignore_n_ending_iterations = 0u;
let bailout_val = 1000.0;
let samples_per_pix = 10u;
let smooth_coloring = true; // depends on the equation. dont use for random equations
let orbit_trap = true;
let distance_estimated = false; // needs distance_estimated_max_iterations < 257 for f32. otherwise it has a lot of noise
let distance_estimated_max_iterations = 256u;

let scale_factor = 0.01; let look_offset = v2f(-0.74571890570893210, 0.11765642707064532);
// let scale_factor = 2.0; let look_offset = v2f(-0.25, 0.0);

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
        // k = v2f(z.x*z.x+z.y*z.y, 2.0*z.x*z.y); // gives square
        // k = v2f(z.x*z.x+z.y*z.y, -2.0*z.x*z.y); // gives bullet/droplet
    }

    if (julia) {
        return k + j;
    } else {
        return k + c;
    }
}

fn df(z: v2f, c: v2f) -> v2f {
    let e = v2f(0.001,0.0);
    // return complex_div( f(z,c) - f(z+e,c), e );
    return 0.5*(f(z+e, c) - f(z-e, c))/e.x;
}

fn escape_func(z: v2f) -> bool {
    return z.x*z.x + z.y*z.y > bailout_val*bailout_val;
}

fn get_color(hits: f32) -> v3f {

    if (distance_estimated) {
        var c = hits;
        c = sqrt( clamp( (150.0/pow(0.1, 1.0 + stuff.scroll*0.01))*c, 0.0, 1.0 ) );
        // c = c*100.0;
        let col = v3f(c);
        return col;
    } else {
        // var map_factor = log2(f32(max_iterations));
        // map_factor = map_factor*17.25;

        // let hits = sqrt(f32(hits)/map_factor);
        // let hits = log2(f32(hits)/map_factor);
        // let hits = f32(hits)/map_factor;

        // let hits = hits*(1.0+0.01*stuff.scroll);
        // return v3f(hits)*v3f(0.0, 1.0, 0.0);

        if (hits == 0.0) {
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

        var col = v3f(r, g, b);
        // col = col.rrr;
        return col;
    }
}

fn combine_orbit_trap_and_iter_count(orbit_trap_dist: f32, iter_count: f32, inside_mbrot: bool) -> f32 {
    let c = iter_count;
    var d = orbit_trap_dist;
    var e = 0.0;
    if (inside_mbrot) {
        // d = abs(d);
        e = d;
    } else {
        // d = abs(d);
        // e = smoothStep(c, d, stuff.scroll*0.01);
        // e = d;
        // e = c;
        e = min(d, c);
        // e = c*d*0.0001*(stuff.scroll + 50.0);
    }
    return e;
}

fn choose_orbit_trap_val(orbit_trap_dist: f32, z: v2f) -> f32 {
    var c = orbit_trap_dist;

    var d = 0.0;
    // d = sdf_point(z);
    // d = sdf_line(z);
    // d = min(sdf_point(z), sdf_line(z));
    d = sdf_ninja_star(z)*200.0;
    // d = sdf_ninja_star_non_smooth(z);
    // d = sdf_sin(z)*400.0;

    var e = 0.0;
    e = min(c, d);
    // e = max(c, d);
    return e;
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
    compute_buffer.buff[index].samples = samples_per_pix;
    compute_buffer.buff[index].c = get_pos(screen_coords) + random_z(index, random_helper)*(scale_factor/f32(stuff.render_height));
    compute_buffer.buff[index].z = compute_buffer.buff[index].c;
    compute_buffer.buff[index].dz = v2f(1.0);
    compute_buffer.buff[index].orbit_trap_dist = 1e30;
}

// returns if a is completed calculating
fn mandlebrot_iterations(screen_coords: vec2<u32>, index: u32) -> bool {
    var ele = compute_buffer.buff[index];
    var z = ele.z;
    let c = ele.c;
    var dz = ele.dz;
    var max_iterations_per_frame = max_iterations_per_frame;
    var max_iterations = max_iterations;
    if (distance_estimated) {
        max_iterations = distance_estimated_max_iterations;
    }

    for (var i=0u; i<max_iterations_per_frame; i=i+1u) {
        dz = complex_mul(dz, df(z, c));
        z = f(z, c);
        ele.iter = ele.iter + 1u;
        if (escape_func(z)) {
            if (ele.iter > min_iterations && ele.iter < max_iterations) {
                if (distance_estimated) {
                    let lzsq = z.x*z.x + z.y*z.y;
                    let ldzsq = dz.x*dz.x + dz.y*dz.y;
                    buf.buf[index] = sqrt(lzsq/ldzsq)*log(lzsq)*0.5;
                } else if (smooth_coloring) {
                    // smooth coloring
                    // consider Z^d + c. when Zn is big, Zn+1 ~= Zn^d (as a consequence, we need big bailout_values ~~50 or 100)
                    // consider a Zn such that it lands just before the bailout_val on x axis
                    // then Zn+1 is somewhere near bailout_val^d. so we map this extra space (bailout_val to bailout_val^d) from 0 to 1
                    // Zn is kind of like C^(d^n)
                    // let B == bailout_val, n == iter_count
                    // B <= |Zn| < B^d
                    // lnB <= d^n lnC < d lnB
                    // 1 <= d^n lnC/lnB < d
                    // 0 <= n lnd/lnB + lnC/lnB < lnd
                    // 0 <= n/lnB + lnC/(lnB lnd) < 1
                    // n >= n - ... > n-1
                    // n - ln(ln|Zn|)/ln(B))/ln(d)
                    // we mapped Zn to n-1 to n.
                    // n-1 when Zn-1 was just smaller than B (i.e. Zn ~= B^d)
                    // n when Zn was just greater than B
                    // note: n - (ln|Zn|/ln(B) - 1)/(d-1) also works, but here, there is a term d^n, which is still exponential in n. hence another log
                    buf.buf[index] = f32(ele.iter) - log(log(sqrt(z.x*z.x+z.y*z.y))/log(bailout_val))/log(2.0);
                    // buf.buf[index] = f32(ele.iter) - (log(sqrt(z.x*z.x+z.y*z.y))/log(bailout_val) - 1.0)/(2.0 - 1.0);
                } else {
                    buf.buf[index] =  f32(ele.iter);
                }

                if (orbit_trap) {
                    buf.buf[index] = combine_orbit_trap_and_iter_count(ele.orbit_trap_dist, buf.buf[index], false);
                }

                ele.samples = ele.samples - 1u;

                ele.z = z;
                compute_buffer.buff[index] = ele;
                return true;
            }
        }
        if (orbit_trap) {
            ele.orbit_trap_dist = choose_orbit_trap_val(ele.orbit_trap_dist, z);
        }
        if (ele.iter > max_iterations) {
            compute_buffer.buff[index].samples = compute_buffer.buff[index].samples - 1u;
            buf.buf[index] = 0.0;
            if (orbit_trap) {
                buf.buf[index] = combine_orbit_trap_and_iter_count(ele.orbit_trap_dist, buf.buf[index], true);
            }
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

    // we need a texture for anti aliasing (collecting color from multiple locations and averaging them)
    if (compute_buffer.buff[index].samples > 0u) {
        if (mandlebrot_iterations(i, index)) {
            let samples = compute_buffer.buff[index].samples;
            reset_ele_at(i, index, 0u);
            compute_buffer.buff[index].samples = samples;

            let col = v4f(get_color(buf.buf[index]), 1.0);
            var c2 = textureLoad(compute_texture, vec2<i32>(i32(i.x), i32(i.y)));
            let samples = f32(samples_per_pix-samples);
            c2 = c2*(samples - 1.0);
            c2 = c2+col;
            c2 = c2/(samples);
            textureStore(compute_texture, vec2<i32>(i32(i.x), i32(i.y)), c2);
            if (compute_buffer.buff[index].samples == 0u) {
                var c = textureLoad(compute_texture, vec2<i32>(i32(i.x), i32(i.y)));
                textureStore(compute_texture, vec2<i32>(i32(i.x), i32(i.y)), c);
            }
        }
    }

    // reset compute_buffer by pressing mouse middle click
    if (stuff.mouse_middle == 1u) {
        reset_ele_at(i, index, 0u);
    }

    var col = textureLoad(compute_texture, vec2<i32>(i32(i.x), i32(i.y))).xyz;
    // gpu or whatever does color correction when showing on screen. so doing reverse of that as the values do not need to be color corrected
    col = v3f(pow(col.r, 2.2), pow(col.g, 2.2), pow(col.b, 2.2));
    return v4f(col, 1.0);
}
