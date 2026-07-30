const std = @import("std");
const flint = @import("flint");
const sdl = flint.sdl.c;
const imgui = flint.imgui;
const math = @import("math");
const renderer = @import("render/renderer.zig");
const game = @import("root.zig");
const car = @import("car.zig");

// Types.
const State = game.State;
const FrameContext = renderer.FrameContext;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;

pub fn draw(state: *State, context: *FrameContext, swapchain_texture: *sdl.SDL_GPUTexture) void {
    imgui.newFrame();

    const dockspace_id: imgui.c.ImGuiID = imgui.c.ImGui_GetID("Dockspace");
    const viewport: *imgui.c.ImGuiViewport = imgui.c.ImGui_GetMainViewport();

    if (imgui.internal.ImGui_DockBuilderGetNode(dockspace_id) == null) {
        _ = imgui.internal.ImGui_DockBuilderAddNodeEx(dockspace_id, imgui.internal.ImGuiDockNodeFlagsPrivate.DockSpace);
        imgui.internal.ImGui_DockBuilderSetNodeSize(dockspace_id, viewport.Size);
        var dock_id_left: imgui.c.ImGuiID = 0;
        var dock_id_right: imgui.c.ImGuiID = 0;
        var dock_id_main: imgui.c.ImGuiID = dockspace_id;
        _ = imgui.internal.ImGui_DockBuilderSplitNode(
            dock_id_main,
            imgui.c.ImGuiDir_Left,
            0.2727,
            &dock_id_left,
            &dock_id_main,
        );
        _ = imgui.internal.ImGui_DockBuilderSplitNode(
            dock_id_main,
            imgui.c.ImGuiDir_Right,
            0.4,
            &dock_id_right,
            &dock_id_main,
        );
        imgui.internal.ImGui_DockBuilderDockWindow("Game", dock_id_main);
        imgui.internal.ImGui_DockBuilderDockWindow("Car spec", dock_id_left);
        imgui.internal.ImGui_DockBuilderDockWindow("Game state", dock_id_right);
        imgui.internal.ImGui_DockBuilderFinish(dockspace_id);
    }

    _ = imgui.c.ImGui_DockSpaceOverViewportEx(
        dockspace_id,
        viewport,
        imgui.c.ImGuiDockNodeFlags_PassthruCentralNode,
        null,
    );

    state.dependencies.internal.fps_window.position =
        if (state.internal.inspect_car_spec)
            .{ .x = 150, .y = -5 }
        else
            .{ .x = 5, .y = 5 };
    state.dependencies.internal.fps_window.draw();
    state.dependencies.internal.output.draw();
    state.dependencies.internal.memory_usage_window.draw();

    if (state.internal.inspect_game_state) {
        imgui.c.ImGui_SetNextWindowPosEx(
            imgui.c.ImVec2{ .x = 475, .y = 30 },
            imgui.c.ImGuiCond_FirstUseEver,
            imgui.c.ImVec2{ .x = 0, .y = 0 },
        );
        imgui.c.ImGui_SetNextWindowSize(imgui.c.ImVec2{ .x = 300, .y = 540 }, imgui.c.ImGuiCond_FirstUseEver);

        _ = imgui.c.ImGui_Begin("Game state", null, imgui.c.ImGuiWindowFlags_NoFocusOnAppearing);
        defer imgui.c.ImGui_End();

        flint.internal.inspectStruct(state, &.{ "io", "allocator", "arena" }, false, &.{
            // .input(f32, "time_of_day", 0.01, 0.1),
            // .drag(f32, "time_of_day", 0.01, 0, 1),
            .slider(f32, "time_of_day", 0, 1),
        }, inputCustomTypes);
    }

    if (state.internal.inspect_car_spec) {
        imgui.c.ImGui_SetNextWindowPosEx(
            imgui.c.ImVec2{ .x = 30, .y = 30 },
            imgui.c.ImGuiCond_FirstUseEver,
            imgui.c.ImVec2{ .x = 0, .y = 0 },
        );
        imgui.c.ImGui_SetNextWindowSize(imgui.c.ImVec2{ .x = 300, .y = 540 }, imgui.c.ImGuiCond_FirstUseEver);

        _ = imgui.c.ImGui_Begin("Car spec", null, imgui.c.ImGuiWindowFlags_NoFocusOnAppearing);
        defer imgui.c.ImGui_End();

        flint.internal.inspectStruct(&car.car_spec, &.{ "wheel_count", "drive_wheels", "steer_wheels" }, false, &.{
            .slider(f32, "suspension_damping_ratio", 0, 1),
        }, inputCustomTypes);

        imgui.c.ImGui_Dummy(imgui.c.ImVec2{ .x = 0, .y = 16 });
        if (imgui.c.ImGui_ButtonEx("Save", imgui.c.ImVec2{ .x = -std.math.floatMin(f32), .y = 0 })) {
            car.car_spec.saveToFile("assets/cars/default.zon", state.allocator, state.dependencies.io.*);
        }
    }

    imgui.renderGPU(context.command_buffer, swapchain_texture);
}

fn inputCustomTypes(
    struct_field_name: [:0]const u8,
    field_ptr: anytype,
) bool {
    var handled: bool = true;

    switch (@TypeOf(field_ptr.*)) {
        Vector2 => {
            imgui.c.ImGui_PushIDPtr(field_ptr);
            defer imgui.c.ImGui_PopID();

            _ = imgui.c.ImGui_InputFloat2Ex(struct_field_name, @ptrCast(field_ptr), "%.2f", 0);
        },
        Vector3 => {
            imgui.c.ImGui_PushIDPtr(field_ptr);
            defer imgui.c.ImGui_PopID();

            _ = imgui.c.ImGui_InputFloat3Ex(struct_field_name, @ptrCast(field_ptr), "%.2f", 0);
        },
        else => handled = false,
    }

    return handled;
}
