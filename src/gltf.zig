const std = @import("std");
const flint = @import("flint");
const math = @import("math");

// Types.
const WorldMesh = @import("render/mesh.zig").WorldMesh;
const CollisionShape = @import("render/mesh.zig").CollisionShape;
const CollisionShapeType = @import("render/mesh.zig").CollisionShapeType;
const WorldVertex = @import("render/mesh.zig").WorldVertex;
const Transform = math.Transform;
const Vector3 = math.Vector3;
const X = math.X;
const Y = math.Y;
const Z = math.Z;
const W = math.W;

const Chunk = struct {
    chunk_length: u32,
    chunk_type: ChunkType,
    chunk_data: []const u8,
};

const ChunkType = enum(u32) {
    json = fourCC("JSON"),
    bin = fourCC("BIN\x00"),
};

const AccessorType = enum(u32) {
    scalar,
    vec2,
    vec3,
    vec4,
    mat2,
    mat3,
    mat4,

    pub fn fromSlice(slice: []const u8) AccessorType {
        var result: AccessorType = .scalar;

        if (std.mem.eql(u8, "VEC2", slice)) {
            result = .vec2;
        } else if (std.mem.eql(u8, "VEC3", slice)) {
            result = .vec3;
        } else if (std.mem.eql(u8, "VEC4", slice)) {
            result = .vec4;
        } else if (std.mem.eql(u8, "MAT2", slice)) {
            result = .mat2;
        } else if (std.mem.eql(u8, "MAT3", slice)) {
            result = .mat3;
        } else if (std.mem.eql(u8, "MAT4", slice)) {
            result = .mat4;
        }

        return result;
    }

    pub fn getComponentCount(self: AccessorType) usize {
        return switch (self) {
            .scalar => 1,
            .vec2 => 2,
            .vec3 => 3,
            .vec4 => 4,
            .mat2 => 2,
            .mat3 => 3,
            .mat4 => 4,
        };
    }
};

const AccessorDataType = enum(u32) {
    signed_byte = 5120,
    unsigned_byte = 5121,
    signed_short = 5122,
    unsigned_short = 5123,
    unsigned_int = 5125,
    float = 5126,

    pub fn getSize(self: AccessorDataType) usize {
        return switch (self) {
            .signed_byte => 1,
            .unsigned_byte => 1,
            .signed_short => 2,
            .unsigned_short => 2,
            .unsigned_int => 4,
            .float => 4,
        };
    }

    pub fn assertType(self: AccessorDataType, T: type) void {
        switch (self) {
            .signed_byte => std.debug.assert(T == i8),
            .unsigned_byte => std.debug.assert(T == u8),
            .signed_short => std.debug.assert(T == i16),
            .unsigned_short => std.debug.assert(T == u16),
            .unsigned_int => std.debug.assert(T == u32),
            .float => std.debug.assert(T == f32),
        }
    }
};

pub fn loadGLB(path: []const u8, allocator: std.mem.Allocator, io: std.Io) !?[]const WorldMesh {
    const file = try flint.fs.openFileRelative(io, path, .{ .mode = .read_only });
    defer file.close(io);

    var buf: [1024 * 1024]u8 = undefined;
    var file_reader: std.Io.File.Reader = file.reader(io, &buf);
    const reader: *std.Io.Reader = &file_reader.interface;

    // Read the header.
    const magic: u32 = try reader.takeInt(u32, .little);
    const version: u32 = try reader.takeInt(u32, .little);
    const length: u32 = try reader.takeInt(u32, .little);

    std.debug.assert(magic == fourCC("glTF"));
    std.log.info("magic: {d}, version: {d}, length: {d}", .{ magic, version, length });

    // Read the data chunks.
    const json_chunk = try parseChunk(reader, .json);
    const bin_chunk = try parseChunk(reader, .bin);

    // Parse the JSON chunk.
    var scanner = std.json.Scanner.initCompleteInput(allocator, json_chunk.chunk_data);
    defer scanner.deinit();
    var diagnostics = std.json.Scanner.Diagnostics{};
    scanner.enableDiagnostics(&diagnostics);

    var result: ?[]WorldMesh = null;
    if (std.json.parseFromTokenSource(std.json.Value, allocator, &scanner, .{})) |json| {
        defer json.deinit();

        const nodes = json.value.object.get("nodes").?;
        var collider_mesh_indices: ?std.json.Value = null;
        for (nodes.array.items) |node| {
            if (node.object.get("name")) |node_name| {
                if (std.mem.eql(u8, node_name.string, "colliders")) {
                    collider_mesh_indices = node.object.get("children");
                }
            }
        }

        const accessors = json.value.object.get("accessors").?;
        const buffer_views = json.value.object.get("bufferViews").?;

        var result_mesh_index: u32 = 0;
        var result_collider_index: u32 = 0;
        if (json.value.object.get("meshes")) |meshes| {
            var mesh_count: u32 = 0;
            var collider_count: u32 = 0;
            for (meshes.array.items, 0..) |mesh, mesh_index| {
                var is_collider: bool = false;
                if (collider_mesh_indices) |indices| {
                    for (indices.array.items) |index| {
                        if (index.integer == mesh_index) {
                            is_collider = true;
                            break;
                        }
                    }
                }

                if (mesh.object.get("primitives")) |primitives| {
                    for (primitives.array.items) |primitive| {
                        var mode: u32 = 4;
                        if (primitive.object.get("mode")) |mode_value| {
                            mode = @intCast(mode_value.integer);
                        }

                        if (mode == 4) {
                            if (is_collider) {
                                collider_count += 1;
                            } else {
                                mesh_count += 1;
                            }
                        }
                    }
                }
            }
            result = try allocator.alloc(WorldMesh, mesh_count);
            var colliders = try allocator.alloc(CollisionShape, collider_count);

            for (meshes.array.items, 0..) |mesh, mesh_index| {
                var is_collider: bool = false;
                var collider_node: ?std.json.Value = null;
                if (collider_mesh_indices) |indices| {
                    for (indices.array.items) |index| {
                        if (index.integer == mesh_index) {
                            is_collider = true;
                            for (nodes.array.items) |node| {
                                if (node.object.get("mesh")) |node_mesh_index| {
                                    if (mesh_index == @as(usize, @intCast(node_mesh_index.integer))) {
                                        collider_node = node;
                                        break;
                                    }
                                }
                            }
                            break;
                        }
                    }
                }

                if (mesh.object.get("primitives")) |primitives| {
                    for (primitives.array.items) |primitive| {
                        var mode: u32 = 4;
                        if (primitive.object.get("mode")) |mode_value| {
                            mode = @intCast(mode_value.integer);
                        }

                        if (mode == 4) {
                            // Positions.
                            const positions_index: usize =
                                @intCast(primitive.object.get("attributes").?.object.get("POSITION").?.integer);
                            var accessor = accessors.array.items[positions_index];
                            var buffer_view_index: usize = @intCast(accessor.object.get("bufferView").?.integer);
                            var buffer_view = buffer_views.array.items[buffer_view_index];
                            const positions =
                                try extractBufferView([3]f32, accessor, buffer_view, bin_chunk, allocator);

                            // Normals.
                            const normals_index: usize =
                                @intCast(primitive.object.get("attributes").?.object.get("NORMAL").?.integer);
                            accessor = accessors.array.items[normals_index];
                            buffer_view_index = @intCast(accessor.object.get("bufferView").?.integer);
                            buffer_view = buffer_views.array.items[buffer_view_index];
                            const normals =
                                try extractBufferView([3]f32, accessor, buffer_view, bin_chunk, allocator);

                            // UVs.
                            const uvs_index: usize =
                                @intCast(primitive.object.get("attributes").?.object.get("TEXCOORD_0").?.integer);
                            accessor = accessors.array.items[uvs_index];
                            buffer_view_index = @intCast(accessor.object.get("bufferView").?.integer);
                            buffer_view = buffer_views.array.items[buffer_view_index];
                            const uvs =
                                try extractBufferView([2]f32, accessor, buffer_view, bin_chunk, allocator);
                            _ = uvs;

                            // Indices.
                            const indices_index: usize = @intCast(primitive.object.get("indices").?.integer);
                            accessor = accessors.array.items[indices_index];
                            buffer_view_index = @intCast(accessor.object.get("bufferView").?.integer);
                            buffer_view = buffer_views.array.items[buffer_view_index];
                            const indices = try extractBufferView(u16, accessor, buffer_view, bin_chunk, allocator);

                            // Build the result.
                            var vertices: []WorldVertex = try allocator.alloc(WorldVertex, positions.len);
                            for (positions, normals, 0..) |position, normal, vertex_index| {
                                vertices[vertex_index] = .{
                                    .x = position[0],
                                    .y = position[1],
                                    .z = position[2],
                                    .nx = normal[0],
                                    .ny = normal[1],
                                    .nz = normal[2],
                                };
                            }

                            if (is_collider) {
                                colliders[result_collider_index] = extractCollider(collider_node.?, vertices);
                                result_collider_index += 1;
                            } else {
                                result.?[result_mesh_index] = .{
                                    .vertices = vertices,
                                    .indices = indices,
                                    .colliders = colliders,
                                };
                                result_mesh_index += 1;
                            }
                        }
                    }
                }
            }
        }
    } else |err| {
        std.log.info("Failed to parse JSON chunk, Error: {t}, Line: {d}, Column: {d}.", .{
            err,
            diagnostics.getLine(),
            diagnostics.getColumn(),
        });
    }

    return result;
}

fn extractCollider(node: std.json.Value, vertices: []WorldVertex) CollisionShape {
    // Identify the colision shape type.
    const name: []const u8 = node.object.get("name").?.string;
    var name_parts = std.mem.splitScalar(u8, name, '.');
    var shape_type: CollisionShapeType = .Box;
    while (name_parts.next()) |part| {
        if (std.mem.eql(u8, part, "box")) {
            shape_type = .Box;
            break;
        }
    }

    // Extract transform from node.
    var transform: Transform = .{};
    if (node.object.get("translation")) |position| {
        transform.position = .{
            @floatCast(position.array.items[X].float),
            @floatCast(position.array.items[Y].float),
            @floatCast(position.array.items[Z].float),
        };
    }
    if (node.object.get("scale")) |scale| {
        transform.scale = .{
            @floatCast(scale.array.items[X].float),
            @floatCast(scale.array.items[Y].float),
            @floatCast(scale.array.items[Z].float),
        };
    }
    if (node.object.get("rotation")) |rotation| {
        transform.rotation = .{
            @floatCast(rotation.array.items[X].float),
            @floatCast(rotation.array.items[Y].float),
            @floatCast(rotation.array.items[Z].float),
            @floatCast(rotation.array.items[W].float),
        };
    }
    // TODO: Handle node.matrix here if we ever see that situation.

    // Calculate extents of box.
    var min: Vector3 = .{ vertices[0].x, vertices[0].y, vertices[0].z };
    var max: Vector3 = .{ vertices[0].x, vertices[0].y, vertices[0].z };
    for (vertices) |vertex| {
        min = @min(min, Vector3{ vertex.x, vertex.y, vertex.z });
        max = @max(max, Vector3{ vertex.x, vertex.y, vertex.z });
    }
    transform.scale *= max - min;

    // Adjust so the box is centered on its position.
    transform.position += (min + max) * @as(Vector3, @splat(0.5));

    return .{
        .shape = shape_type,
        .transform = transform,
    };
}

fn extractBufferView(
    T: type,
    accessor: std.json.Value,
    buffer_view: std.json.Value,
    bin_chunk: Chunk,
    allocator: std.mem.Allocator,
) ![]T {
    const count: usize = @intCast(accessor.object.get("count").?.integer);
    var offset: usize = 0;
    if (buffer_view.object.get("byteOffset")) |buffer_view_offset| {
        offset += @intCast(buffer_view_offset.integer);
    }
    if (accessor.object.get("byteOffset")) |accessor_offset| {
        offset += @intCast(accessor_offset.integer);
    }

    const accessor_type: AccessorType = .fromSlice(accessor.object.get("type").?.string);
    const component_count = accessor_type.getComponentCount();
    const data_type: AccessorDataType =
        @fromBackingInt(@intCast(accessor.object.get("componentType").?.integer));
    var stride: ?usize = data_type.getSize() * component_count;
    if (buffer_view.object.get("byteStride")) |byte_stride| {
        stride = @intCast(byte_stride.integer);
    }

    const result_info = @typeInfo(T);
    switch (result_info) {
        .array => |array_info| {
            std.debug.assert(component_count == array_info.len);
            std.debug.assert(accessor_type != .scalar);
            std.debug.assert(data_type.getSize() == @sizeOf(array_info.child));
            data_type.assertType(array_info.child);
        },
        .int => {
            std.debug.assert(component_count == 1);
            std.debug.assert(accessor_type == .scalar);
            std.debug.assert(data_type.getSize() >= @sizeOf(T));
            data_type.assertType(T);
        },
        .float => {
            std.debug.assert(component_count == 1);
            std.debug.assert(accessor_type == .scalar);
            std.debug.assert(data_type.getSize() == @sizeOf(T));
            data_type.assertType(T);
        },
        else => unreachable,
    }

    const result: []T = try allocator.alloc(T, count);
    for (result, 0..) |*out, index| {
        const bytes = bin_chunk.chunk_data[offset + index * stride.? ..];
        switch (result_info) {
            .array => |array_info| {
                if (array_info.len == 2) {
                    switch (accessor_type) {
                        .vec2 => {
                            out.* = .{
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[0..4], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[4..8], .little))),
                            };
                        },
                        else => unreachable,
                    }
                } else if (array_info.len == 3) {
                    switch (accessor_type) {
                        .vec3 => {
                            out.* = .{
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[0..4], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[4..8], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[8..12], .little))),
                            };
                        },
                        else => unreachable,
                    }
                } else if (array_info.len == 4) {
                    switch (accessor_type) {
                        .vec4 => {
                            out.* = .{
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[0..4], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[4..8], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[8..12], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[12..16], .little))),
                            };
                        },
                        .mat2 => {
                            out.* = .{
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[0..4], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[4..8], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[8..12], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[12..16], .little))),
                            };
                        },
                        else => unreachable,
                    }
                } else if (array_info.len == 9) {
                    switch (accessor_type) {
                        .mat3 => {
                            out.* = .{
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[0..4], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[4..8], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[8..12], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[12..16], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[16..20], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[20..24], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[24..28], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[28..32], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[32..36], .little))),
                            };
                        },
                        else => unreachable,
                    }
                } else if (array_info.len == 16) {
                    switch (accessor_type) {
                        .mat3 => {
                            out.* = .{
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[0..4], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[4..8], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[8..12], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[12..16], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[16..20], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[20..24], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[24..28], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[28..32], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[32..36], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[36..40], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[40..44], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[44..48], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[48..52], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[52..56], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[56..60], .little))),
                                @as(f32, @bitCast(std.mem.readInt(u32, bytes[60..64], .little))),
                            };
                        },
                        else => unreachable,
                    }
                }
            },
            .int => {
                switch (accessor_type) {
                    .scalar => {
                        out.* = std.mem.readInt(T, bytes[0..@sizeOf(T)], .little);
                    },
                    else => unreachable,
                }
            },
            .float => {
                switch (accessor_type) {
                    .scalar => {
                        out.* = @bitCast(std.mem.readInt(u32, bytes[0..4], .little));
                    },
                    else => unreachable,
                }
            },
            else => unreachable,
        }
    }

    return result;
}

fn parseChunk(reader: *std.Io.Reader, required_chunk_type: ChunkType) !Chunk {
    const chunk_length: u32 = try reader.takeInt(u32, .little);
    const chunk_type_int: u32 = try reader.takeInt(u32, .little);
    const chunk_type: ChunkType = @fromBackingInt(@intCast(chunk_type_int));
    const chunk_data: []const u8 = try reader.take(chunk_length);

    std.debug.assert(chunk_type == required_chunk_type);
    std.debug.assert(chunk_data.len == chunk_length);

    std.log.info("chunk_type: {d}, chunk_length: {d}", .{ chunk_type, chunk_length });

    return .{
        .chunk_length = chunk_length,
        .chunk_type = chunk_type,
        .chunk_data = chunk_data,
    };
}

fn fourCC(bytes: []const u8) u32 {
    std.debug.assert(bytes.len == 4);
    return std.mem.readInt(u32, bytes[0..4], .little);
}
