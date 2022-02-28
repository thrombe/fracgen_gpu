
/// import ./src/rng.wgsl

let min_iterations = 100000000u;
let max_iterations = 1000000000u;
let ignore_n_iterations = 5000u;

let max_iterations_per_frame = 1024; // think before touching this!!

fn f(z: v2f, c: v2f) -> v2f {
    return v2f(z.x*z.x-z.y*z.y + c.x, 2.0*z.x*z.y + c.y);
}

fn escape_func(z: v2f) -> bool {
    return z.x*z.x + z.y*z.y > 4.0;
}

fn get_screen_pos(c: v2f) -> u32 {
    let factor = 2.0;
    let scale = 1080.0/factor;
    var index = vec2<i32>(i32((c.x+2.0+(0.25)*factor)*scale), i32((c.y+0.5*factor)*scale));
    if (index.x < 0 || index.x > 1920 || index.y < 0 || index.y > 1080) {
        return 0u;
    }
    return u32(index.x + index.y*1920);
}

fn get_color(hits: u32) -> v3f {
    var map_factor = log2(f32(max_iterations));
    map_factor = map_factor*15.25;

    let hits = sqrt(f32(hits)/map_factor);
    // let hits = log2(f32(hits)/map_factor);
    // let hits = f32(hits)/map_factor;

    var color = v3f(hits);
    let version = 0;
    let color_method_mod_off = v3f(15.0, 48.0, 63.0)/255.0;
    let color_vecs = array<v3f, 6>(
            v3f(0.0, 0.0, 0.0),
            v3f(200.0, 0.0, 200.0), // better visible in linear (1)
            v3f(180.0, 30.0, 190.0),
            v3f(140.0, 80.0, 190.0), // sqrt - (3)
            v3f(80.0, 160.0, 255.0), // log - (4)
            v3f(20.0, 235.0, 255.0),
            );

    if (version == 0) { // overflow version
        color.x = hits;
        if (hits > 0.99) {color.y = hits - 0.99;} else {color.y = 0.0;}
        if (hits > 1.99) {color.z = hits - 0.99;} else {color.z = 0.0;}
    } else if (version == 1) { // mod version
        color.x = f32(u32((hits + color_method_mod_off.x)*255.0)%255u)/255.0;
        color.y = f32((u32((hits + color_method_mod_off.y)*255.0)%511u)/2u)/255.0;
        color.z = f32((u32((hits + color_method_mod_off.z)*255.0)%1023u)/4u)/255.0;
    // } else if (version == 2) { // lerp version
    //     fn lerp_with_chop(a: v3f, b: v3f, t: f32) -> v3f {
    //         if (t > 1.0) {return a;}
    //         if (t < 0.0) {return b;}
    //         return (a*t + b*(1.0-t));
    //     }
    //     var t = hits/255.0;
    //     let intervals = arrayLength(color_vecs);
    //     t = t*f32(intervals);
    //     var index = u32(floor(t)); // gif
    //     if (index < 1u) {index = 1u;}
    //     if (index > intervals) {index = intervals;}
    //     color = lerp_with_chop(color_vecs[index], color_vecs[index - 1], floor(t)); // lerping
    //     // color = smoothStep(color_vecs[index], color_vecs[index - 1], floor(t)); // lerping
    }

    // return color;
    // return color.rbg;
    // return color.gbr;
    return color.brg;
}



fn random_z(id: u32) -> v2f { // does it really need id?
    return v2f(
        sin_rng(f32(id), stuff.time)*4.0 - 2.0,
        sin_rng(f32(id)*PHI, stuff.time*PI*0.1)*4.0 - 2.0
        );
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

    if (ele.iter == 0u) {
        let x = c.x - 0.25;
        let q = x*x + c.y*c.y;
        if (((q + x/2.0)*(q + x/2.0)-q/4.0 < 0.0) || (q - 0.0625 < 0.0)) {
            reset_ele_at(id);
            return;
        }
    }

    for (var i=0; i<max_iterations_per_frame; i=i+1) {
        z = f(z, c);
        if (escape_func(z)) {
            if (ele.iter > min_iterations || ele.iter < max_iterations) {
                if (false) {
                    let index = get_screen_pos(c);
                    buf1.buf[index] = 1u;
                    ele.iter = 0u;
                } else {
                    ele.iter = 0u;
                    ele.b = 1u;
                    z = c;
                }
                break;
            }
        }
        ele.iter = ele.iter + 1u;
    }

    if (ele.iter > max_iterations) {
        reset_ele_at(id);
    } else {
        ele.z = z;
        compute_buffer.buff[id] = ele;
    }
}

fn buddhabrot_iterations(id: u32) {
    var ele = compute_buffer.buff[id];
    var z = ele.z;
    let c = ele.c;

    for (var i=0; i<max_iterations_per_frame; i=i+1) {
        z = f(z, c);
        if (escape_func(z)) {
            reset_ele_at(id);
            return;
        } else {
            ele.iter = ele.iter + 1u;
            let index = get_screen_pos(z);
            if (index != 0u && ele.iter > ignore_n_iterations) {
                buf1.buf[index] = buf1.buf[index] + 1u; // maybe make this atomic
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
    let ele = compute_buffer.buff[id.x];

    // if (stuff.mouse_middle == 1u) {
    //     reset_ele_at(id.x);
    //     return;
    // }

    if (ele.b == 0u) {
        mandlebrot_iterations(id.x);
    } else {
        buddhabrot_iterations(id.x);
    }
}

[[stage(fragment)]]
fn main_fragment([[builtin(position)]] pos: vec4<f32>) -> [[location(0)]] vec4<f32> {
    let index = u32(pos.x) + u32(pos.y)*1920u;
    var col = buf1.buf[index];
    if (stuff.mouse_middle == 1u) { // reset board by pressing mouse middle click
        buf1.buf[index] = 0u;
        reset_ele_at(index);
    }

    var col = get_color(col);
    return v4f(col, 1.0); // gamma correction ruines stuff 
}