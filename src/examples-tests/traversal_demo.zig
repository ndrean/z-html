const std = @import("std");
const z = @import("../src/zhtml.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse some HTML
    const html = "<div><p>Hello</p><span>World</span><p>Again</p></div>";
    const doc = try z.parse(allocator, html);
    defer z.deinitDocument(doc);

    const body = z.bodyElement(doc);
    const div = z.firstElementChild(body).?;

    std.debug.print("=== Using forEach traversal ===\n");

    // Simple forEach traversal
    z.forEachChildElement(div, printElementInfo);

    std.debug.print("\n=== Using collect for P tags ===\n");

    // Collect all P elements
    const p_elements = try z.collectChildElements(allocator, div, *z.HTMLElement, pElementCollector);
    defer allocator.free(p_elements);

    std.debug.print("Found {} P elements:\n", .{p_elements.len});
    for (p_elements) |p| {
        const text = z.getElementText(allocator, p) catch "no text";
        defer if (!std.mem.eql(u8, text, "no text")) allocator.free(text);
        std.debug.print("  P: {s}\n", .{text});
    }

    std.debug.print("\n=== Testing matchers ===\n");

    // Test the matcher functions
    z.forEachChildElement(div, testMatchers);
}

fn printElementInfo(element: *z.HTMLElement) bool {
    const tag = z.tagNameBorrow(element);
    const text = z.getElementText(std.heap.page_allocator, element) catch "no text";
    defer if (!std.mem.eql(u8, text, "no text")) std.heap.page_allocator.free(text);

    std.debug.print("Element: {} - {s}\n", .{ tag, text });
    return true; // Continue traversal
}

fn pElementCollector(element: *z.HTMLElement) ?*z.HTMLElement {
    if (z.matchesTagName(element, "P")) {
        return element;
    }
    return null;
}

fn testMatchers(element: *z.HTMLElement) bool {
    const tag = z.tagNameBorrow(element);

    std.debug.print("Testing element: {s}\n", .{tag});
    std.debug.print("  Is P tag? {}\n", .{z.matchesTagName(element, "P")});
    std.debug.print("  Is SPAN tag? {}\n", .{z.matchesTagName(element, "SPAN")});

    return true;
}
