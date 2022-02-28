
fn get_index(x: i32, y: i32, dx: i32, dy: i32) -> u32 {
    let width = i32(stuff.width);
    var new_x = x;
    if (x >= width) {
        new_x = 0;
    } else if (x < 0) {
        new_x = width - 1;
    }
    let height = i32(stuff.height);
    var new_y = y;
    if (y >= height) {
        new_y = 0;
    } else if (y < 0) {
        new_y = height - 1;
    }

    let scale = 5;

    return u32(((new_y/scale)+dy)*1920 + ((new_x/scale)+dx));
}

fn get_cell_stat(x: i32, y: i32) -> u32 {
    var a = 0u;

    let o = 1;
    if (buf1.buf[get_index(x, y, -o, 0)] == 1u) {
        a = a + 1u;
    }
    if (buf1.buf[get_index(x, y, -o, o)] == 1u) {
        a = a + 1u;
    }
    if (buf1.buf[get_index(x, y, 0, o)] == 1u) {
        a = a + 1u;
    }
    if (buf1.buf[get_index(x, y, o, o)] == 1u) {
        a = a + 1u;
    }
    if (buf1.buf[get_index(x, y, o, 0)] == 1u) {
        a = a + 1u;
    }
    if (buf1.buf[get_index(x, y, o, -o)] == 1u) {
        a = a + 1u;
    }
    if (buf1.buf[get_index(x, y, 0, -o)] == 1u) {
        a = a + 1u;
    }
    if (buf1.buf[get_index(x, y, -o, -o)] == 1u) {
        a = a + 1u;
    }

    var state = buf1.buf[get_index(x, y, 0, 0)];
    if (a == 3u) {
        state = 1u;
    } else if (a == 2u) {} else {
        state = 0u;
    }

   
    return state;
}

fn get_cell_stat_from_mouse(x: i32, y: i32, ori_state: u32) -> u32 {
    var state = ori_state;
    if (stuff.mouse_right == 1u) {
        state = buf1.buf[get_index(x, y, 0, 0)];
    }

    if ((stuff.mouse_left == 1u) && (get_index(i32(stuff.cursor_x), i32(stuff.cursor_y), 0, 0) == get_index(x, y, 0, 0))) {
        state = 1u;
    }

    if (stuff.mouse_middle == 1u) {
        state = 0u;
    }

    return state;
}

[[stage(fragment)]]
fn main_fragment([[builtin(position)]] pos: vec4<f32>) -> [[location(0)]] vec4<f32> {
    let x = i32(pos.x);
    let y = i32(pos.y);
    let index = get_index(x, y, 0, 0);

    // buf2.buf[index] = get_cell_stat(x, y);
    // buf2.buf[index] = get_cell_stat_from_mouse(x, y, buf2.buf[index]);
    // buf1.buf[index] = get_cell_stat_from_mouse(x, y, buf1.buf[index]);

    return v4f(f32(buf2.buf[index]));
}


// 1080*1920/64 = 32400
/// work_group_count 32400
/// compute_enable

[[stage(compute), workgroup_size(64)]] // workgroup_size can take 3 arguments -> x*y*z executions (default x, 1, 1) // minimum opengl requirements are (1024, 1024, 64) but (x*y*z < 1024 (not too sure)) no info about wgsl rn
fn main_compute([[builtin(global_invocation_id)]] global_invocation_id: vec3<u32>) {
    if (global_invocation_id.x >= 1920u*1080u) {
        return;
    }

    let y = i32(global_invocation_id.x/1920u);
    let x = i32(global_invocation_id.x - u32(y)*1920u);

    let index = get_index(x, y, 0, 0);

    buf2.buf[index] = get_cell_stat(x, y);
    buf2.buf[index] = get_cell_stat_from_mouse(x, y, buf2.buf[index]);
    buf1.buf[index] = get_cell_stat_from_mouse(x, y, buf1.buf[index]);
}
