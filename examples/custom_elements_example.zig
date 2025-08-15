const std = @import("std");
const z = @import("../src/zhtml.zig");

test "custom elements and escaping behavior" {
    // Test different tag types
    const test_tags = [_][]const u8{ "my-widget", "code-editor", "script", "custom-button", "div" };

    std.debug.print("\n=== Custom Elements Escaping Example ===\n\n");

    std.debug.print("Standard behavior (safe defaults):\n");
    for (test_tags) |tag| {
        const is_void = z.isVoidElementFast(tag);
        const no_escape = z.isNoEscapeElementFast(tag);
        std.debug.print("  {s:15} -> void: {}, no-escape: {}\n", .{ tag, is_void, no_escape });
    }

    // If you have custom elements that should not be escaped
    const custom_no_escape_tags = [_][]const u8{ "code-editor", "syntax-highlighter" };

    std.debug.print("\nWith custom no-escape tags:\n");
    for (test_tags) |tag| {
        const is_void = z.isVoidElementFast(tag);
        const no_escape = z.isNoEscapeElementExtended(tag, &custom_no_escape_tags);
        std.debug.print("  {s:15} -> void: {}, no-escape: {}\n", .{ tag, is_void, no_escape });
    }

    std.debug.print("\nWhat this means:\n");
    std.debug.print("  • script: no-escape=true  -> JavaScript code won't be escaped\n");
    std.debug.print("  • my-widget: no-escape=false -> HTML inside will be escaped (safer)\n");
    std.debug.print("  • code-editor: custom no-escape -> Raw code content preserved\n\n");
}
