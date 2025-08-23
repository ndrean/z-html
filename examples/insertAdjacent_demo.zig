//! Example demonstrating insertAdjacentElement and insertAdjacentHTML functions
const std = @import("std");
const z = @import("src/zhtml.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a simple document
    const doc = try z.parseFromString(
        \\<html><body>
        \\    <div id="container">
        \\        <p id="target">Target Element</p>
        \\    </div>
        \\</body></html>
    );
    defer z.destroyDocument(doc);

    const target = try z.getElementById(doc, "target");
    const target_node = z.elementToNode(target.?);

    std.debug.print("=== insertAdjacentElement Demo ===\n");

    // Demo insertAdjacentElement with all positions
    const before_elem = try z.createElementAttr(doc, "h2", &.{.{ .name = "class", .value = "before" }});
    try z.setTextContent(z.elementToNode(before_elem), "Before Begin");
    try z.insertAdjacentElement(target_node, .beforebegin, z.elementToNode(before_elem));

    const after_elem = try z.createElementAttr(doc, "h2", &.{.{ .name = "class", .value = "after" }});
    try z.setTextContent(z.elementToNode(after_elem), "After End");
    try z.insertAdjacentElement(target_node, .afterend, z.elementToNode(after_elem));

    // Show result after insertAdjacentElement
    const body = try z.bodyNode(doc);
    const html1 = try z.serializeToString(allocator, body);
    defer allocator.free(html1);
    std.debug.print("After insertAdjacentElement:\n{s}\n\n", .{html1});

    std.debug.print("=== insertAdjacentHTML Demo ===\n");

    // Demo insertAdjacentHTML with different positions
    try z.insertAdjacentHTML(allocator, target_node, .afterbegin, "<span style='color: blue;'>First Child</span>");
    try z.insertAdjacentHTML(allocator, target_node, .beforeend, "<span style='color: red;'>Last Child</span>");

    // Show final result
    const html2 = try z.serializeToString(allocator, body);
    defer allocator.free(html2);
    std.debug.print("After insertAdjacentHTML:\n{s}\n\n", .{html2});

    std.debug.print("=== Position Enum Demo ===\n");

    // Demo InsertPosition.fromString
    const positions = [_][]const u8{ "beforebegin", "afterbegin", "beforeend", "afterend", "invalid" };
    for (positions) |pos_str| {
        if (z.InsertPosition.fromString(pos_str)) |pos| {
            std.debug.print("'{s}' -> {s}\n", .{ pos_str, @tagName(pos) });
        } else {
            std.debug.print("'{s}' -> null (invalid)\n", .{pos_str});
        }
    }
}
