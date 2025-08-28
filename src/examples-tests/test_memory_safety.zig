const std = @import("std");
const z = @import("zhtml.zig");

test "Memory safety demonstration: lexbor ownership vs Zig ownership" {
    const allocator = std.testing.allocator;

    std.debug.print("\n=== Memory Safety Analysis ===\n", .{});

    const doc = try z.printDocStruct("<div><span>content</span></div>");
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const div = z.firstElementChild(body).?;

    // ❌ UNSAFE: Borrowing lexbor's memory
    const unsafe_tag = z.tagNameBorrow(div);
    std.debug.print("Unsafe tag (borrowing): {s}\n", .{unsafe_tag});

    // ✅ SAFE: Copying to Zig-owned memory
    const safe_tag = try z.tagName(allocator, div);
    defer allocator.free(safe_tag);
    std.debug.print("Safe tag (owned): {s}\n", .{safe_tag});

    // Both should be identical initially
    try std.testing.expectEqualStrings(unsafe_tag, safe_tag);

    // Demonstrate that immediate use of unsafe version is OK
    if (z.matchesTagName(div, "DIV")) {
        std.debug.print("✅ Immediate comparison with unsafe version works\n", .{});
    }

    // The owned version remains valid throughout the scope
    try std.testing.expectEqualStrings("DIV", safe_tag);

    std.debug.print("=== Key Takeaways ===\n", .{});
    std.debug.print("• tagName(): Fast but unsafe for storage\n", .{});
    std.debug.print("• tagName(): Safe but requires allocation\n", .{});
    std.debug.print("• Use unsafe version for immediate comparisons\n", .{});
    std.debug.print("• Use owned version when storing tag names\n", .{});
}

test "Practical usage patterns" {
    const allocator = std.testing.allocator;
    const doc = try z.printDocStruct("<div><p>para</p><span>text</span></div>");
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const div = z.firstElementChild(body).?;

    std.debug.print("\n=== Practical Usage Patterns ===\n", .{});

    // ✅ PATTERN 1: Immediate comparison (safe with unsafe function)
    std.debug.print("Pattern 1: Immediate comparison\n", .{});
    var count: u32 = 0;
    var child = z.firstElementChild(div);
    while (child) |element| {
        const tag = z.tagNameBorrow(element); // Safe for immediate use
        std.debug.print("  Found: {s}\n", .{tag});
        if (std.mem.eql(u8, tag, "P")) {
            count += 1;
        }
        child = z.nextElementSibling(element);
    }
    try std.testing.expect(count == 1);

    // ✅ PATTERN 2: Collecting tag names (must use owned version)
    std.debug.print("Pattern 2: Collecting tag names for later use\n", .{});
    var tag_names = std.ArrayList([]u8).init(allocator);
    defer {
        for (tag_names.items) |tag| {
            allocator.free(tag);
        }
        tag_names.deinit();
    }

    child = z.firstElementChild(div);
    while (child) |element| {
        const owned_tag = try z.tagName(allocator, element);
        try tag_names.append(owned_tag);
        child = z.nextElementSibling(element);
    }

    // Now we can safely use these tag names later
    for (tag_names.items) |tag| {
        std.debug.print("  Stored: {s}\n", .{tag});
    }
    try std.testing.expect(tag_names.items.len == 2);
    try std.testing.expectEqualStrings("P", tag_names.items[0]);
    try std.testing.expectEqualStrings("SPAN", tag_names.items[1]);
}
