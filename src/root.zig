const std = @import("std");
const c = @import("c");
const flint = @import("flint");
const sdl_utils = flint.sdl;
const sdl = flint.sdl.c;
const imgui = flint.imgui;
const math = @import("math");
const debug_ui = if (INTERNAL) @import("debug_ui.zig") else undefined;
const renderer = @import("render/renderer.zig");
const scene = @import("scene.zig");

const INTERNAL: bool = @import("build_options").internal;

pub const std_options: std.Options = .{
    .log_level = if (INTERNAL) .info else .err,
};

// Types.
const GameLib = flint.GameLib;
const FPSWindow = flint.internal.FPSWindow;
const Vector3 = math.Vector3;
const Transform = math.Transform;
const Quaternion = math.Quaternion;
const Color = math.Color;
const Color3 = math.Color3;
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
    world_id: c.b3WorldId = undefined,

    light_direction: Vector3 = .{ 0, 1, 0 },
    light_color: Color3 = .{ 1, 0.95, 0.85 },
    ambient_strength: f32 = 0.3,

    sky_color_horizon: Color3 = .{ 0.8, 0.8, 1 },
    sky_color_zenith: Color3 = .{ 0.2, 0.2, 0.75 },
    sky_color_ground: Color3 = .{ 0.3, 0.3, 0.4 },

    input: Input = .{},

    // Internal.
    internal: if (INTERNAL) extern struct {
        output: *flint.internal.DebugOutputWindow = undefined,
        inspect_game_state: bool = false,
        show_collision_bodies: bool = false,
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

    pub fn getScreenFragmentUniforms(self: *State) renderer.ScreenFragmentUniforms {
        return .{
            .time = self.currentTime(),
        };
    }
};

const Input = struct {
    mouse_position: Vector2 = .{ 0, 0 },
    mouse_delta: Vector2 = .{ 0, 0 },

    forward_button: Button = .{},
    backward_button: Button = .{},
    left_button: Button = .{},
    right_button: Button = .{},

    left_mouse: Button = .{},
    middle_mouse: Button = .{},
    right_mouse: Button = .{},

    const Button = struct {
        down: bool = false,
        pressed: bool = false,
        last_time: u64 = 0,

        pub fn update(self: *Button, is_down: bool, time: u64) void {
            self.pressed = (self.down and !is_down);
            self.down = is_down;
            self.last_time = time;
        }

        pub fn reset(self: *Button) void {
            self.pressed = false;
        }
    };

    pub fn reset(self: *Input) void {
        self.forward_button.reset();
        self.backward_button.reset();
        self.left_button.reset();
        self.right_button.reset();

        self.left_mouse.reset();
        self.middle_mouse.reset();
        self.right_mouse.reset();

        self.mouse_delta = .{ 0, 0 };
    }
};

const Entity = struct {
    transform: Transform = .{},
    color: Color = .{ 0.9, 0.3, 0.2, 1 },
    body_id: c.b3BodyId = undefined,
    is_dynamic: bool = false,
};

pub var settings: GameLib.Settings = .{
    .title = "Wildcar",
    .frame_rate = .fixed(60),
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

    state.renderer = renderer.init(
        state.dependencies.window,
        state.dependencies.gpu_device,
        &settings,
        state.dependencies.allocator.*,
        state.dependencies.io.*,
    );
    state.camera = .init(getAspectRatio());

    scene.load(state);

    return state;
}

pub export fn deinit(state_ptr: GameLib.GameStatePtr) void {
    const state: *State = @ptrCast(@alignCast(state_ptr));
    renderer.deinit(&state.renderer);
    scene.unload(state);
}

pub export fn willReload(state_ptr: GameLib.GameStatePtr) void {
    const state: *State = @ptrCast(@alignCast(state_ptr));
    renderer.deinit(&state.renderer);
    scene.unload(state);
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

    // Use this when working on camera.
    // state.camera = .init(getAspectRatio());

    scene.load(state);
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
                sdl.SDLK_C => {
                    if (INTERNAL) {
                        state.internal.show_collision_bodies = !state.internal.show_collision_bodies;
                    }
                },
                else => {},
            }
        }

        if (event.type == sdl.SDL_EVENT_KEY_DOWN or event.type == sdl.SDL_EVENT_KEY_UP) {
            const is_down = event.type == sdl.SDL_EVENT_KEY_DOWN;
            switch (event.key.scancode) {
                sdl.SDL_SCANCODE_W => {
                    state.input.forward_button.update(is_down, state.time);
                },
                sdl.SDL_SCANCODE_A => {
                    state.input.left_button.update(is_down, state.time);
                },
                sdl.SDL_SCANCODE_S => {
                    state.input.backward_button.update(is_down, state.time);
                },
                sdl.SDL_SCANCODE_D => {
                    state.input.right_button.update(is_down, state.time);
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
                    state.input.left_mouse.update(is_down, state.time);
                },
                2 => {
                    state.input.middle_mouse.update(is_down, state.time);
                },
                3 => {
                    state.input.right_mouse.update(is_down, state.time);
                },
                else => {},
            }
        }

        if (event.type == sdl.SDL_EVENT_WINDOW_RESIZED) {
            renderer.reinitWindowSize(&state.renderer, &settings);
            state.camera.setAspectRatio(getAspectRatio());
        }
    }

    return continue_running;
}

pub export fn tick(state_ptr: GameLib.GameStatePtr, time: u64, delta_time: u64) void {
    const state: *State = @ptrCast(@alignCast(state_ptr));

    state.time = time;
    state.delta_time_actual = delta_time;
    state.delta_time = if (state.paused) 0 else state.delta_time_actual;

    // Physics.
    const time_step: f32 = 1.0 / 60.0;
    const sub_step_count: u32 = 4;

    c.b3World_Step(state.world_id, time_step, sub_step_count);

    for (state.entities.items) |*entity| {
        if (entity.is_dynamic) {
            const position: c.b3Vec3 = c.b3Body_GetPosition(entity.body_id);
            const rotation: c.b3Quat = c.b3Body_GetRotation(entity.body_id);

            entity.transform.position = .{ position.x, position.y, position.z };
            entity.transform.rotation = .{ rotation.v.x, rotation.v.y, rotation.v.z, rotation.s };
        }
    }

    // Camera.
    {
        const mouse_delta = state.input.mouse_delta * @as(Vector2, @splat(state.deltaTimeActual()));
        const keyboard_speed: f32 = 0.1;

        if (state.input.left_mouse.down) {
            state.camera.orbit(mouse_delta);
        }

        if (state.input.middle_mouse.down) {
            state.camera.zoom(mouse_delta[Y]);
        }

        if (state.camera.mode == .Orbit) {
            if (state.input.middle_mouse.down) {
                state.camera.zoom(mouse_delta[Y]);
            }
        } else if (state.camera.mode == .Free) {
            if (state.input.middle_mouse.down) {
                state.camera.dolly(mouse_delta[Y]);
            }

            if (state.input.forward_button.down) {
                state.camera.dolly(keyboard_speed);
            }
            if (state.input.backward_button.down) {
                state.camera.dolly(-keyboard_speed);
            }
            if (state.input.left_button.down) {
                state.camera.pan(.{ -keyboard_speed, 0 });
            }
            if (state.input.right_button.down) {
                state.camera.pan(.{ keyboard_speed, 0 });
            }
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
        renderer.drawSky(
            &state.renderer,
            &frame_context,
            &state.camera,
            .{
                .horizon_color = state.sky_color_horizon,
                .zenith_color = state.sky_color_zenith,
                .ground_color = state.sky_color_ground,
            },
        );
        const ambient_color =
            ((state.sky_color_horizon + state.sky_color_zenith) / @as(Color3, @splat(2))) *
            @as(Color3, @splat(state.ambient_strength));

        for (state.entities.items) |entity| {
            renderer.drawCube(&state.renderer, &frame_context, entity.transform, .{
                .color = entity.color,
                .light_color = state.light_color,
                .light_direction = state.light_direction,
                .ambient_color = ambient_color,
            });

            if (INTERNAL) {
                if (state.internal.show_collision_bodies) {
                    const body_transform: c.b3Transform = c.b3Body_GetTransform(entity.body_id);

                    renderer.drawLineCube(&state.renderer, &frame_context, .{
                        .position = .{ body_transform.p.x, body_transform.p.y, body_transform.p.z },
                        .scale = entity.transform.scale,
                        .rotation = .{
                            body_transform.q.v.x,
                            body_transform.q.v.y,
                            body_transform.q.v.z,
                            body_transform.q.s,
                        },
                    }, .{
                        .color = if (entity.is_dynamic) .{ 0, 1, 0, 1 } else .{ 1, 1, 0, 1 },
                        .light_direction = state.light_direction,
                        .light_color = state.light_color,
                        .ambient_color = ambient_color,
                    });
                }
            }
        }

        const swapchain_texture = renderer.compositeToSwapchain(
            &state.renderer,
            &frame_context,
            state.getScreenFragmentUniforms(),
        );

        if (INTERNAL) debug_ui.draw(state, &frame_context, swapchain_texture);
    }
    renderer.endFrame(&frame_context);
}
