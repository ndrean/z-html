const std = @import("std");
const z = @import("../zhtml.zig");
const ChunkParser = @import("../chunks.zig").ChunkParser;

const testing = std.testing;
const print = std.debug.print;

// Example 1: HTTP Streaming Response Processing
test "HTTP streaming response simulation" {
    const allocator = testing.allocator;

    var chunk_parser = try ChunkParser.init(allocator);
    defer chunk_parser.deinit();

    try chunk_parser.beginParsing();

    // Simulate receiving HTTP response in chunks
    const http_response_chunks = [_][]const u8{
        "<!DOCTYPE html><html><head>",
        "<title>Streaming Example</title>",
        "<meta charset=\"utf-8\">",
        "</head><body>",
        "<div class=\"container\">",
        "<h1>Real-time Content</h1>",
        "<ul id=\"messages\">",
        "<li>Message 1</li>",
        "<li>Message 2</li>",
        "</ul></div>",
        "</body></html>",
    };

    // Process each chunk as it "arrives"
    for (http_response_chunks, 0..) |chunk, i| {
        print("Processing chunk {}: '{s}'\n", .{ i + 1, chunk });
        try chunk_parser.processChunk(chunk);
    }

    try chunk_parser.endParsing();

    // Now we can work with the complete document
    const doc = chunk_parser.getDocument();
    const messages_ul = try z.getElementById(doc, "messages");

    try testing.expect(messages_ul != null);

    const children = try z.children(allocator, messages_ul.?);
    defer allocator.free(children);

    try testing.expect(children.len == 2);
    print("Successfully parsed {} message items\n", .{children.len});
}

// Example 2: Large File Processing
test "large file chunk processing simulation" {
    const allocator = testing.allocator;

    var chunk_parser = try ChunkParser.init(allocator);
    defer chunk_parser.deinit();

    try chunk_parser.beginParsing();

    // Simulate reading a large HTML file in 1KB chunks
    try chunk_parser.processChunk("<!DOCTYPE html><html><body>");

    // Generate many elements as if from a large file
    for (0..1000) |i| {
        const chunk = try std.fmt.allocPrint(allocator, "<div id=\"item-{}\">Item {}</div>", .{ i, i });
        defer allocator.free(chunk);

        try chunk_parser.processChunk(chunk);

        // In real usage, you might process chunks as they're read from disk
        if (i % 100 == 0) {
            print("Processed {} items so far...\n", .{i});
        }
    }

    try chunk_parser.processChunk("</body></html>");
    try chunk_parser.endParsing();

    const doc = chunk_parser.getDocument();
    _ = z.bodyElement(doc).?; // Verify body exists

    const all_divs = try z.getElementsByTagName(doc, "DIV");
    defer z.destroyCollection(all_divs);

    const div_count = z.collectionLength(all_divs);
    try testing.expect(div_count == 1000);
    print("Successfully parsed {} div elements from chunked input\n", .{div_count});
}

// Example 3: WebSocket/SSE Real-time Updates
test "real-time HTML fragment streaming" {
    const allocator = testing.allocator;

    var chunk_parser = try ChunkParser.init(allocator);
    defer chunk_parser.deinit();

    try chunk_parser.beginParsing();

    // Initial HTML structure
    try chunk_parser.processChunk(
        \\<!DOCTYPE html><html><body>
        \\<div id="live-feed">
        \\<h2>Live Updates</h2>
    );

    // Simulate real-time updates arriving via WebSocket/SSE
    const live_updates = [_][]const u8{
        "<p class=\"update\">User Alice joined the chat</p>",
        "<p class=\"update\">New message: Hello everyone!</p>",
        "<p class=\"update\">User Bob is typing...</p>",
        "<p class=\"update\">User Bob: How's everyone doing?</p>",
    };

    for (live_updates, 0..) |update, i| {
        print("Streaming update {}: {s}\n", .{ i + 1, update });
        try chunk_parser.processChunk(update);

        // In real usage, you could process the DOM incrementally here
        // without waiting for the complete document
    }

    // Close the structure
    try chunk_parser.processChunk("</div></body></html>");
    try chunk_parser.endParsing();

    const doc = chunk_parser.getDocument();
    const live_feed = try z.getElementById(doc, "live-feed");

    try testing.expect(live_feed != null);

    const updates = try z.getElementsByClassName(doc, "update");
    defer z.destroyCollection(updates);

    try testing.expect(z.collectionLength(updates) == 4);
    print("Processed {} live updates via chunk streaming\n", .{z.collectionLength(updates)});
}

// Example 4: Template Streaming (Server-Side Rendering)
test "SSR template streaming" {
    const allocator = testing.allocator;

    var chunk_parser = try ChunkParser.init(allocator);
    defer chunk_parser.deinit();

    try chunk_parser.beginParsing();

    // Template header
    try chunk_parser.processChunk(
        \\<!DOCTYPE html><html><head>
        \\<title>Product Catalog</title>
        \\</head><body><main class="catalog">
    );

    // Simulate server generating product cards dynamically
    const products = [_]struct { id: u32, name: []const u8, price: f32 }{
        .{ .id = 1, .name = "Laptop", .price = 999.99 },
        .{ .id = 2, .name = "Mouse", .price = 29.99 },
        .{ .id = 3, .name = "Keyboard", .price = 79.99 },
    };

    for (products) |product| {
        const product_html = try std.fmt.allocPrint(allocator,
            \\<div class="product" data-id="{}">
            \\  <h3>{s}</h3>
            \\  <p class="price">${d:.2}</p>
            \\  <button>Add to Cart</button>
            \\</div>
        , .{ product.id, product.name, product.price });
        defer allocator.free(product_html);

        print("Streaming product: {s}\n", .{product.name});
        try chunk_parser.processChunk(product_html);
    }

    // Template footer
    try chunk_parser.processChunk("</main></body></html>");
    try chunk_parser.endParsing();

    const doc = chunk_parser.getDocument();
    const products_collection = try z.getElementsByClassName(doc, "product");
    defer z.destroyCollection(products_collection);

    try testing.expect(z.collectionLength(products_collection) == 3);

    // Verify pricing data
    const first_product = z.getCollectionElementAt(products_collection, 0).?;
    const data_id = try z.getAttribute(allocator, first_product, "data-id");
    if (data_id) |id| {
        defer allocator.free(id);
        try testing.expectEqualStrings("1", id);
    }

    print("Successfully rendered {} products via streaming\n", .{z.collectionLength(products_collection)});
}

// Example 5: Error Recovery in Chunk Parsing
test "chunk parsing with malformed HTML recovery" {
    const allocator = testing.allocator;

    var chunk_parser = try ChunkParser.init(allocator);
    defer chunk_parser.deinit();

    try chunk_parser.beginParsing();

    // Simulate receiving malformed HTML chunks
    const malformed_chunks = [_][]const u8{
        "<html><body>",
        "<div><p>Good content</p>", // Missing closing div
        "<span>More content", // Missing closing span
        "<div>Recovery content</div>",
        "</body></html>",
    };

    for (malformed_chunks, 0..) |chunk, i| {
        print("Processing potentially malformed chunk {}: '{s}'\n", .{ i + 1, chunk });
        try chunk_parser.processChunk(chunk);
    }

    try chunk_parser.endParsing();

    // lexbor automatically recovers and fixes malformed HTML
    const doc = chunk_parser.getDocument();
    const html = try z.outerHTML(allocator, try z.bodyNode(doc));
    defer allocator.free(html);

    print("Recovered HTML: {s}\n", .{html});

    // Verify that lexbor fixed the structure
    try testing.expect(std.mem.indexOf(u8, html, "<div>") != null);
    try testing.expect(std.mem.indexOf(u8, html, "</div>") != null);
    try testing.expect(std.mem.indexOf(u8, html, "<span>") != null);
    try testing.expect(std.mem.indexOf(u8, html, "</span>") != null);
}
