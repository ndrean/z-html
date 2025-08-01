const std = @import("std");
const lxb = @import("lexbor.zig");

const testing = std.testing;
const Print = std.debug.print;

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    const fragment =
        \\<div>
        \\<p>First<span>
        \\Second</span>
        \\</p>
        \\<p>Third </p>
        \\</div>
        \\<div>
        \\ <ul>
        \\<li>Fourth</li>
        \\<li>Fifth</li>
        \\</ul>
        \\</div>"
    ;

    // const allocator = testing.allocator;
    const doc = try lxb.parseFragmentAsDocument(fragment);
    defer lxb.destroyDocument(doc);
    const body_element = lxb.getBodyElement(doc);
    // orelse LexborError.EmptyTextContent;

    const body_node = lxb.elementToNode(body_element.?);
    const text_content = try lxb.getNodeTextContent(allocator, body_node);
    defer allocator.free(text_content);
    Print("{s}\n", .{text_content});
}

test "slice comparison examples" {
    const allocator = testing.allocator;

    // String/slice content comparison
    const text1 = try allocator.dupe(u8, "hello");
    defer allocator.free(text1);
    const text2 = "hello";

    // ✅ Compare slice contents
    try testing.expectEqualStrings(text1, text2);

    // ❌ This would fail - different pointers
    // try testing.expectEqual(text1, text2);

    // Numbers and primitives
    const num1: u32 = 42;
    const num2: u32 = 42;

    // ✅ Compare primitive values
    try testing.expectEqual(num1, num2);

    // Optional comparison
    const maybe_text: ?[]const u8 = "hello";

    // ✅ Compare optional contents
    try testing.expect(maybe_text != null);
    try testing.expectEqualStrings("hello", maybe_text.?);

    // Array comparison
    const arr1 = [_]u8{ 1, 2, 3 };
    const arr2 = [_]u8{ 1, 2, 3 };

    // ✅ Compare array contents
    try testing.expectEqualSlices(u8, &arr1, &arr2);
}
