const std = @import("std");
const z = @import("../zhtml.zig");

const print = std.debug.print;

pub fn runBasicCollectionExample() !void {
    // Example HTML with IDs
    const html =
        \\<html>
        \\  <body>
        \\    <div id="container">
        \\      <h1 id="title">Welcome</h1>
        \\      <p id="description">This is a test page</p>
        \\      <button id="click-me">Click Me!</button>
        \\    </div>
        \\    <div id="footer">Footer content</div>
        \\    <ul id="ul" phx-update="stream">
        \\      <li id="item-1">Item 1</li>
        \\      <li id="item-2">Item 2</li>
        \\      <li id="item-3">Item 3</li>
        \\      <li id="item-4">Item 4</li>
        \\    </ul>
        \\    <tbody id="items" phx-update="stream">
        \\      <tr 
        \\        :for={{dom_id, item} <- @streams.items}}>
        \\        id={dom_id}
        \\        phx-click={select_item(@myself)}
        \\        phx-value-id={item.id}
        \\        class={"group #{if MapSet.member(@selected_items, item), do: "selected"} ..."}
        \\      >
        \\        <td>
        \\          <.icon class="hidden group-[.selected]:block" name="hero-check-circle" />
        \\        </td>
        \\      </tr>
        \\    </tbody>
        \\  </body>
        \\</html>
    ;

    // Parse the HTML
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    print("=== getElementById Examples ===\n", .{});

    // Example 1: Find element by ID
    if (try z.getElementById(doc, "title")) |title_element| {
        print("✓ Found title element: {*}\n", .{title_element});
    } else {
        print("✗ Title element not found\n", .{});
    }

    // Example 2: Find another element
    const inp = z.getElementsByAttribute(doc, "id", "description", false);
    if (inp) |desc_element| {
        print("✓ Found description element: {*}\n", .{desc_element});
    } else {
        print("✗ Description element not found\n", .{});
    }

    // Example 3: Try to find non-existent element
    if (try z.getElementById(doc, "nonexistent")) |_| {
        print("✗ This should not happen\n", .{});
    } else {
        print("✓ Correctly returned null for non-existent ID\n", .{});
    }

    print("\n=== Collection Examples ===\n", .{});

    // Example 4: Create and use a collection manually
    if (z.createDefaultCollection(doc)) |collection| {
        defer z.destroyCollection(collection);

        print("✓ Created collection successfully\n", .{});
        print("Collection length: {}\n", .{z.getCollectionLength(collection)});

        if (z.isCollectionEmpty(collection)) {
            print("✓ Collection is empty as expected\n", .{});
        }
    } else {
        print("✗ Failed to create collection\n", .{});
    }

    // Example 5: Get document element
    if (try z.getDocumentElement(doc)) |root_element| {
        print("✓ Found document root element: {*}\n", .{root_element});
    } else {
        print("✗ Could not get document root element\n", .{});
    }

    print("\n=== Performance Note ===\n", .{});
    print("getElementById is optimized for single element lookup\n", .{});
    print("It uses Lexbor's native lxb_dom_elements_by_attr function\n", .{});
    print("For complex queries, use CSS selectors: z.findElements\n", .{});
}
