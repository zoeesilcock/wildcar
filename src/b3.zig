const c = @import("c");
const math = @import("math");

// Types.
const Vector3 = math.Vector3;
const Quaternion = math.Quaternion;
const X = math.X;
const Y = math.Y;
const Z = math.Z;
const W = math.W;

pub fn vecToB3(in: Vector3) c.b3Vec3 {
    return .{ .x = in[X], .y = in[Y], .z = in[Z] };
}

pub fn b3ToVec(in: c.b3Vec3) Vector3 {
    return .{ in.x, in.y, in.z };
}

pub fn quatToB3(in: Quaternion) c.b3Quat {
    return .{ .v = .{ .x = in[X], .y = in[Y], .z = in[Z] }, .s = in[W] };
}
