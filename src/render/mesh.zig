pub const WorldMesh = struct {
    vertices: []const WorldVertex,
    indices: []const u16,
};

pub const WorldVertex = struct {
    x: f32,
    y: f32,
    z: f32,
    nx: f32,
    ny: f32,
    nz: f32,
};

pub const ScreenVertex = struct {
    x: f32,
    y: f32,
    z: f32,
    u: f32,
    v: f32,
};

pub const CUBE: WorldMesh = .{
    .vertices = CUBE_VERTICES,
    .indices = CUBE_INDICES,
};

pub const CUBE_VERTICES: []const WorldVertex = &.{
    // -Z
    .{ .x = -1, .y = -1, .z = -1, .nx = 0, .ny = 0, .nz = -1 },
    .{ .x = 1, .y = -1, .z = -1, .nx = 0, .ny = 0, .nz = -1 },
    .{ .x = 1, .y = 1, .z = -1, .nx = 0, .ny = 0, .nz = -1 },
    .{ .x = -1, .y = 1, .z = -1, .nx = 0, .ny = 0, .nz = -1 },

    // +Z
    .{ .x = -1, .y = -1, .z = 1, .nx = 0, .ny = 0, .nz = 1 },
    .{ .x = 1, .y = -1, .z = 1, .nx = 0, .ny = 0, .nz = 1 },
    .{ .x = 1, .y = 1, .z = 1, .nx = 0, .ny = 0, .nz = 1 },
    .{ .x = -1, .y = 1, .z = 1, .nx = 0, .ny = 0, .nz = 1 },

    // -X
    .{ .x = -1, .y = -1, .z = -1, .nx = -1, .ny = 0, .nz = 0 },
    .{ .x = -1, .y = 1, .z = -1, .nx = -1, .ny = 0, .nz = 0 },
    .{ .x = -1, .y = 1, .z = 1, .nx = -1, .ny = 0, .nz = 0 },
    .{ .x = -1, .y = -1, .z = 1, .nx = -1, .ny = 0, .nz = 0 },

    // +X
    .{ .x = 1, .y = -1, .z = -1, .nx = 1, .ny = 0, .nz = 0 },
    .{ .x = 1, .y = 1, .z = -1, .nx = 1, .ny = 0, .nz = 0 },
    .{ .x = 1, .y = 1, .z = 1, .nx = 1, .ny = 0, .nz = 0 },
    .{ .x = 1, .y = -1, .z = 1, .nx = 1, .ny = 0, .nz = 0 },

    // -Y
    .{ .x = -1, .y = -1, .z = -1, .nx = 0, .ny = -1, .nz = 0 },
    .{ .x = -1, .y = -1, .z = 1, .nx = 0, .ny = -1, .nz = 0 },
    .{ .x = 1, .y = -1, .z = 1, .nx = 0, .ny = -1, .nz = 0 },
    .{ .x = 1, .y = -1, .z = -1, .nx = 0, .ny = -1, .nz = 0 },

    // +Y
    .{ .x = -1, .y = 1, .z = -1, .nx = 0, .ny = 1, .nz = 0 },
    .{ .x = -1, .y = 1, .z = 1, .nx = 0, .ny = 1, .nz = 0 },
    .{ .x = 1, .y = 1, .z = 1, .nx = 0, .ny = 1, .nz = 0 },
    .{ .x = 1, .y = 1, .z = -1, .nx = 0, .ny = 1, .nz = 0 },
};

pub const CUBE_INDICES: []const u16 = &.{
    0,  1,  2,  0,  2,  3,
    6,  5,  4,  7,  6,  4,
    8,  9,  10, 8,  10, 11,
    14, 13, 12, 15, 14, 12,
    16, 17, 18, 16, 18, 19,
    22, 21, 20, 23, 22, 20,
};

pub const QUAD_VERTICES: []const ScreenVertex = &.{
    .{ .x = -1, .y = -1, .z = 0, .u = 0, .v = 1 },
    .{ .x = 1, .y = -1, .z = 0, .u = 1, .v = 1 },
    .{ .x = -1, .y = 1, .z = 0, .u = 0, .v = 0 },
    .{ .x = 1, .y = 1, .z = 0, .u = 1, .v = 0 },
};

pub const QUAD_INDICES: []const u16 = &.{
    0, 1, 3,
    0, 3, 2,
};
