const std = @import("std");
const flint = @import("flint");
const sdl = flint.sdl.c;
const sdl_utils = flint.sdl;
const renderer = @import("renderer.zig");

// Types.
const WorldMesh = @import("mesh.zig").WorldMesh;
const WorldVertex = @import("mesh.zig").WorldVertex;
const RendererContext = renderer.RendererContext;

pub const MeshBuffer = struct {
    vertex_buffer: *sdl.SDL_GPUBuffer,
    index_buffer: *sdl.SDL_GPUBuffer,
    index_count: u32,
};

fn createBuffer(context: *RendererContext, usage_flags: sdl.SDL_GPUBufferUsageFlags, size: u32) ?*sdl.SDL_GPUBuffer {
    const buffer_create_info: sdl.SDL_GPUBufferCreateInfo = .{
        .usage = usage_flags,
        .size = size,
    };
    return sdl.SDL_CreateGPUBuffer(context.gpu_device, &buffer_create_info);
}

pub fn uploadWorldMesh(context: *RendererContext, mesh: WorldMesh) MeshBuffer {
    return uploadMesh(context, WorldVertex, mesh.vertices, mesh.indices);
}

pub fn uploadMesh(
    context: *RendererContext,
    VertexType: type,
    vertices: []const VertexType,
    indices: []const u16,
) MeshBuffer {
    const vertex_buffer_size: u32 = @intCast(vertices.len * @sizeOf(VertexType));
    const vertex_buffer = sdl_utils.panicIfNull(
        createBuffer(context, sdl.SDL_GPU_BUFFERUSAGE_VERTEX, vertex_buffer_size),
        "Failed to create vertex buffer.",
    );

    const index_buffer_size: u32 = @intCast(indices.len * @sizeOf(u16));
    const index_buffer = sdl_utils.panicIfNull(
        createBuffer(context, sdl.SDL_GPU_BUFFERUSAGE_INDEX, index_buffer_size),
        "Failed to create index buffer.",
    );

    var transfer_buffer_create_info: sdl.SDL_GPUTransferBufferCreateInfo = .{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = vertex_buffer_size + index_buffer_size,
    };
    const opt_transfer_buffer: ?*sdl.SDL_GPUTransferBuffer = sdl.SDL_CreateGPUTransferBuffer(
        context.gpu_device,
        &transfer_buffer_create_info,
    );

    if (opt_transfer_buffer) |transfer_buffer| {
        if (sdl.SDL_MapGPUTransferBuffer(context.gpu_device, transfer_buffer, false)) |data| {
            var transfer_data: [*]VertexType = @ptrCast(@alignCast(data));
            @memcpy(transfer_data[0..vertices.len], vertices);

            var transfer_data2: [*]u16 = @ptrCast(@alignCast(transfer_data + vertices.len));
            @memcpy(transfer_data2[0..indices.len], indices);

            sdl.SDL_UnmapGPUTransferBuffer(context.gpu_device, transfer_buffer);

            const upload_command_buffer: ?*sdl.SDL_GPUCommandBuffer = sdl.SDL_AcquireGPUCommandBuffer(context.gpu_device);
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
            sdl.SDL_ReleaseGPUTransferBuffer(context.gpu_device, transfer_buffer);
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

pub fn uploadTexture(
    context: *RendererContext,
    surface: *sdl.SDL_Surface,
    texture: *sdl.SDL_GPUTexture,
) void {
    const upload_surface: *sdl.SDL_Surface = sdl_utils.panicIfNull(
        sdl.SDL_ConvertSurface(surface, sdl.SDL_PIXELFORMAT_BGRA32),
        "Failed to conver texture pixels to target pixel format.",
    );
    defer sdl.SDL_DestroySurface(upload_surface);

    const texture_buffer_size: u32 = @intCast(upload_surface.pitch * upload_surface.h);

    uploadTextureRaw(
        context,
        texture,
        @as([*]const u8, @ptrCast(upload_surface.pixels))[0..texture_buffer_size],
        @intCast(upload_surface.w),
        @intCast(upload_surface.h),
        @intCast(@divTrunc(upload_surface.pitch, 4)),
        @intCast(upload_surface.h),
    );
}

pub fn uploadTextureRaw(
    context: *RendererContext,
    texture: *sdl.SDL_GPUTexture,
    texture_data: []const u8,
    width: u32,
    height: u32,
    pixels_per_row: u32,
    rows_per_layer: u32,
) void {
    var transfer_buffer_create_info: sdl.SDL_GPUTransferBufferCreateInfo = .{
        .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @intCast(texture_data.len),
    };
    const opt_transfer_buffer: ?*sdl.SDL_GPUTransferBuffer = sdl.SDL_CreateGPUTransferBuffer(
        context.gpu_device,
        &transfer_buffer_create_info,
    );

    if (opt_transfer_buffer) |transfer_buffer| {
        if (sdl.SDL_MapGPUTransferBuffer(context.gpu_device, transfer_buffer, false)) |data| {
            var transfer_data: [*]u8 = @ptrCast(@alignCast(data));
            @memcpy(transfer_data[0..texture_data.len], texture_data);

            sdl.SDL_UnmapGPUTransferBuffer(context.gpu_device, transfer_buffer);

            const upload_command_buffer: ?*sdl.SDL_GPUCommandBuffer = sdl.SDL_AcquireGPUCommandBuffer(context.gpu_device);
            const copy_pass: ?*sdl.SDL_GPUCopyPass = sdl.SDL_BeginGPUCopyPass(upload_command_buffer);
            sdl.SDL_UploadToGPUTexture(
                copy_pass,
                &.{
                    .transfer_buffer = transfer_buffer,
                    .offset = 0,
                    .pixels_per_row = pixels_per_row,
                    .rows_per_layer = rows_per_layer,
                },
                &.{
                    .texture = texture,
                    .mip_level = 0,
                    .x = 0,
                    .y = 0,
                    .z = 0,
                    .w = width,
                    .h = height,
                    .d = 1,
                },
                false,
            );

            sdl.SDL_EndGPUCopyPass(copy_pass);
            _ = sdl.SDL_SubmitGPUCommandBuffer(upload_command_buffer);
            sdl.SDL_ReleaseGPUTransferBuffer(context.gpu_device, transfer_buffer);
        } else {
            @panic("Failed to map transfer buffer to GPU.");
        }
    } else {
        @panic("Failed to create transfer buffer.");
    }
}
