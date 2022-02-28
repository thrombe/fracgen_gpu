
/// import ./src/rng.wgsl


fn f(z: v2f, c: v2f) -> v2f {
    return v2f(z.x*z.x-z.y*z.y + c.x, 2.0*z.x*z.y + c.y);
}

fn escape_func(z: v2f) -> bool {
    return z.x*z.x + z.y*z.y > 4.0;
}

fn random_z(id: u32) -> v2f { // does it really need id?
    return v2f(
        sin_rng(f32(id), stuff.time)*4.0 - 2.0,
        sin_rng(f32(id)*PHI, stuff.time*PI*0.1)*4.0 - 2.0
        );
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

fn reset_ele_at(id: u32) {
    compute_buffer.buff[id].iter = 0;
    compute_buffer.buff[id].c = random_z(id);
    compute_buffer.buff[id].z = compute_buffer.buff[id].c;
}

fn mandlebrot_iterations(id: u32) {
    var ele = compute_buffer.buff[id];
    var z = ele.z;
    let c = ele.c;

    if (ele.iter == 0) {
        let x = c.x - 0.25;
        let q = x*x + c.y*c.y;
        if (((q + x/2.0)*(q + x/2.0)-q/4.0 < 0.0) || (q - 0.0625 < 0.0)) {
            reset_ele_at(id);
            return;
        }
    }

    let min_iterations = 50;
    let max_iterations = 10000;

    for (var i=0; i<256; i=i+1) {
        z = f(z, c);
        if (escape_func(z)) {
            if (ele.iter > min_iterations || ele.iter < max_iterations) {
                if (false) {
                    let index = get_screen_pos(c);
                    buf1.buf[index] = 1u;
                    ele.iter = 0;
                } else {
                    ele.iter = -1;
                    z = c;
                }

                break;
            }
        }
        ele.iter = ele.iter + 1;
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

    for (var i=0; i<256; i=i+1) {
        z = f(z, c);

        if (escape_func(z)) {
            reset_ele_at(id);
            return;
        } else {
            // add point to buffer
            let index = get_screen_pos(z);
            if (index != 0u) {
                buf1.buf[index] = buf1.buf[index] + 1u;
                // buf1.buf[index] = 1u;
            }
        }
        
    }

    ele.z = z;
    compute_buffer.buff[id] = ele;
}


// 1080*1920/64 = 32400
/// work_group_count 40 32 400
/// compute_enable
[[stage(compute), workgroup_size(64)]] // workgroup_size can take 3 arguments -> x*y*z executions (default x, 1, 1) // minimum opengl requirements are (1024, 1024, 64) but (x*y*z < 1024 (not too sure)) no info about wgsl rn
fn main_compute([[builtin(global_invocation_id)]] id: vec3<u32>) { // global_invocation_id = local_invocation_id*work_group_id
    let ele = compute_buffer.buff[id.x];

    if (ele.iter >= 0) {
        mandlebrot_iterations(id.x);
    } else {
        buddhabrot_iterations(id.x);
    }

    // let c = random_z(global_invocation_id.x);
    // var z = v2f(c);
    // for (var i=0; i<256; i=i+1) {
    //     z = f(z, c);
    //     if (escape_func(z)) {
    //         return;
    //     }
    //     let index = 1080u*u32(round(z.y)) + u32(round(z.x));
    // }
}

[[stage(fragment)]]
fn main_fragment([[builtin(position)]] pos: vec4<f32>) -> [[location(0)]] vec4<f32> {
    // var col = atomicLoad(&compute_buffer.buff[u32(pos.x + pos.y*1080.0)]);
    // var col = compute_buffer.buff[u32(pos.x + pos.y*1080.0)];

    var col = buf1.buf[u32(pos.x) + u32(pos.y)*1920u];
    if (stuff.mouse_middle == 1u) {
        buf1.buf[u32(pos.x) + u32(pos.y)*1920u] = 0u;
    }


    // if (col == 0u) {
    //     // compute_buffer.buff[u32(pos.x + pos.y*1080.0)] = 1u;
    //     // return v4f(1.0);
    //     let v = buf1.buf[u32(pos.x) + u32(pos.y)*1920u];
    //    // buf1.buf[u32(pos.x) + u32(pos.y)*1920u] = 0u;
    //     return v4f(f32(v));
    // }
    var col = v3f(f32(col)/69.0);
    return v4f(sign(col)*col*col, 1.0)*v4f(0.0, 1.0, 0.0, 1.0); // gamma correction ruines stuff 
}