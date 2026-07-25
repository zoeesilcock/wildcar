const std = @import("std");
const flint = @import("flint");
const sdl = flint.sdl.c;
const imgui = flint.imgui;
const c = @import("c");
const math = @import("math");
const renderer = @import("render/renderer.zig");
const game = @import("root.zig");

// Types.
const State = game.State;
const Entity = game.Entity;
const FrameContext = renderer.FrameContext;
const Color = math.Color;
const Transform = math.Transform;

pub const Box = struct {
    transform: Transform,
    color: Color,
};

pub fn addBox(state: *State, box: Box) void {
    std.debug.assert(state.internal.debug_box_count < state.internal.debug_boxes.len);
    state.internal.debug_boxes[state.internal.debug_box_count] = box;
    state.internal.debug_box_count += 1;
}

pub fn draw(state: *State, context: *FrameContext) void {
    var index: u32 = 0;
    while (index < state.internal.debug_box_count) : (index += 1) {
        const box: Box = state.internal.debug_boxes[index];
        renderer.drawLineCube(&state.renderer, context, box.transform, .{ .color = box.color });
    }

    state.internal.debug_box_count = 0;
}

pub fn drawCollisionShapes(state: *State, context: *FrameContext, entity: Entity) void {
    if (state.internal.show_collision_bodies) {
        const body_transform: c.b3Transform = c.b3Body_GetTransform(entity.body_id);

        renderer.drawLineCube(&state.renderer, context, .{
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
        });
    }
}
