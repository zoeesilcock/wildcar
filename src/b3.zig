const c = @import("c");
const math = @import("math");

// Types.
const Vector3 = math.Vector3;
const X = math.X;
const Y = math.Y;
const Z = math.Z;

pub fn vecToB3(in: Vector3) c.b3Vec3 {
    return .{ .x = in[X], .y = in[Y], .z = in[Z] };
}
