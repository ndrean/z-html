const std = @import("std");
const z = @import("zhtml.zig");
const tree = @import("modules/dom_tree.zig");
const tree_opt = @import("modules/dom_tree_optimized.zig");
const normalize = @import("modules/normalize.zig");
const print = std.debug.print;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    try demoParser(allocator);
    try demoStreamParser(allocator);
    try demoInsertAdjacentHTML(allocator);
    try demoSuspiciousAttributes(allocator);
    // std.debug.print("=== Z-HTML Performance Benchmark (Release Mode) ===\n", .{});
    // try runNormalizeBenchmark(allocator);
    // try newNormalizeBencharmark(allocator);
    // try runPerformanceBenchmark(allocator);
}

fn demoParser(allocator: std.mem.Allocator) !void {
    const doc = try z.createDocFromString("<div><ul></ul></div>");
    defer z.destroyDocument(doc);
    const body = z.bodyNode(doc).?;

    const ul_elt = z.getElementByTag(body, .ul).?;
    const ul = z.elementToNode(ul_elt);

    var parser = try z.FragmentParser.init(allocator);
    defer parser.deinit();

    for (0..3) |i| {
        const li = try std.fmt.allocPrint(
            allocator,
            "<li id='item-{}'>Item {}</li>",
            .{ i, i },
        );
        defer allocator.free(li);

        try parser.insertFragment(ul, li, .ul, false);
    }
    print("\n === Demonstrate parser engine reuse ===\n\n", .{});
    print("\n Insert interpolated <li id=\"item-X\"> Item X</li>\n\n", .{});

    try z.prettyPrint(body);
    print("\n\n", .{});
}

fn demoStreamParser(allocator: std.mem.Allocator) !void {
    print("\n === Demonstrate parsing streams on-the-fly ===\n\n", .{});
    var streamer = try z.Stream.init(allocator);
    defer streamer.deinit();

    try streamer.beginParsing();

    const streams = [_][]const u8{
        "<!DOCTYPE html><html><head><title>Large",
        " Document</title></head><body>",
        "<table id=\"producttable\">",
        "<caption>Company data</caption><thead>",
        "<tr><th scope=\"col\">",
        "Code</th><th>Product_Name</th>",
        "</tr></thead><tbody>",
    };
    for (streams) |chunk| {
        print("chunk:  {s}\n", .{chunk});
        try streamer.processChunk(chunk);
    }

    for (0..2) |i| {
        const li = try std.fmt.allocPrint(
            allocator,
            "<tr id={}><td >Code: {}</td><td>Name: {}</td></tr>",
            .{ i, i, i },
        );
        defer allocator.free(li);
        print("chunk:  {s}\n", .{li});

        try streamer.processChunk(li);
    }
    const end_chunk = "</tbody></table></body></html>";
    print("chunk:  {s}\n", .{end_chunk});
    try streamer.processChunk(end_chunk);
    try streamer.endParsing();

    const html_doc = streamer.getDocument();
    defer z.destroyDocument(html_doc);
    const html_node = z.documentRoot(html_doc).?;

    print("\n\n", .{});
    try z.prettyPrint(html_node);
    print("\n\n", .{});
    try z.printDocStruct(html_doc);
    print("\n\n", .{});
}

fn demoInsertAdjacentHTML(allocator: std.mem.Allocator) !void {
    const doc = try z.createDocFromString(
        \\<html><body>
        \\    <div id="container">
        \\        <p id="target">Target</p>
        \\    </div>
        \\</body></html>
    );
    defer z.destroyDocument(doc);
    errdefer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;
    const target = z.getElementById(body, "target").?;

    // Demo 1: insertAdjacentElement with all positions
    const before_end_elem = try z.createElementWithAttrs(
        doc,
        "span",
        &.{.{ .name = "class", .value = "before end" }},
    );
    // try z.setContentAsText(z.elementToNode(before_elem), "Before Begin");

    try z.insertAdjacentElement(
        target,
        .beforeend,
        before_end_elem,
    );

    const after_end_elem = try z.createElementWithAttrs(
        doc,
        "span",
        &.{.{ .name = "class", .value = "after end" }},
    );
    // try z.setContentAsText(z.elementToNode(after_elem), "After End");

    try z.insertAdjacentElement(
        target,
        "afterend",
        after_end_elem,
    );

    const after_begin_elem = try z.createElementWithAttrs(
        doc,
        "span",
        &.{.{ .name = "class", .value = "after begin" }},
    );
    // try z.setContentAsText(z.elementToNode(after_elem), "After End");

    try z.insertAdjacentElement(
        target,
        "afterbegin",
        after_begin_elem,
    );
    const before_begin_elem = try z.createElementWithAttrs(
        doc,
        "span",
        &.{.{ .name = "class", .value = "before begin" }},
    );
    // try z.setContentAsText(z.elementToNode(after_elem), "After End");

    try z.insertAdjacentElement(
        target,
        .beforebegin,
        before_begin_elem,
    );

    // Show result after insertAdjacentElement
    const html = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(html);
    print("\n=== Demonstrate insertAdjacentHTML ===\n\n", .{});
    try z.prettyPrint(body);

    // Normalize whitespace for clean comparison
    const clean_html = try z.normalizeText(allocator, html, .{});
    defer allocator.free(clean_html);

    const expected = "<body><div id=\"container\"><span class=\"before begin\"></span><p id=\"target\"><span class=\"after begin\"></span>Target<span class=\"before end\"></span></p><span class=\"after end\"></span></div></body>";

    std.debug.assert(std.mem.eql(u8, expected, clean_html) == true);

    print("\n--- Normalized HTML --- \n\n{s}\n", .{clean_html});
    print("\n\n", .{});
}

fn demoSuspiciousAttributes(allocator: std.mem.Allocator) !void {
    _ = allocator; // Silence unused parameter warning
    // Create a document with lots of suspicious/malicious attributes to see the highlighting
    const malicious_content = "<div><button disabled hidden onclick=\"alert('XSS')\" phx-click=\"increment\" data-invalid=\"bad\" scope=\"invalid\">Dangerous button</button><img src=\"javascript:alert('XSS')\" alt=\"not safe\" onerror=\"alert('hack')\" loading=\"unknown\"><a href=\"javascript:alert('XSS')\" target=\"_self\" role=\"invalid\">Dangerous link</a><p id=\"valid\" class=\"good\" aria-label=\"ok\" style=\"bad\" onload=\"bad()\">Mixed attributes</p></div>";

    const doc = try z.createDocFromString(malicious_content);
    defer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;
    print("\n=== Demonstrating prettyPrint - suspicious/invalid attributes highlighted ===\n\n", .{});
    print("🟥 Red = Dangerous attributes (onclick, onerror, etc.)\n", .{});
    print("🟨 Yellow = Invalid attribute values\n", .{});
    print("🟦 Blue = Valid attributes and values\n\n", .{});
    try z.prettyPrint(body);
    print("\n\n", .{});
}

fn runNormalizeBenchmark(allocator: std.mem.Allocator) !void {
    var html_builder: std.ArrayList(u8) = .empty;
    defer html_builder.deinit(allocator);

    // Pre-allocate capacity for the HTML builder (estimate ~25KB for this test)
    try html_builder.ensureTotalCapacity(allocator, 25_000);

    try html_builder.appendSlice(allocator,
        \\<html>
        \\<body>
        \\  <div class="container">
        \\    <header>
        \\      <h1>   Performance Test Document   </h1>
        \\      <nav>
        \\        <ul>
    );

    // Add many elements with whitespace
    for (0..100) |i| {
        try html_builder.appendSlice(allocator,
            \\          <li>   
            \\            <a href="/page
        );

        const num_str = try std.fmt.allocPrint(allocator, "{d}", .{i});
        defer allocator.free(num_str);
        try html_builder.appendSlice(allocator, num_str);

        try html_builder.appendSlice(allocator,
            \\">   Link 
        );
        try html_builder.appendSlice(allocator, num_str);
        try html_builder.appendSlice(allocator,
            \\   </a>
            \\            <span>   Some text with    whitespace   </span>
            \\            <!-- comment with whitespace -->
            \\            <em>     emphasized text     </em>
            \\          </li>
        );
    }

    try html_builder.appendSlice(allocator,
        \\        </ul>
        \\      </nav>
        \\    </header>
        \\    <main>
        \\      <section>
        \\        <p>   This is a paragraph with    lots of    whitespace   </p>
        \\        <div>
        \\          <pre>   Preserve   this   whitespace   </pre>
        \\          <textarea>   Also preserve   this   </textarea>
        \\        </div>
        \\      </section>
        \\    </main>
        \\  </div>
        \\</body>
        \\</html>
    );

    const large_html = try html_builder.toOwnedSlice(allocator);
    defer allocator.free(large_html);

    const iterations = 100;
    const kb_size = (@as(f64, @floatFromInt(large_html.len)) / 1024.0);
    print("\n NORMALIZE PERFORMANCE BENCHMARK\n", .{});
    print("HTML size: {d} bytes (~{d:.1}KB)\n", .{ large_html.len, kb_size });
    print("Iterations: {d}\n", .{iterations});

    // var  doc = try z.createDocFromString(large_html);
    var doc: *z.HTMLDocument = undefined;
    defer z.destroyDocument(doc);

    var timer = try std.time.Timer.start();
    timer.reset();
    for (0..iterations) |_| {
        doc = try z.createDocFromString(large_html);
        const body_elt = z.bodyElement(doc).?;
        _ = body_elt;
    }
    const parsing_time = @as(f64, @floatFromInt(timer.read()));

    // Test DOM-based normalization
    timer.reset();
    for (0..iterations) |_| {
        doc = try z.createDocFromString(large_html);
        const body_elt = z.bodyElement(doc).?;

        try z.normalizeWithOptions(
            allocator,
            body_elt,
            .{
                .remove_whitespace_text_nodes = true,
                .skip_comments = true,
            },
        );
    }
    const dom_total_time = @as(f64, @floatFromInt(timer.read()));

    // Test string-based normalization (no parsing needed)
    timer.reset();
    for (0..iterations) |_| {
        const normalized = try normalize.normalizeHtmlStringWithOptions(allocator, large_html, .{
            .remove_comments = true,
            .remove_whitespace_text_nodes = true,
        });
        allocator.free(normalized);
    }
    const string_time = @as(f64, @floatFromInt(timer.read()));

    const dom_normalize_time = dom_total_time - parsing_time;

    // Calculate MB/s properly
    const total_mb = (kb_size * @as(f64, @floatFromInt(iterations))) / 1024.0;
    const parsing_time_s = parsing_time / 1_000_000_000.0;
    const dom_normalize_time_s = dom_normalize_time / 1_000_000_000.0;
    const string_time_s = string_time / 1_000_000_000.0;

    const parsing_speed = total_mb / parsing_time_s;
    const dom_normalize_speed = total_mb / dom_normalize_time_s;
    const string_speed = total_mb / string_time_s;

    const speedup = dom_normalize_time_s / string_time_s;

    print("\n--- Results (Release Mode) ---\n", .{});
    print("Parsing processing speed:         {d:.1} MB/s ({d:.2} ms/op)\n", .{ parsing_speed, (parsing_time / @as(f64, @floatFromInt(iterations))) / 1_000_000.0 });
    print("Normalize via DOM processing:     {d:.1} MB/s ({d:.2} ms/op)\n", .{ dom_normalize_speed, (dom_normalize_time / @as(f64, @floatFromInt(iterations))) / 1_000_000.0 });
    print("String Normalize processing:      {d:.1} MB/s ({d:.2} ms/op)\n", .{ string_speed, (string_time / @as(f64, @floatFromInt(iterations))) / 1_000_000.0 });
    print("String vs DOM speedup:            {d:.1}x faster\n", .{speedup});
}

fn runPerformanceBenchmark(allocator: std.mem.Allocator) !void {
    // Create ~300KB HTML document by building it dynamically
    var html_builder: std.ArrayList(u8) = .empty;
    defer html_builder.deinit(allocator);

    try html_builder.appendSlice(allocator,
        \\<html>
        \\  <head>
        \\    <title>Large Performance Test Document</title>
        \\    <meta charset="UTF-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\    <link rel="stylesheet" href="styles.css">
        \\    <script src="app.js"></scrip>
        \\  </head>
        \\  <body class="main-body">
        \\    <header id="main-header" class="sticky-header">
        \\      <nav class="navbar">
        \\        <ul class="nav-list">
        \\          <li><a href="/" class="nav-link active">Home</a></li>
        \\          <li><a href="/about" class="nav-link">About</a></li>
        \\          <li><a href="/contact" class="nav-link">Contact</a></li>
        \\          <li><a href="/products" class="nav-link">Products</a></li>
        \\          <li><a href="/services" class="nav-link">Services</a></li>
        \\        </ul>
        \\      </nav>
        \\    </header>
    );

    // Duplicate main content sections to reach ~100KB
    const section_template =
        \\    <main class="content-wrapper">
        \\      <article class="blog-post">
        \\        <h1>Performance Test Section</h1>
        \\        <p class="intro">This is a section of our <strong>large-scale</strong> HTML document 
        \\           designed to test <em>performance</em> of our tuple serialization system with 
        \\           substantial content that simulates real-world usage patterns.</p>
        \\        <!-- Performance test comment -->
        \\        <div class="content-section">
        \\          <h2>Features We're Testing</h2>
        \\          <ul class="feature-list">
        \\            <li data-feature="speed">Ultra-fast serialization</li>
        \\            <li data-feature="memory">Memory-efficient processing</li>
        \\            <li data-feature="accuracy">Accurate round-trip conversion</li>
        \\            <li data-feature="scalability">Scalability under load</li>
        \\            <li data-feature="reliability">Reliable error handling</li>
        \\          </ul>
        \\        </div>
        \\        <div class="data-table">
        \\          <table class="performance-table">
        \\            <thead>
        \\              <tr><th>Metric</th><th>Value</th><th>Benchmark</th></tr>
        \\            </thead>
        \\            <tbody>
        \\              <tr><td>Latency</td><td>0.5ms</td><td>Excellent</td></tr>
        \\              <tr><td>Throughput</td><td>1000k ops/sec</td><td>Outstanding</td></tr>
        \\              <tr><td>Memory</td><td>256KB</td><td>Optimal</td></tr>
        \\            </tbody>
        \\          </table>
        \\        </div>
        \\        <form class="feedback-form" method="post" action="/feedback">
        \\          <fieldset>
        \\            <legend>Section Feedback</legend>
        \\            <div class="form-group">
        \\              <label for="name">Name:</label>
        \\              <input type="text" id="name" name="name" required placeholder="Your name">
        \\            </div>
        \\            <div class="form-group">
        \\              <label for="email">Email:</label>
        \\              <input type="email" id="email" name="email" required placeholder="your@email.com">
        \\            </div>
        \\            <div class="form-group">
        \\              <label for="rating">Rating:</label>
        \\              <select id="rating" name="rating">
        \\                <option value="5">⭐⭐⭐⭐⭐ Excellent</option>
        \\                <option value="4">⭐⭐⭐⭐ Very Good</option>
        \\                <option value="3">⭐⭐⭐ Good</option>
        \\                <option value="2">⭐⭐ Fair</option>
        \\                <option value="1">⭐ Poor</option>
        \\              </select>
        \\            </div>
        \\            <div class="form-group">
        \\              <textarea name="comments" rows="4" cols="50" 
        \\                        placeholder="Your detailed feedback..."></textarea>
        \\            </div>
        \\            <button type="submit" class="btn-primary">Submit Feedback</button>
        \\          </fieldset>
        \\        </form>
        \\      </article>
        \\      <aside class="sidebar">
        \\        <div class="widget news">
        \\          <h3>Latest News</h3>
        \\          <ul>
        \\            <li><a href="/news/1">Performance improvements</a></li>
        \\            <li><a href="/news/2">Memory optimization</a></li>
        \\            <li><a href="/news/3">Better DOM handling</a></li>
        \\            <li><a href="/news/4">Enhanced error reporting</a></li>
        \\          </ul>
        \\        </div>
        \\        <div class="widget tags">
        \\          <h3>Tags</h3>
        \\          <span class="tag">performance</span>
        \\          <span class="tag">html</span>
        \\          <span class="tag">parsing</span>
        \\          <span class="tag">optimization</span>
        \\          <span class="tag">benchmarks</span>
        \\        </div>
        \\      </aside>
        \\    </main>
    ;

    // Add 100 sections to reach ~100KB
    for (1..101) |_| {
        try html_builder.appendSlice(allocator, section_template);
    }

    try html_builder.appendSlice(allocator,
        \\    <footer class="site-footer">
        \\      <div class="footer-content">
        \\        <p>&copy; 2024 Comprehensive Performance Test Suite. All rights reserved.</p>
        \\        <div class="footer-links">
        \\          <a href="/privacy">Privacy Policy</a> |
        \\          <a href="/terms">Terms of Service</a> |
        \\          <a href="/api">API Documentation</a> |
        \\          <a href="/support">Technical Support</a> |
        \\          <a href="/docs">Documentation</a>
        \\        </div>
        \\        <div class="footer-stats">
        \\          <span>Total operations tested: 1M+</span>
        \\          <span>Average response time: 0.3ms</span>
        \\          <span>Memory usage: <128KB</span>
        \\        </div>
        \\      </div>
        \\    </footer>
        \\  </body>
        \\</html>
    );

    const large_html = try html_builder.toOwnedSlice(allocator);
    defer allocator.free(large_html);

    const iterations = 100;
    print("\n=====================================================================\n", .{});
    print("\nLarge HTML conversions:  HTML<->DOM, DOM->Tuple, Tuple->HTML\n", .{});
    print("HTML size: {d} bytes (~{d:.1}KB)\n", .{ large_html.len, @as(f64, @floatFromInt(large_html.len)) / 1024.0 });
    print("Iterations: {d}\n", .{iterations});

    var timer = try std.time.Timer.start();

    // Test 1: [HTMLstring → DOM]
    timer.reset();
    for (0..iterations) |_| {
        const doc = try z.createDocFromString(large_html);
        z.destroyDocument(doc);
    }
    const html_to_dom_time = timer.read();

    // === Test 1.b: [Normalize-HTMLstring → DOM]
    timer.reset();
    for (0..iterations) |_| {
        const normalized = try normalize.normalizeHtmlStringWithOptions(allocator, large_html, .{
            .remove_comments = true,
            .remove_whitespace_text_nodes = true,
        });
        const doc = try z.createDocFromString(normalized);
        allocator.free(normalized);
        z.destroyDocument(doc);
    }
    _ = timer.read(); // norm_html_to_dom_time unused

    // Parse once for other tests
    const doc = try z.createDocFromString(large_html);
    defer z.destroyDocument(doc);
    const body_element = z.bodyElement(doc).?;

    // Test 2.b: [DOM -> Tuple]
    var tuple_v2_result: []u8 = undefined;
    timer.reset();
    for (0..iterations) |i| {
        if (i > 0) allocator.free(tuple_v2_result);

        tuple_v2_result = try tree.domToTupleString(allocator, doc);
    }
    const dom_to_tuple_time = timer.read();

    // === Test 2: [DOM-Normalize → Tuple]
    var tuple_v21_result: []u8 = undefined;
    timer.reset();
    for (0..iterations) |i| {
        if (i > 0) allocator.free(tuple_v21_result);
        const temp_doc = try z.createDocFromString(large_html);
        const temp_body_element = try z.bodyElement(temp_doc);

        try z.normalizeWithOptions(
            allocator,
            temp_body_element,
            .{
                .remove_whitespace_text_nodes = true,
                .skip_comments = true,
            },
        );
        tuple_v21_result = try tree.domToTupleString(allocator, temp_doc);
        z.destroyDocument(temp_doc);
    }
    const norm_dom_to_tuple_time = timer.read();

    // === Test2.b : [normalized-DOM -> Tuple]
    var tuple_v22_result: []u8 = undefined;
    timer.reset();
    for (0..iterations) |i| {
        if (i > 0) allocator.free(tuple_v22_result);

        const normalized = try normalize.normalizeHtmlStringWithOptions(allocator, large_html, .{
            .remove_comments = true,
            .remove_whitespace_text_nodes = true,
        });
        const temp_doc = try z.createDocFromString(normalized);
        allocator.free(normalized);

        tuple_v22_result = try tree.domToTupleString(allocator, temp_doc);
        z.destroyDocument(temp_doc);
    }
    const pre_norm_dom_to_tuple_time = timer.read();

    // === Test 3: [Tuple → HTMLstring]
    timer.reset();
    var html_result: []u8 = undefined;
    for (0..iterations) |i| {
        if (i > 0) allocator.free(html_result);
        html_result = try tree.tupleStringToHtml(allocator, tuple_v22_result);
    }
    const tuple_to_html_time = timer.read();

    // === Test 4: [DOM -> HTML] - Isolated innerHTML performance
    timer.reset();
    for (0..iterations) |_| {
        const serialized_html = try z.innerHTML(allocator, body_element);
        allocator.free(serialized_html);
    }
    const pure_dom_to_html_time = timer.read();

    // === Test 4.b: [DOM -> HTML] with parsing overhead (original test)
    const normalized = try normalize.normalizeHtmlStringWithOptions(allocator, large_html, .{
        .remove_comments = true,
        .remove_whitespace_text_nodes = true,
    });

    timer.reset();
    for (0..iterations) |_| {
        const temp_doc = try z.createDocFromString(normalized);
        const temp_body_element = try z.bodyElement(temp_doc);
        const serialized_html = try z.innerHTML(allocator, temp_body_element);
        allocator.free(serialized_html);
        z.destroyDocument(temp_doc);
    }
    const dom_to_html_time = timer.read();

    const tuple_len = tuple_v2_result.len;
    const norm_tuple_len = tuple_v22_result.len;
    allocator.free(normalized);
    allocator.free(tuple_v2_result);
    allocator.free(tuple_v22_result);
    allocator.free(html_result);

    // === Results ===
    const ns_to_ms = @as(f64, @floatFromInt(std.time.ns_per_ms));

    print("\n--- Performance Results (100 iterations) ---\n", .{});

    const html2domlxb = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0 * @as(f64, @floatFromInt(iterations))) / (@as(f64, @floatFromInt(html_to_dom_time)) / ns_to_ms / 1000.0);
    print("HTML → DOM (lexbor):       {d:.2} ms/op, {d:.3} MB/s\n", .{ @as(f64, @floatFromInt(html_to_dom_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)), html2domlxb });

    const pre_norm_dom_tuple = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0 * @as(f64, @floatFromInt(iterations))) / (@as(f64, @floatFromInt(pre_norm_dom_to_tuple_time)) / ns_to_ms / 1000.0);
    print("pre-norm-DOM -> Tuple.     {d:.2} ms/op, {d:.1} MB/s\n", .{ @as(f64, @floatFromInt(pre_norm_dom_to_tuple_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)), pre_norm_dom_tuple });

    const pure_dom2html = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0 * @as(f64, @floatFromInt(iterations))) / (@as(f64, @floatFromInt(pure_dom_to_html_time)) / ns_to_ms / 1000.0);
    print("DOM → HTML (pure innerHTML): {d:.2} ms/op, {d:.1} MB/s\n", .{ @as(f64, @floatFromInt(pure_dom_to_html_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)), pure_dom2html });

    const dom2html = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0 * @as(f64, @floatFromInt(iterations))) / (@as(f64, @floatFromInt(dom_to_html_time)) / ns_to_ms / 1000.0);
    print("DOM → HTML (with parsing):   {d:.2} ms/op, {d:.1} MB/s\n", .{ @as(f64, @floatFromInt(dom_to_html_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)), dom2html });

    const norm_dom2tuple = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0 * @as(f64, @floatFromInt(iterations))) / (@as(f64, @floatFromInt(norm_dom_to_tuple_time)) / ns_to_ms / 1000.0);
    print("DOM-Norm → Tuple:           {d:.2} ms/op, {d:.1} MB/s\n", .{ @as(f64, @floatFromInt(norm_dom_to_tuple_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)), norm_dom2tuple });

    const dom2tuple = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0 * @as(f64, @floatFromInt(iterations))) / (@as(f64, @floatFromInt(dom_to_tuple_time)) / ns_to_ms / 1000.0);
    print("DOM → Tuple:               {d:.2} ms/op, {d:.1} MB/s\n", .{ @as(f64, @floatFromInt(dom_to_tuple_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)), dom2tuple });

    print("Tuple size: without norm {d} bytes, with norm {d} bytes\n", .{ tuple_len, norm_tuple_len });

    const tuple2Html = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0 * @as(f64, @floatFromInt(iterations))) / (@as(f64, @floatFromInt(tuple_to_html_time)) / ns_to_ms / 1000.0);
    print("Tuple → HTML:             {d:.2} ms/op, {d:.1} MB/s\n", .{ @as(f64, @floatFromInt(tuple_to_html_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)), tuple2Html });

    // print("\n--- BEAM Scheduler Compliance ---\n", .{});
    // const dom_to_tuple_ms = @as(f64, @floatFromInt(dom_to_tuple_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations));
    // const tuple_to_html_ms = @as(f64, @floatFromInt(tuple_to_html_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations));

    // print("DOM → Tuple: {s} (limit: 1ms)\n", .{if (dom_to_tuple_ms < 1.0) "✅ SAFE" else "❌ DIRTY SCHEDULER"});
    // print("Tuple → HTML: {s} (limit: 1ms)\n", .{if (tuple_to_html_ms < 1.0) "✅ SAFE" else "❌ DIRTY SCHEDULER"});

    // print("\n--- Memory Usage ---\n", .{});
    // print("Original HTML:      {d} bytes ({d:.1}KB)\n", .{ large_html.len, @as(f64, @floatFromInt(large_html.len)) / 1024.0 });
    // print("Tuple string:       {d} bytes ({d:.1}KB)\n", .{ tuple_result.len, @as(f64, @floatFromInt(tuple_result.len)) / 1024.0 });
    // print("Reconstructed HTML: {d} bytes ({d:.1}KB)\n", .{ html_result.len, @as(f64, @floatFromInt(html_result.len)) / 1024.0 });

    // const expansion_ratio = @as(f64, @floatFromInt(tuple_result.len)) / @as(f64, @floatFromInt(large_html.len));
    // print("Tuple size ratio:   {d:.2}x original HTML size\n", .{expansion_ratio});

    // // Calculate throughput for key operation
    // const tuple_to_html_throughput = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0) / (tuple_to_html_ms / 1000.0);
    // print("\n--- Throughput Analysis ---\n", .{});
    // print("Tuple → HTML Throughput: {d:.1} MB/s\n", .{tuple_to_html_throughput});
}

fn newNormalizeBencharmark(allocator: std.mem.Allocator) !void {

    // Create a medium-sized realistic page with lots of whitespace and comments
    var html_builder: std.ArrayList(u8) = .empty;
    defer html_builder.deinit(allocator);

    try html_builder.ensureTotalCapacity(allocator, 50_000);

    try html_builder.appendSlice(allocator,
        \\<!DOCTYPE html>
        \\<!-- Page header comment -->
        \\<html lang="en">
        \\  <head>
        \\    <meta charset="UTF-8"/>
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
        \\    <title>Medium Blog Post - Performance Test</title>
        \\    <link rel="stylesheet" href="/css/main.css"/>
        \\    <!-- Analytics comment -->
        \\    <script src="/js/analytics.js"></script>
        \\  </head>
        \\  <body class="blog-layout">
        \\    <header class="site-header">
        \\      <nav class="main-nav">
        \\        <ul class="nav-list">
        \\          <li><a href="/">Home</a></li>
        \\          <li><a href="/blog">Blog</a></li>
        \\          <li><a href="/about">About</a></li>
        \\        </ul>
        \\        <!-- Navigation comment -->
        \\        <code> const std = @import("std");\n const z = @import("../zhtml.zig");\n</code>
        \\      </nav>
        \\    </header>
        \\    
        \\    <main class="content">
    );

    // Add multiple blog posts with realistic content
    for (0..20) |i| {
        try html_builder.appendSlice(allocator,
            \\      <article class="blog-post">
            \\        <!-- Post comment -->
            \\        <header class="post-header">
            \\          <h2 class="post-title">
        );

        const title = try std.fmt.allocPrint(allocator, "Blog Post #{d}: Performance Testing", .{i + 1});
        defer allocator.free(title);
        try html_builder.appendSlice(allocator, title);

        try html_builder.appendSlice(allocator,
            \\</h2>
            \\          <div class="post-meta">
            \\            <span class="author">John Doe</span>
            \\            <time datetime="2024-01-01">January 1, 2024</time>
            \\          </div>
            \\        </header>
            \\        
            \\        <div class="post-content">
            \\          <p>This is a sample blog post to test our <strong>HTML normalization</strong> 
            \\             and <em>tuple serialization</em> performance. The content includes various 
            \\             HTML elements and whitespace patterns.</p>
            \\             
            \\          <!-- Content comment -->
            \\          <blockquote>
            \\            "Performance is not just about speed, but about providing 
            \\             a smooth user experience."
            \\          </blockquote>
            \\          
            \\          <ul class="feature-list">
            \\            <li>Fast HTML parsing with lexbor</li>
            \\            <li>Efficient DOM normalization</li>
            \\            <li>High-performance tuple serialization</li>
            \\            <li>Memory-optimized string processing</li>
            \\          </ul>
            \\          
            \\          <div class="code-example">
            \\            <pre><code>const html = createDocFromString(input);
            \\const normalized = normalize(html);
            \\const tuple = domToTuple(normalized);</code></pre>
            \\          </div>
            \\          
            \\          <form class="contact-form">
            \\            <div class="form-group">
            \\              <label for="email">Email:</label>
            \\              <input type="email" id="email" name="email" required/>
            \\            </div>
            \\            <button type="submit">Subscribe</button>
            \\          </form>
            \\        </div>
            \\        
            \\        <footer class="post-footer">
            \\          <div class="tags">
            \\            <span class="tag">performance</span>
            \\            <span class="tag">html</span>
            \\            <span class="tag">optimization</span>
            \\          </div>
            \\        </footer>
            \\      </article>
            \\      
        );
    }

    try html_builder.appendSlice(allocator,
        \\    </main>
        \\    
        \\    <aside class="sidebar">
        \\      <!-- Sidebar comment -->
        \\      <div class="widget recent-posts">
        \\        <h3>Recent Posts</h3>
        \\        <ul>
        \\          <li><a href="/post1">Understanding Performance</a></li>
        \\          <li><a href="/post2">Memory Optimization Techniques</a></li>
        \\          <li><a href="/post3">DOM Processing Strategies</a></li>
        \\        </ul>
        \\      </div>
        \\      
        \\      <div class="widget newsletter">
        \\        <h3>Newsletter</h3>
        \\        <p>   Stay updated with our latest posts   </p>
        \\        <form>
        \\          <input type="email" placeholder="Your email"/>
        \\          <button>Subscribe</button>
        \\        </form>
        \\      </div>
        \\    </aside>
        \\    
        \\    <footer class="site-footer">
        \\      <!-- Footer comment -->
        \\      <p>&copy; 2024 Performance Blog. All rights reserved.</p>
        \\    </footer>
        \\    
        \\    <script>
        \\      // Performance tracking
        \\      console.log('Page loaded in:', performance.now(), 'ms');
        \\    </script>
        \\  </body>
        \\</html>
    );

    const medium_html = try html_builder.toOwnedSlice(allocator);
    defer allocator.free(medium_html);

    const iterations = 100;
    print("\n===================================================\n", .{});
    print("\n HTML → NORMALIZE → TUPLE PIPELINE BENCHMARK\n\n", .{});
    print("HTML size: {d} bytes (~{d:.1}KB)\n", .{ medium_html.len, @as(f64, @floatFromInt(medium_html.len)) / 1024.0 });
    print("Iterations: {d}\n", .{iterations});

    var timer = try std.time.Timer.start();

    // Pipeline 0: Without normalization: HTMLstring → parse → Tuple
    timer.reset();
    var tuple_v0: []u8 = undefined;
    for (0..iterations) |i| {
        const doc = try z.createDocFromString(medium_html);
        defer z.destroyDocument(doc);

        if (i > 0) allocator.free(tuple_v0);
        tuple_v0 = try z.domToTupleString(allocator, doc);
    }
    const html2parse2tuple = timer.read();

    // Pipeline 1: HTMLstring → normalize → parse -> Tuple
    timer.reset();
    var tuple_v_norm: []u8 = undefined;
    for (0..iterations) |i| {
        // 1: Normalize HTML string (remove comments + whitespace)
        const normalized = try normalize.normalizeHtmlStringWithOptions(allocator, medium_html, .{
            .remove_comments = true,
            .remove_whitespace_text_nodes = true,
        });
        defer allocator.free(normalized);

        // 2: Parse
        const doc = try z.createDocFromString(normalized);
        defer z.destroyDocument(doc);

        // 3: to Tuple
        if (i > 0) allocator.free(tuple_v_norm);
        tuple_v_norm = try z.domToTupleString(allocator, doc);
    }
    const html2norm2parse2tuple = timer.read();

    // Pipeline 2: Tuple → HTML (reverse)
    timer.reset();
    var final_html: []u8 = undefined;
    for (0..iterations) |i| {
        if (i > 0) allocator.free(final_html);
        final_html = try z.tupleStringToHtml(allocator, tuple_v_norm);
        const doc = try z.createDocFromString(final_html);
        z.destroyDocument(doc);
    }
    const tuple2html2dom = timer.read();

    // Calculate performance metrics
    const ns_to_ms = @as(f64, @floatFromInt(std.time.ns_per_ms));
    const mb_size = @as(f64, @floatFromInt(medium_html.len)) / 1024.0 / 1024.0;

    const html2norm2parse2tuple_ms = @as(f64, @floatFromInt(html2norm2parse2tuple)) / ns_to_ms;
    const tuple2html2dom_ms = @as(f64, @floatFromInt(tuple2html2dom)) / ns_to_ms;
    const html2parse2tuple_ms = @as(f64, @floatFromInt(html2parse2tuple)) / ns_to_ms;

    const normalize_tuple_throughput = (mb_size * @as(f64, @floatFromInt(iterations))) / (html2norm2parse2tuple_ms / 1000.0);
    const tuple2html_throughput = (mb_size * @as(f64, @floatFromInt(iterations))) / (tuple2html2dom_ms / 1000.0);
    const traditional_throughput = (mb_size * @as(f64, @floatFromInt(iterations))) / (html2parse2tuple_ms / 1000.0);

    print("\n--- Speed Results ---\n", .{});
    print("HTML -> norm -> DOM -> Tuple:       {d:.2} ms/op, {d:.1} MB/s\n", .{ html2norm2parse2tuple_ms / iterations, normalize_tuple_throughput });
    print("HTML -> DOM ->Tuple: {d:.2} ms/op,  {d:.1} MB/s\n", .{ html2parse2tuple_ms / iterations, traditional_throughput });
    print("Tuple -> HTML -> DOM:               {d:.2} ms/op, {d:.1} MB/s\n", .{ tuple2html2dom_ms / iterations, tuple2html_throughput });

    print("\n--- Potential impact of normalization ---\n", .{});
    print("Original HTML:              {d} bytes\n", .{medium_html.len});
    print("Tuple_v0 (no norm):         {d} bytes\n", .{tuple_v0.len});

    print("Tuple with norm:            {d} bytes\n", .{tuple_v_norm.len});
    print("Reconstructed norm HTML:    {d} bytes\n", .{final_html.len});

    allocator.free(tuple_v_norm);
    allocator.free(final_html);
    allocator.free(tuple_v0);
}
