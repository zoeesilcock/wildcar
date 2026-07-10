const std = @import("std");
const flint = @import("flint");
const sdl = flint.sdl.c;
const sdl_utils = flint.sdl;
const game = @import("../root.zig");

// Types.
const State = game.State;

pub const MeshBuffer = struct {
    vertex_buffer: *sdl.SDL_GPUBuffer,
    index_buffer: *sdl.SDL_GPUBuffer,
    index_count: u32,
};

fn createBuffer(state: *State, usage_flags: sdl.SDL_GPUBufferUsageFlags, size: u32) ?*sdl.SDL_GPUBuffer {
    const buffer_create_info: sdl.SDL_GPUBufferCreateInfo = .{
        .usage = usage_flags,
        .size = size,
    };
    return sdl.SDL_CreateGPUBuffer(state.device, &buffer_create_info);
}

pub fn upload(state: *State, VertexType: type, vertices: []const VertexType, indices: []const u16) MeshBuffer {
    const vertex_buffer_size: u32 = @intCast(vertices.len * @sizeOf(VertexType));
    const vertex_buffer = sdl_utils.panicIfNull(
        createBuffer(state, sdl.SDL_GPU_BUFFERUSAGE_VERTEX, vertex_buffer_size),
        "Failed to create vertex buffer.",
    );

    const index_buffer_size: u32 = @intCast(indices.len * @sizeOf(u16));
    const index_buffer = sdl_utils.panicIfNull(
        createBuffer(state, sdl.SDL_GPU_BUFFERUSAGE_INDEX, index_buffer_size),
        "Failed to create index buffer.",
    );

    var transfer_buffer_create_info: sdl.SDL_GPUTransferBufferCreateInfo = .{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = vertex_buffer_size + index_buffer_size,
    };
    const opt_transfer_buffer: ?*sdl.SDL_GPUTransferBuffer = sdl.SDL_CreateGPUTransferBuffer(
        state.device,
        &transfer_buffer_create_info,
    );

    if (opt_transfer_buffer) |transfer_buffer| {
        if (sdl.SDL_MapGPUTransferBuffer(state.device, transfer_buffer, false)) |data| {
            var transfer_data: [*]VertexType = @ptrCast(@alignCast(data));
            @memcpy(transfer_data[0..vertices.len], vertices);

            var transfer_data2: [*]u16 = @ptrCast(@alignCast(transfer_data + vertices.len));
            @memcpy(transfer_data2[0..indices.len], indices);

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
                    .buffer = vertex_buffer,
                    .offset = 0,
                    .size = vertex_buffer_size,
                },
                false,
            );
            sdl.SDL_UploadToGPUBuffer(
                copy_pass,
                &.{
                    .transfer_buffer = transfer_buffer,
                    .offset = vertex_buffer_size,
                },
                &.{
                    .buffer = index_buffer,
                    .offset = 0,
                    .size = index_buffer_size,
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

    return .{
        .vertex_buffer = vertex_buffer.?,
        .index_buffer = index_buffer.?,
        .index_count = @intCast(indices.len),
    };
}
