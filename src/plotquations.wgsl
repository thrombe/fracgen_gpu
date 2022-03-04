
/// import ./src/main.wgsl
/// import ./src/vertex.wgsl


fn line_segment(p: v2f, a: v2f, b: v2f) -> f32 {
    return pow(pow(p.x-a.x, 2.0)+pow(p.y-a.y, 2.0), 0.5)
         + pow(pow(p.x-b.x, 2.0)+pow(p.y-b.y, 2.0), 0.5)
         - pow(pow(b.x-a.x, 2.0)+pow(b.y-a.y, 2.0), 0.5);
}
fn triangle_function(x: f32, y: f32, cx: f32, cy: f32) -> v3f {
    var e = 5.0;
    e = e + sin(stuff.time*5.0) + cos(stuff.time*1.0);
    var p = v2f(x, y);
    var a = v2f(e, e);
    var b = v2f(-e, e);
    var c = v2f(0.0, -e);
    // var c = v2f(cx, cy);
    // var c = v2f(-e, -e);
    // var d = v2f(e, -e);
    var f = line_segment(p, a, b) // you can draw pretty much anything made out of line segments
          * line_segment(p, b, c)
          * line_segment(p, c, a)
        //   * line_segment(p, c, d)
        //   * line_segment(p, d, a)
          * 10.0;
    f = 1.0-f;
    f = smoothStep(-9.0, 0.0, f);
    let color = vec3<f32>(3.0, 1.0, 1.6);
    return vec3<f32>(f) * color;
}

fn plotquations(x: f32, y: f32) -> vec3<f32> {
    var time = stuff.time *10.0;
    // time = sin(time);

    var f = cos(x*x+y*y + time) - x*y/4.0;
    // var f = sin(exp(x)) - y;

    f = abs(f);
    // f = fract(f);
    // f = floor(f);
    // f = pow(f, 0.13);
    // f = pow(f, 5.13);
    f = pow(1.0-f, 2.13);
    // f = pow(abs(0.8 - f), 8.0);
    // f = pow(abs(0.6-f), 2.0);
    // f = abs(0.4-f);
    // f = step(f, 0.2);
    let color = vec3<f32>(3.0, 1.0, 1.6);
    return vec3<f32>(f) * color;
}
fn metaballs(x: f32, y:f32, cx: f32, cy: f32) -> v3f {
    var time = stuff.time *0.1;
    let p = (sin(time*3.0))*5.2;
    var f = 1.0/sqrt((x-p)*(x-p) + y*y) 
          + 1.0/sqrt((x+p)*(x+p) + y*y)
          + 1.0/sqrt((y-p)*(y-p) + x*x)
          + 1.0/sqrt((y+p)*(y+p) + x*x);
    f =  f + .7/sqrt((x-cx)*(x-cx) + (y-cy)*(y-cy)); // metaball at cursor
    f = abs(f);
    f = pow(f, 5.5);
    f = pow(abs(0.5-f), 2.0);
    f = abs(0.4-f);
    let color = vec3<f32>(3.0, 1.0, 1.6);
    return vec3<f32>(f) * color;
}
fn square(x: f32, y: f32) -> vec3<f32> {
    let side = 4.2;
    return vec3<f32>(step(abs(x), side)*step(abs(y), 0.8*side));
    // if (abs(x) < side && abs(y) < side) {
    //     return vec3<f32>(0.0);
    // } else {
    //     return vec3<f32>(1.0);
    // }
}
fn circle(x: f32, y: f32) -> vec3<f32> {
    var f = sqrt(x*x+y*y) - abs(sin(stuff.time*1.9))*4.0 - 1.0;
    f = pow(f, 10.0);
    // col = floor(col);
    return vec3<f32>(f);
}
fn polar_function(x: f32, y: f32) -> vec3<f32> {
    var l = length(v2f(x, y));
    var theta = atan2(y, x);
    var r = 2.0 + 4.0*sin(sin(stuff.time*0.4)*20.0*theta + stuff.time*20.);
    var f = smoothStep(0.0, 0.3, -l+r);
    return v3f(f);
}
fn regular_polygon(x: f32, y: f32) -> vec3<f32> {
    var l = length(v2f(x, y));
    var theta = atan2(y, x);
    var sides = 5.0;
    sides = sin(stuff.time*0.4)*10.0;
    var a = 2.0*PI/sides;
    var f = cos(floor(0.5 + theta/a)*a - theta)*l;
    f = f*0.1;
    f = smoothStep(0.4, 0.406, f);
    return v3f(f);
}
fn dot_at_mouse_position(x: f32, y: f32, cx: f32, cy: f32) -> vec3<f32> {
    return v3f(length(v2f(x-cx, y-cy)));
}
fn mandlebrot(x: f32, y: f32, curx: f32, cury: f32) -> v3f {
    var x = x*0.2 - 0.5;
    let curx = curx*0.2 - 0.5;
    let cury = cury*0.2;
    var y = y*0.2;
    let cx = x;
    let cy = y;

    let p = 2.0;

    var iter = 0.0;
    for (var i=0; i<1000; i = i+1) {
        // convert to r*e^(i*theta)
        let r = sqrt(x*x+y*y);
        let t = atan2(y, x);

        // raise to pth power and convert back to x + i*y
        x = pow(r, p)*cos(p*t) + cx;
        y = pow(r, p)*sin(p*t) + cy;
        if (x*x+y*y > 4.0) {
            iter = f32(i);
            break;
        }
    }

    var col = v3f(iter/100.0)*1.0;
    // col = col + 1.0-clamp(4.0*dot_at_mouse_position(cx, cy, curx, cury), v3f(0.0), v3f(1.0));
    // col = col*2.0 + 1.0 - 4.0*dot_at_mouse_position(cx, cy, curx, cury);
    if (stuff.mouse_left == u32(1)) {col = col*2.0 + 1.0 - 4.0*dot_at_mouse_position(cx, cy, curx, cury);}

    // return v3f(length(v3f(x, y, 0.0)));
    return col;
}


[[stage(fragment)]]
fn main_fragment([[builtin(position)]] pos: vec4<f32>) -> [[location(0)]] vec4<f32> {
    let width = f32(stuff.display_width);
    let height = f32(stuff.display_height);
    let offset = vec2<f32>(0.0, 0.0);
    var scale = 15.0;
    var side = min(width, height); // dynamic scaling
    // var side = 300.0; // static scale


    var pos = vec2<f32>(pos.x/width, pos.y/height); // get pos from 0 to 1
    pos.y = 1.0-pos.y; // inverting y axis to get it upright
    pos = pos - vec2<f32>(0.5, 0.5); // (0, 0) at centre of screen
    pos = pos + offset;
    pos = vec2<f32>(pos.x*width/side, pos.y*height/side);
    pos = pos * scale; // control scale

    // transform cursor the same as pos
    var curs = v2f(stuff.cursor_x/width, 1.0-stuff.cursor_y/height) - v2f(0.5) + offset;
    curs = v2f(curs.x*width/side, curs.y*height/side)*scale;

    // pos = floor(pos*1.0);

    var col = metaballs(pos.x, pos.y, curs.x, curs.y);
    // var col = plotquations(pos.x, pos.y);
    return vec4<f32>(sign(col)*col*col, 1.0); // gamma correction ruines stuff
}