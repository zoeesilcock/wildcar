const std = @import("std");
const flint = @import("flint");
const sdl = flint.sdl.c;
const sdl_utils = flint.sdl;
const game = @import("../root.zig");

// Types.
const State = game.State;
const FrameContext = @import("renderer.zig").FrameContext;

pub fn init(state: *State) void {
    state.depth_stencil_format = undefined;
    if (sdl.SDL_GPUTextureSupportsFormat(
        state.device,
        sdl.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT,
        sdl.SDL_GPU_TEXTURETYPE_2D,
        sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    )) {
        state.depth_stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT;
    } else if (sdl.SDL_GPUTextureSupportsFormat(
        state.device,
        sdl.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT,
        sdl.SDL_GPU_TEXTURETYPE_2D,
        sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    )) {
        state.depth_stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT;
    } else {
        @panic("Failed to find a supported stencil format");
    }

    state.render_texture_format = sdl.SDL_GetGPUSwapchainTextureFormat(state.device, state.window);
    var sample_count: usize = 0;
    for (0..4) |i| {
        if (sdl.SDL_GPUTextureSupportsSampleCount(state.device, state.render_texture_format, @intCast(i))) {
            sample_count = i;
        }
    }
    state.render_texture_sample_count = @intCast(sample_count);
    std.log.info("Multisample count: {d}x", .{@as(u8, @intCast(1)) << @intCast(sample_count)});
}

pub fn initWindowSize(state: *State, width: *u32, height: *u32) void {
    _ = sdl.SDL_GetWindowSizeInPixels(
        state.window,
        @ptrCast(width),
        @ptrCast(height),
    );

    if (sdl.SDL_CreateGPUTexture(
        state.device,
        &.{
            .type = sdl.SDL_GPU_TEXTURETYPE_2D,
            .width = width.*,
            .height = height.*,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .format = state.render_texture_format,
            .sample_count = state.render_texture_sample_count,
            .usage = if (state.render_texture_sample_count == sdl.SDL_GPU_SAMPLECOUNT_1)
                sdl.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER
            else
                sdl.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
        },
    )) |texture| {
        state.render_texture = texture;
    } else {
        @panic("Failed to create render texture");
    }

    if (sdl.SDL_CreateGPUSampler(
        state.device,
        &.{
            .min_filter = sdl.SDL_GPU_FILTER_LINEAR,
            .mag_filter = sdl.SDL_GPU_FILTER_LINEAR,
            .mipmap_mode = sdl.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
            .address_mode_u = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_v = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .address_mode_w = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        },
    )) |sampler| {
        state.render_texture_sampler = sampler;
    } else {
        @panic("Failed to create render texture sampler");
    }

    if (sdl.SDL_CreateGPUTexture(
        state.device,
        &.{
            .type = sdl.SDL_GPU_TEXTURETYPE_2D,
            .width = width.*,
            .height = height.*,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .format = state.render_texture_format,
            .usage = sdl.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        },
    )) |texture| {
        state.resolve_texture = texture;
    } else {
        @panic("Failed to create resolve texture");
    }

    if (sdl.SDL_CreateGPUTexture(
        state.device,
        &.{
            .type = sdl.SDL_GPU_TEXTURETYPE_2D,
            .width = width.*,
            .height = height.*,
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = state.render_texture_sample_count,
            .format = state.depth_stencil_format,
            .usage = sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
        },
    )) |texture| {
        state.depth_stencil_texture = texture;
    } else {
        @panic("Failed to create depth stencil texture");
    }
}

pub fn deinitWindowSize(state: *State) void {
    sdl.SDL_ReleaseGPUTexture(state.device, state.render_texture);
    sdl.SDL_ReleaseGPUTexture(state.device, state.resolve_texture);
    sdl.SDL_ReleaseGPUTexture(state.device, state.depth_stencil_texture);
}

pub fn getSwapchainTexture(state: *State, context: *FrameContext) ?*sdl.SDL_GPUTexture {
    var swapchain_texture: ?*sdl.SDL_GPUTexture = null;
    var swapchain_texture_width: u32 = 0;
    var swapchain_texture_height: u32 = 0;

    const swapchain_acquired = sdl.SDL_WaitAndAcquireGPUSwapchainTexture(
        context.command_buffer,
        state.window,
        &swapchain_texture,
        &swapchain_texture_width,
        &swapchain_texture_height,
    );
    sdl_utils.panic(swapchain_acquired, "Failed to acquire GPU swapchain texture");

    return swapchain_texture;
}
