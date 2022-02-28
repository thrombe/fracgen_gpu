
use wgpu::util::{DeviceExt};
use winit::{
    event::{Event, WindowEvent, KeyboardInput, ElementState, VirtualKeyCode},
    event_loop::{ControlFlow, EventLoop},
    window::{WindowBuilder, Window},
};
use std::sync::mpsc::channel;
// use anyhow::{Result, Context};

use super::shader_importer;

struct State {
    surface: Option<wgpu::Surface>,
    config: Option<wgpu::SurfaceConfiguration>,
    size: Option<winit::dpi::PhysicalSize<u32>>,

    screen_texture: Option<wgpu::Texture>,
    screen_texture_size: Option<u32>,
    screen_texture_desc: Option<wgpu::TextureDescriptor<'static>>,
    screen_texture_view: Option<wgpu::TextureView>,

    screen_buffer: wgpu::Buffer,

    device: wgpu::Device,
    queue: wgpu::Queue,

    render_pipeline: Option<wgpu::RenderPipeline>,
    compute_pipeline: Option<wgpu::ComputePipeline>,
    work_group_count: u32,
    vertex_buffer: wgpu::Buffer,
    num_vertices: u32,
    
    importer: shader_importer::Importer,
    compile_status: bool,
    shader_code: Option<String>,
    
    stuff: Stuff,
    stuff_buffer: wgpu::Buffer,
    compute_buffer: wgpu::Buffer,
    bind_group_layouts: wgpu::BindGroupLayout,
    bind_group: wgpu::BindGroup,
    time: std::time::Instant,
}

impl State {
    // Creating some of the wgpu types requires async code
    async fn new_windowed(window: &Window) -> Self {
        let size = window.inner_size();

        // The instance is a handle to our GPU
        // Backends::all => Vulkan + Metal + DX12 + Browser WebGPU
        let instance = wgpu::Instance::new(wgpu::Backends::all());
        let surface = unsafe { instance.create_surface(window) };
        let adapter = instance.request_adapter(
            &wgpu::RequestAdapterOptions {
                // power_preference: wgpu::PowerPreference::HighPerformance,
                power_preference: wgpu::PowerPreference::LowPower,
                compatible_surface: Some(&surface),
                force_fallback_adapter: false,
            },
        ).await.unwrap();
        let (device, queue) = adapter.request_device(
            &wgpu::DeviceDescriptor {
                features: wgpu::Features::empty(),
                limits: wgpu::Limits::default(),
                label: None,
            },
            None, // Trace path
        ).await.unwrap();
        let config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format: surface.get_preferred_format(&adapter).unwrap(),
            width: size.width,
            height: size.height,
            present_mode: wgpu::PresentMode::Fifo,
            // present_mode: wgpu::PresentMode::Immediate,
        };
        surface.configure(&device, &config);
        
        let screen_buffer= Self::get_screen_buffer_couple(&device);

        let (bind_group, bind_group_layouts, stuff_buffer, compute_buffer) = Self::get_bind_group(&device, &screen_buffer);
        let vertex_buffer = Self::get_vertex_buffer(&device);


        let mut state = Self { 
            surface: Some(surface), device, queue, config: Some(config), size: Some(size), render_pipeline: None, compute_pipeline: None, work_group_count: 1,
            vertex_buffer, num_vertices: VERTICES.len() as u32,
            stuff: Stuff::new(), bind_group_layouts, bind_group, stuff_buffer, compute_buffer,
            importer: shader_importer::Importer::new("./src/main.wgsl"),
            compile_status: false,
            shader_code: None,
            time: std::time::Instant::now(),
            screen_texture: None, screen_texture_size: None, screen_texture_desc: None, screen_texture_view: None,
            screen_buffer,
        };
        state.compile();
        state
    }
    
    
    async fn new_windowless() -> Self {
        let instance = wgpu::Instance::new(wgpu::Backends::all());
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                // power_preference: wgpu::PowerPreference::HighPerformance,
                power_preference: wgpu::PowerPreference::LowPower,
                compatible_surface: None,
                force_fallback_adapter: false,
            })
            .await
            .unwrap();
        let (device, queue) = adapter
            .request_device(&Default::default(), None)
            .await
            .unwrap();

        let (texture_size, texture_desc, texture, texture_view) = Self::get_screen_texture(&device);
        let vertex_buffer = Self::get_vertex_buffer(&device);
        let screen_buffer = Self::get_screen_buffer_couple(&device);

        let (bind_group, bind_group_layouts, stuff_buffer, compute_buffer) = Self::get_bind_group(&device, &screen_buffer);
        
        let mut state = Self {
            surface: None, size: None, device, queue, config: None, render_pipeline: None, compute_pipeline: None, work_group_count: 1,
            vertex_buffer, num_vertices: VERTICES.len() as u32,
            stuff: Stuff::new(), bind_group_layouts, bind_group, stuff_buffer, compute_buffer,
            importer: shader_importer::Importer::new("./src/main.wgsl"),
            compile_status: false,
            shader_code: None,
            time: std::time::Instant::now(),
            screen_texture: Some(texture), screen_texture_size: Some(texture_size), screen_texture_desc: Some(texture_desc), screen_texture_view: Some(texture_view),
            screen_buffer,
        };
        state.compile(); // fallback shader
        state.compile();
        state
    }
    
    
    fn get_screen_texture<'a, 'b>(device: &'a wgpu::Device) -> (u32, wgpu::TextureDescriptor<'b>, wgpu::Texture, wgpu::TextureView) {
        let texture_size = 1024u32; // should be a multiple of 256
        let texture_desc = wgpu::TextureDescriptor {
            size: wgpu::Extent3d {
                width: texture_size,
                height: texture_size,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8UnormSrgb,
            usage: wgpu::TextureUsages::COPY_SRC | wgpu::TextureUsages::RENDER_ATTACHMENT,
            label: None,
        };
        let texture = device.create_texture(&texture_desc);
        let texture_view = texture.create_view(&Default::default());
        (texture_size, texture_desc, texture, texture_view)
    }
    
    fn get_screen_buffer_couple<'a, 'b>(device: &'a wgpu::Device) -> wgpu::Buffer {
        let buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some(&format!("screen Buffer")),
            contents: bytemuck::cast_slice(&vec![0u32 ; 1080*1920]),
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        });
        buffer
    }

    fn get_vertex_buffer(device: &wgpu::Device) -> wgpu::Buffer {
        let vertex_buffer = device.create_buffer_init(
            &wgpu::util::BufferInitDescriptor {
                label: Some("Vertex Buffer"),
                contents: bytemuck::cast_slice(VERTICES),
                usage: wgpu::BufferUsages::VERTEX
            }
        );
        vertex_buffer
    }

    fn get_bind_group(device: &wgpu::Device, buff: &wgpu::Buffer) -> (wgpu::BindGroup, wgpu::BindGroupLayout, wgpu::Buffer, wgpu::Buffer) {
        let compute_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some(&format!("Compute Buffer")),
            contents: bytemuck::cast_slice(&vec![0u32 ; 1080*1920*(2+2+1+1)]),
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        });

        let stuff_buffer = device.create_buffer_init(
            &wgpu::util::BufferInitDescriptor {
                label: Some("stuff buffer"),
                contents: bytemuck::cast_slice(&[Stuff::new()]),
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            }
        );

        let bind_group_layouts = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("bind group layouts"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0, // Stuff
                    visibility: wgpu::ShaderStages::FRAGMENT | wgpu::ShaderStages::COMPUTE,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1, // Buffer
                    visibility: wgpu::ShaderStages::COMPUTE | wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 2, // screen_buffer
                    visibility: wgpu::ShaderStages::COMPUTE | wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
            ],
        });
        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("stuff bind group"),
            layout: &bind_group_layouts,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: stuff_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: compute_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: buff.as_entire_binding(),
                },
            ],
        });

        (bind_group, bind_group_layouts, stuff_buffer, compute_buffer)
    }

    fn fallback_shader() -> String {
        String::from("
            [[stage(vertex)]]
            fn main_vertex() -> [[builtin(position)]] vec4<f32> {
                return vec4<f32>(1.0);
            }
            [[stage(fragment)]]
            fn main_fragment([[builtin(position)]] pos: vec4<f32>) -> [[location(0)]] vec4<f32> {
                return vec4<f32>(1.0);
            }
            [[stage(compute), workgroup_size(1)]]
            fn main_compute([[builtin(global_invocation_id)]] global_invocation_id: vec3<u32>) {
            }
        ")
    }

    fn resize(&mut self, new_size: winit::dpi::PhysicalSize<u32>) {
        if new_size.width > 0 && new_size.height > 0 {
            self.size = Some(new_size);
            self.config.as_mut().unwrap().width = new_size.width;
            self.config.as_mut().unwrap().height = new_size.height;
            self.surface.as_mut().unwrap().configure(&self.device, &self.config.as_ref().unwrap());

            self.stuff.width = self.size.unwrap().width as f32;
            self.stuff.height = self.size.unwrap().height as f32;    
        }
    }

    fn input(&mut self, event: &WindowEvent) -> bool {
        match event {
            WindowEvent::CursorMoved { position, .. } => {
                self.stuff.cursor_x = position.x as f32;
                self.stuff.cursor_y = position.y as f32;
            },
            WindowEvent::MouseInput {button, state, ..} => {
                let p_or_r = match state {
                    winit::event::ElementState::Pressed => 1,
                    winit::event::ElementState::Released => 0,
                };
                match button {
                    winit::event::MouseButton::Left => self.stuff.mouse_left = p_or_r,
                    winit::event::MouseButton::Right => self.stuff.mouse_right = p_or_r,
                    winit::event::MouseButton::Middle => self.stuff.mouse_middle = p_or_r,
                    _ => (),
                }
            },
            WindowEvent::MouseWheel {delta, ..} => {
                match delta {
                    // winit::event::MouseScrollDelta::PixelDelta(pp) => self.stuff.scroll += (pp.y+pp.x) as f32,
                    winit::event::MouseScrollDelta::LineDelta(x, y) => self.stuff.scroll += x+y,
                    _ => (),
                }
            },
            _ => return false,
        };
        true
    }

    fn update(&mut self) {
        self.stuff.time = self.time.elapsed().as_secs_f32();

        self.queue.write_buffer(&self.stuff_buffer, 0, bytemuck::cast_slice(&[self.stuff]));

        self.compile();
    }

    fn compile(&mut self) {
        let shader_code = {
            if self.shader_code.is_none() {
                Some(Self::fallback_shader())
            } else if self.compile_status {
                self.importer.check_and_import()
            } else {
                self.importer.import()
            }
        };
        if shader_code.is_none() {return}
        if !self.compile_status && self.shader_code == shader_code {return}
        self.shader_code = shader_code;

        self.compile_render_shaders();
        if self.importer.compute | self.compute_pipeline.is_none() {
            self.compile_compute_shaders();
        }
        
        // update work_group_count if edited in shaders
        if self.importer.work_group_count.is_some() {
            let work_group_count = self.importer.work_group_count.unwrap();
            if work_group_count != self.work_group_count{
                dbg!(format!("work_group count changed from {} to {}", self.work_group_count, work_group_count));
                self.work_group_count = work_group_count;
            }
        };
    }

    fn compile_render_shaders(&mut self) {
        let (tx, rx) = channel::<wgpu::Error>();
        self.device.on_uncaptured_error(move |e: wgpu::Error| {
            tx.send(e).expect("sending error failed");
        });
        let shader = self.device.create_shader_module(&wgpu::ShaderModuleDescriptor {
            label: Some("Shader"),
            source: wgpu::ShaderSource::Wgsl(std::borrow::Cow::Borrowed(self.shader_code.as_ref().unwrap())),
        });
        let render_pipeline_layout = self.device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Render Pipeline Layout"),
            bind_group_layouts: &[
                &self.bind_group_layouts,
            ],
            push_constant_ranges: &[],
        });
        let format = {if self.config.is_some() {self.config.as_ref().unwrap().format} else {self.screen_texture_desc.as_ref().unwrap().format}};
        let render_pipeline = self.device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Render Pipeline"),
            layout: Some(&render_pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: "main_vertex",
                buffers: &[Vertex::desc()],
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: "main_fragment",
                targets: &[wgpu::ColorTargetState {
                    format,
                    blend: Some(wgpu::BlendState::REPLACE),
                    write_mask: wgpu::ColorWrites::ALL,
                }],
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                strip_index_format: None,
                front_face: wgpu::FrontFace::Ccw,
                cull_mode: Some(wgpu::Face::Back),
                // Setting this to anything other than Fill requires Features::NON_FILL_POLYGON_MODE
                polygon_mode: wgpu::PolygonMode::Fill,
                // Requires Features::CONSERVATIVE_RASTERIZATION
                conservative: false,
                unclipped_depth: false,
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState {
                count: 1,
                mask: !0,
                alpha_to_coverage_enabled: false,
            },
            multiview: None,
        });

        if let Ok(err) = rx.try_recv() {
            self.compile_status = false;
            println!("{}", err);
            return;
        }
        dbg!("render shaders compiled");
        self.compile_status = true;
        self.render_pipeline = Some(render_pipeline);
    }

    fn compile_compute_shaders(&mut self) {
        let (tx, rx) = channel::<wgpu::Error>();
        self.device.on_uncaptured_error(move |e: wgpu::Error| {
            tx.send(e).expect("sending error failed");
        });
        let shader = self.device.create_shader_module(&wgpu::ShaderModuleDescriptor {
            label: Some("Shader"),
            source: wgpu::ShaderSource::Wgsl(std::borrow::Cow::Borrowed(self.shader_code.as_ref().unwrap())),
        });
        let compute_pipeline_layout = self.device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("Compute Pipeline Layout"),
            bind_group_layouts: &[
                &self.bind_group_layouts,
            ],
            push_constant_ranges: &[],
        });
        let compute_pipeline = self.device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("Compute Pipeline"),
            layout: Some(&compute_pipeline_layout),
            module: &shader,
            entry_point: "main_compute",
        });

        if let Ok(err) = rx.try_recv() {
            self.compile_status = false;
            println!("{}", err);
            return;
        }
        dbg!("compute shaders compiled");
        self.compile_status = true;
        self.compute_pipeline = Some(compute_pipeline);
    }

    fn get_render_pass<'a>(encoder: &'a mut wgpu::CommandEncoder, view: &'a wgpu::TextureView) -> wgpu::RenderPass<'a> {
        encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("Render Pass"),
            color_attachments: &[wgpu::RenderPassColorAttachment {
                view: view,
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color {
                        r: 0.1,
                        g: 0.2,
                        b: 0.3,
                        a: 1.0,
                    }),
                    store: true,
                },
            }],
            depth_stencil_attachment: None,
        })
    }

    fn execute_render_and_compute_pass(&self, encoder: &mut wgpu::CommandEncoder, view: &wgpu::TextureView) {
        if self.importer.compute {
            let mut compute_pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor { label: None });
            compute_pass.set_pipeline(self.compute_pipeline.as_ref().unwrap());
            compute_pass.set_bind_group(0, &self.bind_group, &[]);
            compute_pass.dispatch(self.work_group_count, 1, 1); // opengl minimum requirements are (65535, 65535, 65535)
        }

        {
            let mut render_pass = Self::get_render_pass(encoder, view);
            render_pass.set_pipeline(self.render_pipeline.as_ref().unwrap());
            render_pass.set_vertex_buffer(0, self.vertex_buffer.slice(..));
            render_pass.set_bind_group(0, &self.bind_group, &[]);
            render_pass.draw(0..self.num_vertices, 0..1);
        }
    }

    fn render_windowed(&mut self) -> Result<(), wgpu::SurfaceError> {
        let output = self.surface.as_ref().unwrap().get_current_texture()?;
        let view = output.texture.create_view(&wgpu::TextureViewDescriptor::default());
        
        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("Render Encoder"),
        });

        self.execute_render_and_compute_pass(&mut encoder, &view);
    
        // submit will accept anything that implements IntoIter
        self.queue.submit(std::iter::once(encoder.finish()));
        output.present();
    
        Ok(())
    }

    async fn render_windowless(&mut self) {

        let u32_size = std::mem::size_of::<u32>() as u32;    
        let output_buffer_size = (u32_size * self.screen_texture_size.as_ref().unwrap() * self.screen_texture_size.as_ref().unwrap()) as wgpu::BufferAddress;
        let output_buffer_desc = wgpu::BufferDescriptor {
            size: output_buffer_size,
            usage: wgpu::BufferUsages::COPY_DST
                // this tells wpgu that we want to read this buffer from the cpu
                | wgpu::BufferUsages::MAP_READ,
            label: None,
            mapped_at_creation: false,
        };
        let output_buffer = self.device.create_buffer(&output_buffer_desc);

        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("Render Encoder"),
        });

        self.execute_render_and_compute_pass(&mut encoder, self.screen_texture_view.as_ref().unwrap());


        encoder.copy_texture_to_buffer(
            wgpu::ImageCopyTexture {
                aspect: wgpu::TextureAspect::All,
                texture: self.screen_texture.as_ref().unwrap(),
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
            },
            wgpu::ImageCopyBuffer {
                buffer: &output_buffer,
                layout: wgpu::ImageDataLayout {
                    offset: 0,
                    bytes_per_row: std::num::NonZeroU32::new(u32_size * self.screen_texture_size.unwrap()),
                    rows_per_image: std::num::NonZeroU32::new(self.screen_texture_size.unwrap()),
                },
            },
            self.screen_texture_desc.as_ref().unwrap().size,
        );

        self.queue.submit(Some(encoder.finish()));

        // We need to scope the mapping variables so that we can
        // unmap the buffer
        {
            let buffer_slice = output_buffer.slice(..);

            // NOTE: We have to create the mapping THEN device.poll() before await
            // the future. Otherwise the application will freeze.
            let mapping = buffer_slice.map_async(wgpu::MapMode::Read);
            self.device.poll(wgpu::Maintain::Wait);
            mapping.await.unwrap();

            let data = buffer_slice.get_mapped_range();

            use image::{ImageBuffer, Rgba};
            let buffer =
                ImageBuffer::<Rgba<u8>, _>::from_raw(self.screen_texture_size.unwrap(), self.screen_texture_size.unwrap(), data).unwrap();
            buffer.save(file_name()).unwrap();
        }
        output_buffer.unmap();
    }
}

pub fn render_to_image() {
    // https://sotrh.github.io/learn-wgpu/showcase/windowless/
    
    let mut state = pollster::block_on(State::new_windowless());
    state.stuff.width = state.screen_texture_size.unwrap() as f32;
    state.stuff.height = state.screen_texture_size.unwrap() as f32;
    state.update();
    pollster::block_on(state.render_windowless());
}

pub fn window_event_loop() {
    env_logger::init();
    let event_loop = EventLoop::new();
    let window = WindowBuilder::new().build(&event_loop).unwrap();

    // State::new uses async code, so we're going to wait for it to finish
    let mut state = pollster::block_on(State::new_windowed(&window));

    event_loop.run(move |event, _, control_flow| {
        match event { // https://docs.rs/winit/0.25.0/winit/event/enum.WindowEvent.html
            Event::WindowEvent {
                ref event,
                window_id,
            } if window_id == window.id() => if !state.input(event) {
                match event {
                    WindowEvent::CloseRequested | WindowEvent::KeyboardInput {
                        input:
                            KeyboardInput {
                                state: ElementState::Pressed,
                                virtual_keycode: Some(VirtualKeyCode::Escape),
                                ..
                            },
                        ..
                    } => *control_flow = ControlFlow::Exit,
                    WindowEvent::Resized(physical_size) => {
                        state.resize(*physical_size);
                    },
                    WindowEvent::ScaleFactorChanged { new_inner_size, .. } => {
                        // new_inner_size is &&mut so we have to dereference it twice
                        state.resize(**new_inner_size);
                    },
                    _ => {}
                }
            }
            Event::RedrawRequested(_) => {
                state.update();
                match state.render_windowed() {
                    Ok(_) => {}
                    // Reconfigure the surface if lost
                    Err(wgpu::SurfaceError::Lost) => state.resize(state.size.unwrap()),
                    // The system is out of memory, we should probably quit
                    Err(wgpu::SurfaceError::OutOfMemory) => *control_flow = ControlFlow::Exit,
                    // All other errors (Outdated, Timeout) should be resolved by the next frame
                    Err(e) => eprintln!("{:?}", e),
                }
            }
            Event::MainEventsCleared => {
                // RedrawRequested will only trigger once, unless we manually
                // request it.
                window.request_redraw();
            }
            _ => {}
        }
    });
}

pub fn main() {
    window_event_loop();
    // render_to_image();
}


fn file_name() -> String {
    let now: u64 = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH).unwrap()
        .as_secs();
    let path = format!("./images/{}.png", now);
    if std::path::Path::new(&path).exists() { // should never happen, but i dont wanna loose files
        println!("file already exists: {}", &path);
        return file_name()
    }
    path
}

#[repr(C)]
#[derive(Clone, Copy, Debug, bytemuck::Pod, bytemuck::Zeroable)]
struct Vertex {
    position: [f32; 3],
}

impl Vertex {
    fn desc<'a>() -> wgpu::VertexBufferLayout<'a> {
        wgpu::VertexBufferLayout {
            array_stride: std::mem::size_of::<Vertex>() as wgpu::BufferAddress,
            step_mode: wgpu::VertexStepMode::Vertex,
            attributes: &[
                wgpu::VertexAttribute {
                    offset: 0,
                    shader_location: 0,
                    format: wgpu::VertexFormat::Float32x3,
                },
            ]
        }
    }
}

// 2 triangles to fill the entire screen
const VERTICES: &[Vertex] = &[
    Vertex { position: [1.0, 1.0, 0.0] },
    Vertex { position: [-1.0, 1.0, 0.0] },
    Vertex { position: [1.0, -1.0, 0.0] },

    Vertex { position: [1.0, -1.0, 0.0] },
    Vertex { position: [-1.0, 1.0, 0.0] },
    Vertex { position: [-1.0, -1.0, 0.0] },
];

#[repr(C)]
#[derive(Clone, Copy, Debug, bytemuck::Pod, bytemuck::Zeroable)]
struct Stuff {
    width: f32,
    height: f32,
    time: f32,
    cursor_x: f32,
    cursor_y: f32,
    scroll: f32,

    // TODO: figure out how to send bool or compress this into a single variable
      // can shove inside a u32 and do (variable & u32(<2^n>)) to get it out
    mouse_left: u32,
    mouse_right: u32,
    mouse_middle: u32,
}

impl Stuff {
    fn new() -> Self {
        Self {
            width: 100.0,
            height: 100.0,
            time: 0.0,
            cursor_x: 0.0,
            cursor_y: 0.0,

            mouse_left: 0,
            mouse_right: 0,
            mouse_middle: 0,
            scroll: 0.0,
        }
    }
}