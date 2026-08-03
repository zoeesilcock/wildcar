const std = @import("std");
const flint = @import("flint");
const sdl = flint.sdl.c;
const imgui = flint.imgui;
const c = @import("c");
const math = @import("math");
const renderer = @import("render/renderer.zig");
const game = @import("root.zig");
const b3 = @import("b3.zig");

// Types.
const State = game.State;
const Entity = game.Entity;
const FrameContext = renderer.FrameContext;
const Transform = math.Transform;
const Vector3 = math.Vector3;
const Quaternion = math.Quaternion;
const Color = math.Color;

pub const Box = struct {
    transform: Transform,
    color: Color,
};

pub fn addBox(state: *State, box: Box) void {
    std.debug.assert(state.internal.debug_box_count < state.internal.debug_boxes.len);
    state.internal.debug_boxes[state.internal.debug_box_count] = box;
    state.internal.debug_box_count += 1;
}

pub fn addRaycast(
    state: *State,
    origin: Vector3,
    translation: Vector3,
    rotation: Quaternion,
    hit_distance: f32,
) void {
    var t: Transform = .{ .position = origin, .rotation = rotation, .scale = @splat(0.05) };
    addBox(state, .{ .transform = t, .color = .{ 1, 0, 1, 1 } });

    const direction = math.normalizeV3(translation);
    t = .{
        .position = origin + direction * @as(Vector3, @splat(hit_distance / 2)),
        .rotation = rotation,
        .scale = .{ 0.01, hit_distance, 0.01 },
    };
    addBox(state, .{ .transform = t, .color = .{ 1, 1, 0, 1 } });
}

pub fn draw(state: *State, context: *FrameContext) void {
    var index: u32 = 0;
    while (index < state.internal.debug_box_count) : (index += 1) {
        const box: Box = state.internal.debug_boxes[index];
        renderer.drawDebugCube(&state.renderer, context, box.transform, .{ .color = box.color });
    }

    state.internal.debug_box_count = 0;
}

pub fn drawCollisionShapes(state: *State, context: *FrameContext, entity: Entity, parent: ?Entity) void {
    if (state.internal.show_collision_bodies and entity.has_collider) {
        if (state.renderer.meshes.get(entity.mesh_id)) |mesh| {
            for (mesh.colliders) |collision_shape| {
                var transform: Transform = collision_shape.transform.toScaledMeshSpace(entity.transform.scale);
                transform = transform.relativeTo(entity.transform);

                if (parent != null) {
                    transform = transform.relativeTo(parent.?.transform);
                }

                transform.scale = entity.transform.scale * collision_shape.transform.scale;
                switch (collision_shape.shape) {
                    .Box => {
                        renderer.drawLineCube(&state.renderer, context, transform, .{
                            .color = if (entity.is_dynamic) .{ 0, 1, 0, 1 } else .{ 1, 1, 0, 1 },
                        });
                    },
                }
            }
        }
    }
}
