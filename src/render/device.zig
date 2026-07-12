const std = @import("std");
const flint = @import("flint");
const sdl = flint.sdl.c;
const sdl_utils = flint.sdl;
const renderer = @import("renderer.zig");

// Types.
const RendererContext = renderer.RendererContext;
const FrameContext = renderer.FrameContext;

pub fn init(context: *RendererContext) void {
    context.depth_stencil_format = undefined;
    if (sdl.SDL_GPUTextureSupportsFormat(
        context.gpu_device,
        sdl.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT,
        sdl.SDL_GPU_TEXTURETYPE_2D,
        sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    )) {
        context.depth_stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT;
    } else if (sdl.SDL_GPUTextureSupportsFormat(
        context.gpu_device,
        sdl.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT,
        sdl.SDL_GPU_TEXTURETYPE_2D,
        sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    )) {
        context.depth_stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT;
    } else {
        @panic("Failed to find a supported stencil format");
    }

    context.render_texture_format = sdl.SDL_GetGPUSwapchainTextureFormat(context.gpu_device, context.window);
    var sample_count: usize = 0;
    for (0..4) |i| {
        if (sdl.SDL_GPUTextureSupportsSampleCount(context.gpu_device, context.render_texture_format, @intCast(i))) {
            sample_count = i;
        }
    }
    context.render_texture_sample_count = @intCast(sample_count);
    std.log.info("Multisample count: {d}x", .{@as(u8, @intCast(1)) << @intCast(sample_count)});
}

pub fn initWindowSize(context: *RendererContext, width: *u32, height: *u32) void {
    _ = sdl.SDL_GetWindowSizeInPixels(
        context.window,
        @ptrCast(width),
        @ptrCast(height),
    );

    if (sdl.SDL_CreateGPUTexture(
        context.gpu_device,
        &.{
            .type = sdl.SDL_GPU_TEXTURETYPE_2D,
            .width = width.*,
            .height = height.*,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .format = context.render_texture_format,
            .sample_count = context.render_texture_sample_count,
            .usage = if (context.render_texture_sample_count == sdl.SDL_GPU_SAMPLECOUNT_1)
                sdl.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER
            else
                sdl.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
        },
    )) |texture| {
        context.render_texture = texture;
    } else {
        @panic("Failed to create render texture");
    }

    if (sdl.SDL_CreateGPUSampler(
        context.gpu_device,
        &.{
            .min_filter = sdl.SDL_GPU_FILTER_LINEAR,
            .mag_filter = sdl.SDL_GPU_FILTER_LINEAR,
            .mipmap_mode = sdl.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
            .address_mode_u = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_v = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_w = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        },
    )) |sampler| {
        context.render_texture_sampler = sampler;
    } else {
        @panic("Failed to create render texture sampler");
    }

    if (sdl.SDL_CreateGPUTexture(
        context.gpu_device,
        &.{
            .type = sdl.SDL_GPU_TEXTURETYPE_2D,
            .width = width.*,
            .height = height.*,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .format = context.render_texture_format,
            .usage = sdl.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        },
    )) |texture| {
        context.resolve_texture = texture;
    } else {
        @panic("Failed to create resolve texture");
    }

    if (sdl.SDL_CreateGPUTexture(
        context.gpu_device,
        &.{
            .type = sdl.SDL_GPU_TEXTURETYPE_2D,
            .width = width.*,
            .height = height.*,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = context.render_texture_sample_count,
            .format = context.depth_stencil_format,
            .usage = sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
        },
    )) |texture| {
        context.depth_stencil_texture = texture;
    } else {
        @panic("Failed to create depth stencil texture");
    }
}

pub fn deinitWindowSize(context: *RendererContext) void {
    sdl.SDL_ReleaseGPUTexture(context.gpu_device, context.render_texture);
    sdl.SDL_ReleaseGPUSampler(context.gpu_device, context.render_texture_sampler);
    sdl.SDL_ReleaseGPUTexture(context.gpu_device, context.resolve_texture);
    sdl.SDL_ReleaseGPUTexture(context.gpu_device, context.depth_stencil_texture);
}

pub fn getSwapchainTexture(context: *RendererContext, frame: *FrameContext) ?*sdl.SDL_GPUTexture {
    var swapchain_texture: ?*sdl.SDL_GPUTexture = null;
    var swapchain_texture_width: u32 = 0;
    var swapchain_texture_height: u32 = 0;

    const swapchain_acquired = sdl.SDL_WaitAndAcquireGPUSwapchainTexture(
        frame.command_buffer,
        context.window,
        &swapchain_texture,
        &swapchain_texture_width,
        &swapchain_texture_height,
    );
    sdl_utils.panic(swapchain_acquired, "Failed to acquire GPU swapchain texture");

    return swapchain_texture;
}
