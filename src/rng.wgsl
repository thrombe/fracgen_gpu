

fn sin_rng(st: v2f) -> f32 {
    var f = sin(dot(st, v2f(12.9898,78.233)))*43758.5453123;
    // var f = (sin(x*y+y*y + 32.0*x)+sin(y+x))*100.0;
    // f = f + stuff.time * 1.0;
    f = fract(f);
    // f = step(0.5, f);
    // return v3f(f);
    return f32(f);
}
// fn smoothstep_noise(x: f32, y:f32) -> v3f {
//     var i = v2f(floor(v2f(x, y)));
//     var f = v2f(fract(v2f(x, y)));

//     // Four corners in 2D of a tile
//     var a = sin_rng(i.x, i.y);
//     let j = i + v2f(1.0, 0.0);
//     var b = sin_rng(j.x, j.y);
//     let j = i + v2f(0.0, 1.0);
//     var c = sin_rng(j.x, j.y);
//     let j = i + v2f(1.0, 1.0);
//     var d = sin_rng(j.x, j.y);

//     // Smooth Interpolation

//     // Cubic Hermine Curve.  Same as SmoothStep()
//     var u = f*f*(3.0- 2.0*f);
//     // u = smoothStep(v2f(0.), v2f(1.), f);

//     // Mix 4 coorners percentages
//     return v3f(mix(a, b, u.x) +
//             (c - a)* u.y * (1.0 - u.x) +
//             (d - b) * u.x * u.y);
// }

fn sin_rng2(st: v2f) -> v2f {
    let st = v2f( dot(st,v2f(127.1,311.7)),
              dot(st,v2f(269.5,183.3)) );
    return -1.0 + 2.0*fract(sin(st)*43758.5453123);
}
fn perlin_noise(st: v2f) -> v3f {
    var i = floor(st);
    var f = fract(st);

    var u = f*f*(3.0- 2.0*f);

    return v3f(mix( mix( dot( sin_rng2(i + v2f(0.0,0.0) ), f - v2f(0.0,0.0) ),
                         dot( sin_rng2(i + v2f(1.0,0.0) ), f - v2f(1.0,0.0) ),
                         u.x),
                    mix( dot( sin_rng2(i + v2f(0.0,1.0) ), f - v2f(0.0,1.0) ),
                         dot( sin_rng2(i + v2f(1.0,1.0) ), f - v2f(1.0,1.0) ),
                         u.x),
                    u.y)
               + 0.2);
}

fn gold_noise(st: v2f) -> v3f {
    let seed = 10.0;
    return v3f(fract(tan(distance(st*PHI, st)*seed)*st.x));
}

// Hash function www.cs.ubc.ca/~rbridson/docs/schechter-sca08-turbulence.pdf
fn hash(state: u32) -> u32 {
    var state = state;
    state = state^2747636419u;
    state = state*2654435769u;
    state = state^(state >> 16u);
    state = state*2654435769u;
    state = state^(state >> 16u);
    state = state*2654435769u;
    return state;
}

fn hash_rng(m: u32) -> f32 {
    var m = hash(m);
    let ieeeMantissa = 0x007FFFFFu; // binary32 mantissa bitmask
    let ieeeOne      = 0x3F800000u; // 1.0 in IEEE binary32

    m = m & ieeeMantissa;                     // Keep only mantissa bits (fractional part)
    m = m | ieeeOne;                          // Add fractional part to 1.0

    let f = bitcast<f32>(m);       // Range [1:2]
    return f - 1.0;
}

//////////////////////////////

// // A single iteration of Bob Jenkins' One-At-A-Time hashing algorithm.
// uint hash( uint x ) {
//     x += ( x << 10u );
//     x ^= ( x >>  6u );
//     x += ( x <<  3u );
//     x ^= ( x >> 11u );
//     x += ( x << 15u );
//     return x;
// }
// // Construct a float with half-open range [0:1] using low 23 bits.
// // All zeroes yields 0.0, all ones yields the next smallest representable value below 1.0.
// float floatConstruct( uint m ) {
//     const uint ieeeMantissa = 0x007FFFFFu; // binary32 mantissa bitmask
//     const uint ieeeOne      = 0x3F800000u; // 1.0 in IEEE binary32

//     m &= ieeeMantissa;                     // Keep only mantissa bits (fractional part)
//     m |= ieeeOne;                          // Add fractional part to 1.0

//     float  f = uintBitsToFloat( m );       // Range [1:2]
//     return f - 1.0;                        // Range [0:1]
// }
// // Pseudo-random value in half-open range [0:1].
// float random( float x ) { return floatConstruct(hash(floatBitsToUint(x))); }

///////////////////////

// const uint k = 1103515245U;  // GLIB C
// //const uint k = 134775813U;   // Delphi and Turbo Pascal
// //const uint k = 20170906U;    // Today's date (use three days ago's dateif you want a prime)
// //const uint k = 1664525U;     // Numerical Recipes
// vec3 hash( uvec3 x )
// {
//     x = ((x>>8U)^x.yzx)*k;
//     x = ((x>>8U)^x.yzx)*k;
//     x = ((x>>8U)^x.yzx)*k;

//     return vec3(x)*(1.0/float(0xffffffffU));
// }
