const std = @import("std");
const z = @import("zhtml.zig");
const tree = @import("modules/dom_tree.zig");

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    std.debug.print("=== Z-HTML Performance Benchmark (Release Mode) ===\n", .{});
    
    try runNormalizeBenchmark(allocator);
    try runPerformanceBenchmark(allocator);
}

fn runNormalizeBenchmark(allocator: std.mem.Allocator) !void {
    // Create large HTML document with lots of whitespace for normalization
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

    const iterations = 50;
    std.debug.print("\n=== NORMALIZE PERFORMANCE BENCHMARK ===\n", .{});
    std.debug.print("HTML size: {d} bytes (~{d:.1}KB)\n", .{ large_html.len, @as(f64, @floatFromInt(large_html.len)) / 1024.0 });
    std.debug.print("Iterations: {d}\n", .{iterations});

    var timer = try std.time.Timer.start();

    // Test optimized normalize approach
    timer.reset();
    for (0..iterations) |_| {
        const doc = try z.parseFromString(large_html);
        defer z.destroyDocument(doc);

        const body_elt = try z.bodyElement(doc);
        try z.normalizeWithOptions(
            allocator,
            body_elt,
            .{
                .trim_text = true,
                .remove_whitespace_text_nodes = true,
                .skip_comments = true,
            },
        );
    }
    const normalize_time = timer.read();

    const ns_to_ms = @as(f64, @floatFromInt(std.time.ns_per_ms));
    const normalize_ms = @as(f64, @floatFromInt(normalize_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations));

    std.debug.print("\n--- Results ---\n", .{});
    std.debug.print("Normalize (zero-copy): {d:.3} ms/op\n", .{normalize_ms});

    // BEAM Scheduler compliance check
    std.debug.print("\n--- BEAM Scheduler Compliance ---\n", .{});
    std.debug.print("Normalize: {s} (limit: 1ms)\n", .{if (normalize_ms < 1.0) "✅ SAFE" else "❌ DIRTY SCHEDULER"});

    // Calculate throughput
    const normalize_throughput = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0) / (normalize_ms / 1000.0);
    std.debug.print("\n--- Throughput Analysis ---\n", .{});
    std.debug.print("Normalize Throughput: {d:.1} MB/s\n", .{normalize_throughput});

    std.debug.print("\n✅ Normalize benchmark completed!\n", .{});
}

fn runPerformanceBenchmark(allocator: std.mem.Allocator) !void {
    // Create ~100KB HTML document by building it dynamically
    var html_builder: std.ArrayList(u8) = .empty;
    defer html_builder.deinit(allocator);

    try html_builder.appendSlice(allocator,
        \\<html>
        \\  <head>
        \\    <title>Large Performance Test Document</title>
        \\    <meta charset="UTF-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\    <link rel="stylesheet" href="styles.css">
        \\    <script src="app.js"></script>
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

    std.debug.print("\n=== COMPREHENSIVE DOM PERFORMANCE BENCHMARK ===\n", .{});
    std.debug.print("HTML size: {d} bytes (~{d:.1}KB)\n", .{ large_html.len, @as(f64, @floatFromInt(large_html.len)) / 1024.0 });
    std.debug.print("Iterations: {d}\n", .{iterations});

    var timer = try std.time.Timer.start();

    // === Test 1: HTML String → DOM (lexbor parsing) ===
    timer.reset();
    for (0..iterations) |_| {
        const doc = try z.parseFromString(large_html);
        z.destroyDocument(doc);
    }
    const html_to_dom_time = timer.read();

    // Parse once for other tests
    const doc = try z.parseFromString(large_html);
    defer z.destroyDocument(doc);

    // === Test 2: DOM → Tuple String ===
    timer.reset();
    var tuple_result: []u8 = undefined;
    for (0..iterations) |i| {
        if (i > 0) allocator.free(tuple_result);
        tuple_result = try tree.domToTupleString(allocator, doc);
    }
    const dom_to_tuple_time = timer.read();

    // === Test 3: Tuple String → HTML String ===
    timer.reset();
    var html_result: []u8 = undefined;
    for (0..iterations) |i| {
        if (i > 0) allocator.free(html_result);
        html_result = try tree.tupleStringToHtml(allocator, tuple_result);
    }
    const tuple_to_html_time = timer.read();

    // === Test 4: HTML String → DOM → HTML String (lexbor round-trip) ===
    timer.reset();
    for (0..iterations) |_| {
        const temp_doc = try z.parseFromString(large_html);
        const body_element = try z.bodyElement(temp_doc);
        const serialized_html = try z.outerHTML(allocator, body_element);
        allocator.free(serialized_html);
        z.destroyDocument(temp_doc);
    }
    const lexbor_roundtrip_time = timer.read();

    // === Test 5: Single Node Operations ===
    const body_node = try z.bodyNode(doc);
    const main_node = z.firstChild(body_node).?;

    timer.reset();
    var node_tuple_result: []u8 = undefined;
    for (0..iterations) |i| {
        if (i > 0) allocator.free(node_tuple_result);
        node_tuple_result = try tree.nodeToTupleString(allocator, main_node);
    }
    const single_node_time = timer.read();

    // Clean up
    allocator.free(tuple_result);
    allocator.free(html_result);
    allocator.free(node_tuple_result);

    // === Results ===
    const ns_to_us = @as(f64, @floatFromInt(std.time.ns_per_us));
    const ns_to_ms = @as(f64, @floatFromInt(std.time.ns_per_ms));

    std.debug.print("\n--- Performance Results (100 iterations) ---\n", .{});

    std.debug.print("HTML → DOM (lexbor):     {d:.2} ms total, {d:.3} ms/op\n", .{ @as(f64, @floatFromInt(html_to_dom_time)) / ns_to_ms, @as(f64, @floatFromInt(html_to_dom_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)) });

    std.debug.print("DOM → Tuple:             {d:.2} ms total, {d:.3} ms/op\n", .{ @as(f64, @floatFromInt(dom_to_tuple_time)) / ns_to_ms, @as(f64, @floatFromInt(dom_to_tuple_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)) });

    std.debug.print("Tuple → HTML:            {d:.2} ms total, {d:.3} ms/op\n", .{ @as(f64, @floatFromInt(tuple_to_html_time)) / ns_to_ms, @as(f64, @floatFromInt(tuple_to_html_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)) });

    std.debug.print("Lexbor Round-trip:       {d:.2} ms total, {d:.3} ms/op\n", .{ @as(f64, @floatFromInt(lexbor_roundtrip_time)) / ns_to_ms, @as(f64, @floatFromInt(lexbor_roundtrip_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)) });

    std.debug.print("Single Node → Tuple:     {d:.2} μs total, {d:.2} μs/op\n", .{ @as(f64, @floatFromInt(single_node_time)) / ns_to_us, @as(f64, @floatFromInt(single_node_time)) / ns_to_us / @as(f64, @floatFromInt(iterations)) });

    std.debug.print("\n--- Full Pipeline Analysis ---\n", .{});
    const total_tuple_pipeline = dom_to_tuple_time + tuple_to_html_time;
    std.debug.print("Tuple Pipeline (DOM→Tuple→HTML): {d:.3} ms/op\n", .{@as(f64, @floatFromInt(total_tuple_pipeline)) / ns_to_ms / @as(f64, @floatFromInt(iterations))});
    std.debug.print("Lexbor Pipeline (HTML→DOM→HTML):  {d:.3} ms/op\n", .{@as(f64, @floatFromInt(lexbor_roundtrip_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations))});

    const pipeline_comparison = @as(f64, @floatFromInt(lexbor_roundtrip_time)) / @as(f64, @floatFromInt(total_tuple_pipeline));
    std.debug.print("Pipeline Comparison: Lexbor is {d:.2}x {s} than tuple pipeline\n", .{ if (pipeline_comparison > 1) pipeline_comparison else 1.0 / pipeline_comparison, if (pipeline_comparison > 1) "slower" else "faster" });

    std.debug.print("\n--- BEAM Scheduler Compliance ---\n", .{});
    const dom_to_tuple_ms = @as(f64, @floatFromInt(dom_to_tuple_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations));
    const tuple_to_html_ms = @as(f64, @floatFromInt(tuple_to_html_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations));

    std.debug.print("DOM → Tuple: {s} (limit: 1ms)\n", .{if (dom_to_tuple_ms < 1.0) "✅ SAFE" else "❌ DIRTY SCHEDULER"});
    std.debug.print("Tuple → HTML: {s} (limit: 1ms)\n", .{if (tuple_to_html_ms < 1.0) "✅ SAFE" else "❌ DIRTY SCHEDULER"});

    std.debug.print("\n--- Memory Usage ---\n", .{});
    std.debug.print("Original HTML:      {d} bytes ({d:.1}KB)\n", .{ large_html.len, @as(f64, @floatFromInt(large_html.len)) / 1024.0 });
    std.debug.print("Tuple string:       {d} bytes ({d:.1}KB)\n", .{ tuple_result.len, @as(f64, @floatFromInt(tuple_result.len)) / 1024.0 });
    std.debug.print("Reconstructed HTML: {d} bytes ({d:.1}KB)\n", .{ html_result.len, @as(f64, @floatFromInt(html_result.len)) / 1024.0 });

    const expansion_ratio = @as(f64, @floatFromInt(tuple_result.len)) / @as(f64, @floatFromInt(large_html.len));
    std.debug.print("Tuple size ratio:   {d:.2}x original HTML size\n", .{expansion_ratio});

    // Calculate throughput for key operation
    const tuple_to_html_throughput = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0) / (tuple_to_html_ms / 1000.0);
    std.debug.print("\n--- Throughput Analysis ---\n", .{});
    std.debug.print("Tuple → HTML Throughput: {d:.1} MB/s\n", .{tuple_to_html_throughput});

    std.debug.print("\n✅ All comprehensive benchmarks completed successfully!\n", .{});
}