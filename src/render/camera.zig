const std = @import("std");
const math = @import("math");
const flint = @import("flint");
const sdl = flint.sdl.c;

// Types.
const Transform = math.Transform;
const Quaternion = math.Quaternion;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Matrix4x4 = math.Matrix4x4;
const X = math.X;
const Y = math.Y;
const Z = math.Z;
const W = math.W;

pub const Camera = struct {
    position: Vector3,
    target: Vector3,

    radius: f32,
    azimuth_angle: f32,
    polar_angle: f32,

    mode: Mode = .Orbit,

    up: Vector3,
    fov: f32,
    aspect_ratio: f32,
    near_plane: f32,
    far_plane: f32,

    pub const Mode = enum(u32) {
        Orbit,
        Free,
    };

    const Basis = struct {
        back: Vector3,
        right: Vector3,
        up: Vector3,
    };

    pub fn init(aspect_ratio: f32) Camera {
        var self: Camera = .{
            .position = .{ -1.17, 5, 11.45 },
            .target = .{ -20, 3, 5 },
            .radius = 8,
            .azimuth_angle = 0.33,
            .polar_angle = 0.1,
            .mode = .Orbit,
            .up = .{ 0, 1, 0 },
            .fov = 50 * sdl.SDL_PI_F / 180,
            .aspect_ratio = aspect_ratio,
            .near_plane = 0.1,
            .far_plane = 10_000,
        };
        self.deriveSpatialState();
        return self;
    }

    pub fn setAspectRatio(self: *Camera, aspect_ratio: f32) void {
        self.aspect_ratio = aspect_ratio;
        self.deriveSpatialState();
    }

    pub fn setTarget(self: *Camera, target: Vector3) void {
        self.target = target;
        self.deriveSpatialState();
    }

    pub fn cycleMode(self: *Camera) void {
        var mode: u32 = @backingInt(self.mode) + 1;
        if (mode >= @typeInfo(Mode).@"enum".field_names.len) {
            mode = 0;
        }
        self.mode = @fromBackingInt(@intCast(mode));
    }

    pub fn orbit(self: *Camera, amount: Vector2) void {
        self.azimuth_angle = @mod(self.azimuth_angle - amount[X], 2 * sdl.SDL_PI_F);

        const polar_limit = (sdl.SDL_PI_F / 2) - 0.01;
        self.polar_angle = std.math.clamp(self.polar_angle - amount[Y], -polar_limit, polar_limit);

        self.deriveSpatialState();
    }

    pub fn zoom(self: *Camera, amount: f32) void {
        self.radius -= amount;
        self.deriveSpatialState();
    }

    pub fn dolly(self: *Camera, amount: f32) void {
        const basis = self.getViewBasis();
        self.position -= basis.back * @as(Vector3, @splat(amount));
        self.deriveSpatialState();
    }

    pub fn pan(self: *Camera, amount: Vector2) void {
        const basis = self.getViewBasis();
        const forward_flat: Vector3 = math.crossV3(self.up, basis.right);
        const pan_amount: Vector3 =
            forward_flat * @as(Vector3, @splat(amount[Y])) - basis.right * @as(Vector3, @splat(amount[X]));

        self.position -= pan_amount;
        self.deriveSpatialState();
    }

    fn deriveSpatialState(self: *Camera) void {
        if (self.mode == .Orbit) {
            self.position = .{
                self.target[X] + self.radius * @cos(self.polar_angle) * @cos(self.azimuth_angle),
                self.target[Y] + self.radius * @sin(self.polar_angle),
                self.target[Z] + self.radius * @cos(self.polar_angle) * @sin(self.azimuth_angle),
            };
        } else if (self.mode == .Free) {
            self.target = .{
                self.position[X] - self.radius * @cos(self.polar_angle) * @cos(self.azimuth_angle),
                self.position[Y] - self.radius * @sin(self.polar_angle),
                self.position[Z] - self.radius * @cos(self.polar_angle) * @sin(self.azimuth_angle),
            };
        }
    }

    fn calculateRotationMatrix(q: Quaternion) Matrix4x4 {
        const x = q[X];
        const y = q[Y];
        const z = q[Z];
        const w = q[W];

        const xx = x * x;
        const yy = y * y;
        const zz = z * z;
        const xy = x * y;
        const xz = x * z;
        const yz = y * z;
        const wx = w * x;
        const wy = w * y;
        const wz = w * z;

        return .new(.{
            1 - 2 * (yy + zz), 2 * (xy + wz),     2 * (xz - wy),     0,
            2 * (xy - wz),     1 - 2 * (xx + zz), 2 * (yz + wx),     0,
            2 * (xz + wy),     2 * (yz - wx),     1 - 2 * (xx + yy), 0,
            0,                 0,                 0,                 1,
        });
    }

    pub fn calculateModelMatrix(target: Transform) Matrix4x4 {
        const translation: Matrix4x4 = .new(.{
            1,                  0,                  0,                  0,
            0,                  1,                  0,                  0,
            0,                  0,                  1,                  0,
            target.position[X], target.position[Y], target.position[Z], 1,
        });
        const rotation: Matrix4x4 = calculateRotationMatrix(target.rotation);
        const scale: Matrix4x4 = .new(.{
            target.scale[X], 0,               0,               0,
            0,               target.scale[Y], 0,               0,
            0,               0,               target.scale[Z], 0,
            0,               0,               0,               1,
        });
        const model: Matrix4x4 = translation.multiply(rotation).multiply(scale);
        return model;
    }

    pub fn calculateViewProjectionMatrix(self: *const Camera) Matrix4x4 {
        const position: Vector3 = self.position;
        const one_over_fov: f32 = 1 / sdl.SDL_tanf(self.fov * 0.5);
        const proj: Matrix4x4 = .new(.{
            one_over_fov / self.aspect_ratio, 0,            0,                                                                       0,
            0,                                one_over_fov, 0,                                                                       0,
            0,                                0,            self.near_plane / (self.far_plane - self.near_plane),                    -1,
            0,                                0,            (self.near_plane * self.far_plane) / (self.far_plane - self.near_plane), 0,
        });

        const basis = self.getViewBasis();
        const view: Matrix4x4 = .new(.{
            basis.right[X],                     basis.up[X],                     basis.back[X],                     0,
            basis.right[Y],                     basis.up[Y],                     basis.back[Y],                     0,
            basis.right[Z],                     basis.up[Z],                     basis.back[Z],                     0,
            -math.dotV3(basis.right, position), -math.dotV3(basis.up, position), -math.dotV3(basis.back, position), 1,
        });

        return proj.multiply(view);
    }

    pub fn calculateDirectionalLightViewProjectionMatrix(light_direction: Vector3, scene_center: Vector3) Matrix4x4 {
        const light_distance: f32 = 50;
        const light_position: Vector3 =
            scene_center + math.normalizeV3(light_direction) * @as(Vector3, @splat(light_distance));
        const light_target: Vector3 = scene_center;

        const b = calculateViewBasis(light_position, light_target, .{ 0, 1, 0 }, .{ 0, 0, 1 });

        const view: Matrix4x4 = .new(.{
            b.right[X],                           b.up[X],                           b.back[X],                           0,
            b.right[Y],                           b.up[Y],                           b.back[Y],                           0,
            b.right[Z],                           b.up[Z],                           b.back[Z],                           0,
            -math.dotV3(b.right, light_position), -math.dotV3(b.up, light_position), -math.dotV3(b.back, light_position), 1,
        });

        const half_extent: f32 = 50;
        const near_plane: f32 = 0.1;
        const far_plane: f32 = 100;

        const projection: Matrix4x4 = .new(.{
            1 / half_extent, 0,               0,                                    0,
            0,               1 / half_extent, 0,                                    0,
            0,               0,               1 / (far_plane - near_plane),         0,
            0,               0,               far_plane / (far_plane - near_plane), 1,
        });

        return projection.multiply(view);
    }

    pub fn getViewBasis(self: *const Camera) Basis {
        return calculateViewBasis(self.position, self.target, self.up, null);
    }

    /// `position` and `target` must differ.
    /// `up_in` must be normalized.
    /// `fallback_up` must be normalized when provided.
    pub fn calculateViewBasis(position: Vector3, target: Vector3, up_in: Vector3, fallback_up: ?Vector3) Basis {
        const target_to_position: Vector3 = position - target;
        std.debug.assert(math.dotV3(target_to_position, target_to_position) > 0);
        const back: Vector3 = math.normalizeV3(target_to_position);

        var up = up_in;
        if (fallback_up) |fallback| {
            if (@abs(math.dotV3(back, up)) > 0.99) {
                up = fallback;
            }
        }

        var right: Vector3 = math.crossV3(up, back);
        std.debug.assert(math.dotV3(right, right) > 1e-12); // Guard against near-alignment between up and back.
        right = math.normalizeV3(right);

        return .{
            .back = back,
            .right = right,
            .up = math.crossV3(back, right),
        };
    }
};
