const std = @import("std");
const flint = @import("flint");
const sdl = flint.sdl.c;
const sdl_utils = flint.sdl;
const math = @import("math");
const device = @import("device.zig");
const pipeline = @import("pipeline.zig");
const buffer = @import("buffer.zig");
const gltf = @import("../gltf.zig");

// Types.
pub const Camera = @import("camera.zig").Camera;
const MeshBuffer = @import("buffer.zig").MeshBuffer;
const Model = @import("model.zig").Model;
const Transform = math.Transform;
const Color = math.Color;
const Vector3 = math.Vector3;
const Settings = flint.GameLib.Settings;
const Matrix4x4 = math.Matrix4x4;

pub const ModelId = enum(u32) {
    Cube,
    DefaultCar,
    DefaultWheel1,
    DefaultWheel2,
    DefaultWheel3,
    DefaultWheel4,
    Truck,
    TruckWheel1,
    TruckWheel2,
    TruckWheel3,
    TruckWheel4,
    Cone,
};

pub const ImportModel = struct {
    id: ModelId,
    index: u32 = 0,
};

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

    shadow_depth_texture: *sdl.SDL_GPUTexture = undefined,
    shadow_depth_texture_sampler: *sdl.SDL_GPUSampler = undefined,

    // Pipeline.
    fill_pipeline: *sdl.SDL_GPUGraphicsPipeline = undefined,
    line_pipeline: *sdl.SDL_GPUGraphicsPipeline = undefined,
    debug_shape_pipeline: *sdl.SDL_GPUGraphicsPipeline = undefined,
    screen_pipeline: *sdl.SDL_GPUGraphicsPipeline = undefined,
    sky_pipeline: *sdl.SDL_GPUGraphicsPipeline = undefined,
    shadow_pipeline: *sdl.SDL_GPUGraphicsPipeline = undefined,

    quad_mesh_buffer: MeshBuffer = undefined,

    white_texture: *TextureResource = undefined,

    models: std.AutoHashMap(ModelId, *const Model) = undefined,
    model_textures: std.AutoHashMap(ModelId, *const TextureResource) = undefined,
    mesh_buffers: std.AutoHashMap(ModelId, MeshBuffer) = undefined,

    pub fn getMeshBuffer(self: *RendererContext, model_id: ModelId) ?*const MeshBuffer {
        return self.mesh_buffers.getPtr(model_id);
    }

    pub fn importModel(
        context: *RendererContext,
        path: []const u8,
        imports: []const ImportModel,
        allocator: std.mem.Allocator,
        io: std.Io,
    ) void {
        std.log.info("Importing model: {s}", .{path});

        if ((gltf.loadGLB(path, allocator, io) catch @panic("Failed to load model"))) |models| {
            for (imports) |import| {
                const mesh_buffer = buffer.uploadWorldMesh(context, models[import.index].mesh);
                context.mesh_buffers.put(import.id, mesh_buffer) catch @panic("OOM");
                context.models.put(import.id, &models[import.index]) catch @panic("OOM");

                if (models[import.index].texture) |texture| {
                    const sdl_io = sdl_utils.panicIfNull(
                        sdl.SDL_IOFromConstMem(@ptrCast(@constCast(texture.data.ptr)), texture.data.len),
                        "Failed to open texture bytes.",
                    );
                    const surface: *sdl.SDL_Surface = sdl_utils.panicIfNull(
                        sdl.SDL_LoadPNG_IO(sdl_io, true),
                        "Failed to decode PNG texture",
                    );
                    defer sdl.SDL_DestroySurface(surface);

                    const texture_resource = TextureResource.create(
                        context,
                        allocator,
                        @intCast(surface.w),
                        @intCast(surface.h),
                        texture.getSamplerCreateInfo(),
                    );

                    buffer.uploadTexture(context, surface, texture_resource.texture);
                    context.model_textures.put(import.id, texture_resource) catch @panic("OOM");
                }
            }
        }
    }
};

pub const FrameContext = struct {
    bound_pipeline: ?*sdl.SDL_GPUGraphicsPipeline = null,
    bound_mesh: ?*const MeshBuffer = null,

    command_buffer: ?*sdl.SDL_GPUCommandBuffer = null,
    render_pass: ?*sdl.SDL_GPURenderPass = null,
    color_target_info: sdl.SDL_GPUColorTargetInfo = undefined,
    view_projection: Matrix4x4 = undefined,
    light_view_projection: Matrix4x4 = undefined,
};

pub const TextureResource = struct {
    texture: *sdl.SDL_GPUTexture,
    sampler: *sdl.SDL_GPUSampler,

    pub fn create(
        context: *RendererContext,
        allocator: std.mem.Allocator,
        width: u32,
        height: u32,
        sampler_info: sdl.SDL_GPUSamplerCreateInfo,
    ) *TextureResource {
        var texture_resource: *TextureResource = allocator.create(TextureResource) catch @panic("OOM");

        if (sdl.SDL_CreateGPUTexture(context.gpu_device, &.{
            .type = sdl.SDL_GPU_TEXTURETYPE_2D,
            .format = sdl.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
            .usage = sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
            .width = @intCast(width),
            .height = @intCast(height),
            .layer_count_or_depth = 1,
            .num_levels = 1,
        })) |gpu_texture| {
            texture_resource.texture = gpu_texture;
        } else {
            @panic("Failed to create GPU texture");
        }

        if (sdl.SDL_CreateGPUSampler(context.gpu_device, &sampler_info)) |sampler| {
            texture_resource.sampler = sampler;
        } else {
            @panic("Failed to create texture sampler");
        }

        return texture_resource;
    }

    pub fn deinit(self: *const TextureResource, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

const LambertVertexUniforms = extern struct {
    mvp: Matrix4x4,
    model: Matrix4x4,
};

const LambertFragmentUniforms = extern struct {
    color: [4]f32,
};

const LightFragmentUniforms = extern struct {
    light_view_projection: [16]f32 = @splat(0),
    light_direction: [3]f32,
    _pad1: f32 = 0,
    light_color: [3]f32,
    _pad2: f32 = 0,
    ambient_color: [3]f32,
    _pad3: f32 = 0,
};

const ShadowVertexUniforms = extern struct {
    light_mvp: Matrix4x4,
};

pub const SkyVertexUniforms = extern struct {
    cam_forward: [3]f32,
    tan_half_fov: f32, // Filling a spot that would otherwise require padding, don't re-order.
    cam_right: [3]f32,
    aspect: f32, // Filling a spot that would otherwise require padding, don't re-order.
    cam_up: [3]f32,
};

pub const SkyFragmentUniforms = extern struct {
    horizon_color: [3]f32,
    _pad1: f32 = 0,
    zenith_color: [3]f32,
    _pad2: f32 = 0,
    ground_color: [3]f32,
    _pad3: f32 = 0,
    light_color: [3]f32,
    _pad4: f32 = 0,
    light_direction: [3]f32,
    _pad5: f32 = 0,
};

pub const ScreenFragmentUniforms = extern struct {
    time: f32,
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

pub fn deinit(context: *RendererContext, allocator: std.mem.Allocator) void {
    pipeline.deinit(context, allocator);
    device.deinitWindowSize(context);
}

pub fn reinitWindowSize(context: *RendererContext, settings: *Settings) void {
    device.deinitWindowSize(context);
    device.initWindowSize(context, &settings.window_width, &settings.window_height);
}

pub fn beginFrame(context: *RendererContext, camera: *const Camera, light_direction: Vector3) FrameContext {
    var frame: FrameContext = .{
        .view_projection = camera.calculateViewProjectionMatrix(),
        .light_view_projection = Camera.calculateDirectionalLightViewProjectionMatrix(light_direction, camera.target),
    };

    frame.command_buffer = sdl_utils.panicIfNull(
        sdl.SDL_AcquireGPUCommandBuffer(context.gpu_device),
        "Failed to acquire GPU command buffer",
    );

    return frame;
}

pub fn beginShadowPass(context: *RendererContext, frame: *FrameContext) void {
    frame.bound_pipeline = null;
    frame.bound_mesh = null;

    var depth_stencil_target_info: sdl.SDL_GPUDepthStencilTargetInfo = .{
        .texture = context.shadow_depth_texture,
        .cycle = true,
        .clear_depth = 0,
        .clear_stencil = 0,
        .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl.SDL_GPU_STOREOP_STORE,
        .stencil_load_op = sdl.SDL_GPU_LOADOP_CLEAR,
        .stencil_store_op = sdl.SDL_GPU_STOREOP_STORE,
    };

    frame.render_pass = sdl.SDL_BeginGPURenderPass(frame.command_buffer, null, 0, &depth_stencil_target_info);
}

pub fn beginDrawPass(context: *RendererContext, frame: *FrameContext) void {
    sdl.SDL_EndGPURenderPass(frame.render_pass);

    frame.bound_pipeline = null;
    frame.bound_mesh = null;

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
        .clear_depth = 0,
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
}

fn bindFillPipeline(context: *RendererContext, frame: *FrameContext, opt_texture: ?*const TextureResource) void {
    if (frame.bound_pipeline != context.fill_pipeline) {
        sdl.SDL_BindGPUGraphicsPipeline(frame.render_pass, context.fill_pipeline);
        frame.bound_pipeline = context.fill_pipeline;
    }

    sdl.SDL_BindGPUFragmentSamplers(
        frame.render_pass,
        0,
        &.{
            .texture = context.shadow_depth_texture,
            .sampler = context.shadow_depth_texture_sampler,
        },
        1,
    );

    if (opt_texture) |texture| {
        sdl.SDL_BindGPUFragmentSamplers(
            frame.render_pass,
            1,
            &.{
                .texture = texture.texture,
                .sampler = texture.sampler,
            },
            1,
        );
    }
}

fn bindLinePipeline(context: *RendererContext, frame: *FrameContext) void {
    if (frame.bound_pipeline != context.line_pipeline) {
        sdl.SDL_BindGPUGraphicsPipeline(frame.render_pass, context.line_pipeline);
        frame.bound_pipeline = context.line_pipeline;
    }
}

fn bindDebugShapePipeline(context: *RendererContext, frame: *FrameContext) void {
    if (frame.bound_pipeline != context.debug_shape_pipeline) {
        sdl.SDL_BindGPUGraphicsPipeline(frame.render_pass, context.debug_shape_pipeline);
        frame.bound_pipeline = context.debug_shape_pipeline;
    }
}

fn bindShadowPipeline(context: *RendererContext, frame: *FrameContext) void {
    if (frame.bound_pipeline != context.shadow_pipeline) {
        sdl.SDL_BindGPUGraphicsPipeline(frame.render_pass, context.shadow_pipeline);
        frame.bound_pipeline = context.shadow_pipeline;
    }
}

fn bindMeshBuffer(frame: *FrameContext, mesh_buffer: *const MeshBuffer) void {
    if (frame.bound_mesh != mesh_buffer) {
        sdl.SDL_BindGPUVertexBuffers(frame.render_pass, 0, &.{
            .buffer = mesh_buffer.vertex_buffer,
            .offset = 0,
        }, 1);
        sdl.SDL_BindGPUIndexBuffer(frame.render_pass, &.{
            .buffer = mesh_buffer.index_buffer,
            .offset = 0,
        }, sdl.SDL_GPU_INDEXELEMENTSIZE_16BIT);
        frame.bound_mesh = mesh_buffer;
    }
}

fn bindSkyPipeline(context: *RendererContext, frame: *FrameContext) void {
    if (frame.bound_pipeline != context.sky_pipeline) {
        sdl.SDL_BindGPUGraphicsPipeline(frame.render_pass, context.sky_pipeline);
        frame.bound_pipeline = context.sky_pipeline;
    }
}

fn bindScreenPipeline(context: *RendererContext, frame: *FrameContext) void {
    if (frame.bound_pipeline != context.screen_pipeline) {
        sdl.SDL_BindGPUGraphicsPipeline(frame.render_pass, context.screen_pipeline);
    }

    if (frame.bound_mesh != &context.quad_mesh_buffer) {
        sdl.SDL_BindGPUVertexBuffers(frame.render_pass, 0, &.{ .buffer = context.quad_mesh_buffer.vertex_buffer, .offset = 0 }, 1);
        sdl.SDL_BindGPUIndexBuffer(
            frame.render_pass,
            &.{ .buffer = context.quad_mesh_buffer.index_buffer, .offset = 0 },
            sdl.SDL_GPU_INDEXELEMENTSIZE_16BIT,
        );
        frame.bound_pipeline = context.screen_pipeline;
    }

    sdl.SDL_BindGPUFragmentSamplers(
        frame.render_pass,
        0,
        &.{
            .texture = frame.color_target_info.resolve_texture orelse frame.color_target_info.texture,
            .sampler = context.render_texture_sampler,
        },
        1,
    );
}

pub fn drawSky(
    context: *RendererContext,
    frame: *FrameContext,
    camera: *Camera,
    fragment_uniforms: SkyFragmentUniforms,
) void {
    bindSkyPipeline(context, frame);

    const basis = camera.getViewBasis();
    const vertex_uniforms = SkyVertexUniforms{
        .cam_forward = -basis.back,
        .cam_right = basis.right,
        .cam_up = basis.up,
        .tan_half_fov = @tan(camera.fov * 0.5),
        .aspect = camera.aspect_ratio,
    };
    sdl.SDL_PushGPUVertexUniformData(frame.command_buffer, 0, &vertex_uniforms, @sizeOf(SkyVertexUniforms));

    sdl.SDL_PushGPUFragmentUniformData(frame.command_buffer, 0, &fragment_uniforms, @sizeOf(SkyFragmentUniforms));

    sdl.SDL_DrawGPUPrimitives(frame.render_pass, 3, 1, 0, 0);
}

pub fn submitLighting(context: *RendererContext, frame: *FrameContext, fragment_uniforms: LightFragmentUniforms) void {
    _ = context;
    sdl.SDL_PushGPUFragmentUniformData(frame.command_buffer, 1, &fragment_uniforms, @sizeOf(LightFragmentUniforms));
}

pub fn drawLineCube(
    context: *RendererContext,
    frame: *FrameContext,
    transform: Transform,
    fragment_uniforms: LambertFragmentUniforms,
) void {
    bindLinePipeline(context, frame);
    drawCubeInternal(context, frame, transform, fragment_uniforms);
}

pub fn drawDebugCube(
    context: *RendererContext,
    frame: *FrameContext,
    transform: Transform,
    fragment_uniforms: LambertFragmentUniforms,
) void {
    bindDebugShapePipeline(context, frame);
    drawCubeInternal(context, frame, transform, fragment_uniforms);
}

fn drawCubeInternal(
    context: *RendererContext,
    frame: *FrameContext,
    transform: Transform,
    fragment_uniforms: LambertFragmentUniforms,
) void {
    if (context.getMeshBuffer(.Cube)) |mesh_buffer| {
        bindMeshBuffer(frame, mesh_buffer);

        const model_matrix: Matrix4x4 = Camera.calculateModelMatrix(transform);
        const mvp = frame.view_projection.multiply(model_matrix);
        const vertex_uniforms: LambertVertexUniforms = .{ .mvp = mvp, .model = model_matrix };
        sdl.SDL_PushGPUVertexUniformData(frame.command_buffer, 0, &vertex_uniforms, @sizeOf(LambertVertexUniforms));

        sdl.SDL_PushGPUFragmentUniformData(frame.command_buffer, 0, &fragment_uniforms, @sizeOf(LambertFragmentUniforms));

        sdl.SDL_DrawGPUIndexedPrimitives(frame.render_pass, mesh_buffer.index_count, 1, 0, 0, 0);
    }
}

pub fn drawMesh(
    context: *RendererContext,
    frame: *FrameContext,
    transform: Transform,
    model_id: ModelId,
    fragment_uniforms: LambertFragmentUniforms,
) void {
    if (context.getMeshBuffer(model_id)) |mesh_buffer| {
        bindFillPipeline(context, frame, context.model_textures.get(model_id));

        bindMeshBuffer(frame, mesh_buffer);

        const model_matrix: Matrix4x4 = Camera.calculateModelMatrix(transform);
        const mvp = frame.view_projection.multiply(model_matrix);
        const vertex_uniforms: LambertVertexUniforms = .{ .mvp = mvp, .model = model_matrix };
        sdl.SDL_PushGPUVertexUniformData(frame.command_buffer, 0, &vertex_uniforms, @sizeOf(LambertVertexUniforms));

        sdl.SDL_PushGPUFragmentUniformData(frame.command_buffer, 0, &fragment_uniforms, @sizeOf(LambertFragmentUniforms));

        sdl.SDL_DrawGPUIndexedPrimitives(frame.render_pass, mesh_buffer.index_count, 1, 0, 0, 0);
    }
}

pub fn drawMeshShadow(
    context: *RendererContext,
    frame: *FrameContext,
    transform: Transform,
    model_id: ModelId,
) void {
    if (context.getMeshBuffer(model_id)) |mesh_buffer| {
        bindShadowPipeline(context, frame);

        bindMeshBuffer(frame, mesh_buffer);

        const model_matrix: Matrix4x4 = Camera.calculateModelMatrix(transform);
        const light_mvp = frame.light_view_projection.multiply(model_matrix);
        const vertex_uniforms: ShadowVertexUniforms = .{ .light_mvp = light_mvp };
        sdl.SDL_PushGPUVertexUniformData(frame.command_buffer, 0, &vertex_uniforms, @sizeOf(ShadowVertexUniforms));

        sdl.SDL_DrawGPUIndexedPrimitives(frame.render_pass, mesh_buffer.index_count, 1, 0, 0, 0);
    }
}

pub fn compositeToSwapchain(
    context: *RendererContext,
    frame: *FrameContext,
    fragment_uniforms: ScreenFragmentUniforms,
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
    frame.render_pass = sdl.SDL_BeginGPURenderPass(
        frame.command_buffer,
        &screen_target_info,
        1,
        null,
    );
    sdl.SDL_PushGPUFragmentUniformData(frame.command_buffer, 0, &fragment_uniforms, @sizeOf(ScreenFragmentUniforms));
    bindScreenPipeline(context, frame);
    sdl.SDL_DrawGPUIndexedPrimitives(frame.render_pass, context.quad_mesh_buffer.index_count, 1, 0, 0, 0);
    sdl.SDL_EndGPURenderPass(frame.render_pass);

    return swapchain_texture;
}

pub fn endFrame(frame: *FrameContext) void {
    const command_buffer_submitted = sdl.SDL_SubmitGPUCommandBuffer(frame.command_buffer);
    sdl_utils.panic(command_buffer_submitted, "Failed to submit GPU command buffer");
}
