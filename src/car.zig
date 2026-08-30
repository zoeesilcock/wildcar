const std = @import("std");
const c = @import("c");
const flint = @import("flint");
const math = @import("math");
const game = @import("root.zig");
const renderer = @import("render/renderer.zig");
const debug_shapes = if (INTERNAL) @import("debug_shapes.zig") else undefined;
const b3 = @import("b3.zig");

const INTERNAL: bool = @import("build_options").internal;

// Types.
const Entity = game.Entity;
const Transform = math.Transform;
const Quaternion = math.Quaternion;
const Vector3 = math.Vector3;
const X = math.X;
const Y = math.Y;
const Z = math.Z;

const WheelSpec = struct {
    model_id: renderer.ModelId,
    model_index: u32,
    radius: f32, // M.
    drive: bool = false,
    steer: bool = false,
};

pub const Spec = struct {
    model_id: renderer.ModelId,
    model_name: []const u8,

    wheels: []const WheelSpec,

    mass: f32, // Kg.
    engine_power: f32, // kW.
    max_acceleration: f32, // M/s².
    max_braking_deceleration: f32, // M/s².

    max_steering_angle: f32,
    lateral_stiffness: f32, // N / (m/s).
    friction_coefficient: f32,
    suspension_max_extension: f32, // M.
    suspension_max_compression: f32, // M.
    suspension_stiffness: f32, // N / m.
    suspension_damping_ratio: f32,
    suspension_bump_stop_start: f32, // M.
    suspension_bump_stop_stiffness: f32, // N / m.
    suspension_bump_stop_damping_ratio: f32,

    pub fn driveWheelCount(self: *const Spec) u32 {
        var result: u32 = 0;
        for (self.wheels) |wheel| {
            if (wheel.drive) {
                result += 1;
            }
        }
        return result;
    }

    pub fn loadFromFile(path: []const u8, allocator: std.mem.Allocator, io: std.Io) *Spec {
        const spec: *Spec = allocator.create(Spec) catch @panic("OOM");
        errdefer allocator.destroy(spec);

        if (flint.fs.getFilePathRelative(io, path, allocator)) |relative_path| {
            defer allocator.free(relative_path);

            const scene_file = flint.fs.openFileRelative(io, relative_path, .{ .mode = .read_only }) catch
                @panic("Failed to open car spec file");
            defer scene_file.close(io);

            const spec_slice = std.Io.Dir.cwd().readFileAllocOptions(io, path, allocator, .unlimited, .@"1", 0) catch
                @panic("Failed to read car spec file");
            defer allocator.free(spec_slice);

            var diagnostics: std.zon.parse.Diagnostics = .{};
            defer diagnostics.deinit(allocator);

            spec.* = std.zon.parse.fromSliceAlloc(Spec, allocator, spec_slice, &diagnostics, .{}) catch {
                std.log.err("Errors in car spec .zon file:\n{f}", .{diagnostics});
                @panic("Failed to parse car spec .zon file");
            };
        } else |_| {
            @panic("Failed to open car spec file for reading");
        }

        return spec;
    }

    pub fn saveToFile(self: Spec, path: []const u8, allocator: std.mem.Allocator, io: std.Io) void {
        if (flint.fs.getFilePathRelative(io, path, allocator)) |relative_path| {
            defer allocator.free(relative_path);

            const scene_file = flint.fs.createFileRelative(io, relative_path, .{}) catch
                @panic("Failed to open car spec file");
            defer scene_file.close(io);

            var buf: [1024]u8 = undefined;
            var file_writer = scene_file.writer(io, &buf);
            const writer = &file_writer.interface;

            std.zon.stringify.serialize(self, .{
                .emit_default_optional_fields = false,
            }, writer) catch @panic("Failed to stringify car spec");
            writer.flush() catch undefined;
        } else |_| {
            @panic("Failed to open car spec file for saving");
        }
    }

    pub fn loadModel(
        self: *const Spec,
        context: *renderer.RendererContext,
        allocator: std.mem.Allocator,
        io: std.Io,
    ) void {
        var import_array = std.ArrayList(renderer.ImportModel).initCapacity(allocator, 5) catch @panic("OOM");

        import_array.append(allocator, .{ .id = self.model_id }) catch @panic("OOM");
        for (self.wheels) |wheel| {
            import_array.append(allocator, .{ .id = wheel.model_id, .index = wheel.model_index }) catch @panic("OOM");
        }

        const imports: []renderer.ImportModel = import_array.toOwnedSlice(allocator) catch @panic("OOM");
        defer allocator.free(imports);

        const model_path = std.fmt.allocPrint(allocator, "assets/models/{s}", .{self.model_name}) catch @panic("OOM");
        defer allocator.free(model_path);
        context.importModel(model_path, imports, allocator, io);
    }
};

pub const State = struct {
    wheel_transforms: [4]Transform = @splat(.{}),
    wheel_roll_signs: [4]f32 = @splat(1),
    wheel_spin_angles: [4]f32 = @splat(0),
    mass_per_wheel: f32 = 0,

    fn setWheels(self: *State, wheels: *[4]Entity) void {
        const car_forward: Vector3 = .{ -1, 0, 0 };
        const car_up: Vector3 = .{ 0, 1, 0 };
        const local_axle: Vector3 = .{ 0, 0, 1 };
        const expected_roll_axis = math.crossV3(car_forward, car_up);

        for (wheels, 0..) |wheel, i| {
            self.wheel_transforms[i] = wheel.transform;

            const car_space_axle: Vector3 = math.rotateVectorBy(local_axle, wheel.transform.rotation);
            self.wheel_roll_signs[i] = if (math.dotV3(car_space_axle, expected_roll_axis) >= 0) -1 else 1;
        }
    }
};

pub fn init(state: *game.State, car: *Entity, car_spec_name: []const u8) void {
    if (car.car_state == null) {
        car.car_state = .{};
    }

    // Load the car spec.
    const spec_path = std.fmt.allocPrint(state.allocator, "assets/cars/{s}", .{car_spec_name}) catch @panic("OOM");
    defer state.allocator.free(spec_path);
    car.car_spec = .loadFromFile(spec_path, state.allocator, state.dependencies.io.*);

    // Load the car model.
    car.car_spec.?.loadModel(&state.renderer, state.allocator, state.dependencies.io.*);

    // Spawn the wheels.
    if (car.children.len > 0) {
        // TODO: If we want to support children from the scene we will need to merge them with the wheels here instead.
        state.allocator.free(car.children);
    }
    car.children = state.allocator.alloc(Entity, car.car_spec.?.wheels.len) catch
        @panic("Failed to allocate wheel entities");
    for (car.car_spec.?.wheels, 0..) |wheel, i| {
        if (state.renderer.models.get(wheel.model_id)) |model| {
            car.children[i] = .{
                .transform = model.transform,
                .has_collider = false,
                .model_id = wheel.model_id,
                .color = .{ 1, 1, 1, 1 },
            };
        }
    }

    // Set wheel state.
    car.car_state.?.setWheels(car.children[0..4]);
    car.car_state.?.mass_per_wheel = car.car_spec.?.mass / @as(f32, @floatFromInt(car.car_spec.?.wheels.len));
}

pub fn initPhysics(car: *Entity) void {
    var mass_data = c.b3Body_GetMassData(car.body_id);
    const mass_scale: f32 = car.car_spec.?.mass / mass_data.mass;
    mass_data.mass = car.car_spec.?.mass;
    mass_data.inertia = c.b3MulSM(mass_scale, mass_data.inertia);
    c.b3Body_SetMassData(car.body_id, mass_data);
}

pub fn updatePhysics(state: *game.State, car: *Entity) void {
    var car_state: *State = &car.car_state.?;
    const car_spec: *const Spec = car.car_spec.?;
    const current_car = if (state.car_index) |car_index| &state.entities.items[car_index] else null;
    const ignore_input = state.camera.mode != .Orbit or
        // TODO: Temporary until we add an ID to the entity since this doesn't handle the case of multiple
        // cars of the same type.
        (current_car != null and car.model_id != current_car.?.model_id);
    const body_id: c.b3BodyId = car.body_id;
    const wheel_entities: []Entity = car.children[0..4];

    const center_of_mass: Vector3 = b3.b3ToVec(c.b3Body_GetWorldCenter(body_id));
    const linear_velocity: Vector3 = b3.b3ToVec(c.b3Body_GetLinearVelocity(body_id));
    const angular_velocity: Vector3 = b3.b3ToVec(c.b3Body_GetAngularVelocity(body_id));

    // Calculate engine/braking force based on player input.
    var has_engine_force: bool = false;
    var has_braking_force: bool = false;
    var longitudinal_force: Vector3 = @splat(0);
    const local_forward: Vector3 = .{ -1, 0, 0 };
    const world_forward: Vector3 = math.rotateVectorBy(local_forward, car.transform.rotation);
    const world_backward: Vector3 = -world_forward;
    const forward_velocity: f32 = math.dotV3(linear_velocity, world_forward);
    if (!ignore_input and (state.input.forward_button.down or state.input.backward_button.down)) {
        const minimum_speed: f32 = 1;
        const forward_speed: f32 = @abs(forward_velocity);
        const low_speed_force: f32 = car_spec.mass * car_spec.max_acceleration;
        const engine_force = @min(low_speed_force, car_spec.engine_power * 1000 / @max(forward_speed, minimum_speed));

        if (state.input.forward_button.down) {
            if (forward_velocity < 0) {
                has_braking_force = true;
                longitudinal_force =
                    world_forward * @as(Vector3, @splat(car_spec.mass * car_spec.max_braking_deceleration));
            } else {
                has_engine_force = true;
                longitudinal_force = world_forward * @as(Vector3, @splat(engine_force));
            }
        }

        if (state.input.backward_button.down) {
            if (forward_velocity > 0) {
                has_braking_force = true;
                longitudinal_force =
                    world_backward * @as(Vector3, @splat(car_spec.mass * car_spec.max_braking_deceleration));
            } else {
                has_engine_force = true;
                longitudinal_force = world_backward * @as(Vector3, @splat(engine_force));
            }
        }

        if (has_engine_force) {
            longitudinal_force /= @as(Vector3, @splat(@floatFromInt(car_spec.driveWheelCount())));
        } else if (has_braking_force) {
            longitudinal_force /= @as(Vector3, @splat(@floatFromInt(car_spec.wheels.len)));
        }
    }

    var steering_input: f32 = 0;
    if (!ignore_input and state.input.left_button.down) {
        steering_input = 1;
    } else if (!ignore_input and state.input.right_button.down) {
        steering_input = -1;
    }
    const steering_angle: f32 = steering_input * car_spec.max_steering_angle;
    const steering_rotation: Quaternion = math.eulerToQuaternion(.{ 0, steering_angle, 0 });

    // Calculate suspension damping.
    const suspension_critical_damping = 2 * @sqrt(car_spec.suspension_stiffness * car_state.mass_per_wheel);
    const suspension_damping_coefficient = car_spec.suspension_damping_ratio * suspension_critical_damping;
    const bump_stop_critical_damping = 2 * @sqrt(car_spec.suspension_bump_stop_stiffness * car_state.mass_per_wheel);
    const bump_stop_damping_coefficient = car_spec.suspension_bump_stop_damping_ratio * bump_stop_critical_damping;

    for (car_state.wheel_transforms, 0..) |wheel, i| {
        const wheel_spec: WheelSpec = car_spec.wheels[i];
        const is_drive_wheel: bool = wheel_spec.drive;
        const is_steer_wheel: bool = wheel_spec.steer;

        const wheel_transform = wheel.relativeTo(car.transform);
        const wheel_origin = wheel_transform.position;

        const ray_rotation: Quaternion = car.transform.rotation;
        const local_down: Vector3 = .{ 0, -1, 0 };
        const world_down: Vector3 = math.rotateVectorBy(local_down, ray_rotation);

        const epsilon_length: f32 = 0.01;
        const epsilon: Vector3 = world_down * @as(Vector3, @splat(epsilon_length)); // Avoid starting in the ground.

        const ray_length: f32 = wheel_spec.radius + car_spec.suspension_max_extension;
        const ray_origin = wheel_origin - epsilon;
        const ray_translation: Vector3 = world_down * @as(Vector3, @splat(ray_length));

        var distance = ray_length;

        // Calculate distance to ground.
        const query_filter = c.b3DefaultQueryFilter();
        const cast = c.b3World_CastRayClosest(
            state.world_id,
            b3.vecToB3(ray_origin),
            b3.vecToB3(ray_translation),
            query_filter,
        );

        if (cast.hit) {
            distance = cast.fraction * ray_length;
        }

        if (INTERNAL and state.internal.show_suspension) {
            debug_shapes.addRaycast(state, ray_origin, ray_translation, ray_rotation, distance);
        }

        // Update position of wheel mesh based on ground distance.
        const displacement_from_parked: f32 = wheel_spec.radius - distance;
        const clamped_displacement_from_parked: f32 = std.math.clamp(
            displacement_from_parked,
            -car_spec.suspension_max_extension,
            car_spec.suspension_max_compression,
        );
        wheel_entities[i].transform.position[Y] = wheel.position[Y] + clamped_displacement_from_parked;

        // Calculate the amount of spin to add to the wheel based on forward velocity.
        const wheel_angular_velocity: f32 = forward_velocity / wheel_spec.radius;
        const spin_delta: f32 = wheel_angular_velocity * state.deltaTime();
        car_state.wheel_spin_angles[i] += spin_delta;

        // Update rotation of wheel mesh based on spin and steering.
        const roll_rotation: Quaternion = math.eulerToQuaternion(
            .{ 0, 0, car_state.wheel_roll_signs[i] * car_state.wheel_spin_angles[i] },
        );
        var wheel_physics_rotation: Quaternion = car.transform.rotation;
        var wheel_visual_rotation: Quaternion = math.multiplyQuaternion(wheel.rotation, roll_rotation);
        if (is_steer_wheel) {
            wheel_physics_rotation = math.multiplyQuaternion(wheel_physics_rotation, steering_rotation);
            wheel_visual_rotation = math.multiplyQuaternion(steering_rotation, wheel_visual_rotation);
        }
        wheel_entities[i].transform.rotation = wheel_visual_rotation;

        if (cast.hit) {
            // Calculate velocity at wheel origin.
            const offset: Vector3 = wheel_origin - center_of_mass;
            const rotational_velocity: Vector3 = math.crossV3(angular_velocity, offset);
            const point_velocity: Vector3 = linear_velocity + rotational_velocity;
            const suspension_velocity: f32 = math.dotV3(point_velocity, world_down);

            // Calculate bump stop force.
            const bump_stop_range: f32 = car_spec.suspension_max_compression - car_spec.suspension_bump_stop_start;
            const bump_stop_compression: f32 = std.math.clamp(
                displacement_from_parked - car_spec.suspension_bump_stop_start,
                0,
                bump_stop_range,
            );
            const bump_stop_force: f32 = car_spec.suspension_bump_stop_stiffness * bump_stop_compression;
            const bump_stop_damping_force: f32 = if (bump_stop_compression > 0)
                bump_stop_damping_coefficient * suspension_velocity
            else
                0;

            // Calculate spring force.
            const parked_spring_force: f32 = car_state.mass_per_wheel * game.GRAVITY;
            const spring_force: f32 = parked_spring_force +
                car_spec.suspension_stiffness * clamped_displacement_from_parked +
                bump_stop_force;

            // Apply damping on the spring force.
            const damping_force: f32 = suspension_damping_coefficient * suspension_velocity;
            const support_force: f32 = @max(spring_force + damping_force + bump_stop_damping_force, 0);

            // Calculate and apply the final force for the wheel.
            const force: Vector3 = -world_down * @as(Vector3, @splat(support_force));

            // Apply suspension force to car.
            c.b3Body_ApplyForce(body_id, b3.vecToB3(force), b3.vecToB3(wheel_origin), true);

            // Calculate lateral force.
            const wheel_forward: Vector3 = math.rotateVectorBy(.{ -1, 0, 0 }, wheel_physics_rotation);
            const wheel_lateral: Vector3 = math.crossV3(wheel_forward, world_down);
            const lateral_velocity: f32 = math.dotV3(point_velocity, wheel_lateral);

            const max_tire_force: f32 = car_spec.friction_coefficient * support_force;
            const requested_lateral_force: f32 = car_spec.lateral_stiffness * lateral_velocity;
            const lateral_force: Vector3 = -wheel_lateral * @as(Vector3, @splat(requested_lateral_force));

            // Combine with engine/braking force.
            var total_force: Vector3 = lateral_force;
            if ((is_drive_wheel and has_engine_force) or has_braking_force) {
                total_force += longitudinal_force;
            }

            // Clamp total force.
            const total_force_magnitude: f32 = @sqrt(math.dotV3(total_force, total_force));
            if (total_force_magnitude > max_tire_force) {
                const scale: f32 = max_tire_force / total_force_magnitude;
                total_force *= @as(Vector3, @splat(scale));
            }

            c.b3Body_ApplyForce(body_id, b3.vecToB3(total_force), b3.vecToB3(wheel_origin), true);
        }
    }
}
