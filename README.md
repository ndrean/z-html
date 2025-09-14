# zexplorer: a `lexbor` in `Zig` project

[![Zig support](https://img.shields.io/badge/Zig-0.15.1-color?logo=zig&color=%23f3ab20)](http://github.com/ndrean/z-html)
[![Scc Code Badge](https://sloc.xyz/github/ndrean/z-html/)](https://github.com/ndrean/z-html)

`zexplorer` is a wrapper of the `C` library [lexbor](https://github.com/lexbor/lexbor), an HTML parser/DOM emulator.

This is useful for web scraping, email sanitization, test engine for integrated tests, SSR post-processing of fragments.

The primitives exposed here stay as close as possible to `JavaScript` semantics.

**Features:**

This project exposes a significant / essential subset of all available `lexbor` functions:

- Direct parsing or parsing with a parser engine (document or fragment context-aware)
- streaming and chunk processing
- Serialization
- Sanitization
- CSS selectors search with cached CSS selectors parsing
- Support of `<template>` elements.
- Attribute search
- DOM manipulation
- DOM / HTML-string normalization with options (remove comments, whitespace, empty nodes)
- Pretty printing

## `lexbor` DOM memory management: Document Ownership and zero-copy functions

In `lexbor`, nodes belong to documents, and the document acts as the memory manager.

When a node is attached to a document (either directly or through a fragment that gets appended), the document owns it.

Every time you create a document, you need to call `destroyDocument()`: it automatically destroys ALL nodes that belong to it.

When a node is NOT attached to any document, you must manually destroy it.

Some functions borrow memory from `lexbor` for zero-copy operations: their result is consumed immediately.

We opted for the following convention: add `_zc` (for _zero_copy_) to the **non allocated** version of a function. For example, you can get the qualifiedName of an HTMLElement with the allocated version `qualifiedName(allocator, node)` or by mapping to `lexbor` memory with `qualifiedName_zc(node)`. The non-allocated must be consumed immediately whilst the allocated result can outlive the calling function.

<hr>

## Install

[![Zig support](https://img.shields.io/badge/Zig-0.15.1-color?logo=zig&color=%23f3ab20)](http://github.com/ndrean/z-html)

```sh
zig fetch --save https://github.com/ndrean/zexplorer/archive/main.tar.gz
```

In your _build.zig_:

```zig
const zexplorer = b.dependency("zexplorer", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zexplorer", zexplorer.module("zexplorer"));
```


## Example: Create document and parse

You have two methods available.

1. The `parseString()` creates a `<head>` and a `<body>` element and replaces BODY innerContent with the nodes created by the parsing of the given string.

```zig
const z = @import("zexplorer");

const doc: *HTMLDocument = try z.createDocument();
defer z.destroyDocument(doc);

try z.parseString(doc, "<div></div>");
const body: *DomNode = z.bodyNode(doc).?;

// you can create programmatically and append elements to a node
const p: *HTMLElement = try z.createElement(doc, "p");
z.appendChild(body, z.elementToNode(p));
```

Your document now contains this HTML:

```html
<head></head>
<body>
  <div></div>
  <p></p>
</body>
```

You have a shortcut to directly create and parse an HTML string with `createDocFromString()`.

```zig
const doc: *HTMLDocument = try z.createDocFromString("<div></div><p></p>");
defer z.destroyDocument(doc);
```

2. You have the _parser engine_:

```zig
var parser = try z.Parser.init(allocator);
defer parser.deinit();
const doc = try parser.parse("<div><p></p></div>");
defer z.destroyDocument(doc);
```


<hr>

## Example: scrap the web and explore a page

```zig
test "scrap example.com" {
  const allocator = std.testing.allocator;

  const page = try z.get(allocator, "https://example.com");
  defer allocator.free(page);

  const doc = try z.createDocFromString(page);
  defer z.destroyDocument(doc);

  const html = z.documentRoot(doc).?;
  try z.prettyPrint(allocator, html); // see image below

  var css_engine = try z.createCssEngine(allocator);
  defer css_engine.deinit();

  const a_link = try css_engine.querySelector(html, "a[href]");

  const href_value = z.getAttribute_zc(z.nodeToElement(a_link.?).?, "href").?;
  std.debug.z.print("\n{s}\n", .{href_value}); // result below

  var css_content: []const u8 = undefined;
  const style_by_css = try css_engine.querySelector(html, "style");

  if (style_by_css) |style| {
      css_content = z.textContent_zc(style);
      z.print("\n{s}\n", .{css_content}); // see below
  }

  // alternative search by DOM traverse
  const style_by_walker = z.getElementByTag(html, .style);
  if (style_by_walker) |style| {
      const css_content_walker = z.textContent_zc(z.elementToNode(style));
      std.debug.assert(std.mem.eql(u8, css_content, css_content_walker));
  }
}
```

<br>

You will get a colourful print in your terminal, where the attributes, values, html elements get coloured.

<details><summary> HTML content of example.com</summary>

<img width="965" height="739" alt="Screenshot 2025-09-09 at 13 54 12" src="https://github.com/user-attachments/assets/ff770cdb-95ab-468b-aa5e-5bbc30cf6649" />

</details>
<br>

You will also see the value of the `href` attribute of a the first `<a>` link:

```txt
 https://www.iana.org/domains/example
 ```

<details>
<summary>You will then see the text content of the STYLE element (no CSS parsing):</summary>

```css
body {
    background-color: #f0f0f2;
    margin: 0;
    padding: 0;
    font-family: -apple-system, system-ui, BlinkMacSystemFont, "Segoe UI", "Open Sans", "Helvetica Neue", Helvetica, Arial, sans-serif;
    
}
div {
    width: 600px;
    margin: 5em auto;
    padding: 2em;
    background-color: #fdfdff;
    border-radius: 0.5em;
    box-shadow: 2px 3px 7px 2px rgba(0,0,0,0.02);
}
a:link, a:visited {
    color: #38488f;
    text-decoration: none;
}
@media (max-width: 700px) {
    div {
        margin: 0 auto;
        width: auto;
    }
}
```

</details>

<hr>

## HTMX Server-Side Rendering with Template Interpolation

This example demonstrates high-performance server-side rendering with `HTMX` integration and template interpolation, achieving 280K+ operations per second.

The rendering is _stateless_. The state is server-side driven, maintained in a database.

There is no need for a templating langugage: using multiline strings and loops or conditionals is largely enough to build HTML strings, and faster.

<details><summary>Fake HTML page</summary>

```zig
const blog_html =
    \\<!DOCTYPE html>
    \\<html lang="en">
    \\  <head>
    \\    <meta charset="UTF-8"/>
    \\    <title>HTMX Blog - High Performance Server Rendering</title>
    \\    <meta name="viewport" content="width=device-width, initial-scale=1"/>
    \\    <script src="https://unpkg.com/htmx.org@1.9.6"></script>
    \\    <style>
    \\      .blog-post { margin: 2rem 0; padding: 1.5rem; border: 1px solid #ddd; 
}
    \\      .post-title { color: #333; font-size: 1.5rem; cursor: pointer; }
    \\      .post-title:hover { color: #0066cc; }
    \\      .post-meta { color: #666; font-size: 0.9rem; margin: 0.5rem 0; }
    \\      .post-actions { margin-top: 1rem; }
    \\      .post-actions button { margin-right: 0.5rem; padding: 0.25rem 0.5rem; 
}
    \\    </style>
    \\  </head>
    \\  <body>
    \\    <main class="content">
    \\      <article class="blog-post" data-post-id="{post_id}">
    \\        <header class="post-header">
    \\          <h2 class="post-title" hx-get="/posts/{post_id}/edit" 
hx-target="#edit-modal">
    \\            {title_template}
    \\          </h2>
    \\          <div class="post-meta">
    \\            <span class="author">{author_name}</span>
    \\            <time datetime="2024-01-01">{publish_date}</time>
    \\            <span class="views" hx-get="/posts/{post_id}/views"
hx-trigger="revealed">
    \\              {view_count} views
    \\            </span>
    \\          </div>
    \\        </header>
    \\
    \\        <div class="post-content">
    \\          <p>Welcome {user_name}! This demonstrates high-performance HTMX
server-side rendering with Zig.</p>
    \\          <p>Current user: <strong>{user_name}</strong>, Post ID:
<strong>{post_id}</strong></p>
    \\        </div>
    \\
    \\        <footer class="post-actions">
    \\          <button hx-post="/posts/{post_id}/like" hx-swap="innerHTML">
    \\            ❤️ {like_count}
    \\          </button>
    \\          <button hx-get="/posts/{post_id}/comments"
hx-target="#comments-{post_id}">
    \\            💬 {comment_count}
    \\          </button>
    \\          <button hx-delete="/posts/{post_id}" hx-confirm="Delete this
post?" hx-target="closest .blog-post">
    \\            🗑️ Delete
    \\          </button>
    \\        </footer>
    \\      </article>
    \\    </main>
    \\  </body>
    \\</html>
;
```

</details>
<br>

The code below parses the whole HTML delivered when the client connects, and starts the parser and css engine.

When the webserver receives an HTMX request, the server returns a serialized updated HTML string.

```zig
const std = @import("std");
const z = @import("zexplorer");

pub fn main() !void {
    const gpa = std.heap.c_allocator;

    // One-time setup (server startup)
    const doc = try z.createDocFromString(blog_html);
    defer z.destroyDocument(doc);

    var css_engine = try z.createCssEngine(allocator);
    defer css_engine.deinit();

    var parser = try z.Parser.init(allocator);
    defer parser.deinit();

    // 1. start the webserver: not implemented
    // 2. Simulate handling requests received by the webserver
    try requestHandler(gpa, doc, &css_engine, &parser);
}

// an example: tailored for each request
fn requestHandler(
    allocator: std.mem.Allocator,
    doc: *z.HTMLDocument,
    css_engine: *z.CssSelectorEngine,
    parser: *z.Parser,
) !void {

    // 1. Target elements with CSS selectors
    const title_elements = try css_engine.querySelectorAll(allocator, doc, ".post-title");
    defer allocator.free(title_elements);

    if (title_elements.len > 0) {
        // 2. Clone element for modification (original DOM stays pristine)
        const cloned_title = z.cloneNode(z.elementToNode(title_elements[0])).?;
        defer z.destroyNode(cloned_title);

        // 3. Template interpolation with curly brackets after reading the db or kv store
        const template = "{user_name}'s Blog Post #{post_id}: {title}";
        var content = try interpolateTemplate(allocator, template, "user_name",
"Mr Magoo");
        defer allocator.free(content);

        const post_id_str = try std.fmt.allocPrint(allocator, "{}", .{42});
        defer allocator.free(post_id_str);

        const temp = try interpolateTemplate(allocator, content, "post_id",
post_id_str);
        defer allocator.free(temp);

        const final_content = try interpolateTemplate(allocator, temp, "title",
"HTMX Performance");
        defer allocator.free(final_content);

        // 4. Update element content and HTMX attributes
        _ = try z.setInnerHTML(z.nodeToElement(cloned_title).?, final_content);

        // Interpolate HTMX attributes dynamically
        const hx_get_value = try interpolateTemplate(allocator,
"/posts/{post_id}/edit", "post_id", post_id_str);
        defer allocator.free(hx_get_value);
        _ = z.setAttribute(z.nodeToElement(cloned_title).?, "hx-get",
hx_get_value);

        // 5. Serialize modified element (ready to send to client)
        const response_html = try z.outerHTML(allocator,
z.nodeToElement(cloned_title).?);
        defer allocator.free(response_html);

        // POST back to the client
        std.debug.print("HTMX Response: {s}\n", .{response_html});
        // Output: <h2 class="post-title" hx-get="/posts/42/edit">M. Magoo's Blog
Post #42: HTMX Performance</h2>
    }
}

// Template interpolation helper - replaces {key} with values
fn interpolateTemplate(
    allocator: std.mem.Allocator, 
    template: []const u8, 
    key: []const u8, 
    value: []const u8) ![]u8 {
    const placeholder = try std.fmt.allocPrint(allocator, "{{{s}}}", .{key});
    defer allocator.free(placeholder);

    // Count occurrences for efficient pre-allocation
    var count: usize = 0;
    var pos: usize = 0;
    while (std.mem.indexOf(u8, template[pos..], placeholder)) |found| {
        count += 1;
        pos += found + placeholder.len;
    }

    if (count == 0) return try allocator.dupe(u8, template);

    // Pre-allocate and replace all occurrences
    const new_size = template.len + (value.len * count) - (placeholder.len *
count);
    var result = try std.ArrayList(u8).initCapacity(allocator, new_size);

    pos = 0;
    while (std.mem.indexOf(u8, template[pos..], placeholder)) |found| {
        const actual_pos = pos + found;
        try result.appendSlice(allocator, template[pos..actual_pos]);
        try result.appendSlice(allocator, value);
        pos = actual_pos + placeholder.len;
    }
    try result.appendSlice(allocator, template[pos..]);

    return result.toOwnedSlice(allocator);
}
```

<hr>

## Example: scan a page for potential malicious content

The intent is to highlight potential XSS threats. It works by parsing the string into a fragment. When a HTMLElement gets an unknown attribute, its colour is white and the attribute value is highlighted in RED.

Let's parse and print the following HTML string:

```html
const html_string = 
    <div>
    <!-- a comment -->
    <button disabled hidden onclick="alert('XSS')" phx-click="increment" data-invalid="bad" scope="invalid">Dangerous button</button>
    <img src="javascript:alert('XSS')" alt="not safe" onerror="alert('hack')" loading="unknown">
    <a href="javascript:alert('XSS')" target="_self" role="invalid">Dangerous link</a>
    <p id="valid" class="good" aria-label="ok" style="bad" onload="bad()">Mixed attributes</p>
    <custom-elt><p>Hi there</p></custom-elt>
    <template><span>Reuse me</span></template>
    </div>
```

You parse this HTML string:

```zig
const doc = try z.createDocFromString(html_string);
defer z.destroyDocument(doc);

const body = z.bodyNode(doc).?;
try z.prettyPrint(allocator, body);
```

You get the following output in your terminal.

<br>
<img width="931" height="499" alt="Screenshot 2025-09-09 at 16 08 19" src="https://github.com/user-attachments/assets/45cfea8b-73d9-401e-8c23-457e0a6f92e1" />
<br>

We can then run a _sanitization_ process against the DOM, so you get a context where the attributes are whitelisted.

```zig
try z.sanitizeNode(allocator, body, .permissive);
try z.prettyPrint(allocator, body);
```

The result is shown below.

<br>
<img width="900" height="500" alt="Screenshot 2025-09-09 at 16 11 30" src="https://github.com/user-attachments/assets/ff7fa678-328b-495a-8a81-2ff465141be3" />

<br>
<hr>

## Example: using the parser with sanitization option

You can create a sanitized document with the parser (a ready-to-use parsing engine).

```c
var parser = try z.Parser.init(testing.allocator);
defer parser.deinit();

const doc = try parser.parse(html, .none);
defer z.destroyDocument(doc);
```

<hr>

## Example: Processing streams

You receive chunks and build a document.

```zig
const z = @import("zexplorer");
const print = std.debug.print;

fn demoStreamParser(allocator: std.mem.Allocator) !void {

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
        z.print("chunk:  {s}\n", .{chunk});
        try streamer.processChunk(chunk);
    }

    for (0..2) |i| {
        const li = try std.fmt.allocPrint(
            allocator,
            "<tr id={}><th >Code: {}</th><td>Name: {}</td></tr>",
            .{ i, i, i },
        );
        defer allocator.free(li);
        z.print("chunk:  {s}\n", .{li});

        try streamer.processChunk(li);
    }
    const end_chunk = "</tbody></table></body></html>";
    z.print("chunk:  {s}\n", .{end_chunk});
    try streamer.processChunk(end_chunk);
    try streamer.endParsing();

    const html_doc = streamer.getDocument();
    defer z.destroyDocument(html_doc);
    const html_node = z.documentRoot(html_doc).?;

    z.print("\n\n", .{});
    try z.prettyPrint(allocator, html_node);
    z.print("\n", .{});
    try z.printDocStruct(html_doc);
}
```

You get the output:

```txt
chunk:  <!DOCTYPE html><html><head><title>Large
chunk:   Document</title></head><body>
chunk:  <table id="producttable">
chunk:  <caption>Company data</caption><thead>
chunk:  <tr><th scope="col">Items</th><th>
chunk:  Code</th><th>Product_Name</th>
chunk:  </tr></thead><tbody>
chunk:  <tr id=0><th >Code: 0</th><td>Name: 0</td></tr>
chunk:  <tr id=1><th >Code: 1</th><td>Name: 1</td></tr>
chunk:  </tbody></table></body></html>;
```

<p align="center">
  <img src="https://github.com/ndrean/z-html/blob/main/images/html-table.png" width="300" alt="image"/>
  <img src="https://github.com/ndrean/z-html/blob/main/images/tree-table.png" width="300" alt="image"/>
</p>

<hr>

## Example: Search examples and attributes and classList DOMTOkenList like

We have two types of search available, each with different behaviors and use cases:

```html
const html = 
    <div class="main-container">
        <h1 class="title main">Main Title</h1>
        <section class="content">
        <p class="text main-text">First paragraph</p>
        <div class="box main-box">Box content</div>
        <article class="post main-post">Article content</article>
        </section>
        <aside class="sidebar">
            <h2 class="subtitle">Sidebar Title</h2>
            <p class="text sidebar-text">Sidebar paragraph</p>
            <div class="widget">Widget content</div>
        </aside>
        <footer class="main-footer" aria-label="foot">
        <p class="copyright">© 2024</p>
        </footer>
    </div>
```

A CSS Selector search and some walker search and attributes:

```zig
const doc = try z.createDocFromString(html);
defer z.destroyDocument(doc);
const body = z.bodyNode(doc).?;

var css_engine = try z.createCssEngine(allocator);
defer css_engine.deinit();

const divs = try css_engine.querySelectorAll(body, "div");
std.debug.assert(divs.len == 3);

const p1 = try css_engine.querySelector(body, "p.text");
const p_elt = z.nodeToElement(p1.?).?;
const cl_p1 = z.classList_zc(p_elt);

std.debug.assert(std.mem.eql(u8, "text main-text", cl_p1));

const p2 = z.getElementByClass(body, "text").?;
const cl_p2 = z.classList_zc(p2);
std.debug.assert(std.mem.eql(u8, cl_p1, cl_p2));

const footer = z.getElementByAttribute(body, "aria-label").?;
const aria_value = z.getAttribute_zc(footer, "aria-label").?;
std.debug.assert(std.mem.eql(u8, "foot", aria_value));
```

Working the `classList` like a DOMTokenList

```zig
var footer_token_list = try z.ClassList.init(allocator, footer);
defer footer_token_list.deinit();

try footer_token_list.add("new-footer");
std.debug.assert(footer_token_list.contains("new-footer"));

_ = try footer_token_list.toggle("new-footer");
std.debug.assert(!footer_token_list.contains("new-footer"));
```

<hr>

## Example: HTML Normalization

The library provides both DOM-based and string-based HTML normalization to clean up whitespace and comments.

This helps to visualize a clean output in the terminal and also minimize what is potentially sent back over the wire (e.g. when using `HTMX` frontend).

DOM-based normalization works on parsed documents and provides browser-like behavior. It is the best choice.

We take the example below:

```zig
const doc = try z.createDocument();
defer z.destroyDocument(doc);

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
```

```zig
const expected = "<div><!-- comment --><p>Content</p><pre>  preserve  this  </pre></div>";
```

Dom-base normalization:

```zig
try z.parseString(doc, messy_html);

const body_elt1 = z.bodyElement(doc).?;
try z.normalizeDOM(gpa, body_elt1);

const result1 = try z.innerHTML(gpa, body_elt1);
defer gpa.free(result1);

std.debug.assert(std.mem.eql(u8, expected, result1));
```

String-based "pre-normalization":

```zig
const cleaned = try z.normalizeHtmlStringWithOptions(
    gpa,
    messy_html,
    .{ .remove_comments = false },
);
defer gpa.free(cleaned);

std.debug.assert(std.mem.eql(u8, cleaned, result1));

try z.parseString(doc, cleaned);
const body_elt2 = z.bodyElement(doc).?;
const result2 = try z.innerHTML(gpa, body_elt2);
defer gpa.free(result2);

std.debug.assert(std.mem.eql(u8, result2, result1));
```

Some results shown in the _ main.zig_  file of parsing a 38kB HTML string (average 500 iterations using `std.heap.c_allocator` and `-release=fast`).

To parse a 38kB string, it takes 50µs on average.

The overhead of normalization:

```txt
--- Speed Results ---
createDoc -> parseString:                        0.05 ms/op, 830 kB/s
new parser -> new doc = parser.parse -> DOMnorm:     0.06 ms/op, 660 kB/s
createDoc -> normString -> parseString:   0.08 ms/op, 470 kB/s
```

<hr>


## Other examples in _main.zig_

The file _main.zig_ shows more use cases with parsing and serialization as well as the tests  (`setInnerHTML`, `setInnerSafeHTML`, `insertAdjacentElement` or `insertAdjacentHTML`...)

<hr>

## Building the lib

- `lexbor` is built with static linking

```sh
make -f Makefile.lexbor
```

- tests: The _build.zig_ file runs all the tests from _root.zig_. It imports all the submodules and runs the tests.

```sh
zig build test --summary all
```

- run the demo in the __main.zig_ demo with:

```sh
zig build run -Doptimize=ReleaseFast
```

- Use the library: check _LIBRARY.md_.



### Notes on search in `lexbor` source/examples

<https://github.com/lexbor/lexbor/tree/master/examples/lexbor>

Once you build `lexbor`, you have the static object located at _/lexbor_src_master/build/liblexbor_static.a_.

To check which primitives are exported, you can use:

```sh
nm lexbor_src_master/build/liblexbor_static.a | grep -i "serialize"
```

Directly in the source code:

```sh
find lexbor_src_master/source -name "*.h" | xargs grep -l "lxb_selectors_opt_set_noi"
```
