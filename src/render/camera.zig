const std = @import("std");
const math = @import("math");
const flint = @import("flint");
const sdl = flint.sdl.c;

// Types.
const Transform = math.Transform;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Matrix4x4 = math.Matrix4x4;
const X = math.X;
const Y = math.Y;
const Z = math.Z;

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
            .position = .{ 5.62, 2.11, 0 },
            .target = .{ 0, 0, 0 },
            .radius = 6,
            .azimuth_angle = 0,
            .polar_angle = 0.36,
            .up = .{ 0, 1, 0 },
            .fov = 75 * sdl.SDL_PI_F / 180,
            .aspect_ratio = aspect_ratio,
            .near_plane = 0.01,
            .far_plane = 100,
        };
        self.deriveSpatialState();
        return self;
    }

    pub fn setAspectRatio(self: *Camera, aspect_ratio: f32) void {
        self.aspect_ratio = aspect_ratio;
        self.deriveSpatialState();
    }

    pub fn cycleMode(self: *Camera) void {
        var mode: u32 = @intFromEnum(self.mode) + 1;
        if (mode >= @typeInfo(Mode).@"enum".field_names.len) {
            mode = 0;
        }
        self.mode = @enumFromInt(mode);
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

    fn calculateRotationMatrix(rotation: Vector3) Matrix4x4 {
        const a: f32 = @cos(rotation[X]);
        const b: f32 = @sin(rotation[X]);
        const c: f32 = @cos(rotation[Y]);
        const d: f32 = @sin(rotation[Y]);
        const e: f32 = @cos(rotation[Z]);
        const f: f32 = @sin(rotation[Z]);
        const ad: f32 = a * d;
        const bd: f32 = b * d;
        return .new(.{
            c * e,           -c * f,          d,      0,
            bd * e + a * f,  -bd * f + a * e, -b * c, 0,
            -ad * e + b * f, ad * f + b * e,  a * c,  0,
            0,               0,               0,      1,
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
            0,                                0,            self.far_plane / (self.near_plane - self.far_plane),                     -1,
            0,                                0,            (self.near_plane * self.far_plane) / (self.near_plane - self.far_plane), 0,
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

    pub fn getViewBasis(self: *const Camera) Basis {
        const target_to_position: Vector3 = self.position - self.target;
        const back: Vector3 = math.normalizeV3(target_to_position);
        const right: Vector3 = math.normalizeV3(math.crossV3(self.up, back));
        const cam_up: Vector3 = math.crossV3(back, right);
        return .{ .back = back, .right = right, .up = cam_up };
    }
};
