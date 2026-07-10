const math = @import("math");
const flint = @import("flint");
const sdl = flint.sdl.c;
const game = @import("../root.zig");

// Types.
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;
const Matrix4x4 = math.Matrix4x4;
const X = math.X;
const Y = math.Y;
const Z = math.Z;
const Entity = game.Entity;

pub const Camera = struct {
    position: Vector3,
    target: Vector3,
    up: Vector3,
    fov: f32,
    aspect_ratio: f32,
    near_plane: f32,
    far_plane: f32,

    pub fn init(aspect_ratio: f32) Camera {
        return .{
            .position = .{ 3, 3, 3 },
            .target = .{ 0, 0, 0 },
            .up = .{ 0, 1, 0 },
            .fov = 75 * sdl.SDL_PI_F / 180,
            .aspect_ratio = aspect_ratio,
            .near_plane = 0.01,
            .far_plane = 100,
        };
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

    pub fn calculateMVPMatrix(self: *Camera, entity: Entity) Matrix4x4 {
        const translation: Matrix4x4 = .new(.{
            1,                  0,                  0,                  0,
            0,                  1,                  0,                  0,
            0,                  0,                  1,                  0,
            entity.position[X], entity.position[Y], entity.position[Z], 1,
        });
        const rotation: Matrix4x4 = calculateRotationMatrix(entity.rotation);
        const scale: Matrix4x4 = .new(.{
            entity.scale[X], 0,               0,               0,
            0,               entity.scale[Y], 0,               0,
            0,               0,               entity.scale[Z], 0,
            0,               0,               0,               1,
        });
        const model: Matrix4x4 = translation.multiply(scale).multiply(rotation);

        const position = self.position;
        const one_over_fov: f32 = 1 / sdl.SDL_tanf(self.fov * 0.5);
        const proj: Matrix4x4 = .new(.{
            one_over_fov / self.aspect_ratio, 0,            0,                                                                       0,
            0,                                one_over_fov, 0,                                                                       0,
            0,                                0,            self.far_plane / (self.near_plane - self.far_plane),                     -1,
            0,                                0,            (self.near_plane * self.far_plane) / (self.near_plane - self.far_plane), 0,
        });

        const target_to_position = position - self.target;
        const vector_a: Vector3 = math.normalizeV3(target_to_position);
        const vector_b: Vector3 = math.normalizeV3(math.crossV3(self.up, vector_a));
        const vector_c: Vector3 = math.crossV3(vector_a, vector_b);
        const view: Matrix4x4 = .new(.{
            vector_b[X],                     vector_c[X],                     vector_a[X],                     0,
            vector_b[Y],                     vector_c[Y],                     vector_a[Y],                     0,
            vector_b[Z],                     vector_c[Z],                     vector_a[Z],                     0,
            -math.dotV3(vector_b, position), -math.dotV3(vector_c, position), -math.dotV3(vector_a, position), 1,
        });

        return model.multiply(view).multiply(proj);
    }
};
