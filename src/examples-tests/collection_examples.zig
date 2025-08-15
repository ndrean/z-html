const std = @import("std");
const z = @import("../zhtml.zig");

pub fn runCollectionExamples() !void {
    // Example HTML with various attributes
    const html =
        \\<html>
        \\  <body>
        \\    <form id="login-form" class="form" method="post">
        \\      <h2 id="title" class="heading">Login Form</h2>
        \\      <div class="form-group">
        \\        <input type="text" name="username" id="username" required placeholder="Username">
        \\        <input type="password" name="password" id="password" required placeholder="Password">
        \\      </div>
        \\      <div class="form-actions">
        \\        <button type="submit" id="submit-btn" class="btn primary">Login</button>
        \\        <button type="reset" id="reset-btn" class="btn secondary">Reset</button>
        \\      </div>
        \\    </form>
        \\    <div id="messages" class="hidden"></div>
        \\  </body>
        \\</html>
    ;

    // Parse the HTML
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    std.debug.print("=== getElementById Examples ===\n", .{});

    // Example 1: Find specific elements by ID
    if (try z.getElementById(doc, "login-form")) |form| {
        std.debug.print("✓ Found login form: {*}\n", .{form});
    }

    if (z.getElementById(doc, "username")) |input| {
        std.debug.print("✓ Found username input: {*}\n", .{input});
    }

    std.debug.print("\n=== getElementsByAttribute Examples ===\n", .{});

    // Example 2: Find elements by attribute value
    {
        const text_inputs = z.getElementsByAttribute(doc, "type", "text", false) orelse {
            std.debug.print("✗ Failed to create collection\n", .{});
            return;
        };
        defer z.destroyCollection(text_inputs);

        std.debug.print("Found {} text input(s)\n", .{z.collectionLength(text_inputs)});
    }

    // Example 3: Find elements by class
    {
        const buttons = z.getElementsByAttribute(doc, "class", "btn", false) orelse {
            std.debug.print("✗ Failed to create collection\n", .{});
            return;
        };
        defer z.destroyCollection(buttons);

        std.debug.print("Found {} button(s) with 'btn' class\n", .{z.collectionLength(buttons)});
    }

    std.debug.print("\n=== getElementsByAttributeName Examples ===\n", .{});

    // Example 4: Find all elements with 'id' attribute
    {
        const id_elements = z.getElementsByAttributeName(doc, "id") orelse {
            std.debug.print("✗ Failed to create collection\n", .{});
            return;
        };
        defer z.destroyCollection(id_elements);

        const count = z.collectionLength(id_elements);
        std.debug.print("Found {} element(s) with 'id' attribute:\n", .{count});

        // Use iterator to go through all elements
        var iter = z.collectionIterator(id_elements);
        var i: usize = 0;
        while (iter.next()) |element| {
            std.debug.print("  [{}]: Element with ID attribute {*}\n", .{ i, element });
            i += 1;
        }
    }

    // Example 5: Find all elements with 'required' attribute
    {
        const required_elements = z.getElementsByAttributeName(doc, "required") orelse {
            std.debug.print("✗ Failed to create collection\n", .{});
            return;
        };
        defer z.destroyCollection(required_elements);

        std.debug.print("Found {} required field(s)\n", .{z.collectionLength(required_elements)});
    }

    // Example 6: Find all elements with 'class' attribute
    {
        const class_elements = z.getElementsByAttributeName(doc, "class") orelse {
            std.debug.print("✗ Failed to create collection\n", .{});
            return;
        };
        defer z.destroyCollection(class_elements);

        std.debug.print("Found {} element(s) with 'class' attribute\n", .{z.collectionLength(class_elements)});
    }

    std.debug.print("\n=== Iterator Examples ===\n", .{});

    // Example 7: Advanced iterator usage
    {
        const all_inputs = z.getElementsByAttribute(doc, "type", "text", false) orelse return;
        defer z.destroyCollection(all_inputs);

        const input_count = z.collectionLength(all_inputs);
        if (input_count > 0) {
            std.debug.print("Iterating through {} input(s):\n", .{input_count});

            // Method 1: Using iterator
            std.debug.print("Method 1 - Iterator:\n", .{});
            var iter = z.collectionIterator(all_inputs);
            var index: usize = 0;
            while (iter.next()) |input| {
                std.debug.print("  Input {}: {*}\n", .{ index, input });
                index += 1;
            }

            // Method 2: Manual indexing
            std.debug.print("Method 2 - Manual indexing:\n", .{});
            for (0..input_count) |i| {
                if (z.getCollectionElement(all_inputs, i)) |input| {
                    std.debug.print("  Input {}: {*}\n", .{ i, input });
                }
            }

            // Method 3: Using utility functions
            std.debug.print("Method 3 - Utility functions:\n", .{});
            if (z.getFirstCollectionElement(all_inputs)) |first| {
                std.debug.print("  First input: {*}\n", .{first});
            }
            if (z.getLastCollectionElement(all_inputs)) |last| {
                std.debug.print("  Last input: {*}\n", .{last});
            }
        }
    }

    std.debug.print("\n=== Performance Comparison ===\n", .{});

    // Example 8: Performance comparison
    {
        const start = std.time.nanoTimestamp();

        // Method 1: getElementById (optimized)
        _ = z.getElementById(doc, "submit-btn");

        const mid = std.time.nanoTimestamp();

        // Method 2: getElementsByAttribute (general purpose)
        const collection = z.getElementsByAttribute(doc, "id", "submit-btn", false) orelse return;
        _ = z.getFirstCollectionElement(collection);
        z.destroyCollection(collection);

        const end = std.time.nanoTimestamp();

        std.debug.print("getElementById time: {} ns\n", .{mid - start});
        std.debug.print("getElementsByAttribute time: {} ns\n", .{end - mid});
        std.debug.print("getElementById is typically faster for single ID lookups\n", .{});
    }

    std.debug.print("\n=== Summary ===\n", .{});
    std.debug.print("✓ getElementById: Fast single element lookup by ID\n", .{});
    std.debug.print("✓ getElementsByAttribute: Find elements by attribute name + value\n", .{});
    std.debug.print("✓ getElementsByAttributeName: Find elements that have an attribute (any value)\n", .{});
    std.debug.print("✓ Collection iterators: Multiple ways to process results\n", .{});
    std.debug.print("✓ Memory management: Automatic cleanup with defer\n", .{});
}
