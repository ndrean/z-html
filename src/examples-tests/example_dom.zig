const std = @import("std");
const z = @import("src/zhtml.zig");
const print = std.debug.print;

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    // Example of the DOM functionality you requested

    // 1. Parse some HTML
    const html =
        \\<html>
        \\  <body>
        \\    <div class="container">
        \\      <p>First paragraph</p>
        \\      <p>Second paragraph</p>
        \\      <span>A span element</span>
        \\      <div>
        \\        <p>Nested paragraph</p>
        \\      </div>
        \\    </div>
        \\  </body>
        \\</html>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    print("=== DOM Search Functions Demo ===\n", .{});

    // 2. Search function: getElementsByTagName
    print("\n1. Finding all paragraphs with getElementsByTagName:\n", .{});
    if (try z.getElementsByTagName(doc, "P")) |paragraphs| {
        defer z.destroyCollection(paragraphs);
        print("Found {} paragraph(s)\n", .{z.collectionLength(paragraphs)});

        for (0..z.collectionLength(paragraphs)) |i| {
            if (z.getCollectionElementAt(paragraphs, i)) |p| {
                const p_node = z.elementToNode(p);
                const text = try z.textContentOpts(allocator, p_node, .{});
                defer allocator.free(text);

                print("  - Paragraph {}: '{}'\n", .{ i + 1, text });
            }
        }
    }

    // 3. Search by class
    print("\n2. Finding elements by class:\n", .{});
    if (try z.getElementsByClassName(doc, "container")) |containers| {
        defer z.destroyCollection(containers);
        print("Found {} element(s) with class 'container'\n", .{z.collectionLength(containers)});
    }

    print("\n=== DOM Manipulation Demo ===\n", .{});

    // 4. Create a document fragment and manipulate DOM
    print("\n3. Creating document fragment:\n", .{});
    const fragment = try z.createDocumentFragment(doc);

    // Create some new elements to add to the fragment
    const new_div1 = try z.createElementAttr(doc, "div", &.{});
    const new_div2 = try z.createElementAttr(doc, "div", &.{});
    const new_div3 = try z.createElementAttr(doc, "div", &.{});

    // Add text content to the divs
    const text1 = try z.createTextNode(doc, "Fragment child 1");
    const text2 = try z.createTextNode(doc, "Fragment child 2");
    const text3 = try z.createTextNode(doc, "Fragment child 3");

    z.appendChild(z.elementToNode(new_div1), text1);
    z.appendChild(z.elementToNode(new_div2), text2);
    z.appendChild(z.elementToNode(new_div3), text3);

    // Add elements to the fragment
    z.appendChild(z.documentFragmentToNode(fragment), z.elementToNode(new_div1));
    z.appendChild(z.documentFragmentToNode(fragment), z.elementToNode(new_div2));
    z.appendChild(z.documentFragmentToNode(fragment), z.elementToNode(new_div3));

    print("Created fragment with 3 div elements\n", .{});

    // 5. Get the body element and append the fragment
    if (z.bodyElement(doc)) |body| {
        print("\n4. Appending fragment to body:\n", .{});
        try z.appendFragment(body, fragment);
        print("Fragment children moved to body (fragment semantics - children move, not copy)\n", .{});

        // Verify the new structure
        print("\n5. Verifying final document structure:\n", .{});
        if (try z.getElementsByTagName(doc, "DIV")) |all_divs| {
            defer z.destroyCollection(all_divs);
            print("Total DIV elements in document: {}\n", .{z.collectionLength(all_divs)});

            for (0..z.collectionLength(all_divs)) |i| {
                if (z.getCollectionElementAt(all_divs, i)) |div| {
                    if (z.getElementTextContent(div)) |text| {
                        print("  - DIV {}: '{}'\n", .{ i + 1, text });
                    } else {
                        print("  - DIV {}: (no text content)\n", .{i + 1});
                    }
                }
            }
        }
    }

    print("\n=== Demo Complete ===\n", .{});
    print("Available DOM functions:\n", .{});
    print("  Search: getElementsByTagName, getElementsByClassName, getElementsById\n", .{});
    print("  Manipulation: createDocumentFragment, appendFragment, appendChild\n", .{});
    print("  Creation: createElementAttr, createTextNode\n", .{});
    print("  Note: insertNodeBefore/After fallback to appendChild (Lexbor limitation)\n", .{});
}
