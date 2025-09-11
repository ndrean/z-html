const std = @import("std");
const builtin = @import("builtin");
const z = @import("root.zig");
const native_os = builtin.os.tag;
const print = std.debug.print;

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const gpa, const is_debug = gpa: {
        if (native_os == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.c_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    // try zexplore_example_com(gpa, "https://www.example.com");
    // try demoSimpleParsing(gpa);
    // try demoTemplateWithParser(gpa);
    // try demoParserReUse(gpa);
    // try demoStreamParser(gpa);
    // try demoInsertAdjacentElement(gpa);
    // try demoInsertAdjacentHTML(gpa);
    // try demoSetInnerHTML(gpa);
    // try demoSearchComparison(gpa);
    // try demoSuspiciousAttributes(gpa);
    try normalizeString_DOM_parsing_bencharmark(gpa);
}

/// use `parseString` or `createDocFromString` to create a document with a BODY element populated by the input string
fn demoSimpleParsing(_: std.mem.Allocator) !void {
    const html = "<div></div>";
    {
        const doc = try z.createDocument();
        defer z.destroyDocument(doc);

        try z.parseString(doc, html);

        const body = z.bodyNode(doc).?;
        const div = z.firstChild(body).?;
        const tag_name = z.nodeName_zc(div);
        std.debug.assert(std.mem.eql(u8, tag_name, "DIV"));
    }
    {
        const doc = try z.createDocFromString(html);
        defer z.destroyDocument(doc);

        const body = z.bodyNode(doc).?;
        const div = z.firstChild(body).?;
        const tag_name = z.nodeName_zc(div);
        std.debug.assert(std.mem.eql(u8, tag_name, "DIV"));
    }
}

/// use the `Parser` engine to parse HTML with template support
fn demoTemplateWithParser(allocator: std.mem.Allocator) !void {
    const html =
        \\<table id="producttable">
        \\  <thead>
        \\    <tr>
        \\      <td>Code</td>
        \\      <td>Product_Name</td>
        \\    </tr>
        \\  </thead>
        \\  <tbody>
        \\    <!-- existing data could optionally be included here -->
        \\  </tbody>
        \\</table>
        \\
        \\<template id="productrow">
        \\  <tr>
        \\    <td class="record">Code: 1</td>
        \\    <td>Name: 1</td>
        \\  </tr>
        \\</template>
    ;

    // eliminate all the whitespace between tags
    const normed_html = try z.normalizeText(allocator, html);
    defer allocator.free(normed_html);

    var parser = try z.Parser.init(allocator);
    defer parser.deinit();
    const doc = try parser.parse(normed_html, .none);
    defer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;

    const template_elt = z.getElementById(
        body,
        "productrow",
    ).?;

    const tbody_elt = z.getElementByTag(body, .tbody);
    const tbody_node = z.elementToNode(tbody_elt.?);

    // add twice the template
    try parser.useTemplateElement(template_elt, tbody_node, .none);
    try parser.useTemplateElement(template_elt, tbody_node, .none);

    try z.normalizeDOM(allocator, z.nodeToElement(body).?);

    const resulting_html = try z.innerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(resulting_html);

    const expected = "<table id=\"producttable\"><thead><tr><td>Code</td><td>Product_Name</td></tr></thead><tbody><!-- existing data could optionally be included here --><tr><td class=\"record\">Code: 1</td><td>Name: 1</td></tr><tr><td class=\"record\">Code: 1</td><td>Name: 1</td></tr></tbody></table><template id=\"productrow\"><tr><td class=\"record\">Code: 1</td><td>Name: 1</td></tr></template>";
    try std.testing.expectEqualStrings(expected, resulting_html);
}

fn demoParserReUse(allocator: std.mem.Allocator) !void {
    var parser = try z.Parser.init(allocator);
    defer parser.deinit();

    const doc = try parser.parse("<div><ul></ul></div>", .none);
    defer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;
    const ul_elt = z.getElementByTag(body, .ul).?;
    const ul = z.elementToNode(ul_elt);

    for (0..3) |i| {
        const li = try std.fmt.allocPrint(
            allocator,
            "<li id='item-{}'>Item {}</li>",
            .{ i, i },
        );
        defer allocator.free(li);

        try parser.insertFragment(ul, li, .ul, .none);
    }
    // print("\n === Demonstrate parser engine reuse ===\n\n", .{});
    // print("\n Insert interpolated <li id=\"item-X\"> Item X</li>\n\n", .{});

    // try z.prettyPrint(allocator, body);
    // print("\n\n", .{});
}

/// use Stream engine
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

    for (0..3) |i| {
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
    // const html_node = z.documentRoot(html_doc).?;

    // print("\n\n", .{});
    // try z.prettyPrint(allocator, html_node);
    // print("\n\n", .{});
    // try z.printDocStruct(html_doc);
    // print("\n\n", .{});
}

fn demoInsertAdjacentElement(allocator: std.mem.Allocator) !void {
    const doc = try z.createDocFromString(
        \\<div id="container">
        \\ <p id="target">Target</p>
        \\</div>
    );
    defer z.destroyDocument(doc);
    errdefer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;
    const target = z.getElementById(body, "target").?;

    const before_end_elem = try z.createElementWithAttrs(
        doc,
        "span",
        &.{.{ .name = "class", .value = "before end" }},
    );
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
    try z.setContentAsText(z.elementToNode(after_end_elem), "After End");

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

    try z.insertAdjacentElement(
        target,
        .beforebegin,
        before_begin_elem,
    );

    const html = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(html);
    // print("\n=== Demonstrate insertAdjacentElement ===\n\n", .{});
    // try z.prettyPrint(allocator, body);

    // Normalize whitespace for clean comparison
    const clean_html = try z.normalizeText(allocator, html);
    defer allocator.free(clean_html);

    const expected = "<body><div id=\"container\"><span class=\"before begin\"></span><p id=\"target\"><span class=\"after begin\"></span>Target<span class=\"before end\"></span></p><span class=\"after end\">After End</span></div></body>";

    std.debug.assert(std.mem.eql(u8, expected, clean_html) == true);
}

fn demoInsertAdjacentHTML(allocator: std.mem.Allocator) !void {
    // const allocator = std.testing.allocator;
    const doc = try z.createDocFromString(
        \\<div id="container">
        \\    <p id="target">Target</p>
        \\</div>
    );
    defer z.destroyDocument(doc);
    errdefer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;
    const target = z.getElementById(body, "target").?;

    try z.insertAdjacentHTML(
        allocator,
        target,
        .beforeend,
        "<span class=\"before end\"></span>",
        .none,
    );

    try z.insertAdjacentHTML(
        allocator,
        target,
        "afterend",
        "<span class=\"after end\">After End</span>",
        .none,
    );

    try z.insertAdjacentHTML(
        allocator,
        target,
        "afterbegin",
        "<span class=\"after begin\"></span>",
        .none,
    );

    try z.insertAdjacentHTML(
        allocator,
        target,
        "beforebegin",
        "<span class=\"before begin\"></span>",
        .none,
    );

    // Show result after insertAdjacentElement
    const html = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(html);
    // print("\n=== Demonstrate insertAdjacentHTML ===\n\n", .{});
    // try z.prettyPrint(allocator, body);

    // Normalize whitespace for clean comparison
    const clean_html = try z.normalizeText(allocator, html);
    defer allocator.free(clean_html);

    const expected = "<body><div id=\"container\"><span class=\"before begin\"></span><p id=\"target\"><span class=\"after begin\"></span>Target<span class=\"before end\"></span></p><span class=\"after end\">After End</span></div></body>";

    std.debug.assert(std.mem.eql(u8, expected, clean_html) == true);

    // print("\n--- Normalized HTML --- \n\n{s}\n", .{clean_html});
    // print("\n\n", .{});
}

/// `setInnerHTML` and `innerHTML` with `normalize` for easy comparison (remove whitespace only text nodes)
fn demoSetInnerHTML(allocator: std.mem.Allocator) !void {
    // print("\n=== Demonstrate setInnerHTML & innerHTML ===\n\n", .{});
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);
    try z.parseString(doc, "<div id=\"target\"></div>");

    const body = z.bodyNode(doc).?;
    const div = z.getElementById(body, "target").?;

    const new_div_elt = try z.setInnerHTML(div, "<p class=\"new-content\">New Content</p>");

    // try z.prettyPrint(allocator,z.documentRoot(doc).?);

    try z.normalizeDOM(allocator, new_div_elt);

    // Show result after setInnerHTML
    const html_new_div = try z.innerHTML(
        allocator,
        new_div_elt,
    );
    defer allocator.free(html_new_div);

    const expected = "<p class=\"new-content\">New Content</p>";

    std.debug.assert(std.mem.eql(u8, expected, html_new_div) == true);
}

fn demoSearchComparison(allocator: std.mem.Allocator) !void {
    print("\n=== Search Comparison --------------------------\n\n", .{});

    // Create test HTML with diverse elements
    const test_html =
        \\<div class="main-container">
        \\  <h1 class="title main">Main Title</h1>
        \\  <section class="content">
        \\    <p id="1" class="text main-text">First paragraph</p>
        \\    <div class="box main-box">Box content</div>
        \\    <article class="post main-post">Article content</article>
        \\  </section>
        \\  <aside class="sidebar">
        \\    <h2 class="subtitle">Sidebar Title</h2>
        \\    <p class="text sidebar-text">Sidebar paragraph</p>
        \\    <div class="widget">Widget content</div>
        \\  </aside>
        \\  <footer  aria-label="foot" class="main-footer container">
        \\    <p class="copyright">© 2024</p>
        \\  </footer>
        \\</div>
    ;

    const doc = try z.createDocFromString(test_html);
    defer z.destroyDocument(doc);
    const body = z.bodyNode(doc).?;
    // try z.prettyPrint(allocator, body);
    var css_engine = try z.createCssEngine(allocator);
    defer css_engine.deinit();

    // 1. Walker-based attribute search (token-based matching with hasClass)
    const walker_results = try z.getElementsByClassName(allocator, doc, "main");
    defer allocator.free(walker_results);
    const walker_count = walker_results.len;
    print("\n1. Walker-based attribute [class = 'main']:     Found {} elements\n", .{walker_count});

    for (walker_results, 0..) |element, i| {
        const tag = z.tagName_zc(element);
        const class_attr = z.getAttribute_zc(element, "class") orelse "none";
        print("   [{}]: <{s}> class=\"{s}\"\n", .{ i, tag, class_attr });
    }

    // 2. CSS Selector search (case-insensitive, token-based)

    const css_results = try z.querySelectorAll(allocator, doc, ".main");
    defer allocator.free(css_results);
    const css_count = css_results.len;
    print("\n2. CSS Selector search [class = 'main']:        Found {} elements (case-insensitive)\n", .{css_count});

    for (css_results, 0..) |element, i| {
        const tag = z.tagName_zc(element);
        const class_attr = z.getAttribute_zc(element, "class") orelse "none";
        print("   [{}]: <{s}> class=\"{s}\"\n", .{ i, tag, class_attr });
    }

    const footer = try z.getElementByDataAttribute(
        body,
        "aria",
        "label",
        null,
    );
    if (footer) |foot| {
        const i = 0;
        const tag = z.tagName_zc(foot);
        const class_attr = z.getAttribute_zc(foot, "class") orelse "none";
        print("\n3. Walker ByDataAttribute 'aria-label':         Found  1 element\n", .{});
        print("{s}\n", .{z.getAttribute_zc(foot, "aria-label").?});
        print("   [{}]: <{s}> class=\"{s}\"\n", .{ i, tag, class_attr });
        var footer_token_list = try z.ClassList.init(
            allocator,
            foot,
        );
        defer footer_token_list.deinit();
        print("   nb classes: {d}\n", .{footer_token_list.length()});
        try footer_token_list.add("footer");
        std.debug.assert(footer_token_list.contains("footer"));
        _ = try footer_token_list.toggle("footer");
        std.debug.assert(!footer_token_list.contains("footer"));
    }

    // Demonstrate DOM synchronization by adding an element
    const new_element = try z.createElementWithAttrs(doc, "span", &.{.{ .name = "class", .value = "main new-element" }});
    z.appendChild(body, z.elementToNode(new_element));

    // Search again to show updated results
    const updated_walker_results = try z.getElementsByClassName(allocator, doc, "main");
    defer allocator.free(updated_walker_results);
    const updated_walker_count = updated_walker_results.len;

    const updated_css_results = try z.querySelectorAll(allocator, doc, ".main");
    defer allocator.free(updated_css_results);
    const updated_css_count = updated_css_results.len;

    print("\nAdd a new element <span class=\"main new-element\"> with class 'main' and rerun the search:\n\n", .{});
    print("1. Walker-based: {} -> {} elements\n", .{ walker_count, updated_walker_count });
    print("2. CSS Selectors: {} -> {} elements\n", .{ css_count, updated_css_count });

    print("\n", .{});
}

fn demoSuspiciousAttributes(allocator: std.mem.Allocator) !void {
    // Create a document with lots of suspicious/malicious attributes to see the highlighting
    const malicious_content =
        \\<div>
        \\  <!-- a comment -->
        \\  <button disabled hidden onclick="alert('XSS')" phx-click="increment" data-invalid="bad" scope="invalid">Dangerous button</button>
        \\  <img src="javascript:alert('XSS')" alt="not safe" onerror="alert('hack')" loading="unknown">
        \\  <a href="javascript:alert('XSS')" target="_self" role="invalid">Dangerous link</a>
        \\  <p id="valid" class="good" aria-label="ok" style="bad" onload="bad()">Mixed attributes</p>
        \\  <custom-elt><p>Hi there</p></custom-elt>
        \\  <template>
        \\      <span>Reuse me</span>
        \\      <script>console.log('Hello from template');</script>
        \\  </template>
        \\</div>
    ;

    const doc = try z.createDocFromString(malicious_content);
    defer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;
    const div = z.firstChild(body).?;
    const text = z.firstChild(div).?;
    const com = z.nextSibling(text).?;
    print("{s}\n", .{z.nodeTypeName(com)});
    try z.prettyPrint(allocator, body);
    print("\n", .{});

    try z.sanitizeNode(allocator, body, .permissive);
    try z.prettyPrint(allocator, body);
    print("\n", .{});
}

fn zexplore_example_com(allocator: std.mem.Allocator, url: []const u8) !void {
    const page = try z.get(allocator, url);
    defer allocator.free(page);
    const doc = try z.createDocFromString(page);
    defer z.destroyDocument(doc);
    const html = z.documentRoot(doc).?;
    try z.prettyPrint(allocator, html);

    var css_engine = try z.createCssEngine(allocator);
    defer css_engine.deinit();

    const a_link = try css_engine.querySelector(html, "a[href]");

    const href_value = z.getAttribute_zc(z.nodeToElement(a_link.?).?, "href").?;
    std.debug.print("{s}\n", .{href_value});

    const style_by_walker = z.getElementByTag(html, .style);
    var css_content: []const u8 = undefined;
    if (style_by_walker) |style| {
        css_content = z.textContent_zc(z.elementToNode(style));
        print("{s}\n", .{css_content});
    }

    const style_by_css = try css_engine.querySelector(html, "style");

    if (style_by_css) |style| {
        const css_content_2 = z.textContent_zc(style);
        // print("{s}\n", .{css_content_2});
        std.debug.assert(std.mem.eql(u8, css_content, css_content_2));
    }
}

// fn runPerformanceBenchmark(allocator: std.mem.Allocator) !void {
//     // Create ~300KB HTML document by building it dynamically
//     var html_builder: std.ArrayList(u8) = .empty;
//     defer html_builder.deinit(allocator);

//     try html_builder.appendSlice(allocator,
//         \\<html>
//         \\  <head>
//         \\    <title>Large Performance Test Document</title>
//         \\    <meta charset="UTF-8">
//         \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
//         \\    <link rel="stylesheet" href="styles.css">
//         \\    <script src="app.js"></scrip>
//         \\  </head>
//         \\  <body class="main-body">
//         \\    <header id="main-header" class="sticky-header">
//         \\      <nav class="navbar">
//         \\        <ul class="nav-list">
//         \\          <li><a href="/" class="nav-link active">Home</a></li>
//         \\          <li><a href="/about" class="nav-link">About</a></li>
//         \\          <li><a href="/contact" class="nav-link">Contact</a></li>
//         \\          <li><a href="/products" class="nav-link">Products</a></li>
//         \\          <li><a href="/services" class="nav-link">Services</a></li>
//         \\        </ul>
//         \\      </nav>
//         \\    </header>
//     );

//     // Duplicate main content sections to reach ~100KB
//     const section_template =
//         \\    <main class="content-wrapper">
//         \\      <article class="blog-post">
//         \\        <h1>Performance Test Section</h1>
//         \\        <p class="intro">This is a section of our <strong>large-scale</strong> HTML document
//         \\           designed to test <em>performance</em> of our tuple serialization system with
//         \\           substantial content that simulates real-world usage patterns.</p>
//         \\        <!-- Performance test comment -->
//         \\        <div class="content-section">
//         \\          <h2>Features We're Testing</h2>
//         \\          <ul class="feature-list">
//         \\            <li data-feature="speed">Ultra-fast serialization</li>
//         \\            <li data-feature="memory">Memory-efficient processing</li>
//         \\            <li data-feature="accuracy">Accurate round-trip conversion</li>
//         \\            <li data-feature="scalability">Scalability under load</li>
//         \\            <li data-feature="reliability">Reliable error handling</li>
//         \\          </ul>
//         \\        </div>
//         \\        <div class="data-table">
//         \\          <table class="performance-table">
//         \\            <thead>
//         \\              <tr><th>Metric</th><th>Value</th><th>Benchmark</th></tr>
//         \\            </thead>
//         \\            <tbody>
//         \\              <tr><td>Latency</td><td>0.5ms</td><td>Excellent</td></tr>
//         \\              <tr><td>Throughput</td><td>1000k ops/sec</td><td>Outstanding</td></tr>
//         \\              <tr><td>Memory</td><td>256KB</td><td>Optimal</td></tr>
//         \\            </tbody>
//         \\          </table>
//         \\        </div>
//         \\        <form class="feedback-form" method="post" action="/feedback">
//         \\          <fieldset>
//         \\            <legend>Section Feedback</legend>
//         \\            <div class="form-group">
//         \\              <label for="name">Name:</label>
//         \\              <input type="text" id="name" name="name" required placeholder="Your name">
//         \\            </div>
//         \\            <div class="form-group">
//         \\              <label for="email">Email:</label>
//         \\              <input type="email" id="email" name="email" required placeholder="your@email.com">
//         \\            </div>
//         \\            <div class="form-group">
//         \\              <label for="rating">Rating:</label>
//         \\              <select id="rating" name="rating">
//         \\                <option value="5">⭐⭐⭐⭐⭐ Excellent</option>
//         \\                <option value="4">⭐⭐⭐⭐ Very Good</option>
//         \\                <option value="3">⭐⭐⭐ Good</option>
//         \\                <option value="2">⭐⭐ Fair</option>
//         \\                <option value="1">⭐ Poor</option>
//         \\              </select>
//         \\            </div>
//         \\            <div class="form-group">
//         \\              <textarea name="comments" rows="4" cols="50"
//         \\                        placeholder="Your detailed feedback..."></textarea>
//         \\            </div>
//         \\            <button type="submit" class="btn-primary">Submit Feedback</button>
//         \\          </fieldset>
//         \\        </form>
//         \\      </article>
//         \\      <aside class="sidebar">
//         \\        <div class="widget news">
//         \\          <h3>Latest News</h3>
//         \\          <ul>
//         \\            <li><a href="/news/1">Performance improvements</a></li>
//         \\            <li><a href="/news/2">Memory optimization</a></li>
//         \\            <li><a href="/news/3">Better DOM handling</a></li>
//         \\            <li><a href="/news/4">Enhanced error reporting</a></li>
//         \\          </ul>
//         \\        </div>
//         \\        <div class="widget tags">
//         \\          <h3>Tags</h3>
//         \\          <span class="tag">performance</span>
//         \\          <span class="tag">html</span>
//         \\          <span class="tag">parsing</span>
//         \\          <span class="tag">optimization</span>
//         \\          <span class="tag">benchmarks</span>
//         \\        </div>
//         \\      </aside>
//         \\    </main>
//     ;

//     // Add 100 sections to reach ~100KB
//     for (1..101) |_| {
//         try html_builder.appendSlice(allocator, section_template);
//     }

//     try html_builder.appendSlice(allocator,
//         \\    <footer class="site-footer">
//         \\      <div class="footer-content">
//         \\        <p>&copy; 2024 Comprehensive Performance Test Suite. All rights reserved.</p>
//         \\        <div class="footer-links">
//         \\          <a href="/privacy">Privacy Policy</a> |
//         \\          <a href="/terms">Terms of Service</a> |
//         \\          <a href="/api">API Documentation</a> |
//         \\          <a href="/support">Technical Support</a> |
//         \\          <a href="/docs">Documentation</a>
//         \\        </div>
//         \\        <div class="footer-stats">
//         \\          <span>Total operations tested: 1M+</span>
//         \\          <span>Average response time: 0.3ms</span>
//         \\          <span>Memory usage: <128KB</span>
//         \\        </div>
//         \\      </div>
//         \\    </footer>
//         \\  </body>
//         \\</html>
//     );

//     const large_html = try html_builder.toOwnedSlice(allocator);
//     defer allocator.free(large_html);

//     const iterations = 100;
//     print("\n=====================================================================\n", .{});
//     print("\nLarge HTML conversions:  HTML<->DOM, DOM->Tuple, Tuple->HTML\n", .{});
//     print("HTML size: {d} bytes (~{d:.1}KB)\n", .{ large_html.len, @as(f64, @floatFromInt(large_html.len)) / 1024.0 });
//     print("Iterations: {d}\n", .{iterations});

//     var timer = try std.time.Timer.start();

//     // Test 1: [HTMLstring → DOM]
//     timer.reset();
//     for (0..iterations) |_| {
//         const doc = try z.createDocFromString(large_html);
//         z.destroyDocument(doc);
//     }
//     const html_to_dom_time = timer.read();

//     // === Test 1.b: [Normalize-HTMLstring → DOM]
//     timer.reset();
//     for (0..iterations) |_| {
//         const normalized = try z.normalize.normalizeHtmlStringWithOptions(allocator, large_html, .{
//             .remove_comments = true,
//             .remove_whitespace_text_nodes = true,
//         });
//         const doc = try z.createDocFromString(normalized);
//         allocator.free(normalized);
//         z.destroyDocument(doc);
//     }
//     _ = timer.read(); // norm_html_to_dom_time unused

//     // Parse once for other tests
//     const doc = try z.createDocFromString(large_html);
//     defer z.destroyDocument(doc);
//     const body_element = z.bodyElement(doc).?;

//     // Test 2.b: [DOM -> Tuple]
//     var tuple_v2_result: []u8 = undefined;
//     timer.reset();
//     for (0..iterations) |i| {
//         if (i > 0) allocator.free(tuple_v2_result);

//         tuple_v2_result = try tree.domToTupleString(allocator, doc);
//     }
//     const dom_to_tuple_time = timer.read();

//     // === Test 2: [DOM-Normalize → Tuple]
//     var tuple_v21_result: []u8 = undefined;
//     timer.reset();
//     for (0..iterations) |i| {
//         if (i > 0) allocator.free(tuple_v21_result);
//         const temp_doc = try z.createDocFromString(large_html);
//         const temp_body_element = try z.bodyElement(temp_doc);

//         try z.normalizeDOMwithOptions(
//             allocator,
//             temp_body_element,
//             .{
//                 .remove_whitespace_text_nodes = true,
//                 .skip_comments = true,
//             },
//         );
//         tuple_v21_result = try tree.domToTupleString(allocator, temp_doc);
//         z.destroyDocument(temp_doc);
//     }
//     const norm_dom_to_tuple_time = timer.read();

//     // === Test2.b : [normalized-DOM -> Tuple]
//     var tuple_v22_result: []u8 = undefined;
//     timer.reset();
//     for (0..iterations) |i| {
//         if (i > 0) allocator.free(tuple_v22_result);

//         const normalized = try z.normalize.normalizeHtmlStringWithOptions(allocator, large_html, .{
//             .remove_comments = true,
//             .remove_whitespace_text_nodes = true,
//         });
//         const temp_doc = try z.createDocFromString(normalized);
//         allocator.free(normalized);

//         tuple_v22_result = try tree.domToTupleString(allocator, temp_doc);
//         z.destroyDocument(temp_doc);
//     }
//     const pre_norm_dom_to_tuple_time = timer.read();

//     // === Test 3: [Tuple → HTMLstring]
//     timer.reset();
//     var html_result: []u8 = undefined;
//     for (0..iterations) |i| {
//         if (i > 0) allocator.free(html_result);
//         html_result = try tree.tupleStringToHtml(allocator, tuple_v22_result);
//     }
//     const tuple_to_html_time = timer.read();

//     // === Test 4: [DOM -> HTML] - Isolated innerHTML performance
//     timer.reset();
//     for (0..iterations) |_| {
//         const serialized_html = try z.innerHTML(allocator, body_element);
//         allocator.free(serialized_html);
//     }
//     const pure_dom_to_html_time = timer.read();

//     // === Test 4.b: [DOM -> HTML] with parsing overhead (original test)
//     const normalized = try z.normalize.normalizeHtmlStringWithOptions(allocator, large_html, .{
//         .remove_comments = true,
//         .remove_whitespace_text_nodes = true,
//     });

//     timer.reset();
//     for (0..iterations) |_| {
//         const temp_doc = try z.createDocFromString(normalized);
//         const temp_body_element = try z.bodyElement(temp_doc);
//         const serialized_html = try z.innerHTML(allocator, temp_body_element);
//         allocator.free(serialized_html);
//         z.destroyDocument(temp_doc);
//     }
//     const dom_to_html_time = timer.read();

//     const tuple_len = tuple_v2_result.len;
//     const norm_tuple_len = tuple_v22_result.len;
//     allocator.free(normalized);
//     allocator.free(tuple_v2_result);
//     allocator.free(tuple_v22_result);
//     allocator.free(html_result);

//     // === Results ===
//     const ns_to_ms = @as(f64, @floatFromInt(std.time.ns_per_ms));

//     print("\n--- Performance Results (100 iterations) ---\n", .{});

//     const html2domlxb = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0 * @as(f64, @floatFromInt(iterations))) / (@as(f64, @floatFromInt(html_to_dom_time)) / ns_to_ms / 1000.0);
//     print("HTML → DOM (lexbor):       {d:.2} ms/op, {d:.3} MB/s\n", .{ @as(f64, @floatFromInt(html_to_dom_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)), html2domlxb });

//     const pre_norm_dom_tuple = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0 * @as(f64, @floatFromInt(iterations))) / (@as(f64, @floatFromInt(pre_norm_dom_to_tuple_time)) / ns_to_ms / 1000.0);
//     print("pre-norm-DOM -> Tuple.     {d:.2} ms/op, {d:.1} MB/s\n", .{ @as(f64, @floatFromInt(pre_norm_dom_to_tuple_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)), pre_norm_dom_tuple });

//     const pure_dom2html = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0 * @as(f64, @floatFromInt(iterations))) / (@as(f64, @floatFromInt(pure_dom_to_html_time)) / ns_to_ms / 1000.0);
//     print("DOM → HTML (pure innerHTML): {d:.2} ms/op, {d:.1} MB/s\n", .{ @as(f64, @floatFromInt(pure_dom_to_html_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)), pure_dom2html });

//     const dom2html = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0 * @as(f64, @floatFromInt(iterations))) / (@as(f64, @floatFromInt(dom_to_html_time)) / ns_to_ms / 1000.0);
//     print("DOM → HTML (with parsing):   {d:.2} ms/op, {d:.1} MB/s\n", .{ @as(f64, @floatFromInt(dom_to_html_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)), dom2html });

//     const norm_dom2tuple = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0 * @as(f64, @floatFromInt(iterations))) / (@as(f64, @floatFromInt(norm_dom_to_tuple_time)) / ns_to_ms / 1000.0);
//     print("DOM-Norm → Tuple:           {d:.2} ms/op, {d:.1} MB/s\n", .{ @as(f64, @floatFromInt(norm_dom_to_tuple_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)), norm_dom2tuple });

//     const dom2tuple = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0 * @as(f64, @floatFromInt(iterations))) / (@as(f64, @floatFromInt(dom_to_tuple_time)) / ns_to_ms / 1000.0);
//     print("DOM → Tuple:               {d:.2} ms/op, {d:.1} MB/s\n", .{ @as(f64, @floatFromInt(dom_to_tuple_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)), dom2tuple });

//     print("Tuple size: without norm {d} bytes, with norm {d} bytes\n", .{ tuple_len, norm_tuple_len });

//     const tuple2Html = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0 * @as(f64, @floatFromInt(iterations))) / (@as(f64, @floatFromInt(tuple_to_html_time)) / ns_to_ms / 1000.0);
//     print("Tuple → HTML:             {d:.2} ms/op, {d:.1} MB/s\n", .{ @as(f64, @floatFromInt(tuple_to_html_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations)), tuple2Html });

//     // print("\n--- BEAM Scheduler Compliance ---\n", .{});
//     // const dom_to_tuple_ms = @as(f64, @floatFromInt(dom_to_tuple_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations));
//     // const tuple_to_html_ms = @as(f64, @floatFromInt(tuple_to_html_time)) / ns_to_ms / @as(f64, @floatFromInt(iterations));

//     // print("DOM → Tuple: {s} (limit: 1ms)\n", .{if (dom_to_tuple_ms < 1.0) "✅ SAFE" else "❌ DIRTY SCHEDULER"});
//     // print("Tuple → HTML: {s} (limit: 1ms)\n", .{if (tuple_to_html_ms < 1.0) "✅ SAFE" else "❌ DIRTY SCHEDULER"});

//     // print("\n--- Memory Usage ---\n", .{});
//     // print("Original HTML:      {d} bytes ({d:.1}KB)\n", .{ large_html.len, @as(f64, @floatFromInt(large_html.len)) / 1024.0 });
//     // print("Tuple string:       {d} bytes ({d:.1}KB)\n", .{ tuple_result.len, @as(f64, @floatFromInt(tuple_result.len)) / 1024.0 });
//     // print("Reconstructed HTML: {d} bytes ({d:.1}KB)\n", .{ html_result.len, @as(f64, @floatFromInt(html_result.len)) / 1024.0 });

//     // const expansion_ratio = @as(f64, @floatFromInt(tuple_result.len)) / @as(f64, @floatFromInt(large_html.len));
//     // print("Tuple size ratio:   {d:.2}x original HTML size\n", .{expansion_ratio});

//     // // Calculate throughput for key operation
//     // const tuple_to_html_throughput = (@as(f64, @floatFromInt(large_html.len)) / 1024.0 / 1024.0) / (tuple_to_html_ms / 1000.0);
//     // print("\n--- Throughput Analysis ---\n", .{});
//     // print("Tuple → HTML Throughput: {d:.1} MB/s\n", .{tuple_to_html_throughput});
// }

// fn runNormalizeBenchmark(allocator: std.mem.Allocator) !void {
//     // var html_builder: std.ArrayList(u8) = .empty;
//     const initBuffer = try allocator.alloc(u8, 25_000);
//     var html_builder: std.mem.Allocating = .initOwnedSlice(allocator, initBuffer);
//     defer html_builder.deinit();

//     // Pre-allocate capacity for the HTML builder (estimate ~25KB for this test)
//     // try html_builder.ensureTotalCapacity(allocator, 25_000);

//     try html_builder.writer.writeAll(
//         \\<html>
//         \\<body>
//         \\  <div class="container">
//         \\    <header>
//         \\      <h1>   Performance Test Document   </h1>
//         \\      <nav>
//         \\        <ul>
//     );

//     // Add many elements with whitespace
//     for (0..100) |i| {
//         try html_builder.appendSlice(allocator,
//             \\          <li>
//             \\            <a href="/page
//         );

//         const num_str = try std.fmt.allocPrint(allocator, "{d}", .{i});
//         defer allocator.free(num_str);
//         try html_builder.appendSlice(allocator, num_str);

//         try html_builder.appendSlice(allocator,
//             \\">   Link
//         );
//         try html_builder.appendSlice(allocator, num_str);
//         try html_builder.appendSlice(allocator,
//             \\   </a>
//             \\            <span>   Some text with    whitespace   </span>
//             \\            <!-- comment with whitespace -->
//             \\            <em>     emphasized text     </em>
//             \\          </li>
//         );
//     }

//     try html_builder.appendSlice(allocator,
//         \\        </ul>
//         \\      </nav>
//         \\    </header>
//         \\    <main>
//         \\      <section>
//         \\        <p>   This is a paragraph with    lots of    whitespace   </p>
//         \\        <div>
//         \\          <pre>   Preserve   this   whitespace   </pre>
//         \\          <textarea>   Also preserve   this   </textarea>
//         \\        </div>
//         \\      </section>
//         \\    </main>
//         \\  </div>
//         \\</body>
//         \\</html>
//     );

//     const large_html = try html_builder.toOwnedSlice(allocator);
//     defer allocator.free(large_html);

//     const iterations = 100;
//     const kb_size = (@as(f64, @floatFromInt(large_html.len)) / 1024.0);
//     print("\n NORMALIZE PERFORMANCE BENCHMARK\n", .{});
//     print("HTML size: {d} bytes (~{d:.1}KB)\n", .{ large_html.len, kb_size });
//     print("Iterations: {d}\n", .{iterations});

//     // var  doc = try z.createDocFromString(large_html);
//     var doc: *z.HTMLDocument = undefined;
//     defer z.destroyDocument(doc);

//     var timer = try std.time.Timer.start();
//     timer.reset();
//     for (0..iterations) |_| {
//         doc = try z.createDocFromString(large_html);
//         const body_elt = z.bodyElement(doc).?;
//         _ = body_elt;
//     }
//     const parsing_time = @as(f64, @floatFromInt(timer.read()));

//     // Test DOM-based normalization
//     timer.reset();
//     for (0..iterations) |_| {
//         doc = try z.createDocFromString(large_html);
//         const body_elt = z.bodyElement(doc).?;

//         try z.normalizeDOMwithOptions(
//             allocator,
//             body_elt,
//             .{
//                 .remove_whitespace_text_nodes = true,
//                 .skip_comments = true,
//             },
//         );
//     }
//     const dom_total_time = @as(f64, @floatFromInt(timer.read()));

//     // Test string-based normalization (no parsing needed)
//     timer.reset();
//     for (0..iterations) |_| {
//         const normalized = try z.normalize.normalizeHtmlStringWithOptions(allocator, large_html, .{
//             .remove_comments = true,
//             .remove_whitespace_text_nodes = true,
//         });
//         allocator.free(normalized);
//     }
//     const string_time = @as(f64, @floatFromInt(timer.read()));

//     const dom_normalize_time = dom_total_time - parsing_time;

//     // Calculate MB/s properly
//     const total_mb = (kb_size * @as(f64, @floatFromInt(iterations))) / 1024.0;
//     const parsing_time_s = parsing_time / 1_000_000_000.0;
//     const dom_normalize_time_s = dom_normalize_time / 1_000_000_000.0;
//     const string_time_s = string_time / 1_000_000_000.0;

//     const parsing_speed = total_mb / parsing_time_s;
//     const dom_normalize_speed = total_mb / dom_normalize_time_s;
//     const string_speed = total_mb / string_time_s;

//     const speedup = dom_normalize_time_s / string_time_s;

//     print("\n--- Results (Release Mode) ---\n", .{});
//     print("Parsing processing speed:         {d:.1} MB/s ({d:.2} ms/op)\n", .{ parsing_speed, (parsing_time / @as(f64, @floatFromInt(iterations))) / 1_000_000.0 });
//     print("Normalize via DOM processing:     {d:.1} MB/s ({d:.2} ms/op)\n", .{ dom_normalize_speed, (dom_normalize_time / @as(f64, @floatFromInt(iterations))) / 1_000_000.0 });
//     print("String Normalize processing:      {d:.1} MB/s ({d:.2} ms/op)\n", .{ string_speed, (string_time / @as(f64, @floatFromInt(iterations))) / 1_000_000.0 });
//     print("String vs DOM speedup:            {d:.1}x faster\n", .{speedup});
// }

fn normalizeString_DOM_parsing_bencharmark(allocator: std.mem.Allocator) !void {

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
        \\    <script src="/js/analytics.js"></>
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
        \\        <code> const std = @import("std");\n const z = @import("../root.zig");\n</code>
        \\      </nav>
        \\    </header>
        \\
        \\    <main class="content">
    );

    // Add multiple blog posts
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
            \\const normalized = normalizeDOM(html);
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
    print("\n=== HTML parsing / normalization string vs DOM BENCHMARK----------------\n\n", .{});
    print("HTML size: {d} bytes (~{d:.1}KB)\n", .{ medium_html.len, @as(f64, @floatFromInt(medium_html.len)) / 1024.0 });
    print("Iterations: {d}\n", .{iterations});

    var timer = try std.time.Timer.start();

    // Pipeline 1: HTMLstring → normalize_string → parser.append_to_DOM
    timer.reset();
    const doc0 = try z.createDocument();
    defer z.destroyDocument(doc0);
    for (0..iterations) |_| {
        // 1: Normalize HTML string (remove comments + whitespace)
        const normalized = try z.normalizeHtmlStringWithOptions(allocator, medium_html, .{
            .remove_comments = true,
            .remove_whitespace_text_nodes = true,
        });
        defer allocator.free(normalized);
        try z.parseString(doc0, normalized);
        try z.parseString(doc0, ""); // reset
    }
    const html_normString_parse_into_a_doc = timer.read();

    timer.reset();
    const doc1 = try z.createDocFromString("");
    defer z.destroyDocument(doc1);
    var parser1 = try z.Parser.init(allocator);
    defer parser1.deinit();
    const body_elt1 = z.bodyElement(doc1);
    for (0..iterations) |_| {
        // 1: Normalize HTML string (remove comments + whitespace)
        const normalized = try z.normalizeHtmlStringWithOptions(allocator, medium_html, .{
            .remove_comments = true,
            .remove_whitespace_text_nodes = true,
        });
        defer allocator.free(normalized);

        try parser1.parseAndAppend(
            body_elt1.?,
            normalized,
            .body,
            .none,
        );
        _ = try z.setInnerHTML(body_elt1.?, ""); // reset
    }
    const html_normString_parser_append = timer.read();

    timer.reset();
    var parser2 = try z.Parser.init(allocator);
    defer parser2.deinit();
    for (0..iterations) |_| {
        const doc2 = try parser2.parse(medium_html, .none);
        defer z.destroyDocument(doc2);
        const body_elt2 = z.bodyElement(doc2);

        try z.normalizeDOMwithOptions(
            allocator,
            body_elt2.?,
            .{
                .skip_comments = true,
            },
        );
        _ = try z.setInnerHTML(body_elt2.?, "");
    }
    const html_parser_parse_into_new_DOM_norm_DOM = timer.read();

    // Calculate performance metrics
    const ns_to_ms = @as(f64, @floatFromInt(std.time.ns_per_ms));
    const mb_size = @as(f64, @floatFromInt(medium_html.len)) / 1024.0 / 1024.0;
    const iter = @as(f64, @floatFromInt(iterations));

    const html_normString_parse_into_a_doc_ms = @as(f64, @floatFromInt(html_normString_parse_into_a_doc)) / ns_to_ms;
    const html_normString_parser_append_ms = @as(f64, @floatFromInt(html_normString_parser_append)) / ns_to_ms;
    const html_parser_parse_into_new_DOM_norm_DOM_ms = @as(f64, @floatFromInt(html_parser_parse_into_new_DOM_norm_DOM)) / ns_to_ms;

    print("\n--- Speed Results ---\n", .{});

    print("new doc:           normString    -> parseString :       {d:.2} ms/op, {d:.1} MB/s\n", .{ html_normString_parse_into_a_doc_ms / iter, html_normString_parse_into_a_doc_ms / mb_size });

    print("parser, new doc:   normString    -> parser.append:      {d:.2} ms/op, {d:.1} MB/s\n", .{ html_normString_parser_append_ms / iter, html_normString_parser_append_ms / mb_size });

    print("parser:  (new doc: parser.parse  -> DOMnorm:            {d:.2} ms/op,  {d:.1} MB/s\n", .{ html_parser_parse_into_new_DOM_norm_DOM_ms / iter, html_parser_parse_into_new_DOM_norm_DOM_ms / mb_size });
}
