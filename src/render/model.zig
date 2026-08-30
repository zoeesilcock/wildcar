const math = @import("math");
const flint = @import("flint");
const sdl = flint.sdl.c;
const mesh = @import("mesh.zig");

// Types.
const Transform = math.Transform;
const WorldMesh = mesh.WorldMesh;

pub const Model = struct {
    mesh: WorldMesh,
    transform: Transform = .{},
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

    pub fn toSDL(self: Filter) sdl.SDL_GPUFilter {
        return switch (self) {
            .Nearest => sdl.SDL_GPU_FILTER_NEAREST,
            .Linear => sdl.SDL_GPU_FILTER_LINEAR,
            .NearestMipmapNearest => sdl.SDL_GPU_FILTER_NEAREST,
            .LinearMipmapNearest => sdl.SDL_GPU_FILTER_LINEAR,
            .NearestMipmapLinear => sdl.SDL_GPU_FILTER_NEAREST,
            .LinearMipmapLinear => sdl.SDL_GPU_FILTER_LINEAR,
        };
    }

    pub fn toSDLMipmap(self: Filter) sdl.SDL_GPUSamplerMipmapMode {
        return switch (self) {
            .Nearest, .Linear, .NearestMipmapNearest, .LinearMipmapNearest => sdl.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
            .NearestMipmapLinear, .LinearMipmapLinear => sdl.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
        };
    }
};

pub const UVWrap = enum(u32) {
    ClampToEdge,
    MirroredRepeat,
    Repeat,

    pub fn toSDL(self: UVWrap) sdl.SDL_GPUSamplerAddressMode {
        return switch (self) {
            .ClampToEdge => sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .MirroredRepeat => sdl.SDL_GPU_SAMPLERADDRESSMODE_MIRRORED_REPEAT,
            .Repeat => sdl.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
        };
    }
};

pub const Texture = struct {
    data: []const u8,
    min_filter: Filter,
    mag_filter: Filter,
    wrap_u: UVWrap,
    wrap_v: UVWrap,

    pub fn getSamplerCreateInfo(self: *const Texture) sdl.SDL_GPUSamplerCreateInfo {
        return .{
            .min_filter = self.min_filter.toSDL(),
            .mag_filter = self.mag_filter.toSDL(),
            .address_mode_u = self.wrap_u.toSDL(),
            .address_mode_v = self.wrap_v.toSDL(),
            .address_mode_w = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
            .mipmap_mode = self.min_filter.toSDLMipmap(),
        };
    }
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
