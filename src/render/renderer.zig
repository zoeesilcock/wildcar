const std = @import("std");
const flint = @import("flint");
const sdl = flint.sdl.c;
const sdl_utils = flint.sdl;
const math = @import("math");
const device = @import("device.zig");
const pipeline = @import("pipeline.zig");

// Types.
pub const Camera = @import("camera.zig").Camera;
const MeshBuffer = @import("buffer.zig").MeshBuffer;
const Transform = math.Transform;
const Color = math.Color;
const Settings = flint.GameLib.Settings;
const Matrix4x4 = math.Matrix4x4;

pub const RendererContext = struct {
    // Device.
    window: *sdl.SDL_Window,
    gpu_device: *sdl.SDL_GPUDevice,

    render_texture_format: sdl.SDL_GPUTextureFormat = undefined,
    render_texture_sample_count: sdl.SDL_GPUSampleCount = sdl.SDL_GPU_SAMPLECOUNT_1,
    render_texture: *sdl.SDL_GPUTexture = undefined,
    render_texture_sampler: *sdl.SDL_GPUSampler = undefined,

    resolve_texture: *sdl.SDL_GPUTexture = undefined,

    depth_stencil_format: sdl.SDL_GPUTextureFormat = undefined,
    depth_stencil_texture: *sdl.SDL_GPUTexture = undefined,

    // Pipeline.
    fill_pipeline: *sdl.SDL_GPUGraphicsPipeline = undefined,
    line_pipeline: *sdl.SDL_GPUGraphicsPipeline = undefined,
    screen_pipeline: *sdl.SDL_GPUGraphicsPipeline = undefined,

    quad_mesh: MeshBuffer = undefined,
    cube_mesh: MeshBuffer = undefined,
};

pub const FrameContext = struct {
    command_buffer: ?*sdl.SDL_GPUCommandBuffer = null,
    render_pass: ?*sdl.SDL_GPURenderPass = null,
    color_target_info: sdl.SDL_GPUColorTargetInfo = undefined,
    view_projection: Matrix4x4 = undefined,
};

pub const FragmentUniforms = struct {
    time: f32,
};

const CubeUniforms = struct {
    color: [4]f32,
};

pub fn init(
    window: *sdl.SDL_Window,
    gpu_device: *sdl.SDL_GPUDevice,
    settings: *Settings,
    allocator: std.mem.Allocator,
    io: std.Io,
) RendererContext {
    var context: RendererContext = .{
        .window = window,
        .gpu_device = gpu_device,
    };

    device.init(&context);
    pipeline.init(&context, allocator, io);
    device.initWindowSize(&context, &settings.window_width, &settings.window_height);

    return context;
}

pub fn deinit(context: *RendererContext) void {
    pipeline.deinit(context);
    device.deinitWindowSize(context);
}

pub fn reinitWindowSize(context: *RendererContext, settings: *Settings) void {
    device.deinitWindowSize(context);
    device.initWindowSize(context, &settings.window_width, &settings.window_height);
}

pub fn beginFrame(context: *RendererContext, camera: *const Camera) FrameContext {
    var frame: FrameContext = .{
        .view_projection = camera.calculateViewProjectionMatrix(),
    };

    frame.command_buffer =
        sdl_utils.panicIfNull(sdl.SDL_AcquireGPUCommandBuffer(context.gpu_device), "Failed to acquire GPU command buffer");

    frame.color_target_info = .{
        .texture = context.render_texture,
        .clear_color = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
        .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl.SDL_GPU_STOREOP_STORE,
    };

    if (context.render_texture_sample_count != sdl.SDL_GPU_SAMPLECOUNT_1) {
        frame.color_target_info.store_op = sdl.SDL_GPU_STOREOP_RESOLVE;
        frame.color_target_info.resolve_texture = context.resolve_texture;
    }

    var depth_stencil_target_info: sdl.SDL_GPUDepthStencilTargetInfo = .{
        .texture = context.depth_stencil_texture,
        .cycle = true,
        .clear_depth = 1,
        .clear_stencil = 0,
        .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl.SDL_GPU_STOREOP_STORE,
        .stencil_load_op = sdl.SDL_GPU_LOADOP_CLEAR,
        .stencil_store_op = sdl.SDL_GPU_STOREOP_STORE,
    };

    frame.render_pass = sdl.SDL_BeginGPURenderPass(
        frame.command_buffer,
        &frame.color_target_info,
        1,
        &depth_stencil_target_info,
    );
    sdl.SDL_BindGPUGraphicsPipeline(frame.render_pass, context.fill_pipeline);
    sdl.SDL_BindGPUVertexBuffers(frame.render_pass, 0, &.{ .buffer = context.cube_mesh.vertex_buffer, .offset = 0 }, 1);
    sdl.SDL_BindGPUIndexBuffer(
        frame.render_pass,
        &.{ .buffer = context.cube_mesh.index_buffer, .offset = 0 },
        sdl.SDL_GPU_INDEXELEMENTSIZE_16BIT,
    );

    return frame;
}

pub fn drawCube(context: *RendererContext, frame: *FrameContext, transform: Transform, color: Color) void {
    const model_matrix: Matrix4x4 = Camera.calculateModelMatrix(transform);
    var mvp = frame.view_projection.multiply(model_matrix);
    sdl.SDL_PushGPUVertexUniformData(frame.command_buffer, 0, &mvp, @sizeOf(Matrix4x4));

    const uniforms: CubeUniforms = .{ .color = color };
    sdl.SDL_PushGPUFragmentUniformData(frame.command_buffer, 0, &uniforms, @sizeOf(CubeUniforms));

    sdl.SDL_DrawGPUIndexedPrimitives(frame.render_pass, context.cube_mesh.index_count, 1, 0, 0, 0);
}

pub fn compositeToSwapchain(
    context: *RendererContext,
    frame: *FrameContext,
    uniforms: FragmentUniforms,
) *sdl.SDL_GPUTexture {
    sdl.SDL_EndGPURenderPass(frame.render_pass);

    const command_buffer_submitted = sdl.SDL_SubmitGPUCommandBuffer(frame.command_buffer);
    sdl_utils.panic(command_buffer_submitted, "Failed to submit GPU command buffer");
    frame.command_buffer = sdl.SDL_AcquireGPUCommandBuffer(context.gpu_device);

    const swapchain_texture = device.getSwapchainTexture(context, frame) orelse
        @panic("Failed to get swapchain texture.");
    var screen_target_info: sdl.SDL_GPUColorTargetInfo = .{
        .texture = swapchain_texture,
        .clear_color = .{ .r = 0, .g = 0, .b = 1, .a = 1 },
        .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl.SDL_GPU_STOREOP_STORE,
    };
    const screen_render_pass: ?*sdl.SDL_GPURenderPass = sdl.SDL_BeginGPURenderPass(
        frame.command_buffer,
        &screen_target_info,
        1,
        null,
    );
    sdl.SDL_PushGPUFragmentUniformData(frame.command_buffer, 0, &uniforms, @sizeOf(FragmentUniforms));
    sdl.SDL_BindGPUGraphicsPipeline(screen_render_pass, context.screen_pipeline);
    sdl.SDL_BindGPUVertexBuffers(screen_render_pass, 0, &.{ .buffer = context.quad_mesh.vertex_buffer, .offset = 0 }, 1);
    sdl.SDL_BindGPUIndexBuffer(
        screen_render_pass,
        &.{ .buffer = context.quad_mesh.index_buffer, .offset = 0 },
        sdl.SDL_GPU_INDEXELEMENTSIZE_16BIT,
    );
    sdl.SDL_BindGPUFragmentSamplers(
        screen_render_pass,
        0,
        &.{
            .texture = frame.color_target_info.resolve_texture orelse frame.color_target_info.texture,
            .sampler = context.render_texture_sampler,
        },
        1,
    );
    sdl.SDL_DrawGPUIndexedPrimitives(screen_render_pass, context.quad_mesh.index_count, 1, 0, 0, 0);
    sdl.SDL_EndGPURenderPass(screen_render_pass);

    return swapchain_texture;
}

pub fn endFrame(frame: *FrameContext) void {
    const command_buffer_submitted = sdl.SDL_SubmitGPUCommandBuffer(frame.command_buffer);
    sdl_utils.panic(command_buffer_submitted, "Failed to submit GPU command buffer");
}
