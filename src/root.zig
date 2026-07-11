const std = @import("std");
const flint = @import("flint");
const sdl_utils = flint.sdl;
const sdl = flint.sdl.c;
const imgui = flint.imgui;
const math = @import("math");
const debug_ui = if (INTERNAL) @import("debug_ui.zig") else undefined;
const renderer = @import("render/renderer.zig");

const INTERNAL: bool = @import("build_options").internal;

pub const std_options: std.Options = .{
    .log_level = if (INTERNAL) .info else .err,
};

// Types.
const GameLib = flint.GameLib;
const FPSWindow = flint.internal.FPSWindow;
const Transform = math.Transform;
const Color = math.Color;
const Vector2 = math.Vector2;
const X = math.X;
const Y = math.Y;
const Z = math.Z;

pub const State = struct {
    dependencies: GameLib.Dependencies.Full3D,

    allocator: std.mem.Allocator,

    renderer: renderer.RendererContext = undefined,

    fullscreen: bool = false,

    paused: bool = false,
    time: u64 = 0,
    delta_time: u64 = 0,
    delta_time_actual: u64 = 0,

    camera: renderer.Camera,
    entities: std.ArrayList(Entity),

    input: Input = .{},

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

const Input = struct {
    mouse_position: Vector2 = .{ 0, 0 },
    mouse_delta: Vector2 = .{ 0, 0 },

    left_mouse_down: bool = false,
    left_mouse_pressed: bool = false,
    left_mouse_last_time: u64 = 0,

    middle_mouse_down: bool = false,
    middle_mouse_pressed: bool = false,
    middle_mouse_last_time: u64 = 0,

    right_mouse_down: bool = false,
    right_mouse_pressed: bool = false,
    right_mouse_last_time: u64 = 0,

    pub fn reset(self: *Input) void {
        self.mouse_delta = .{ 0, 0 };
        self.left_mouse_pressed = false;
        self.middle_mouse_pressed = false;
        self.right_mouse_pressed = false;
    }
};

const Entity = struct {
    transform: Transform = .{},
    color: Color = .{ 0.9, 0.3, 0.2, 1 },
};

pub var settings: GameLib.Settings = .{
    .title = "Wildcar",
};

pub export fn getSettings() GameLib.Settings {
    return settings;
}

fn getAspectRatio() f32 {
    return @as(f32, @floatFromInt(settings.window_width)) /
        @as(f32, @floatFromInt(settings.window_height));
}

pub export fn initFull3D(dependencies: GameLib.Dependencies.Full3D) GameLib.GameStatePtr {
    var allocator = dependencies.allocator;

    var state: *State = allocator.create(State) catch @panic("Out of memory.");
    state.* = .{
        .allocator = allocator.*,
        .dependencies = dependencies,
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

    state.renderer = renderer.init(
        state.dependencies.window,
        state.dependencies.gpu_device,
        &settings,
        state.dependencies.allocator.*,
        state.dependencies.io.*,
    );
    state.camera = .init(getAspectRatio());

    return state;
}

pub export fn deinit(state_ptr: GameLib.GameStatePtr) void {
    const state: *State = @ptrCast(@alignCast(state_ptr));
    renderer.deinit(&state.renderer);
}

pub export fn willReload(state_ptr: GameLib.GameStatePtr) void {
    const state: *State = @ptrCast(@alignCast(state_ptr));
    renderer.deinit(&state.renderer);
}

pub export fn reloaded(state_ptr: GameLib.GameStatePtr, imgui_context: ?*imgui.ImGuiContext) void {
    const state: *State = @ptrCast(@alignCast(state_ptr));

    if (INTERNAL) {
        state.dependencies.internal.imgui_context = imgui_context.?;
        imgui.setup(imgui_context, .GPU);
    }

    state.renderer = renderer.init(
        state.dependencies.window,
        state.dependencies.gpu_device,
        &settings,
        state.dependencies.allocator.*,
        state.dependencies.io.*,
    );
    state.camera = .init(getAspectRatio());
}

pub export fn processInput(state_ptr: GameLib.GameStatePtr) bool {
    const state: *State = @ptrCast(@alignCast(state_ptr));

    state.input.reset();

    var continue_running: bool = true;
    var event: sdl.SDL_Event = undefined;
    while (sdl.SDL_PollEvent(&event)) {
        const event_used = if (INTERNAL) imgui.processEvent(&event) else false;
        if (event_used) {
            continue;
        }

        // Keyboard.
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
                    _ = sdl.SDL_SetWindowFullscreen(state.dependencies.window, state.fullscreen);
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
                sdl.SDLK_F3 => {
                    state.camera.cycleMode();
                },
                sdl.SDLK_G => {
                    if (INTERNAL) {
                        state.internal.inspect_game_state = !state.internal.inspect_game_state;
                    }
                },
                else => {},
            }
        }

        // Mouse movement.
        if (event.type == sdl.SDL_EVENT_MOUSE_MOTION) {
            const new_position: Vector2 = .{ event.motion.x, event.motion.y };
            state.input.mouse_delta = state.input.mouse_position - new_position;
            state.input.mouse_position = new_position;
        }

        // Mouse buttons.
        if (event.type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN or event.type == sdl.SDL_EVENT_MOUSE_BUTTON_UP) {
            const is_down = event.type == sdl.SDL_EVENT_MOUSE_BUTTON_DOWN;

            switch (event.button.button) {
                1 => {
                    state.input.left_mouse_pressed = (state.input.left_mouse_down and !is_down);
                    state.input.left_mouse_down = is_down;
                },
                2 => {
                    state.input.middle_mouse_pressed = (state.input.middle_mouse_down and !is_down);
                    state.input.middle_mouse_down = is_down;
                },
                3 => {
                    state.input.right_mouse_pressed = (state.input.right_mouse_down and !is_down);
                    state.input.right_mouse_down = is_down;
                },
                else => {},
            }
        }

        if (event.type == sdl.SDL_EVENT_WINDOW_RESIZED) {
            renderer.reinitWindowSize(&state.renderer, &settings);
        }
    }

    return continue_running;
}

pub export fn tick(state_ptr: GameLib.GameStatePtr, time: u64, delta_time: u64) void {
    const state: *State = @ptrCast(@alignCast(state_ptr));

    state.time = time;
    state.delta_time_actual = delta_time;
    state.delta_time = if (state.paused) 0 else state.delta_time_actual;

    // Camera.
    {
        const mouse_delta = state.input.mouse_delta * @as(Vector2, @splat(state.deltaTimeActual()));
        if (state.input.left_mouse_down) {
            state.camera.orbit(mouse_delta);
        }

        if (state.input.middle_mouse_down) {
            state.camera.zoom(mouse_delta[Y]);
        }

        if (state.input.middle_mouse_down) {
            state.camera.zoom(mouse_delta[Y]);
        }

        if (state.camera.mode == .Free) {
            // WASD movement.
        }
    }

    if (INTERNAL) {
        state.dependencies.internal.fps_window.addFrameTime(sdl.SDL_GetPerformanceCounter());
    }
}

pub export fn draw(state_ptr: GameLib.GameStatePtr) void {
    const state: *State = @ptrCast(@alignCast(state_ptr));

    var frame_context = renderer.beginFrame(&state.renderer, &state.camera);
    {
        for (state.entities.items) |entity| {
            renderer.drawCube(&state.renderer, &frame_context, entity.transform, entity.color);
        }

        const swapchain_texture = renderer.compositeToSwapchain(
            &state.renderer,
            &frame_context,
            state.getFragmentUniforms(),
        );

        if (INTERNAL) debug_ui.draw(state, &frame_context, swapchain_texture);
    }
    renderer.endFrame(&frame_context);
}
