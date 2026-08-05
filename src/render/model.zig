const math = @import("math");
const flint = @import("flint");
const sdl = flint.sdl.c;
const mesh = @import("mesh.zig");

// Types.
const Transform = math.Transform;
const WorldMesh = mesh.WorldMesh;

pub const Model = struct {
    mesh: WorldMesh,
    colliders: []const CollisionShape = &.{},
    texture: ?Texture = null,
};

pub const CollisionShapeType = enum(u32) {
    Box,
};

pub const CollisionShape = struct {
    shape: CollisionShapeType = .Box,
    transform: Transform,
};

pub const Filter = enum(u32) {
    Nearest,
    Linear,
    NearestMipmapNearest,
    LinearMipmapNearest,
    NearestMipmapLinear,
    LinearMipmapLinear,
};

pub const UVWrap = enum(u32) {
    ClampToEdge,
    MirroredRepeat,
    Repeat,
};

pub const Texture = struct {
    data: []const u8,
    min_filter: Filter,
    mag_filter: Filter,
    wrap_u: UVWrap,
    wrap_v: UVWrap,
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
