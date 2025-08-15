const std = @import("std");
const z = @import("zhtml.zig");
const builtin = @import("builtin");
const writer = std.io.getStdOut().writer();

// Import the collection examples
// const collection_examples = @import("examples/collection_examples.zig");
// const example_collection = @import("examples/example_collection.zig");

// const request = @import("examples/http.zig").request;

fn serialiazeAndClean(allocator: std.mem.Allocator, fragment: []const u8) !void {
    const doc = try z.parseFromString(fragment);
    defer z.destroyDocument(doc);

    const body_node = try z.bodyNode(doc);

    const html = try z.serializeToString(
        allocator,
        body_node,
    );
    defer allocator.free(html);

    try writer.print("\n\n---------HTML string to parse---------\n\n", .{});
    try z.printDocumentStructure(doc);
    try writer.print("{s}\n\n", .{html});

    try z.cleanDomTree(
        allocator,
        body_node,
        .{ .remove_comments = true },
    );

    const new_html = try z.serializeToString(
        allocator,
        body_node,
    );
    defer allocator.free(new_html);

    try writer.print("\n\n ==== cleaned HTML =======\n\n", .{});
    try writer.print("{s}\n\n", .{new_html});
    try writer.print("\n\n---------DOCUMENT STRUCTURE---------\n\n", .{});
    try z.printDocumentStructure(doc);

    // _ = try request(allocator, "https://google.com", "text/html");
}

// fn findAttributes(allocator: std.mem.Allocator, html: []const u8, tag_name: []const u8) !void {
//     const doc = try z.parseFromString(html);
//     const elements = try z.findElements(allocator, doc, tag_name);

//     // defer allocator.free(elements);

//     for (elements) |element| {
//         _ = element;
//         // print("{s}\n", .{z.tagName(element)});
//     }

//     // for (elements) |element| {
//     //     if (z.getElementFirstAttribute(element)) |attribute| {
//     //         const name = try z.getAttributeName(allocator, attribute);
//     //         defer allocator.free(name);
//     //         // const value = try z.getAttributeValue(allocator, attribute);
//     //         // defer allocator.free(value);
//     //         // print("Element: {s}, Attribute: {s} = {s}\n", .{
//     //         //     z.tagName(element),
//     //         //     name,
//     //         //     value,
//     //         // });
//     //     } else {
//     //         // print("Element: {s} has no attributes\n", .{z.tagName(element)});
//     //     }
//     // }
// }

fn demonstrateAttributes(html: []const u8) !void {
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);
    const body_node = try z.bodyNode(doc);
    const div = z.firstChild(body_node).?;

    try writer.print("Demonstrating attribute iteration:\n", .{});
    if (z.nodeToElement(div)) |element| {
        var attr = z.getElementFirstAttribute(element);
        var count: usize = 0;
        while (attr != null) {
            count += 1;
            try writer.print("  Found attribute #{}\n", .{count});
            attr = z.getElementNextAttribute(attr.?);
        }
        try writer.print("Total attributes found: {}\n", .{count});
    }
}
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
        \\<div   class  =  " container test "   id  = "main"  >
        \\    
        \\    <p>   Hello     World   </p>
        \\    
        \\    <!-- Remove this comment -->
        \\    <span data-id = "123"></span>
        \\    <pre>    preserve    this    </pre>
        \\    
        \\    <p>  </p>
        \\
        \\   <br/> <!-- This should be removed -->
        \\
        \\    <img src = 'http://google.com' alt = 'my-image' data-value=''/> 
        \\
        \\     <script> const div  = document.querySelector('div'); </script>
        \\</div>
        \\<div data-empty='' title='  spaces  '>Content</div>
        \\<article>
        \\<h1>Title</h1><p>Para 1</p><p>Para 2</p>
        \\<footer>End</footer>
        \\</article>
    ;

    try serialiazeAndClean(allocator, fragment);

    try demonstrateAttributes(fragment);

    try writer.print("\n\n---------ELEMENTS---------\n\n", .{});

    // Example menu system
    try writer.print("\n=== Z-HTML Examples ===\n", .{});
    try writer.print("Choose an example to run:\n", .{});
    try writer.print("1. Basic Collection Example (getElementById, simple demos)\n", .{});
    try writer.print("2. Comprehensive Collection Examples (all features, iterators, performance)\n", .{});
    try writer.print("3. Skip examples\n", .{});
    try writer.print("Enter choice (1-3): ", .{});

    // For now, let's run both examples automatically
    // You can modify this to read from stdin if you want interactive selection

    try writer.print("\n\n=== Running Basic Collection Example ===\n", .{});
    // Collection example temporarily disabled due to missing functions
    // try example_collection.runBasicCollectionExample();

    try writer.print("\n\n=== Running Comprehensive Collection Examples ===\n", .{});
    // Collection examples temporarily disabled due to missing functions
    // try collection_examples.runCollectionExamples();
}
