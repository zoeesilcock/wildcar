const std = @import("std");
const c = @import("c");
const flint = @import("flint");
const math = @import("math");
const game = @import("root.zig");
const renderer = @import("render/renderer.zig");
const car = @import("car.zig");
const b3 = @import("b3.zig");

// Types.
const State = game.State;
const Entity = game.Entity;
const ModelId = renderer.ModelId;
const Model = @import("render/model.zig").Model;
const Transform = math.Transform;
const Vector3 = math.Vector3;
const Color = math.Color;
const X = math.X;
const Y = math.Y;
const Z = math.Z;
const W = math.W;

const SceneEntity = struct {
    position: Vector3,
    scale: Vector3,
    rotation: Vector3,
    color: Color = .{ 0.9, 0.3, 0.2, 1 },
    model_id: ModelId = .Cube,
    has_collider: bool = true,
    is_dynamic: bool = false,
    children: []SceneEntity = &.{},
};

const Scene = struct {
    items: []SceneEntity = &.{},

    pub fn loadFromFile(path: []const u8, allocator: std.mem.Allocator, io: std.Io) Scene {
        var scene: Scene = .{};
        if (flint.fs.getFilePathRelative(io, path, allocator)) |relative_path| {
            defer allocator.free(relative_path);

            const scene_file = flint.fs.openFileRelative(io, relative_path, .{ .mode = .read_only }) catch
                @panic("Failed to open scene file");
            defer scene_file.close(io);

            const scene_slice = std.Io.Dir.cwd().readFileAllocOptions(io, path, allocator, .unlimited, .@"1", 0) catch
                @panic("Failed to read scene file");
            defer allocator.free(scene_slice);

            scene = std.zon.parse.fromSliceAlloc(Scene, allocator, scene_slice, null, .{}) catch
                @panic("Failed to parse scene .zon file");
        } else |_| {
            @panic("Failed to open scene file");
        }
        return scene;
    }
};

pub fn load(state: *State) void {
    const scene: Scene = .loadFromFile("assets/scene.zon", state.allocator, state.dependencies.io.*);
    defer std.zon.parse.free(state.allocator, scene);

    for (scene.items) |item| {
        const entity = state.entities.addOne(state.allocator) catch @panic("Failed to add entity");
        entity.* = .{
            .transform = .{
                .position = item.position,
                .scale = item.scale,
                .rotation = math.eulerToQuaternion(item.rotation),
            },
            .has_collider = item.has_collider,
            .is_dynamic = item.is_dynamic,
            .color = item.color,
            .model_id = item.model_id,
            .children = state.allocator.alloc(Entity, item.children.len) catch @panic("Failed to allocate child entities"),
        };

        for (item.children, 0..) |child, i| {
            entity.children[i] = .{
                .transform = .{
                    .position = child.position,
                    .scale = child.scale,
                    .rotation = math.eulerToQuaternion(child.rotation),
                },
                .has_collider = child.has_collider,
                .is_dynamic = child.is_dynamic,
                .color = child.color,
                .model_id = child.model_id,
            };
        }
    }
}

pub fn unload(state: *State) void {
    state.entities.clearRetainingCapacity();
}

pub fn initBox3D(state: *State) void {
    var world_definition: c.b3WorldDef = c.b3DefaultWorldDef();
    world_definition.gravity = .{ .x = 0, .y = -game.GRAVITY, .z = 0 };
    state.world_id = c.b3CreateWorld(&world_definition);

    var ground_body_def: c.b3BodyDef = c.b3DefaultBodyDef();
    ground_body_def.position = .{ .x = 0, .y = -20, .z = 0 };

    const ground_id: c.b3BodyId = c.b3CreateBody(state.world_id, &ground_body_def);

    const ground_box: c.b3BoxHull = c.b3MakeBoxHull(500, 10, 500);
    const ground_shape_def: c.b3ShapeDef = c.b3DefaultShapeDef();
    _ = c.b3CreateHullShape(ground_id, &ground_shape_def, &ground_box.base);

    for (state.entities.items) |*entity| {
        if (entity.has_collider) {
            entity.body_id = spawnBodyForEntity(
                entity,
                null,
                state.renderer.models.get(entity.model_id),
                state.world_id,
            );
        }

        for (entity.children) |*child_entity| {
            if (child_entity.has_collider) {
                child_entity.body_id = spawnBodyForEntity(
                    child_entity,
                    entity,
                    state.renderer.models.get(entity.model_id),
                    state.world_id,
                );
            }
        }
    }
}

fn spawnBodyForEntity(
    entity: *const Entity,
    parent_entity: ?*const Entity,
    opt_model: ?*const Model,
    world_id: c.b3WorldId,
) c.b3BodyId {
    var body_id: c.b3BodyId = undefined;

    if (parent_entity) |parent| {
        body_id = parent.body_id;
    } else {
        var body_def: c.b3BodyDef = c.b3DefaultBodyDef();
        body_def.position = .{
            .x = entity.transform.position[X],
            .y = entity.transform.position[Y],
            .z = entity.transform.position[Z],
        };
        body_def.rotation = .{
            .v = .{
                .x = entity.transform.rotation[X],
                .y = entity.transform.rotation[Y],
                .z = entity.transform.rotation[Z],
            },
            .s = entity.transform.rotation[W],
        };
        body_def.type = if (entity.is_dynamic or (parent_entity != null and parent_entity.?.is_dynamic))
            c.b3_dynamicBody
        else
            c.b3_staticBody;

        body_id = c.b3CreateBody(world_id, &body_def);
    }

    if (opt_model) |model| {
        for (model.colliders) |collision_shape| {
            var transform: Transform = collision_shape.transform.toScaledMeshSpace(entity.transform.scale);

            if (parent_entity != null) {
                transform = transform.relativeTo(entity.transform);
            }

            switch (collision_shape.shape) {
                .Box => {
                    const box: c.b3BoxHull = c.b3MakeTransformedBoxHull(
                        transform.scale[X] / 2,
                        transform.scale[Y] / 2,
                        transform.scale[Z] / 2,
                        .{
                            .p = b3.vecToB3(transform.position),
                            .q = b3.quatToB3(transform.rotation),
                        },
                    );

                    var shape_def: c.b3ShapeDef = c.b3DefaultShapeDef();
                    shape_def.density = 1;
                    shape_def.baseMaterial.friction = 0.3;

                    _ = c.b3CreateHullShape(body_id, &shape_def, &box.base);
                },
            }
        }
    }

    return body_id;
}

pub fn deinitBox3D(state: *State) void {
    c.b3DestroyWorld(state.world_id);
}
