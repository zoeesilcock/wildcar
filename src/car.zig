//! Car measurements:
//!
//! Chassi size: 4x2
//! Wheel radius: 0.33
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
const Vector3 = math.Vector3;
const X = math.X;
const Y = math.Y;
const Z = math.Z;

const WHEEL_OFFSETS = [_]Vector3{
    .{ 2, 0, 2 },
    .{ 2, 0, -2 },
    .{ -2, 0, -2 },
    .{ -2, 0, 2 },
};

pub fn updatePhysics(state: *State) void {
    const car: Entity = state.entities.items[0];
    const body_id: c.b3BodyId = car.body_id;
    const wheels: []Entity = car.children[0..4];

    for (wheels) |wheel| {
        const wheel_transform = wheel.transform.relativeTo(car.transform);
        const wheel_origin = wheel_transform.position;
        const wheel_radius: f32 = 0.66;
        const ray_length: f32 = wheel_radius;
        const ray_origin = wheel_origin;
        const local_down: Vector3 = .{ 0, -1, 0 };
        const world_down: Vector3 = math.rotateVectorBy(local_down, car.transform.rotation);
        const ray_translation: Vector3 = world_down * @as(Vector3, @splat(ray_length));
        var distance = ray_length;

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

        if (INTERNAL) {
            // Wheel origin.
            var t: Transform = .{ .position = wheel_origin, .scale = .{ 0.1, 0.1, 0.5 } };
            debug_shapes.addBox(state, .{ .transform = t, .color = .{ 1, 0, 1, 1 } });

            // Wheel raycast.
            t = .{
                .position = ray_origin + world_down * @as(Vector3, @splat(distance / 2)),
                .rotation = car.transform.rotation,
                .scale = .{ 0.1, distance / 2, 0.5 },
            };
            debug_shapes.addBox(state, .{ .transform = t, .color = .{ 1, 1, 0, 1 } });
        }
    }

    _ = body_id;
}
