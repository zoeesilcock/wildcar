const std = @import("std");
const c = @import("c");
const flint = @import("flint");
const sdl_utils = flint.sdl;
const sdl = flint.sdl.c;
const imgui = flint.imgui;
const math = @import("math");
const debug_ui = if (INTERNAL) @import("debug_ui.zig") else undefined;
const debug_shapes = if (INTERNAL) @import("debug_shapes.zig") else undefined;
const renderer = @import("render/renderer.zig");
const scene = @import("scene.zig");
const car = @import("car.zig");
const b3 = @import("b3.zig");

const INTERNAL: bool = @import("build_options").internal;
pub const GRAVITY = 9.81;

pub const std_options: std.Options = .{
    .log_level = if (INTERNAL) .info else .err,
};

// Types.
const GameLib = flint.GameLib;
const FPSWindow = flint.internal.FPSWindow;
const ModelId = renderer.ModelId;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Transform = math.Transform;
const Quaternion = math.Quaternion;
const Color = math.Color;
const Color3 = math.Color3;
const X = math.X;
const Y = math.Y;
const Z = math.Z;

const DAY_SEGMENTS = [_]DaySegment{
    .{
        .time = 0,
        .ambient_strength = 0.3,
        .light_direction = .{ 0, -1, 0 },
        .light_color = .{ 1, 0.15, 0.25 },
        .sky_color_horizon = .{ 0, 0, 0.2 },
        .sky_color_zenith = .{ 0, 0, 0 },
        .sky_color_ground = .{ 0, 0, 0 },
    },
    .{
        .time = 0.2,
        .ambient_strength = 0.3,
        .light_direction = .{ 0.83, -0.06, 0.55 },
        .light_color = .{ 1, 0.15, 0.25 },
        .sky_color_horizon = .{ 0.4, 0.1, 0.3 },
        .sky_color_zenith = .{ 0, 0, 0.2 },
        .sky_color_ground = .{ 0, 0, 0.1 },
    },
    .{
        .time = 0.25,
        .ambient_strength = 0.4,
        .light_direction = .{ 0.75, 0.2, 0.5 },
        .light_color = .{ 1, 0.85, 0.75 },
        .sky_color_horizon = .{ 0.6, 0.4, 0.5 },
        .sky_color_zenith = .{ 0.1, 0.1, 0.7 },
        .sky_color_ground = .{ 0.1, 0.1, 0.2 },
    },
    .{
        .time = 0.5,
        .ambient_strength = 0.6,
        .light_direction = .{ 0, 1, 0 },
        .light_color = .{ 1, 1, 0.6 },
        .sky_color_horizon = .{ 0.8, 0.8, 1 },
        .sky_color_zenith = .{ 0.2, 0.2, 0.75 },
        .sky_color_ground = .{ 0.3, 0.3, 0.4 },
    },
    .{
        .time = 0.75,
        .ambient_strength = 0.4,
        .light_direction = .{ -0.75, 0.2, -0.5 },
        .light_color = .{ 1, 0.75, 0.45 },
        .sky_color_horizon = .{ 0.6, 0.4, 0.3 },
        .sky_color_zenith = .{ 0.1, 0.1, 0.7 },
        .sky_color_ground = .{ 0.1, 0.1, 0.2 },
    },
    .{
        .time = 0.8,
        .ambient_strength = 0.3,
        .light_direction = .{ -0.83, -0.06, -0.55 },
        .light_color = .{ 1, 0.25, 0.15 },
        .sky_color_horizon = .{ 0.4, 0.1, 0.1 },
        .sky_color_zenith = .{ 0, 0, 0.2 },
        .sky_color_ground = .{ 0, 0, 0.1 },
    },
    .{
        .time = 1,
        .ambient_strength = 0.3,
        .light_direction = .{ 0, -1.0, 0 },
        .light_color = .{ 1, 0.25, 0.15 },
        .sky_color_horizon = .{ 0, 0, 0.2 },
        .sky_color_zenith = .{ 0, 0, 0 },
        .sky_color_ground = .{ 0, 0, 0 },
    },
};

const DaySegment = struct {
    time: f32,
    ambient_strength: f32,
    light_direction: Vector3,
    light_color: Color3,
    sky_color_horizon: Color3,
    sky_color_zenith: Color3,
    sky_color_ground: Color3,
};

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

    time_of_day: f32 = 0.4,
    light_direction: Vector3 = .{ 0, 1, 0 }, // Direction to light.
    light_color: Color3 = .{ 1, 0.95, 0.85 },
    ambient_strength: f32 = 0.3,

    sky_color_horizon: Color3 = .{ 0.8, 0.8, 1 },
    sky_color_zenith: Color3 = .{ 0.2, 0.2, 0.75 },
    sky_color_ground: Color3 = .{ 0.3, 0.3, 0.4 },

    input: Input = .{},

    // Internal.
    internal: if (INTERNAL) struct {
        output: *flint.internal.DebugOutputWindow = undefined,
        debug_box_count: u32 = 0,
        debug_boxes: [128]debug_shapes.Box = @splat(undefined),
        debug_ui_active: bool = false,
        inspect_game_state: bool = false,
        inspect_car_spec: bool = false,
        show_collision_bodies: bool = false,
        show_suspension: bool = false,
        reset_scene_on_reload: bool = false,
        reset_camera_on_reload: bool = false,
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

    shift_is_down: bool = false,

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

pub const Entity = struct {
    transform: Transform = .{},
    color: Color = .{ 0.9, 0.3, 0.2, 1 },
    model_id: ModelId = .Cube,
    body_id: c.b3BodyId = undefined,
    has_collider: bool = true,
    is_dynamic: bool = false,
    children: []Entity = &.{},
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
        state.internal = .{};
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
    scene.initBox3D(state);

    car.init(
        &state.entities.items[0],
        .loadFromFile("assets/cars/truck.zon", state.allocator, state.dependencies.io.*),
    );

    return state;
}

pub export fn deinit(state_ptr: GameLib.GameStatePtr) void {
    const state: *State = @ptrCast(@alignCast(state_ptr));
    renderer.deinit(&state.renderer, state.allocator);
    scene.unload(state);
    scene.deinitBox3D(state);
    car.deinit(state.allocator);
}

pub export fn willReload(state_ptr: GameLib.GameStatePtr) void {
    const state: *State = @ptrCast(@alignCast(state_ptr));
    renderer.deinit(&state.renderer, state.allocator);

    if (state.internal.reset_scene_on_reload) {
        scene.unload(state);
    }
    scene.deinitBox3D(state);
    car.deinit(state.allocator);
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

    if (state.internal.reset_camera_on_reload) {
        state.camera = .init(getAspectRatio());
    }

    if (state.internal.reset_scene_on_reload) {
        scene.load(state);
    }
    scene.initBox3D(state);

    car.init(
        &state.entities.items[0],
        .loadFromFile("assets/cars/truck.zon", state.allocator, state.dependencies.io.*),
    );
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

        if (event.key.key == sdl.SDLK_LSHIFT or event.key.key == sdl.SDLK_RSHIFT) {
            state.input.shift_is_down = event.type == sdl.SDL_EVENT_KEY_DOWN;
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
                sdl.SDLK_F4 => {
                    if (INTERNAL) {
                        state.internal.show_collision_bodies = !state.internal.show_collision_bodies;
                    }
                },
                sdl.SDLK_F5 => {
                    if (INTERNAL) {
                        state.internal.show_suspension = !state.internal.show_suspension;
                    }
                },
                sdl.SDLK_F6 => {
                    if (INTERNAL) {
                        state.internal.reset_scene_on_reload = !state.internal.reset_scene_on_reload;
                    }
                },
                sdl.SDLK_F7 => {
                    if (INTERNAL) {
                        state.internal.reset_camera_on_reload = !state.internal.reset_camera_on_reload;
                    }
                },
                sdl.SDLK_G => {
                    if (INTERNAL) {
                        state.internal.inspect_game_state = !state.internal.inspect_game_state;
                    }
                },
                sdl.SDLK_C => {
                    if (INTERNAL) {
                        state.internal.inspect_car_spec = !state.internal.inspect_car_spec;
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
            const new_position: Vector2 = .{ event.motion.xrel, event.motion.yrel };
            state.input.mouse_delta = new_position;
            state.input.mouse_position = .{ event.motion.x, event.motion.y };
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

        if (INTERNAL) {
            state.internal.debug_ui_active = state.internal.inspect_game_state or state.internal.inspect_car_spec;
        }

        if ((!INTERNAL or !state.internal.debug_ui_active) and
            (state.input.left_button.down or state.camera.mode == .Orbit))
        {
            _ = sdl.SDL_SetWindowRelativeMouseMode(state.dependencies.window, true);
        } else {
            _ = sdl.SDL_SetWindowRelativeMouseMode(state.dependencies.window, false);
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

    car.updatePhysics(state, &state.entities.items[0]);

    c.b3World_Step(state.world_id, time_step, sub_step_count);

    for (state.entities.items) |*entity| {
        if (entity.is_dynamic) {
            const position: c.b3Vec3 = c.b3Body_GetPosition(entity.body_id);
            const rotation: c.b3Quat = c.b3Body_GetRotation(entity.body_id);

            entity.transform.position = .{ position.x, position.y, position.z };
            entity.transform.rotation = .{ rotation.v.x, rotation.v.y, rotation.v.z, rotation.s };
        }
    }

    // Time of day.
    for (DAY_SEGMENTS[0 .. DAY_SEGMENTS.len - 1], 0..) |current, i| {
        const next: DaySegment = DAY_SEGMENTS[i + 1];
        if (state.time_of_day < next.time) {
            const t: f32 = (state.time_of_day - current.time) / (next.time - current.time);
            state.ambient_strength = math.lerp(current.ambient_strength, next.ambient_strength, t);
            state.light_direction = math.normalizeV3(
                math.lerpV3(current.light_direction, next.light_direction, t),
            );
            state.light_color = math.lerpV3(current.light_color, next.light_color, t);
            state.sky_color_horizon = math.lerpV3(current.sky_color_horizon, next.sky_color_horizon, t);
            state.sky_color_zenith = math.lerpV3(current.sky_color_zenith, next.sky_color_zenith, t);
            state.sky_color_ground = math.lerpV3(current.sky_color_ground, next.sky_color_ground, t);
            break;
        }
    }

    // Camera.
    {
        const keyboard_speed: f32 = if (state.input.shift_is_down) 0.4 else 0.1;
        const mouse_sensitivity: Vector2 = @splat(0.25);
        const mouse_delta = mouse_sensitivity * state.input.mouse_delta * @as(Vector2, @splat(state.deltaTimeActual()));

        if (state.camera.mode == .Orbit) {
            if (state.input.middle_mouse.down) {
                state.camera.zoom(mouse_delta[Y]);
            }

            if (state.input.shift_is_down and state.input.forward_button.down) {
                state.camera.zoom(keyboard_speed);
            }
            if (state.input.shift_is_down and state.input.backward_button.down) {
                state.camera.zoom(-keyboard_speed);
            }

            if (!INTERNAL or !state.internal.debug_ui_active) {
                state.camera.orbit(-mouse_delta);
            }
            state.camera.setTarget(state.entities.items[0].transform.position);
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

            if (state.input.left_mouse.down) {
                state.camera.orbit(mouse_delta);
            }
        }
    }

    if (INTERNAL) {
        state.dependencies.internal.fps_window.addFrameTime(sdl.SDL_GetPerformanceCounter());
    }
}

pub export fn draw(state_ptr: GameLib.GameStatePtr) void {
    const state: *State = @ptrCast(@alignCast(state_ptr));

    var frame_context = renderer.beginFrame(&state.renderer, &state.camera, state.light_direction);
    renderer.beginShadowPass(&state.renderer, &frame_context);
    {
        for (state.entities.items) |entity| {
            renderer.drawMeshShadow(&state.renderer, &frame_context, entity.transform, entity.model_id);

            for (entity.children) |child| {
                renderer.drawMeshShadow(
                    &state.renderer,
                    &frame_context,
                    child.transform.relativeTo(entity.transform),
                    child.model_id,
                );
            }
        }
    }
    renderer.beginDrawPass(&state.renderer, &frame_context);
    {
        renderer.drawSky(
            &state.renderer,
            &frame_context,
            &state.camera,
            .{
                .horizon_color = state.sky_color_horizon,
                .zenith_color = state.sky_color_zenith,
                .ground_color = state.sky_color_ground,
                .light_color = state.light_color,
                .light_direction = state.light_direction,
            },
        );

        renderer.submitLighting(
            &state.renderer,
            &frame_context,
            .{
                .light_color = state.light_color,
                .light_direction = state.light_direction,
                .ambient_color = ((state.sky_color_horizon + state.sky_color_zenith) / @as(Color3, @splat(2))) *
                    @as(Color3, @splat(state.ambient_strength)),
                .light_view_projection = frame_context.light_view_projection.values,
            },
        );

        for (state.entities.items) |entity| {
            renderer.drawMesh(
                &state.renderer,
                &frame_context,
                entity.transform,
                entity.model_id,
                .{ .color = entity.color },
            );
            if (INTERNAL) {
                debug_shapes.drawCollisionShapes(state, &frame_context, entity, null);
            }

            for (entity.children) |child| {
                renderer.drawMesh(
                    &state.renderer,
                    &frame_context,
                    child.transform.relativeTo(entity.transform),
                    child.model_id,
                    .{ .color = child.color },
                );
                if (INTERNAL) {
                    debug_shapes.drawCollisionShapes(state, &frame_context, child, entity);
                }
            }
        }
        if (INTERNAL) debug_shapes.draw(state, &frame_context);

        const swapchain_texture = renderer.compositeToSwapchain(
            &state.renderer,
            &frame_context,
            state.getScreenFragmentUniforms(),
        );

        if (INTERNAL) debug_ui.draw(state, &frame_context, swapchain_texture);
    }
    renderer.endFrame(&frame_context);
}
