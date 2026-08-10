const std = @import("std");
const flint = @import("flint");
const sdl_utils = flint.sdl;
const sdl = flint.sdl.c;
const renderer = @import("renderer.zig");
const buffer = @import("buffer.zig");
const mesh = @import("mesh.zig");

const INTERNAL: bool = @import("build_options").internal;
const CUBE_MODEL = @import("model.zig").CUBE;

// Types.
const RendererContext = renderer.RendererContext;
const TextureResource = renderer.TextureResource;
const ModelId = renderer.ModelId;
const WorldVertex = mesh.WorldVertex;
const ScreenVertex = mesh.ScreenVertex;

pub fn init(context: *RendererContext, allocator: std.mem.Allocator, io: std.Io) void {
    const vertex_shader = loadShader(context, "lambert.vert", 0, 1, 0, 0, allocator, io);
    if (vertex_shader == null) {
        @panic("Failed to load vertex shader");
    }
    defer sdl.SDL_ReleaseGPUShader(context.gpu_device, vertex_shader);

    const fragment_shader = loadShader(context, "lambert.frag", 2, 2, 0, 0, allocator, io);
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
        .{
            .buffer_slot = 0,
            .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
            .location = 2,
            .offset = @sizeOf(f32) * 6,
        },
    };
    var pipeline_create_info: sdl.SDL_GPUGraphicsPipelineCreateInfo = .{
        .target_info = .{
            .num_color_targets = color_target_descriptions.len,
            .color_target_descriptions = &color_target_descriptions,
            .has_depth_stencil_target = true,
            .depth_stencil_format = context.depth_stencil_format,
        },
        .vertex_input_state = .{
            .num_vertex_buffers = vertex_buffer_descriptions.len,
            .vertex_buffer_descriptions = &vertex_buffer_descriptions,
            .num_vertex_attributes = vertex_attributes.len,
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
            .num_color_targets = color_target_descriptions.len,
            .color_target_descriptions = &color_target_descriptions,
        },
        .vertex_input_state = .{
            .num_vertex_buffers = screen_vertex_buffer_descriptions.len,
            .vertex_buffer_descriptions = &screen_vertex_buffer_descriptions,
            .num_vertex_attributes = screen_vertex_attributes.len,
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
            .num_color_targets = color_target_descriptions.len,
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
            .num_vertex_buffers = vertex_buffer_descriptions.len,
            .vertex_buffer_descriptions = &vertex_buffer_descriptions,
            .num_vertex_attributes = vertex_attributes.len,
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

    context.models = .init(allocator);
    context.model_textures = .init(allocator);
    context.mesh_buffers = .init(allocator);

    context.quad_mesh_buffer = buffer.uploadMesh(context, ScreenVertex, mesh.QUAD_VERTICES, mesh.QUAD_INDICES);

    context.mesh_buffers.put(.Cube, buffer.uploadWorldMesh(context, CUBE_MODEL.mesh)) catch @panic("OOM");
    context.models.put(.Cube, &CUBE_MODEL) catch @panic("OOM");

    context.white_texture = TextureResource.create(context, allocator, 1, 1, .{
        .min_filter = sdl.SDL_GPU_FILTER_NEAREST,
        .mag_filter = sdl.SDL_GPU_FILTER_NEAREST,
        .address_mode_u = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .mipmap_mode = sdl.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
    });
    buffer.uploadTextureRaw(context, context.white_texture.texture, &.{ 255, 255, 255, 255 }, 1, 1, 1, 1);
    context.model_textures.put(.Cube, context.white_texture) catch @panic("OOM");

    context.importModel("assets/models/cone.glb", .Cone, 0, allocator, io);
    context.importModel("assets/models/truck.glb", .Truck, 0, allocator, io);
    context.importModel("assets/models/default.glb", .Default, 0, allocator, io);
}

pub fn deinit(context: *RendererContext, allocator: std.mem.Allocator) void {
    sdl.SDL_ReleaseGPUGraphicsPipeline(context.gpu_device, context.fill_pipeline);
    sdl.SDL_ReleaseGPUGraphicsPipeline(context.gpu_device, context.line_pipeline);
    sdl.SDL_ReleaseGPUGraphicsPipeline(context.gpu_device, context.screen_pipeline);
    sdl.SDL_ReleaseGPUGraphicsPipeline(context.gpu_device, context.sky_pipeline);
    sdl.SDL_ReleaseGPUGraphicsPipeline(context.gpu_device, context.shadow_pipeline);

    sdl.SDL_ReleaseGPUBuffer(context.gpu_device, context.quad_mesh_buffer.vertex_buffer);
    sdl.SDL_ReleaseGPUBuffer(context.gpu_device, context.quad_mesh_buffer.index_buffer);

    var mesh_buffer_iterator = context.mesh_buffers.iterator();
    while (mesh_buffer_iterator.next()) |entry| {
        const mesh_buffer = entry.value_ptr.*;
        sdl.SDL_ReleaseGPUBuffer(context.gpu_device, mesh_buffer.vertex_buffer);
        sdl.SDL_ReleaseGPUBuffer(context.gpu_device, mesh_buffer.index_buffer);
    }

    var texture_iterator = context.model_textures.iterator();
    while (texture_iterator.next()) |entry| {
        const texture = entry.value_ptr.*;
        sdl.SDL_ReleaseGPUTexture(context.gpu_device, texture.texture);
        sdl.SDL_ReleaseGPUSampler(context.gpu_device, texture.sampler);
        texture.deinit(allocator);
    }

    context.model_textures.deinit();
    context.models.deinit();
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
