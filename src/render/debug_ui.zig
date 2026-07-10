const math = @import("math");
const game = @import("../root.zig");

// Types.
const State = game.State;
const Vector2 = math.Vector2;
const Vector3 = math.Vector3;

pub fn draw(state: *State, context: *FrameContext) void {
    if (INTERNAL) {
        imgui.newFrame();
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

            flint.internal.inspectStruct(state, &.{ "io", "allocator", "arena" }, false, inputCustomTypes);
        }

        imgui.renderGPU(context.command_buffer, swapchain_texture);
    }
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
