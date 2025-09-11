# zexplorer: a `lexbor` in `Zig` project


[![Zig support](https://img.shields.io/badge/Zig-0.15.1-color?logo=zig&color=%23f3ab20)](http://github.com/ndrean/z-html)
[![Scc Code Badge](https://sloc.xyz/github/ndrean/z-html/)](https://github.com/ndrean/z-html)

`zexplorer` is a wrapper of the `C` library [lexbor](https://github.com/lexbor/lexbor), an HTML parser/DOM emulator.

This is useful for web scraping, email sanitization, test engine for integrated tests, SSR post-processing of fragments.

The primitives exposed here stay as close as possible to `JavaScript` semantics.

**Features:**

This project exposes a significant / essential subset of all available `lexbor` functions:

- Direct parsing or  with a parser engine (document or fragment context-aware)
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

## Example: scrap the web and explore a page

```cpp
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
  std.debug.print("\n{s}\n", .{href_value}); // result below

  var css_content: []const u8 = undefined;
  const style_by_css = try css_engine.querySelector(html, "style");

  if (style_by_css) |style| {
      css_content = z.textContent_zc(style);
      print("\n{s}\n", .{css_content}); // see below
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

## Example: scan a page for potential malicious content

The intent is to highlight potential XSS threats. It works by parsing the string into a fragment. When a HTMLElement gets an unknow attribute, its colour is white and the attribute value is highlighted in RED.

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

```cpp
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

```cpp
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

const doc = try parser.parse(body, html, .body, .permissive);
defer z.destroyDocument(doc);
```

<hr>

## Example: Processing streams

You receive chunks and build a document.

```cpp
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
        print("chunk:  {s}\n", .{chunk});
        try streamer.processChunk(chunk);
    }

    for (0..2) |i| {
        const li = try std.fmt.allocPrint(
            allocator,
            "<tr id={}><th >Code: {}</th><td>Name: {}</td></tr>",
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
    try z.prettyPrint(allocator, html_node);
    print("\n", .{});
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
  <img src="https://github.com/ndrean/z-html/blob/main/src/images/html-table.png" width="300" alt="image"/>
  <img src="https://github.com/ndrean/z-html/blob/main/src/images/tree-table.png" width="300" alt="image"/>
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

```cpp
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

```cpp
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

Some results:

```txt
--- Speed Results ---
new doc:           normString    -> parseString :       0.41 ms/op, 1110.7 MB/s
parser, new doc:   normString    -> parser.append:      0.50 ms/op, 1364.2 MB/s
parser:  (new doc: parser.parse  -> DOMnorm:            0.08 ms/op,  218.7 MB/s
```

### DOM-based Normalization

DOM-based normalization works on parsed documents and provides browser-like behavior:

```cpp
const html = 
    \\<div>
    \\  <!-- comment -->
    \\  <p>Text with   spaces</p>
    \\  <pre>  preserve  whitespace  </pre>
    \\  
    \\  <script>
    \\    console.log('preserve script content');
    \\  </script>
    \\</div>
;

const doc = try z.createDocFromString(html);
defer z.destroyDocument(doc);
const body = z.bodyElement(doc).?;

// Standard browser-like normalization (removes collapsible whitespace)
try z.normalizeDOM(allocator, body);

// Or with options to remove comments
try z.normalizeDOMwithOptions(allocator, body, .{ .skip_comments = true });

// For clean terminal output (aggressive - removes ALL whitespace-only nodes)
try z.normalizeDOMForDisplay(allocator, body);

const result = try z.innerHTML(allocator, body);
defer allocator.free(result);
// Result: clean HTML with normalized whitespace
```

### String-based Normalization

For faster processing when you don't need full DOM parsing:

```cpp
const messy_html = 
    \\<div>
    \\  <!-- comment -->
    \\  
    \\  <p>Content</p>
    \\  
    \\  <pre>  preserve  this  </pre>
    \\  
    \\</div>
;

// Basic normalization (removes whitespace-only text nodes)
const normalized = try z.normalizeHtmlString(allocator, messy_html);
defer allocator.free(normalized);

// With options for comment handling
const clean = try z.normalizeHtmlStringWithOptions(allocator, messy_html, .{
    .remove_comments = true,
    .remove_whitespace_text_nodes = true,
});
defer allocator.free(clean);
```

You can also "clean" text node content:

```cpp
// Text normalization (collapses whitespace)
const text = "  Hello   world!  \n\n  ";
const normalized_text = try z.normalizeText(allocator, text);
defer allocator.free(normalized_text);
// Result: "Hello world!"
```

<hr>

## Other examples

You have several methods available.

1. The `parseString` creates a `<head>` and a `<body>` element and replaces BODY innerContent with the nodes created by the parsing of the given string.

```cpp
const z = @import("zexplorer");

const doc: *HTMLDocument = try z.createDocument();
defer z.destroyDocument(doc);
try z.parseString(doc, "<div></div>");
const body: *DomNode = z.bodyNode(doc).?;

// you can create programmatically and append elemments to a node
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

2. You have a shortcut to directly create and parse an HTML string with `createDocFromString`.

```cpp
const doc: *HTMLDocument = try z.createDocFromString("<div></div><p></p>");
defer z.destroyDocument(doc);
```

3. You have the parser engine as seen before

```cpp
var parser = try z.Parser.init(allocator);
defer parser.deinit();
const doc = try parser.parse("<div><p></p></div>");
defer z.destroyDocument(doc);
```

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
zig build run -Doptimize=Debug
# or
zig build run -Doptimize=ReleaseFast
```

- library:

```sh
zig build --release=fast
```

- fetch to include source code:

```sh
# to test
```

### Notes on search in `lexbor` source/examples

<https://github.com/lexbor/lexbor/tree/master/examples/lexbor>

Once you build `lexbor`, you have the static object located at _/lexbor_src_2.5.0/build/liblexbor_static.a_.

To check which primitives are exported, you can use:

```sh
nm lexbor_src_2.5.0/build/liblexbor_static.a | grep -i "serialize"
```

Directly in the source code:

```sh
find lexbor_src_2.5.0/source -name "*.h" | xargs grep -l "lxb_selectors_opt_set_noi"
```
