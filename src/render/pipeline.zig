const std = @import("std");
const flint = @import("flint");
const sdl = flint.sdl.c;
const renderer = @import("renderer.zig");
const buffer = @import("buffer.zig");
const mesh = @import("mesh.zig");
const gltf = @import("../gltf.zig");

const INTERNAL: bool = @import("build_options").internal;

// Types.
const RendererContext = renderer.RendererContext;
const WorldVertex = mesh.WorldVertex;
const ScreenVertex = mesh.ScreenVertex;

pub fn init(context: *RendererContext, allocator: std.mem.Allocator, io: std.Io) void {
    const vertex_shader = loadShader(context, "lambert.vert", 0, 1, 0, 0, allocator, io);
    if (vertex_shader == null) {
        @panic("Failed to load vertex shader");
    }
    defer sdl.SDL_ReleaseGPUShader(context.gpu_device, vertex_shader);

    const fragment_shader = loadShader(context, "lambert.frag", 1, 2, 0, 0, allocator, io);
    if (fragment_shader == null) {
        @panic("Failed to load fragment shader");
    }
    defer sdl.SDL_ReleaseGPUShader(context.gpu_device, fragment_shader);

    const screen_vertex_shader = loadShader(context, "screen.vert", 0, 0, 0, 0, allocator, io);
    if (screen_vertex_shader == null) {
        @panic("Failed to load screen vertex shader");
    }
    defer sdl.SDL_ReleaseGPUShader(context.gpu_device, screen_vertex_shader);

    const screen_fragment_shader = loadShader(context, "screen.frag", 1, 1, 0, 0, allocator, io);
    if (screen_fragment_shader == null) {
        @panic("Failed to load screen fragment shader");
    }
    defer sdl.SDL_ReleaseGPUShader(context.gpu_device, screen_fragment_shader);

    const sky_vertex_shader = loadShader(context, "sky.vert", 0, 1, 0, 0, allocator, io);
    if (sky_vertex_shader == null) {
        @panic("Failed to load sky vertex shader");
    }
    defer sdl.SDL_ReleaseGPUShader(context.gpu_device, sky_vertex_shader);

    const sky_fragment_shader = loadShader(context, "sky.frag", 0, 1, 0, 0, allocator, io);
    if (sky_fragment_shader == null) {
        @panic("Failed to load sky fragment shader");
    }
    defer sdl.SDL_ReleaseGPUShader(context.gpu_device, sky_fragment_shader);

    const shadow_vertex_shader = loadShader(context, "shadow.vert", 0, 1, 0, 0, allocator, io);
    if (shadow_vertex_shader == null) {
        @panic("Failed to load shadow vertex shader");
    }
    defer sdl.SDL_ReleaseGPUShader(context.gpu_device, shadow_vertex_shader);
    const shadow_fragment_shader = loadShader(context, "shadow.frag", 0, 0, 0, 0, allocator, io);
    if (shadow_fragment_shader == null) {
        @panic("Failed to load shadow fragment shader");
    }
    defer sdl.SDL_ReleaseGPUShader(context.gpu_device, shadow_fragment_shader);

    const debug_shapes_vertex_shader = loadShader(context, "debug_shapes.vert", 0, 1, 0, 0, allocator, io);
    if (debug_shapes_vertex_shader == null) {
        @panic("Failed to load debug shapes vertex shader");
    }
    defer sdl.SDL_ReleaseGPUShader(context.gpu_device, debug_shapes_vertex_shader);

    const debug_shapes_fragment_shader = loadShader(context, "debug_shapes.frag", 1, 2, 0, 0, allocator, io);
    if (debug_shapes_fragment_shader == null) {
        @panic("Failed to load debug shapes fragment shader");
    }
    defer sdl.SDL_ReleaseGPUShader(context.gpu_device, debug_shapes_fragment_shader);

    // Fill pipeline.
    const color_target_descriptions = [_]sdl.SDL_GPUColorTargetDescription{.{
        .format = context.render_texture_format,
    }};
    var vertex_buffer_descriptions = [_]sdl.SDL_GPUVertexBufferDescription{
        .{
            .slot = 0,
            .input_rate = sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
            .pitch = @sizeOf(WorldVertex),
        },
    };
    var vertex_attributes = [_]sdl.SDL_GPUVertexAttribute{
        .{
            .buffer_slot = 0,
            .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
            .location = 0,
            .offset = 0,
        },
        .{
            .buffer_slot = 0,
            .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
            .location = 1,
            .offset = @sizeOf(f32) * 3,
        },
    };
    var pipeline_create_info: sdl.SDL_GPUGraphicsPipelineCreateInfo = .{
        .target_info = .{
            .num_color_targets = 1,
            .color_target_descriptions = &color_target_descriptions,
            .has_depth_stencil_target = true,
            .depth_stencil_format = context.depth_stencil_format,
        },
        .vertex_input_state = .{
            .num_vertex_buffers = 1,
            .vertex_buffer_descriptions = &vertex_buffer_descriptions,
            .num_vertex_attributes = 2,
            .vertex_attributes = &vertex_attributes,
        },
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = true,
            .enable_stencil_test = false,
            .compare_op = sdl.SDL_GPU_COMPAREOP_GREATER,
            .write_mask = 0xFF,
        },
        .multisample_state = .{
            .sample_count = context.render_texture_sample_count,
        },
        .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
    };

    pipeline_create_info.rasterizer_state.fill_mode = sdl.SDL_GPU_FILLMODE_FILL;
    if (sdl.SDL_CreateGPUGraphicsPipeline(context.gpu_device, &pipeline_create_info)) |fill_pipeline| {
        context.fill_pipeline = fill_pipeline;
    } else {
        @panic("Failed to create fill pipeline.");
    }

    // Line pipeline.
    pipeline_create_info.rasterizer_state.fill_mode = sdl.SDL_GPU_FILLMODE_LINE;
    pipeline_create_info.vertex_shader = debug_shapes_vertex_shader;
    pipeline_create_info.fragment_shader = debug_shapes_fragment_shader;
    if (sdl.SDL_CreateGPUGraphicsPipeline(context.gpu_device, &pipeline_create_info)) |line_pipeline| {
        context.line_pipeline = line_pipeline;
    } else {
        @panic("Failed to create line pipeline.");
    }

    if (INTERNAL) {
        // Debug shape pipeline.
        pipeline_create_info.rasterizer_state.fill_mode = sdl.SDL_GPU_FILLMODE_FILL;
        pipeline_create_info.depth_stencil_state = .{
            .compare_op = sdl.SDL_GPU_COMPAREOP_ALWAYS,
        };
        pipeline_create_info.vertex_shader = debug_shapes_vertex_shader;
        pipeline_create_info.fragment_shader = debug_shapes_fragment_shader;
        if (sdl.SDL_CreateGPUGraphicsPipeline(context.gpu_device, &pipeline_create_info)) |line_pipeline| {
            context.debug_shape_pipeline = line_pipeline;
        } else {
            @panic("Failed to create debug shape pipeline.");
        }
    }

    // Screen pipeline.
    const screen_vertex_buffer_descriptions = [_]sdl.SDL_GPUVertexBufferDescription{
        .{
            .slot = 0,
            .input_rate = sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
            .pitch = @sizeOf(ScreenVertex),
        },
    };
    const screen_vertex_attributes = [_]sdl.SDL_GPUVertexAttribute{
        .{
            .buffer_slot = 0,
            .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
            .location = 0,
            .offset = 0,
        },
        .{
            .buffer_slot = 0,
            .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
            .location = 1,
            .offset = @sizeOf(f32) * 3,
        },
    };
    pipeline_create_info = .{
        .target_info = .{
            .num_color_targets = 1,
            .color_target_descriptions = &color_target_descriptions,
        },
        .vertex_input_state = .{
            .num_vertex_buffers = 1,
            .vertex_buffer_descriptions = &screen_vertex_buffer_descriptions,
            .num_vertex_attributes = 2,
            .vertex_attributes = &screen_vertex_attributes,
        },
        .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .vertex_shader = screen_vertex_shader,
        .fragment_shader = screen_fragment_shader,
    };
    if (sdl.SDL_CreateGPUGraphicsPipeline(context.gpu_device, &pipeline_create_info)) |screen_pipeline| {
        context.screen_pipeline = screen_pipeline;
    } else {
        @panic("Failed to create screen pipeline.");
    }

    // Sky pipeline.
    pipeline_create_info = .{
        .target_info = .{
            .num_color_targets = 1,
            .color_target_descriptions = &color_target_descriptions,
            .has_depth_stencil_target = true,
            .depth_stencil_format = context.depth_stencil_format,
        },
        .depth_stencil_state = .{
            .enable_depth_test = false,
            .enable_depth_write = false,
            .enable_stencil_test = false,
            .write_mask = 0xFF,
        },
        .multisample_state = .{
            .sample_count = context.render_texture_sample_count,
        },
        .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .vertex_shader = sky_vertex_shader,
        .fragment_shader = sky_fragment_shader,
    };
    if (sdl.SDL_CreateGPUGraphicsPipeline(context.gpu_device, &pipeline_create_info)) |sky_pipeline| {
        context.sky_pipeline = sky_pipeline;
    } else {
        @panic("Failed to create sky pipeline.");
    }

    // Shadow pipeline.
    pipeline_create_info = .{
        .target_info = .{
            .num_color_targets = 0,
            .has_depth_stencil_target = true,
            .depth_stencil_format = context.depth_stencil_format,
        },
        .vertex_input_state = .{
            .num_vertex_buffers = 1,
            .vertex_buffer_descriptions = &vertex_buffer_descriptions,
            .num_vertex_attributes = 2,
            .vertex_attributes = &vertex_attributes,
        },
        .depth_stencil_state = .{
            .enable_depth_test = true,
            .enable_depth_write = true,
            .enable_stencil_test = false,
            .compare_op = sdl.SDL_GPU_COMPAREOP_GREATER,
            .write_mask = 0xFF,
        },
        .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .vertex_shader = shadow_vertex_shader,
        .fragment_shader = shadow_fragment_shader,
    };
    if (sdl.SDL_CreateGPUGraphicsPipeline(context.gpu_device, &pipeline_create_info)) |shadow_pipeline| {
        context.shadow_pipeline = shadow_pipeline;
    } else {
        @panic("Failed to create shadow pipeline.");
    }

    context.meshes = .init(allocator);

    context.quad_mesh_buffer = buffer.upload(context, ScreenVertex, mesh.QUAD_VERTICES, mesh.QUAD_INDICES);

    context.cube_mesh_buffer = buffer.uploadWorldMesh(context, mesh.CUBE);
    context.meshes.put(.Cube, &mesh.CUBE) catch @panic("OOM");

    if ((gltf.loadGLB("assets/models/cone.glb", allocator, io) catch @panic("Failed to load model"))) |meshes| {
        context.cone_mesh_buffer = buffer.uploadWorldMesh(context, meshes[0]);
        context.meshes.put(.Cone, &meshes[0]) catch @panic("OOM");
    }
}

pub fn deinit(context: *RendererContext) void {
    sdl.SDL_ReleaseGPUGraphicsPipeline(context.gpu_device, context.fill_pipeline);
    sdl.SDL_ReleaseGPUGraphicsPipeline(context.gpu_device, context.line_pipeline);
    sdl.SDL_ReleaseGPUGraphicsPipeline(context.gpu_device, context.screen_pipeline);
    sdl.SDL_ReleaseGPUGraphicsPipeline(context.gpu_device, context.sky_pipeline);
    sdl.SDL_ReleaseGPUGraphicsPipeline(context.gpu_device, context.shadow_pipeline);

    sdl.SDL_ReleaseGPUBuffer(context.gpu_device, context.quad_mesh_buffer.vertex_buffer);
    sdl.SDL_ReleaseGPUBuffer(context.gpu_device, context.quad_mesh_buffer.index_buffer);
    sdl.SDL_ReleaseGPUBuffer(context.gpu_device, context.cube_mesh_buffer.vertex_buffer);
    sdl.SDL_ReleaseGPUBuffer(context.gpu_device, context.cube_mesh_buffer.index_buffer);
    sdl.SDL_ReleaseGPUBuffer(context.gpu_device, context.cone_mesh_buffer.vertex_buffer);
    sdl.SDL_ReleaseGPUBuffer(context.gpu_device, context.cone_mesh_buffer.index_buffer);

    context.meshes.deinit();
}

fn loadShader(
    context: *RendererContext,
    name: []const u8,
    sampler_count: u32,
    uniform_buffer_count: u32,
    storage_buffer_count: u32,
    storage_texture_count: u32,
    allocator: std.mem.Allocator,
    io: std.Io,
) ?*sdl.SDL_GPUShader {
    var shader: ?*sdl.SDL_GPUShader = null;
    var entrypoint: [*:0]const u8 = "main";
    var extension: []const u8 = "";
    var format: sdl.SDL_GPUShaderFormat = sdl.SDL_GPU_SHADERFORMAT_INVALID;
    var stage: sdl.SDL_GPUShaderStage = sdl.SDL_GPU_SHADERSTAGE_VERTEX;
    if (std.mem.indexOf(u8, name, ".frag") != null) {
        stage = sdl.SDL_GPU_SHADERSTAGE_FRAGMENT;
    }

    const backend_formats: sdl.SDL_GPUShaderFormat = sdl.SDL_GetGPUShaderFormats(context.gpu_device);
    if ((backend_formats & sdl.SDL_GPU_SHADERFORMAT_SPIRV) != 0) {
        std.log.info("Loading {s} shader in SPIRV format.", .{name});
        format = sdl.SDL_GPU_SHADERFORMAT_SPIRV;
        extension = ".spv";
    } else if ((backend_formats & sdl.SDL_GPU_SHADERFORMAT_MSL) != 0) {
        std.log.info("Loading {s} shader in MSL format.", .{name});
        format = sdl.SDL_GPU_SHADERFORMAT_MSL;
        entrypoint = "main0";
        extension = ".msl";
    } else if ((backend_formats & sdl.SDL_GPU_SHADERFORMAT_DXIL) != 0) {
        std.log.info("Loading {s} shader in DXIL format.", .{name});
        format = sdl.SDL_GPU_SHADERFORMAT_DXIL;
        extension = ".dxil";
    } else {
        std.log.info("Unrecognized shader format: {d}", .{format});
        @panic("Unrecognized shader format");
    }

    var buf: [128]u8 = undefined;
    const path: []u8 = std.fmt.bufPrintSentinel(&buf, "assets/shaders/{s}{s}", .{ name, extension }, 0) catch "";
    const relative_path = flint.fs.getFilePathRelative(io, path, allocator) catch "";
    var code_size: usize = 0;
    if (sdl.SDL_LoadFile(relative_path.ptr, &code_size)) |code| {
        const shader_info: sdl.SDL_GPUShaderCreateInfo = .{
            .code = @ptrCast(code),
            .code_size = code_size,
            .entrypoint = entrypoint,
            .format = format,
            .stage = stage,
            .num_samplers = sampler_count,
            .num_uniform_buffers = uniform_buffer_count,
            .num_storage_buffers = storage_buffer_count,
            .num_storage_textures = storage_texture_count,
        };
        shader = sdl.SDL_CreateGPUShader(context.gpu_device, &shader_info);
    } else {
        std.log.info("Failed to load shader file: {s}", .{relative_path});
    }

    return shader;
}
