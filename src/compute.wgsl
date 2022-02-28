
// 1080*1920/64 = 32400
/// work_group_count 32400
/// compute_enable


[[stage(compute), workgroup_size(64)]] // workgroup_size can take 3 arguments -> x*y*z executions (default x, 1, 1) // minimum opengl requirements are (1024, 1024, 64) but (x*y*z < 1024 (not too sure)) no info about wgsl rn
fn main_compute([[builtin(global_invocation_id)]] global_invocation_id: vec3<u32>) {
    ! idk dont run this without thinking
    // var temp: array<u32, 2073600>;
    // let max_index = u32(2073600 - 1);
    var temp: array<u32, 2073>;
    let max_index = u32(207 - 1);
    let cx = sin_rng(f32(global_invocation_id.x), stuff.time)*2.0;
    let cy = sin_rng(f32(global_invocation_id.x)*PHI, stuff.time*PI*0.1)*2.0;
    var x = cx;
    var y = cy;
    for (var i=0; i<10; i=i+1) {
        let ex = x;
        x = x*x-y*y + cx;
        y = 2.0*ex*y + cy;
        if (x*x+y*y > 4.0) {
            return;
        }
        let index = u32(1080)*u32(round(y)) + u32(round(x));
        if (index > max_index) {continue;}
        temp[index] = temp[index] + 1u;
    }

    // for (var i=0u; i<=max_index; i=i+1u) {
    //     if (temp[i] == 0u) {continue;}
    //     atomicStore(&compute_buffer.buff[i], temp[i]);
    // }
    // atomicStore(&compute_buffer.buff[index], u32(0));
    // compute_buffer.buff[index] = u32(0);
}

[[stage(fragment)]]
fn main([[builtin(position)]] pos: vec4<f32>) -> [[location(0)]] vec4<f32> {
    var col = atomicLoad(&compute_buffer.buff[u32(pos.x + pos.y*1080.0)]);
    // var col = compute_buffer.buff[u32(pos.x + pos.y*1080.0)];
    var col = v3f(f32(col));
    return vec4<f32>(sign(col)*col*col, 1.0); // gamma correction ruines stuff
}