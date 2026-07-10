const std = @import("std");
const flint = @import("flint");
const sdl_utils = flint.sdl;
const sdl = flint.sdl.c;
const imgui = flint.imgui;
const math = @import("math");
const renderer = @import("render/renderer.zig");

const INTERNAL: bool = @import("build_options").internal;

pub const std_options: std.Options = .{
    .log_level = if (INTERNAL) .info else .err,
};

// Types.
const Vector3 = math.Vector3;
const GameLib = flint.GameLib;
const FPSWindow = flint.internal.FPSWindow;

pub const State = struct {
    dependencies: GameLib.Dependencies.Full3D,

    allocator: std.mem.Allocator,

    window: *sdl.SDL_Window,
    device: *sdl.SDL_GPUDevice,
    fill_pipeline: *sdl.SDL_GPUGraphicsPipeline = undefined,
    line_pipeline: *sdl.SDL_GPUGraphicsPipeline = undefined,
    screen_pipeline: *sdl.SDL_GPUGraphicsPipeline = undefined,

    quad_mesh: renderer.MeshBuffer = undefined,
    cube_mesh: renderer.MeshBuffer = undefined,

    render_texture_format: sdl.SDL_GPUTextureFormat = undefined,
    render_texture_sample_count: sdl.SDL_GPUSampleCount = sdl.SDL_GPU_SAMPLECOUNT_1,
    render_texture: *sdl.SDL_GPUTexture = undefined,
    render_texture_sampler: *sdl.SDL_GPUSampler = undefined,
    resolve_texture: *sdl.SDL_GPUTexture = undefined,
    depth_stencil_format: sdl.SDL_GPUTextureFormat = undefined,
    depth_stencil_texture: *sdl.SDL_GPUTexture = undefined,

    fullscreen: bool = false,

    paused: bool = false,
    time: u64 = 0,
    delta_time: u64 = 0,
    delta_time_actual: u64 = 0,

    camera: renderer.Camera,
    entities: std.ArrayList(Entity),

    // Internal.
    internal: if (INTERNAL) extern struct {
        output: *flint.internal.DebugOutputWindow = undefined,
        inspect_game_state: bool = false,
    } else extern struct {} = undefined,

    pub fn currentTime(self: *State) f32 {
        return @as(f32, @floatFromInt(self.time)) / 1000;
    }

    pub fn deltaTime(self: *State) f32 {
        return @as(f32, @floatFromInt(self.delta_time)) / 1000;
    }

    pub fn deltaTimeActual(self: *State) f32 {
        return @as(f32, @floatFromInt(self.delta_time_actual)) / 1000;
    }

    pub fn getFragmentUniforms(self: *State) renderer.FragmentUniforms {
        return .{
            .time = self.currentTime(),
        };
    }
};

pub const Entity = struct {
    position: Vector3 = .{ 0, 0, 0 },
    scale: Vector3 = .{ 1, 1, 1 },
    rotation: Vector3 = .{ 0, 0, 0 },
};

pub var settings: GameLib.Settings = .{
    .title = "Wildcar",
};

pub export fn getSettings() GameLib.Settings {
    return settings;
}

pub export fn initFull3D(dependencies: GameLib.Dependencies.Full3D) GameLib.GameStatePtr {
    var allocator = dependencies.allocator;

    var state: *State = allocator.create(State) catch @panic("Out of memory.");
    state.* = .{
        .allocator = allocator.*,
        .dependencies = dependencies,
        .window = dependencies.window,
        .device = dependencies.gpu_device,
        .time = sdl.SDL_GetTicks(),
        .camera = undefined,
        .entities = .empty,
    };

    if (INTERNAL) {
        imgui.setup(state.dependencies.internal.imgui_context, .GPU);
        state.internal.output = dependencies.internal.output;
    }

    const new_entity = state.entities.addOne(state.allocator) catch @panic("Failed to add entity");
    new_entity.* = .{};

    renderer.init(state, &settings);

    return state;
}

pub export fn deinit(state_ptr: GameLib.GameStatePtr) void {
    const state: *State = @ptrCast(@alignCast(state_ptr));
    renderer.deinit(state);
}

pub export fn willReload(state_ptr: GameLib.GameStatePtr) void {
    const state: *State = @ptrCast(@alignCast(state_ptr));
    renderer.deinit(state);
}

pub export fn reloaded(state_ptr: GameLib.GameStatePtr, imgui_context: ?*imgui.ImGuiContext) void {
    const state: *State = @ptrCast(@alignCast(state_ptr));

    if (INTERNAL) {
        state.dependencies.internal.imgui_context = imgui_context.?;
        imgui.setup(imgui_context, .GPU);
    }

    renderer.init(state, &settings);
}

pub export fn processInput(state_ptr: GameLib.GameStatePtr) bool {
    const state: *State = @ptrCast(@alignCast(state_ptr));

    var continue_running: bool = true;
    var event: sdl.SDL_Event = undefined;
    while (sdl.SDL_PollEvent(&event)) {
        const event_used = if (INTERNAL) imgui.processEvent(&event) else false;
        if (event_used) {
            continue;
        }

        if (event.type == sdl.SDL_EVENT_QUIT or
            (event.type == sdl.SDL_EVENT_KEY_DOWN and event.key.key == sdl.SDLK_ESCAPE))
        {
            continue_running = false;
            break;
        }

        if (event.type == sdl.SDL_EVENT_KEY_DOWN) {
            switch (event.key.key) {
                sdl.SDLK_P => {
                    state.paused = !state.paused;
                },
                sdl.SDLK_F => {
                    state.fullscreen = !state.fullscreen;
                    _ = sdl.SDL_SetWindowFullscreen(state.window, state.fullscreen);
                },
                sdl.SDLK_F1 => {
                    if (INTERNAL) {
                        state.dependencies.internal.fps_window.cycleMode();
                    }
                },
                sdl.SDLK_F2 => {
                    if (INTERNAL) {
                        state.dependencies.internal.memory_usage_window.visible =
                            !state.dependencies.internal.memory_usage_window.visible;
                    }
                },
                sdl.SDLK_G => {
                    if (INTERNAL) {
                        state.internal.inspect_game_state = !state.internal.inspect_game_state;
                    }
                },
                else => {},
            }
        }

        if (event.type == sdl.SDL_EVENT_WINDOW_RESIZED) {
            renderer.reinitWindowSize(state, &settings);
        }
    }

    return continue_running;
}

pub export fn tick(state_ptr: GameLib.GameStatePtr, time: u64, delta_time: u64) void {
    const state: *State = @ptrCast(@alignCast(state_ptr));

    state.time = time;
    state.delta_time_actual = delta_time;
    state.delta_time = if (state.paused) 0 else state.delta_time_actual;

    if (INTERNAL) {
        state.dependencies.internal.fps_window.addFrameTime(sdl.SDL_GetPerformanceCounter());
    }
}

pub export fn draw(state_ptr: GameLib.GameStatePtr) void {
    const state: *State = @ptrCast(@alignCast(state_ptr));

    var frame_context = renderer.beginFrame(state);

    for (state.entities.items) |entity| {
        renderer.drawCube(state, &frame_context, entity);
    }

    renderer.endFrame(state, &frame_context);
}
