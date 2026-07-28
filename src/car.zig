//! Car measurements:
//!
//! Chassi size: 4x2
//! Wheel radius: 0.66
//! Wheel positions:
//! * X: 2/-2
//! * Z: 2/-2

const std = @import("std");
const c = @import("c");
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

const CAR_MASS = 1000;
const MASS_PER_WHEEL = CAR_MASS / 4;
const SUSPENSION_PARKED_COMPRESSION = 0.1;
const SUSPENSION_STIFFNESS = (MASS_PER_WHEEL * game.GRAVITY) / SUSPENSION_PARKED_COMPRESSION;
const SUSPENSION_DAMPING_RATIO = 0.7;
const SUSPENSION_CRITICAL_DAMPING = 2 * @sqrt(SUSPENSION_STIFFNESS * MASS_PER_WHEEL);
const SUSPENSION_DAMPING_COEFFICIENT = SUSPENSION_DAMPING_RATIO * SUSPENSION_CRITICAL_DAMPING;
const ACCELERATION_FORCE = 10000;
const BRAKING_FORCE = 30000;
const STEER_WHEELS = .{ 0, 2 };
const DRIVE_WHEELS = .{ 1, 3 };
const LATERAL_GRIP = 1000;
const MAX_STEERING_ANGLE = 0.5;

var wheel_transforms: [4]Transform = @splat(.{});

pub fn init(car: Entity) void {
    setWheels(car.children[0..4]);

    // Set mass.
    var mass_data = c.b3Body_GetMassData(car.body_id);
    const mass_scale: f32 = CAR_MASS / mass_data.mass;
    mass_data.mass = CAR_MASS;
    mass_data.inertia = c.b3MulSM(mass_scale, mass_data.inertia);
    c.b3Body_SetMassData(car.body_id, mass_data);
}

fn setWheels(wheels: *[4]Entity) void {
    for (wheels, 0..) |wheel, i| {
        wheel_transforms[i] = wheel.transform;
    }
}

pub fn updatePhysics(state: *State) void {
    const car: Entity = state.entities.items[0];
    const body_id: c.b3BodyId = car.body_id;
    const wheel_entities: []Entity = car.children[0..4];

    const center_of_mass: Vector3 = b3.b3ToVec(c.b3Body_GetWorldCenter(body_id));
    const linear_velocity: Vector3 = b3.b3ToVec(c.b3Body_GetLinearVelocity(body_id));
    const angular_velocity: Vector3 = b3.b3ToVec(c.b3Body_GetAngularVelocity(body_id));

    // Calculate engine/braking force based on player input.
    var has_forward_force: bool = false;
    var forward_force: Vector3 = @splat(0);
    if (state.input.forward_button.down or state.input.backward_button.down) {
        has_forward_force = true;
        const local_forward: Vector3 = .{ -1, 0, 0 };
        const world_forward: Vector3 = math.rotateVectorBy(local_forward, car.transform.rotation);
        const world_backward: Vector3 = -world_forward;
        const forward_velocity: f32 = math.dotV3(linear_velocity, world_forward);

        if (state.input.forward_button.down) {
            forward_force = if (forward_velocity < 0)
                world_forward * @as(Vector3, @splat(BRAKING_FORCE))
            else
                world_forward * @as(Vector3, @splat(ACCELERATION_FORCE));
        }

        if (state.input.backward_button.down) {
            forward_force = if (forward_velocity > 0)
                world_backward * @as(Vector3, @splat(BRAKING_FORCE))
            else
                world_backward * @as(Vector3, @splat(ACCELERATION_FORCE));
        }
        forward_force /= @as(Vector3, @splat(DRIVE_WHEELS.len));
    }

    var steering_input: f32 = 0;
    if (state.input.left_button.down) {
        steering_input = 1;
    } else if (state.input.right_button.down) {
        steering_input = -1;
    }
    const steering_angle: f32 = steering_input * MAX_STEERING_ANGLE;
    const steering_rotation: Quaternion = math.eulerToQuaternion(.{ 0, steering_angle, 0 });

    for (wheel_transforms, 0..) |wheel, i| {
        const drive_wheel: bool = DRIVE_WHEELS[0] == i or DRIVE_WHEELS[1] == i;
        const steer_wheel: bool = STEER_WHEELS[0] == i or STEER_WHEELS[1] == i;

        const wheel_transform = wheel.relativeTo(car.transform);
        const wheel_origin = wheel_transform.position;
        const wheel_radius: f32 = 0.66;

        const ray_rotation: Quaternion = car.transform.rotation;
        const local_down: Vector3 = .{ 0, -1, 0 };
        const world_down: Vector3 = math.rotateVectorBy(local_down, ray_rotation);

        const epsilon_length: f32 = 0.01;
        const epsilon: Vector3 = world_down * @as(Vector3, @splat(epsilon_length)); // Avoid starting in the ground.

        const ray_length: f32 = wheel_radius + epsilon_length;
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
        if (steer_wheel) {
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
            const spring_force: f32 = SUSPENSION_STIFFNESS * @max(compression, 0);

            // Apply damping on the spring force.
            const damping_force: f32 = SUSPENSION_DAMPING_COEFFICIENT * suspension_velocity;
            const support_force: f32 = @max(spring_force + damping_force, 0);

            // Calculate and apply the final force for the wheel.
            const force: Vector3 = -world_down * @as(Vector3, @splat(support_force));

            // Apply suspension force to car.
            c.b3Body_ApplyForce(body_id, b3.vecToB3(force), b3.vecToB3(wheel_origin), false);

            // Apply lateral force.
            const wheel_forward: Vector3 = math.rotateVectorBy(.{ -1, 0, 0 }, wheel_rotation);

            const wheel_lateral: Vector3 = math.crossV3(wheel_forward, world_down);
            const lateral_velocity: f32 = math.dotV3(point_velocity, wheel_lateral);
            const lateral_force: Vector3 = -wheel_lateral * @as(Vector3, @splat(LATERAL_GRIP * lateral_velocity));
            c.b3Body_ApplyForce(body_id, b3.vecToB3(lateral_force), b3.vecToB3(wheel_origin), false);
        }

        // Apply engine/braking force.
        if (cast.hit and drive_wheel and has_forward_force) {
            c.b3Body_ApplyForce(body_id, b3.vecToB3(forward_force), b3.vecToB3(wheel_origin), false);
        }
    }
}
