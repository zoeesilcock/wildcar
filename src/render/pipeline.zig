const std = @import("std");
const flint = @import("flint");
const sdl = flint.sdl.c;
const buffer = @import("buffer.zig");

// Types.
const State = @import("../root.zig").State;

const PositionColorVertex = struct {
    x: f32,
    y: f32,
    z: f32,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const PositionUVVertex = struct {
    x: f32,
    y: f32,
    z: f32,
    u: f32,
    v: f32,
};

const VERTICES: []const PositionColorVertex = &.{
    .{ .x = -1, .y = -1, .z = -1, .r = 255, .g = 0, .b = 0, .a = 255 },
    .{ .x = 1, .y = -1, .z = -1, .r = 255, .g = 0, .b = 0, .a = 255 },
    .{ .x = 1, .y = 1, .z = -1, .r = 255, .g = 0, .b = 0, .a = 255 },
    .{ .x = -1, .y = 1, .z = -1, .r = 255, .g = 0, .b = 0, .a = 255 },

    .{ .x = -1, .y = -1, .z = 1, .r = 0, .g = 255, .b = 0, .a = 255 },
    .{ .x = 1, .y = -1, .z = 1, .r = 0, .g = 255, .b = 0, .a = 255 },
    .{ .x = 1, .y = 1, .z = 1, .r = 0, .g = 255, .b = 0, .a = 255 },
    .{ .x = -1, .y = 1, .z = 1, .r = 0, .g = 255, .b = 0, .a = 255 },

    .{ .x = -1, .y = -1, .z = -1, .r = 0, .g = 0, .b = 255, .a = 255 },
    .{ .x = -1, .y = 1, .z = -1, .r = 0, .g = 0, .b = 255, .a = 255 },
    .{ .x = -1, .y = 1, .z = 1, .r = 0, .g = 0, .b = 255, .a = 255 },
    .{ .x = -1, .y = -1, .z = 1, .r = 0, .g = 0, .b = 255, .a = 255 },

    .{ .x = 1, .y = -1, .z = -1, .r = 200, .g = 0, .b = 200, .a = 255 },
    .{ .x = 1, .y = 1, .z = -1, .r = 200, .g = 0, .b = 200, .a = 255 },
    .{ .x = 1, .y = 1, .z = 1, .r = 200, .g = 0, .b = 200, .a = 255 },
    .{ .x = 1, .y = -1, .z = 1, .r = 200, .g = 0, .b = 200, .a = 255 },

    .{ .x = -1, .y = -1, .z = -1, .r = 200, .g = 200, .b = 0, .a = 255 },
    .{ .x = -1, .y = -1, .z = 1, .r = 200, .g = 200, .b = 0, .a = 255 },
    .{ .x = 1, .y = -1, .z = 1, .r = 200, .g = 200, .b = 0, .a = 255 },
    .{ .x = 1, .y = -1, .z = -1, .r = 200, .g = 200, .b = 0, .a = 255 },

    .{ .x = -1, .y = 1, .z = -1, .r = 0, .g = 200, .b = 200, .a = 255 },
    .{ .x = -1, .y = 1, .z = 1, .r = 0, .g = 200, .b = 200, .a = 255 },
    .{ .x = 1, .y = 1, .z = 1, .r = 0, .g = 200, .b = 200, .a = 255 },
    .{ .x = 1, .y = 1, .z = -1, .r = 0, .g = 200, .b = 200, .a = 255 },
};

pub const INDICES: []const u16 = &.{
    0,  1,  2,  0,  2,  3,
    6,  5,  4,  7,  6,  4,
    8,  9,  10, 8,  10, 11,
    14, 13, 12, 15, 14, 12,
    16, 17, 18, 16, 18, 19,
    22, 21, 20, 23, 22, 20,
};

pub const QUAD: []const PositionUVVertex = &.{
    .{ .x = -1, .y = -1, .z = 0, .u = 0, .v = 1 },
    .{ .x = 1, .y = -1, .z = 0, .u = 1, .v = 1 },
    .{ .x = -1, .y = 1, .z = 0, .u = 0, .v = 0 },
    .{ .x = 1, .y = 1, .z = 0, .u = 1, .v = 0 },
};

pub const QUAD_INDICES: []const u16 = &.{
    0, 1, 3,
    0, 3, 2,
};

pub fn init(state: *State) void {
    const vertex_shader = loadShader(state, "cube.vert", 0, 1, 0, 0);
    if (vertex_shader == null) {
        @panic("Failed to load vertex shader");
    }
    defer sdl.SDL_ReleaseGPUShader(state.device, vertex_shader);

    const fragment_shader = loadShader(state, "solid_color.frag", 0, 0, 0, 0);
    if (fragment_shader == null) {
        @panic("Failed to load fragment shader");
    }
    defer sdl.SDL_ReleaseGPUShader(state.device, fragment_shader);

    const screen_vertex_shader = loadShader(state, "screen.vert", 0, 0, 0, 0);
    if (screen_vertex_shader == null) {
        @panic("Failed to load screen vertex shader");
    }
    defer sdl.SDL_ReleaseGPUShader(state.device, screen_vertex_shader);

    const screen_fragment_shader = loadShader(state, "screen.frag", 1, 1, 0, 0);
    if (screen_fragment_shader == null) {
        @panic("Failed to load screen fragment shader");
    }
    defer sdl.SDL_ReleaseGPUShader(state.device, screen_fragment_shader);

    const color_target_descriptions = [_]sdl.SDL_GPUColorTargetDescription{.{
        .format = state.render_texture_format,
    }};
    const vertex_buffer_descriptions = [_]sdl.SDL_GPUVertexBufferDescription{
        .{
            .slot = 0,
            .input_rate = sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
            .pitch = @sizeOf(PositionColorVertex),
        },
    };
    const vertex_attributes = [_]sdl.SDL_GPUVertexAttribute{
        .{
            .buffer_slot = 0,
            .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
            .location = 0,
            .offset = 0,
        },
        .{
            .buffer_slot = 0,
            .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM,
            .location = 1,
            .offset = @sizeOf(f32) * 3,
        },
    };
    var pipeline_create_info: sdl.SDL_GPUGraphicsPipelineCreateInfo = .{
        .target_info = .{
            .num_color_targets = 1,
            .color_target_descriptions = &color_target_descriptions,
            .has_depth_stencil_target = true,
            .depth_stencil_format = state.depth_stencil_format,
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
            .compare_op = sdl.SDL_GPU_COMPAREOP_LESS,
            .write_mask = 0xFF,
        },
        .multisample_state = .{
            .sample_count = state.render_texture_sample_count,
        },
        .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
    };

    pipeline_create_info.rasterizer_state.fill_mode = sdl.SDL_GPU_FILLMODE_FILL;
    if (sdl.SDL_CreateGPUGraphicsPipeline(state.device, &pipeline_create_info)) |fill_pipeline| {
        state.fill_pipeline = fill_pipeline;
    } else {
        @panic("Failed to create fill pipeline.");
    }

    pipeline_create_info.rasterizer_state.fill_mode = sdl.SDL_GPU_FILLMODE_LINE;
    if (sdl.SDL_CreateGPUGraphicsPipeline(state.device, &pipeline_create_info)) |line_pipeline| {
        state.line_pipeline = line_pipeline;
    } else {
        @panic("Failed to create line pipeline.");
    }

    const screen_vertex_buffer_descriptions = [_]sdl.SDL_GPUVertexBufferDescription{
        .{
            .slot = 0,
            .input_rate = sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
            .instance_step_rate = 0,
            .pitch = @sizeOf(PositionUVVertex),
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
    if (sdl.SDL_CreateGPUGraphicsPipeline(state.device, &pipeline_create_info)) |screen_pipeline| {
        state.screen_pipeline = screen_pipeline;
    } else {
        @panic("Failed to create screen pipeline.");
    }

    state.quad_mesh = buffer.upload(state, PositionUVVertex, QUAD, QUAD_INDICES);
    state.cube_mesh = buffer.upload(state, PositionColorVertex, VERTICES, INDICES);
}

pub fn deinit(state: *State) void {
    sdl.SDL_ReleaseGPUGraphicsPipeline(state.device, state.fill_pipeline);
    sdl.SDL_ReleaseGPUGraphicsPipeline(state.device, state.line_pipeline);
    sdl.SDL_ReleaseGPUGraphicsPipeline(state.device, state.screen_pipeline);

    sdl.SDL_ReleaseGPUBuffer(state.device, state.cube_mesh.vertex_buffer);
    sdl.SDL_ReleaseGPUBuffer(state.device, state.cube_mesh.index_buffer);
    sdl.SDL_ReleaseGPUBuffer(state.device, state.quad_mesh.vertex_buffer);
    sdl.SDL_ReleaseGPUBuffer(state.device, state.quad_mesh.index_buffer);

    sdl.SDL_ReleaseGPUSampler(state.device, state.render_texture_sampler);
}

fn loadShader(
    state: *State,
    name: []const u8,
    sampler_count: u32,
    uniform_buffer_count: u32,
    storage_buffer_count: u32,
    storage_texture_count: u32,
) ?*sdl.SDL_GPUShader {
    var shader: ?*sdl.SDL_GPUShader = null;
    var entrypoint: [*:0]const u8 = "main";
    var extension: []const u8 = "";
    var format: sdl.SDL_GPUShaderFormat = sdl.SDL_GPU_SHADERFORMAT_INVALID;
    var stage: sdl.SDL_GPUShaderStage = sdl.SDL_GPU_SHADERSTAGE_VERTEX;
    if (std.mem.indexOf(u8, name, ".frag") != null) {
        stage = sdl.SDL_GPU_SHADERSTAGE_FRAGMENT;
    }

    const backend_formats: sdl.SDL_GPUShaderFormat = sdl.SDL_GetGPUShaderFormats(state.device);
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
    const relative_path = flint.fs.getFilePathRelative(state.dependencies.io.*, path, state.allocator) catch "";
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
        shader = sdl.SDL_CreateGPUShader(state.device, &shader_info);
    } else {
        std.log.info("Failed to load shader file: {s}", .{relative_path});
    }

    return shader;
}
