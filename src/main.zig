const std = @import("std");
const builtin = @import("builtin");
const z = @import("root.zig");
const native_os = builtin.os.tag;
// const print = std.debug.print;

const W = std.Io.Writer;
// const print = switch (builtin.mode) {
//     .Debug => std.debug.print,
//     else => std.Io.Writer.print,
// };
const print = std.debug.print;
var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    // Arena allocator setup for benchmarking
    // var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    // defer arena.deinit();
    // const gpa = arena.allocator();

    // Original allocator logic (commented out for arena test)
    const gpa, const is_debug = gpa: {
        if (native_os == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.page_allocator, false },
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
    try demoNormalizer(gpa);
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

fn demoNormalizer(gpa: std.mem.Allocator) !void {
    const messy_html =
        \\<div>
        \\<!-- comment -->
        \\
        \\<p>Content</p>
        \\
        \\<pre>  preserve  this  </pre>
        \\
        \\</div>
    ;

    // const expected = "<div><!-- comment --><p>Content</p><pre>  preserve  this  </pre></div>";
    const expected_noc = "<div><p>Content</p><pre>  preserve  this  </pre></div>";

    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    // -- DOM-based normalization
    try z.parseString(doc, messy_html);

    const body_elt1 = z.bodyElement(doc).?;
    try z.normalizeDOMwithOptions(
        gpa,
        body_elt1,
        .{ .skip_comments = true },
    );

    const result1 = try z.innerHTML(gpa, body_elt1);
    defer gpa.free(result1);

    std.debug.assert(std.mem.eql(u8, expected_noc, result1));

    // -- string normalization
    const cleaned = try z.normalizeHtmlStringWithOptions(
        gpa,
        messy_html,
        .{ .remove_comments = true },
    );
    defer gpa.free(cleaned);
    print("\n\n Normalized sring: {s}\n\n", .{cleaned});
    std.debug.assert(std.mem.eql(u8, cleaned, result1));

    try z.parseString(doc, cleaned);
    const body_elt2 = z.bodyElement(doc).?;
    const result2 = try z.innerHTML(gpa, body_elt2);
    defer gpa.free(result2);

    std.debug.assert(std.mem.eql(u8, result2, result1));
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

    const iterations = 500;
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
            .remove_comments = false,
            .remove_whitespace_text_nodes = true,
        });
        try z.parseString(doc0, normalized);
        try z.parseString(doc0, ""); // reset
        allocator.free(normalized);
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
        // defer allocator.free(normalized);

        try parser1.parseAndAppend(
            body_elt1.?,
            normalized,
            .body,
            .none,
        );
        _ = try z.setInnerHTML(body_elt1.?, ""); // reset
        allocator.free(normalized);
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

    // Test 4: Fair comparison - fresh createDocFromString each iteration + DOMnorm
    timer.reset();
    for (0..iterations) |_| {
        const doc4 = try z.createDocFromString(medium_html);
        defer z.destroyDocument(doc4);
        const body_elt4 = z.bodyElement(doc4);

        try z.normalizeDOMwithOptions(
            allocator,
            body_elt4.?,
            .{
                .skip_comments = true,
            },
        );
    }
    const fresh_doc_DOMnorm = timer.read();

    // Test 5: String normalization with fresh parsing each iteration
    timer.reset();
    // const doc5 = try z.createDocument();
    // defer z.destroyDocument(doc5);
    for (0..iterations) |_| {
        const normalized = try z.normalizeHtmlStringWithOptions(allocator, medium_html, .{
            .remove_comments = true,
            .remove_whitespace_text_nodes = true,
        });
        defer allocator.free(normalized);
        // try z.parseString(doc5, normalized);

        const doc5 = try z.createDocFromString(normalized);
        defer z.destroyDocument(doc5);
    }
    const fresh_normString_fresh_doc = timer.read();

    // test 5b : reuse document for parsing normalized string
    timer.reset();
    const doc5 = try z.createDocument();
    defer z.destroyDocument(doc5);
    for (0..iterations) |_| {
        const normalized = try z.normalizeHtmlStringWithOptions(allocator, medium_html, .{
            .remove_comments = false,
            .remove_whitespace_text_nodes = true,
        });
        defer allocator.free(normalized);
        try z.parseString(doc5, normalized);

        // const doc5 = try z.createDocFromString(normalized);
        // defer z.destroyDocument(doc5);
    }
    const reuse_doc_normString_parse = timer.read();

    // Calculate performance metrics
    const ns_to_ms = @as(f64, @floatFromInt(std.time.ns_per_ms));
    const kb_size = @as(f64, @floatFromInt(medium_html.len)) / 1024.0;
    const iter = @as(f64, @floatFromInt(iterations));

    const html_normString_parse_into_a_doc_ms = @as(f64, @floatFromInt(html_normString_parse_into_a_doc)) / ns_to_ms;
    const html_normString_parser_append_ms = @as(f64, @floatFromInt(html_normString_parser_append)) / ns_to_ms;
    const html_parser_parse_into_new_DOM_norm_DOM_ms = @as(f64, @floatFromInt(html_parser_parse_into_new_DOM_norm_DOM)) / ns_to_ms;
    const fresh_doc_DOMnorm_ms = @as(f64, @floatFromInt(fresh_doc_DOMnorm)) / ns_to_ms;
    const fresh_normString_fresh_doc_ms = @as(f64, @floatFromInt(fresh_normString_fresh_doc)) / ns_to_ms;
    const reuse_doc_normString_parse_ms = @as(f64, @floatFromInt(reuse_doc_normString_parse)) / ns_to_ms;

    print("\n--- Speed Results ---\n", .{});
    print("REUSED DOCS:\n", .{});
    print("1. reused doc:     normString    -> parseString :       {d:.2} ms/op, {d:.1} kB/s\n", .{ html_normString_parse_into_a_doc_ms / iter, kb_size * iter / html_normString_parse_into_a_doc_ms });

    print("2. reused doc:     normString    -> parser.append:      {d:.2} ms/op, {d:.1} kB/s\n", .{ html_normString_parser_append_ms / iter, kb_size * iter / html_normString_parser_append_ms });

    print("3. fresh doc:      parser.parse  -> DOMnorm:            {d:.2} ms/op,  {d:.1} kB/s\n", .{ html_parser_parse_into_new_DOM_norm_DOM_ms / iter, kb_size * iter / html_parser_parse_into_new_DOM_norm_DOM_ms });

    print("\nFRESH DOCS (fair comparison):\n", .{});
    print("4. fresh doc:      createDoc     -> DOMnorm:            {d:.2} ms/op,  {d:.1} kB/s\n", .{ fresh_doc_DOMnorm_ms / iter, kb_size * iter / fresh_doc_DOMnorm_ms });

    print("5. fresh doc:      normString    -> createDoc:          {d:.2} ms/op,  {d:.1} kB/s\n", .{ fresh_normString_fresh_doc_ms / iter, kb_size * iter / fresh_normString_fresh_doc_ms });

    print("5b. reuse doc:  normString  -> parse:                   {d:.2} ms/op,  {d:.1} kB/s\n", .{ reuse_doc_normString_parse_ms / iter, kb_size * iter / reuse_doc_normString_parse_ms });

    // Test 6: setInnerHTML with string normalization on fresh document
    timer.reset();
    for (0..iterations) |_| {
        const doc6 = try z.createDocument();
        defer z.destroyDocument(doc6);
        try z.parseString(doc6, "<div id='target'></div>");

        const target_elt = z.getElementById(z.bodyNode(doc6).?, "target").?;

        const normalized = try z.normalizeHtmlStringWithOptions(allocator, medium_html, .{
            .remove_comments = true,
            .remove_whitespace_text_nodes = true,
        });
        defer allocator.free(normalized);

        _ = try z.setInnerHTML(target_elt, normalized);
    }
    const setInnerHTML_normString_fresh_doc = timer.read();

    // Test 7: setInnerHTML with DOM normalization on fresh document
    timer.reset();
    for (0..iterations) |_| {
        const doc7 = try z.createDocument();
        defer z.destroyDocument(doc7);
        try z.parseString(doc7, "<div id='target'></div>");

        const target_elt = z.getElementById(z.bodyNode(doc7).?, "target").?;
        const new_elt = try z.setInnerHTML(target_elt, medium_html);

        try z.normalizeDOMwithOptions(
            allocator,
            new_elt,
            .{
                .skip_comments = true,
            },
        );
    }
    const setInnerHTML_DOMnorm_fresh_doc = timer.read();

    const setInnerHTML_normString_fresh_doc_ms = @as(f64, @floatFromInt(setInnerHTML_normString_fresh_doc)) / ns_to_ms;
    const setInnerHTML_DOMnorm_fresh_doc_ms = @as(f64, @floatFromInt(setInnerHTML_DOMnorm_fresh_doc)) / ns_to_ms;

    print("\nsetInnerHTML (fresh document):\n", .{});
    print("6. setInnerHTML:   normString    -> fresh doc:          {d:.2} ms/op,  {d:.1} kB/s\n", .{ setInnerHTML_normString_fresh_doc_ms / iter, kb_size * iter / setInnerHTML_normString_fresh_doc_ms });
    print("7. setInnerHTML:   DOMnorm       -> fresh doc:          {d:.2} ms/op,  {d:.1} kB/s\n", .{ setInnerHTML_DOMnorm_fresh_doc_ms / iter, kb_size * iter / setInnerHTML_DOMnorm_fresh_doc_ms });

    // Test 8: Reused document + parseString (clear document each time)
    timer.reset();
    const reused_doc = try z.createDocument();
    defer z.destroyDocument(reused_doc);
    for (0..iterations) |_| {
        try z.parseString(reused_doc, medium_html);
    }
    const reused_doc_parseString = timer.read();

    // Test 9: Parser + parser.parse (new doc each time)
    timer.reset();
    var parser_reused = try z.Parser.init(allocator);
    defer parser_reused.deinit();
    for (0..iterations) |_| {
        const doc9 = try parser_reused.parse(medium_html, .none);
        defer z.destroyDocument(doc9);
    }
    const parser_parse_new_doc = timer.read();

    // Test 10: createDocument + parseString each time
    timer.reset();
    for (0..iterations) |_| {
        const doc10 = try z.createDocument();
        defer z.destroyDocument(doc10);
        try z.parseString(doc10, medium_html);
    }
    const createDoc_parseString = timer.read();

    const reused_doc_parseString_ms = @as(f64, @floatFromInt(reused_doc_parseString)) / ns_to_ms;
    const parser_parse_new_doc_ms = @as(f64, @floatFromInt(parser_parse_new_doc)) / ns_to_ms;
    const createDoc_parseString_ms = @as(f64, @floatFromInt(createDoc_parseString)) / ns_to_ms;

    print("\nPARSING COMPARISON:\n", .{});
    print("8. reused doc:     parseString   (clear each time):     {d:.2} ms/op,  {d:.1} kB/s\n", .{ reused_doc_parseString_ms / iter, kb_size * iter / reused_doc_parseString_ms });
    print("9. parser.parse:   new doc       (each time):          {d:.2} ms/op,  {d:.1} kB/s\n", .{ parser_parse_new_doc_ms / iter, kb_size * iter / parser_parse_new_doc_ms });
    print("10. createDoc:     parseString   (fresh each time):    {d:.2} ms/op,  {d:.1} kB/s\n", .{ createDoc_parseString_ms / iter, kb_size * iter / createDoc_parseString_ms });
}
