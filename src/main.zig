const std = @import("std");
const zhtml = @import("zhtml.zig");
const builtin = @import("builtin");

const print = std.debug.print;

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator, const is_debug = switch (builtin.mode) {
        .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
        .ReleaseFast, .ReleaseSmall => .{ std.heap.c_allocator, false },
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

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
    const doc = try zhtml.parseFragmentAsDocument(fragment);
    defer zhtml.destroyDocument(doc);
    const body_element = zhtml.getBodyElement(doc);
    // orelse LexborError.EmptyTextContent;

    const body_node = zhtml.elementToNode(body_element.?);
    const text_content = try zhtml.getTextContent(allocator, body_node, .{});
    defer allocator.free(text_content);
    print("{s}\n", .{text_content});

    const elements = try zhtml.findElements(allocator, doc, "p");
    defer allocator.free(elements);
    print("elements: {s}\n", .{elements});

    var chunk_parser = try zhtml.ChunkParser.init(allocator);
    defer chunk_parser.deinit();

    const new_doc = try zhtml.parseFragmentAsDocument("<div><p class='test'>Hello World</p></div>");
    defer zhtml.destroyDocument(new_doc);
}
