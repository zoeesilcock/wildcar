const math = @import("math");
const mesh = @import("mesh.zig");

// Types.
const Transform = math.Transform;
const WorldMesh = mesh.WorldMesh;

pub const Model = struct {
    mesh: WorldMesh,
    colliders: []const CollisionShape = &.{},
};

pub const CollisionShapeType = enum(u32) {
    Box,
};

pub const CollisionShape = struct {
    shape: CollisionShapeType = .Box,
    transform: Transform,
};

pub const CUBE: Model = .{
    .mesh = mesh.CUBE,
    .colliders = &.{
        .{
            .shape = .Box,
            .transform = .{},
        },
    },
};
