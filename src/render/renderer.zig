const flint = @import("flint");
const math = @import("math");
const sdl = flint.sdl.c;
const sdl_utils = flint.sdl;
const imgui = flint.imgui;
const device = @import("device.zig");
const pipeline = @import("pipeline.zig");
const game = @import("../root.zig");

const INTERNAL: bool = @import("build_options").internal;

// Types.
const State = game.State;
const Settings = flint.GameLib.Settings;
const Entity = game.Entity;
const Matrix4x4 = math.Matrix4x4;

pub const FragmentUniforms = struct {
    time: f32,
};

pub const FrameContext = struct {
    command_buffer: ?*sdl.SDL_GPUCommandBuffer = null,
    render_pass: ?*sdl.SDL_GPURenderPass = null,
    color_target_info: sdl.SDL_GPUColorTargetInfo = undefined,
};

pub fn init(state: *State, settings: *Settings) void {
    device.init(state);
    pipeline.init(state);
    device.initWindowSize(state, &settings.window_width, &settings.window_height);

    const aspect_ratio: f32 =
        @as(f32, @floatFromInt(settings.window_width)) /
        @as(f32, @floatFromInt(settings.window_height));
    state.camera = .init(aspect_ratio);
}

pub fn deinit(state: *State) void {
    pipeline.deinit(state);
    device.deinitWindowSize(state);
}

pub fn beginFrame(state: *State) FrameContext {
    var context: FrameContext = .{};

    context.command_buffer =
        sdl_utils.panicIfNull(sdl.SDL_AcquireGPUCommandBuffer(state.device), "Failed to acquire GPU command buffer");

    context.color_target_info = .{
        .texture = state.render_texture,
        .clear_color = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
        .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl.SDL_GPU_STOREOP_STORE,
    };

    if (state.render_texture_sample_count != sdl.SDL_GPU_SAMPLECOUNT_1) {
        context.color_target_info.store_op = sdl.SDL_GPU_STOREOP_RESOLVE;
        context.color_target_info.resolve_texture = state.resolve_texture;
    }

    var depth_stencil_target_info: sdl.SDL_GPUDepthStencilTargetInfo = .{
        .texture = state.depth_stencil_texture,
        .cycle = true,
        .clear_depth = 1,
        .clear_stencil = 0,
        .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl.SDL_GPU_STOREOP_STORE,
        .stencil_load_op = sdl.SDL_GPU_LOADOP_CLEAR,
        .stencil_store_op = sdl.SDL_GPU_STOREOP_STORE,
    };

    context.render_pass = sdl.SDL_BeginGPURenderPass(
        context.command_buffer,
        &context.color_target_info,
        1,
        &depth_stencil_target_info,
    );
    sdl.SDL_BindGPUGraphicsPipeline(context.render_pass, state.fill_pipeline);
    sdl.SDL_BindGPUVertexBuffers(context.render_pass, 0, &.{ .buffer = state.vertex_buffer, .offset = 0 }, 1);
    sdl.SDL_BindGPUIndexBuffer(
        context.render_pass,
        &.{ .buffer = state.index_buffer, .offset = 0 },
        sdl.SDL_GPU_INDEXELEMENTSIZE_16BIT,
    );

    return context;
}

pub fn drawCube(state: *State, context: *FrameContext, entity: Entity) void {
    var mvp = state.camera.calculateMVPMatrix(entity);
    sdl.SDL_PushGPUVertexUniformData(context.command_buffer, 0, &mvp, @sizeOf(Matrix4x4));
    sdl.SDL_DrawGPUIndexedPrimitives(context.render_pass, pipeline.INDICES.len, 1, 0, 0, 0);
}

pub fn endFrame(state: *State, context: *FrameContext) void {
    sdl.SDL_EndGPURenderPass(context.render_pass);

    // Draw texture to screen.
    var command_buffer_submitted = sdl.SDL_SubmitGPUCommandBuffer(context.command_buffer);
    sdl_utils.panic(command_buffer_submitted, "Failed to submit GPU command buffer");
    context.command_buffer = sdl.SDL_AcquireGPUCommandBuffer(state.device);

    if (device.getSwapchainTexture(state, context)) |swapchain_texture| {
        var screen_target_info: sdl.SDL_GPUColorTargetInfo = .{
            .texture = swapchain_texture,
            .clear_color = .{ .r = 0, .g = 0, .b = 1, .a = 1 },
            .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
            .store_op = sdl.SDL_GPU_STOREOP_STORE,
        };
        const screen_render_pass: ?*sdl.SDL_GPURenderPass = sdl.SDL_BeginGPURenderPass(
            context.command_buffer,
            &screen_target_info,
            1,
            null,
        );
        sdl.SDL_PushGPUFragmentUniformData(
            context.command_buffer,
            0,
            &state.getFragmentUniforms(),
            @sizeOf(FragmentUniforms),
        );
        sdl.SDL_BindGPUGraphicsPipeline(screen_render_pass, state.screen_pipeline);
        sdl.SDL_BindGPUVertexBuffers(screen_render_pass, 0, &.{ .buffer = state.quad_vertex_buffer, .offset = 0 }, 1);
        sdl.SDL_BindGPUIndexBuffer(
            screen_render_pass,
            &.{ .buffer = state.quad_index_buffer, .offset = 0 },
            sdl.SDL_GPU_INDEXELEMENTSIZE_16BIT,
        );
        sdl.SDL_BindGPUFragmentSamplers(
            screen_render_pass,
            0,
            &.{
                .texture = context.color_target_info.resolve_texture orelse context.color_target_info.texture,
                .sampler = state.render_texture_sampler,
            },
            1,
        );
        sdl.SDL_DrawGPUIndexedPrimitives(screen_render_pass, pipeline.QUAD_INDICES.len, 1, 0, 0, 0);
        sdl.SDL_EndGPURenderPass(screen_render_pass);
    }
    command_buffer_submitted = sdl.SDL_SubmitGPUCommandBuffer(context.command_buffer);
    sdl_utils.panic(command_buffer_submitted, "Failed to submit GPU command buffer");
}
