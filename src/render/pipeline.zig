const std = @import("std");
const flint = @import("flint");
const sdl = flint.sdl.c;

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

    var buffer_create_info: sdl.SDL_GPUBufferCreateInfo = .{
        .usage = sdl.SDL_GPU_BUFFERUSAGE_VERTEX,
        .size = VERTICES.len * @sizeOf(PositionColorVertex),
    };
    if (sdl.SDL_CreateGPUBuffer(state.device, &buffer_create_info)) |buffer| {
        state.vertex_buffer = buffer;
    } else {
        @panic("Failed to create vertex buffer.");
    }
    buffer_create_info = .{
        .usage = sdl.SDL_GPU_BUFFERUSAGE_INDEX,
        .size = INDICES.len * @sizeOf(u16),
    };
    if (sdl.SDL_CreateGPUBuffer(state.device, &buffer_create_info)) |buffer| {
        state.index_buffer = buffer;
    } else {
        @panic("Failed to create index buffer.");
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

    buffer_create_info = .{
        .usage = sdl.SDL_GPU_BUFFERUSAGE_VERTEX,
        .size = QUAD.len * @sizeOf(PositionUVVertex),
    };
    if (sdl.SDL_CreateGPUBuffer(state.device, &buffer_create_info)) |buffer| {
        state.quad_vertex_buffer = buffer;
    } else {
        @panic("Failed to create vertex buffer.");
    }
    buffer_create_info = .{
        .usage = sdl.SDL_GPU_BUFFERUSAGE_INDEX,
        .size = QUAD_INDICES.len * @sizeOf(u16),
    };
    if (sdl.SDL_CreateGPUBuffer(state.device, &buffer_create_info)) |buffer| {
        state.quad_index_buffer = buffer;
    } else {
        @panic("Failed to create index buffer.");
    }

    submitVertexData(state);
    submitQuadData(state);
}

pub fn deinit(state: *State) void {
    sdl.SDL_ReleaseGPUGraphicsPipeline(state.device, state.fill_pipeline);
    sdl.SDL_ReleaseGPUGraphicsPipeline(state.device, state.line_pipeline);
    sdl.SDL_ReleaseGPUGraphicsPipeline(state.device, state.screen_pipeline);

    sdl.SDL_ReleaseGPUBuffer(state.device, state.vertex_buffer);
    sdl.SDL_ReleaseGPUBuffer(state.device, state.index_buffer);
    sdl.SDL_ReleaseGPUBuffer(state.device, state.quad_vertex_buffer);
    sdl.SDL_ReleaseGPUBuffer(state.device, state.quad_index_buffer);

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

fn submitQuadData(state: *State) void {
    var transfer_buffer_create_info: sdl.SDL_GPUTransferBufferCreateInfo = .{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @sizeOf(PositionUVVertex) * QUAD.len + @sizeOf(u16) * QUAD_INDICES.len,
    };
    const opt_transfer_buffer: ?*sdl.SDL_GPUTransferBuffer = sdl.SDL_CreateGPUTransferBuffer(
        state.device,
        &transfer_buffer_create_info,
    );

    if (opt_transfer_buffer) |transfer_buffer| {
        if (sdl.SDL_MapGPUTransferBuffer(state.device, transfer_buffer, false)) |data| {
            var transfer_data: [*]PositionUVVertex = @ptrCast(@alignCast(data));
            @memcpy(transfer_data[0..QUAD.len], QUAD);

            var transfer_data2: [*]u16 = @ptrCast(@alignCast(transfer_data + QUAD.len));
            @memcpy(transfer_data2[0..QUAD_INDICES.len], QUAD_INDICES);

            sdl.SDL_UnmapGPUTransferBuffer(state.device, transfer_buffer);

            const upload_command_buffer: ?*sdl.SDL_GPUCommandBuffer = sdl.SDL_AcquireGPUCommandBuffer(state.device);
            const copy_pass: ?*sdl.SDL_GPUCopyPass = sdl.SDL_BeginGPUCopyPass(upload_command_buffer);
            sdl.SDL_UploadToGPUBuffer(
                copy_pass,
                &.{
                    .transfer_buffer = transfer_buffer,
                    .offset = 0,
                },
                &.{
                    .buffer = state.quad_vertex_buffer,
                    .offset = 0,
                    .size = QUAD.len * @sizeOf(PositionUVVertex),
                },
                false,
            );
            sdl.SDL_UploadToGPUBuffer(
                copy_pass,
                &.{
                    .transfer_buffer = transfer_buffer,
                    .offset = QUAD.len * @sizeOf(PositionUVVertex),
                },
                &.{
                    .buffer = state.quad_index_buffer,
                    .offset = 0,
                    .size = QUAD_INDICES.len * @sizeOf(u16),
                },
                false,
            );

            sdl.SDL_EndGPUCopyPass(copy_pass);
            _ = sdl.SDL_SubmitGPUCommandBuffer(upload_command_buffer);
            _ = sdl.SDL_WaitForGPUIdle(state.device);
            sdl.SDL_ReleaseGPUTransferBuffer(state.device, transfer_buffer);
        } else {
            @panic("Failed to map transfer buffer to GPU.");
        }
    } else {
        @panic("Failed to create transfer buffer.");
    }
}

fn submitVertexData(state: *State) void {
    var transfer_buffer_create_info: sdl.SDL_GPUTransferBufferCreateInfo = .{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @sizeOf(PositionColorVertex) * VERTICES.len + @sizeOf(u16) * INDICES.len,
    };
    const opt_transfer_buffer: ?*sdl.SDL_GPUTransferBuffer = sdl.SDL_CreateGPUTransferBuffer(
        state.device,
        &transfer_buffer_create_info,
    );

    if (opt_transfer_buffer) |transfer_buffer| {
        if (sdl.SDL_MapGPUTransferBuffer(state.device, transfer_buffer, false)) |data| {
            var transfer_data: [*]PositionColorVertex = @ptrCast(@alignCast(data));
            @memcpy(transfer_data[0..VERTICES.len], VERTICES);

            var transfer_data2: [*]u16 = @ptrCast(@alignCast(transfer_data + VERTICES.len));
            @memcpy(transfer_data2[0..INDICES.len], INDICES);

            sdl.SDL_UnmapGPUTransferBuffer(state.device, transfer_buffer);

            const upload_command_buffer: ?*sdl.SDL_GPUCommandBuffer = sdl.SDL_AcquireGPUCommandBuffer(state.device);
            const copy_pass: ?*sdl.SDL_GPUCopyPass = sdl.SDL_BeginGPUCopyPass(upload_command_buffer);
            sdl.SDL_UploadToGPUBuffer(
                copy_pass,
                &.{
                    .transfer_buffer = transfer_buffer,
                    .offset = 0,
                },
                &.{
                    .buffer = state.vertex_buffer,
                    .offset = 0,
                    .size = VERTICES.len * @sizeOf(PositionColorVertex),
                },
                false,
            );
            sdl.SDL_UploadToGPUBuffer(
                copy_pass,
                &.{
                    .transfer_buffer = transfer_buffer,
                    .offset = VERTICES.len * @sizeOf(PositionColorVertex),
                },
                &.{
                    .buffer = state.index_buffer,
                    .offset = 0,
                    .size = INDICES.len * @sizeOf(u16),
                },
                false,
            );

            sdl.SDL_EndGPUCopyPass(copy_pass);
            _ = sdl.SDL_SubmitGPUCommandBuffer(upload_command_buffer);
            sdl.SDL_ReleaseGPUTransferBuffer(state.device, transfer_buffer);
        } else {
            @panic("Failed to map transfer buffer to GPU.");
        }
    } else {
        @panic("Failed to create transfer buffer.");
    }
}
