const std = @import("std");
const z = @import("../zhtml.zig");
const print = std.debug.print;

pub fn main() !void {
    // Example: Configurable Default Collection Capacity

    print("=== Configurable Default Collection Capacity Demo ===\n", .{});

    // 1. Check initial default capacity
    print("Initial default capacity: {}\n", .{z.getDefaultCapacity()});

    // 2. Change the default capacity for all future collections
    print("Setting default capacity to 50...\n", .{});
    z.setDefaultCapacity(50);

    print("New default capacity: {}\n", .{z.getDefaultCapacity()});

    // 3. Parse some HTML and test collection creation
    const html =
        \\<html>
        \\  <body>
        \\    <div class="container">
        \\      <p>First paragraph</p>
        \\      <p>Second paragraph</p>
        \\      <span>A span element</span>
        \\    </div>
        \\  </body>
        \\</html>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // 4. Create collections with different capacity options
    print("\n=== Collection Creation Examples ===\n", .{});

    // Default collection now uses capacity 50
    print("Creating collection with .default capacity (should be 50)...\n", .{});
    if (z.createDefaultCollection(doc)) |default_collection| {
        defer z.destroyCollection(default_collection);
        print("✅ Default collection created successfully\n", .{});
    }

    // Single element collection (always capacity 1)
    print("Creating collection with .single capacity (always 1)...\n", .{});
    if (z.createSingleElementCollection(doc)) |single_collection| {
        defer z.destroyCollection(single_collection);
        print("✅ Single element collection created successfully\n", .{});
    }

    // Custom capacity collection (explicit capacity)
    print("Creating collection with custom capacity of 100...\n", .{});
    if (z.createCollection(doc, .{ .custom = .{ .value = 100 } })) |custom_collection| {
        defer z.destroyCollection(custom_collection);
        print("✅ Custom capacity collection created successfully\n", .{});
    }

    // 5. Test with getElementsByAttributeName (uses configurable default)
    print("\n=== Testing with Search Functions ===\n", .{});
    if (try z.getElementsByAttributeName(doc, "class", .default)) |class_elements| {
        defer z.destroyCollection(class_elements);
        print("Found {} elements with 'class' attribute using default capacity ({})\n", .{ z.collectionLength(class_elements), z.getDefaultCapacity() });
    }

    // 6. Reset to original default
    print("\nResetting to original default capacity (10)...\n", .{});
    z.resetDefaultCapacity();
    print("Reset complete. Current default capacity: {}\n", .{z.getDefaultCapacity()});

    print("\n=== Usage Summary ===\n", .{});
    print("Available capacity configuration functions:\n", .{});
    print("  • z.setDefaultCapacity(value) - Set global default\n", .{});
    print("  • z.getDefaultCapacity() - Get current default\n", .{});
    print("  • z.resetDefaultCapacity() - Reset to 10\n", .{});
    print("\nCapacity options for collections:\n", .{});
    print("  • .single - Always capacity 1\n", .{});
    print("  • .default - Uses global default (configurable)\n", .{});
    print("  • .{{ .custom = .{{ .value = N }} }} - Explicit capacity N\n", .{});

    print("\nThis is useful for:\n", .{});
    print("  • Large documents with many elements\n", .{});
    print("  • Memory-constrained environments\n", .{});
    print("  • Performance tuning based on expected result sizes\n", .{});
}
