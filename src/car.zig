const std = @import("std");
const c = @import("c");
const flint = @import("flint");
const math = @import("math");
const game = @import("root.zig");
const debug_shapes = if (INTERNAL) @import("debug_shapes.zig") else undefined;
const b3 = @import("b3.zig");

const INTERNAL: bool = @import("build_options").internal;

// Types.
const State = game.State;
const Entity = game.Entity;
const Transform = math.Transform;
const Quaternion = math.Quaternion;
const Vector3 = math.Vector3;
const X = math.X;
const Y = math.Y;
const Z = math.Z;

pub const Spec = struct {
    mass: f32, // Kg.

    engine_power: f32, // kW.
    max_acceleration: f32, // m/s²
    max_braking_deceleration: f32, // m/s²

    wheel_count: i32 = 4,
    wheel_radius: f32, // M.
    drive_wheels: []const usize,
    steer_wheels: []const usize,
    max_steering_angle: f32,
    lateral_grip: f32,
    suspension_parked_compression: f32,
    suspension_damping_ratio: f32,

    pub fn loadFromFile(path: []const u8, allocator: std.mem.Allocator, io: std.Io) Spec {
        var spec: Spec = undefined;
        if (flint.fs.getFilePathRelative(io, path, allocator)) |relative_path| {
            defer allocator.free(relative_path);

            const scene_file = flint.fs.openFileRelative(io, relative_path, .{ .mode = .read_only }) catch
                @panic("Failed to open car spec file");
            defer scene_file.close(io);

            const spec_slice = std.Io.Dir.cwd().readFileAllocOptions(io, path, allocator, .unlimited, .@"1", 0) catch
                @panic("Failed to read car spec file");
            defer allocator.free(spec_slice);

            spec = std.zon.parse.fromSliceAlloc(Spec, allocator, spec_slice, null, .{}) catch
                @panic("Failed to parse car spec .zon file");
        } else |_| {
            @panic("Failed to open car spec file");
        }
        return spec;
    }
};

var car_spec: Spec = undefined;
var wheel_transforms: [4]Transform = @splat(.{});
var mass_per_wheel: f32 = 0;
var suspension_stiffness: f32 = 0;
var suspension_damping_ratio: f32 = 0;
var suspension_critical_damping: f32 = 0;
var suspension_damping_coefficient: f32 = 0;

pub fn init(car: *const Entity, spec: Spec) void {
    car_spec = spec;

    mass_per_wheel = car_spec.mass / @as(f32, @floatFromInt(car_spec.wheel_count));
    suspension_stiffness = (mass_per_wheel * game.GRAVITY) / car_spec.suspension_parked_compression;
    suspension_damping_ratio = 0.7;
    suspension_critical_damping = 2 * @sqrt(suspension_stiffness * mass_per_wheel);
    suspension_damping_coefficient = suspension_damping_ratio * suspension_critical_damping;

    setWheels(car.children[0..4]);

    // Set mass.
    var mass_data = c.b3Body_GetMassData(car.body_id);
    const mass_scale: f32 = car_spec.mass / mass_data.mass;
    mass_data.mass = car_spec.mass;
    mass_data.inertia = c.b3MulSM(mass_scale, mass_data.inertia);
    c.b3Body_SetMassData(car.body_id, mass_data);
}

pub fn deinit(allocator: std.mem.Allocator) void {
    std.zon.parse.free(allocator, car_spec);
}

fn setWheels(wheels: *[4]Entity) void {
    for (wheels, 0..) |wheel, i| {
        wheel_transforms[i] = wheel.transform;
    }
}

pub fn updatePhysics(state: *State, car: *const Entity) void {
    const body_id: c.b3BodyId = car.body_id;
    const wheel_entities: []Entity = car.children[0..4];

    const center_of_mass: Vector3 = b3.b3ToVec(c.b3Body_GetWorldCenter(body_id));
    const linear_velocity: Vector3 = b3.b3ToVec(c.b3Body_GetLinearVelocity(body_id));
    const angular_velocity: Vector3 = b3.b3ToVec(c.b3Body_GetAngularVelocity(body_id));

    // Calculate engine/braking force based on player input.
    var has_engine_force: bool = false;
    var has_braking_force: bool = false;
    var wheel_force: Vector3 = @splat(0);
    if (state.input.forward_button.down or state.input.backward_button.down) {
        const local_forward: Vector3 = .{ -1, 0, 0 };
        const world_forward: Vector3 = math.rotateVectorBy(local_forward, car.transform.rotation);
        const world_backward: Vector3 = -world_forward;
        const forward_velocity: f32 = math.dotV3(linear_velocity, world_forward);
        const minimum_speed: f32 = 1;
        const forward_speed: f32 = @abs(forward_velocity);
        const low_speed_force: f32 = car_spec.mass * car_spec.max_acceleration;
        const engine_force = @min(low_speed_force, car_spec.engine_power * 1000 / @max(forward_speed, minimum_speed));

        if (state.input.forward_button.down) {
            if (forward_velocity < 0) {
                has_braking_force = true;
                wheel_force = world_forward * @as(Vector3, @splat(car_spec.mass * car_spec.max_braking_deceleration));
            } else {
                has_engine_force = true;
                wheel_force = world_forward * @as(Vector3, @splat(engine_force));
            }
        }

        if (state.input.backward_button.down) {
            if (forward_velocity > 0) {
                has_braking_force = true;
                wheel_force = world_backward * @as(Vector3, @splat(car_spec.mass * car_spec.max_braking_deceleration));
            } else {
                has_engine_force = true;
                wheel_force = world_backward * @as(Vector3, @splat(engine_force));
            }
        }

        if (has_engine_force) {
            wheel_force /= @as(Vector3, @splat(@floatFromInt(car_spec.drive_wheels.len)));
        } else if (has_braking_force) {
            wheel_force /= @as(Vector3, @splat(@floatFromInt(car_spec.wheel_count)));
        }
    }

    var steering_input: f32 = 0;
    if (state.input.left_button.down) {
        steering_input = 1;
    } else if (state.input.right_button.down) {
        steering_input = -1;
    }
    const steering_angle: f32 = steering_input * car_spec.max_steering_angle;
    const steering_rotation: Quaternion = math.eulerToQuaternion(.{ 0, steering_angle, 0 });

    for (wheel_transforms, 0..) |wheel, i| {
        const is_drive_wheel: bool = car_spec.drive_wheels[0] == i or car_spec.drive_wheels[1] == i;
        const is_steer_wheel: bool = car_spec.steer_wheels[0] == i or car_spec.steer_wheels[1] == i;

        const wheel_transform = wheel.relativeTo(car.transform);
        const wheel_origin = wheel_transform.position;

        const ray_rotation: Quaternion = car.transform.rotation;
        const local_down: Vector3 = .{ 0, -1, 0 };
        const world_down: Vector3 = math.rotateVectorBy(local_down, ray_rotation);

        const epsilon_length: f32 = 0.01;
        const epsilon: Vector3 = world_down * @as(Vector3, @splat(epsilon_length)); // Avoid starting in the ground.

        const ray_length: f32 = car_spec.wheel_radius + epsilon_length;
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
        wheel_entities[i].transform.position[Y] = wheel.position[Y] + (ray_length - distance);

        var wheel_rotation: Quaternion = car.transform.rotation;
        if (is_steer_wheel) {
            wheel_rotation = math.multiplyQuaternion(car.transform.rotation, steering_rotation);

            // Update rotation of wheel mesh.
            wheel_entities[i].transform.rotation = math.multiplyQuaternion(steering_rotation, wheel.rotation);
        }

        if (cast.hit) {
            const rest_length: f32 = ray_length;
            const compression: f32 = rest_length - distance;

            // Calculate velocity at wheel origin.
            const offset: Vector3 = wheel_origin - center_of_mass;
            const rotational_velocity: Vector3 = math.crossV3(angular_velocity, offset);
            const point_velocity: Vector3 = linear_velocity + rotational_velocity;
            const suspension_velocity: f32 = math.dotV3(point_velocity, world_down);

            // Calculate spring force.
            const spring_force: f32 = suspension_stiffness * @max(compression, 0);

            // Apply damping on the spring force.
            const damping_force: f32 = suspension_damping_coefficient * suspension_velocity;
            const support_force: f32 = @max(spring_force + damping_force, 0);

            // Calculate and apply the final force for the wheel.
            const force: Vector3 = -world_down * @as(Vector3, @splat(support_force));

            // Apply suspension force to car.
            c.b3Body_ApplyForce(body_id, b3.vecToB3(force), b3.vecToB3(wheel_origin), false);

            // Apply lateral force.
            const wheel_forward: Vector3 = math.rotateVectorBy(.{ -1, 0, 0 }, wheel_rotation);

            const wheel_lateral: Vector3 = math.crossV3(wheel_forward, world_down);
            const lateral_velocity: f32 = math.dotV3(point_velocity, wheel_lateral);
            const lateral_force: Vector3 = -wheel_lateral * @as(Vector3, @splat(car_spec.lateral_grip * lateral_velocity));
            c.b3Body_ApplyForce(body_id, b3.vecToB3(lateral_force), b3.vecToB3(wheel_origin), false);
        }

        // Apply engine/braking force.
        if (cast.hit and ((is_drive_wheel and has_engine_force) or has_braking_force)) {
            c.b3Body_ApplyForce(body_id, b3.vecToB3(wheel_force), b3.vecToB3(wheel_origin), false);
        }
    }
}
