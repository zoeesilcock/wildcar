const std = @import("std");
const flint = @import("flint");

const Chunk = struct {
    chunk_length: u32,
    chunk_type: ChunkType,
    chunk_data: []const u8,
};

const ChunkType = enum(u32) {
    json = fourCC("JSON"),
    bin = fourCC("BIN\x00"),
};

pub fn loadGLB(path: []const u8, allocator: std.mem.Allocator, io: std.Io) !void {
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

    _ = bin_chunk;

    // Parse the JSON chunk.
    var scanner = std.json.Scanner.initCompleteInput(allocator, json_chunk.chunk_data);
    defer scanner.deinit();
    var diagnostics = std.json.Scanner.Diagnostics{};
    scanner.enableDiagnostics(&diagnostics);

    if (std.json.parseFromTokenSource(std.json.Value, allocator, &scanner, .{})) |json| {
        defer json.deinit();

        // TODO: Extract the data from the bin chunk based on the json.
        // * Use meshes.primitives.0 to get the index for each of the accessors.
        //   * attributes contains position, normal and uv.
        //   * indices contains vertex indices.
        // * Use the bufferView on each accessor to grab the data from the binary chunk.
        // * Create a slice of WorldVertex, length based on the position accessor.
        // * Create a slice of u16 indices into the vertex slice, length based on the indices accessor.
        // * Later we need to expand our WorldVertex struct to include UV.
    } else |err| {
        std.log.err("Failed to parse JSON chunk: {t}", .{err});
    }
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
