# z-html: a `lexbor` in `Zig` project

> [!WARNING]
> Work in progress

[![Zig support](https://img.shields.io/badge/Zig-0.15.1-color?logo=zig&color=%23f3ab20)](http://github.com/ndrean/z-html)
[![Scc Code Badge](https://sloc.xyz/github/ndrean/z-html/)](https://github.com/ndrean/z-html)

`zhtml` is a wrapper of the `C` library [lexbor](https://github.com/lexbor/lexbor), an HTML parser/DOM emulator.

This is useful for web scraping, email sanitization, test engine for integrated tests, SSR post-processing of fragments.

The primitives exposed here stay as close as possible to `JavaScript` semantics.

**Features:**

This project exposes a significant / essential subset of all available `lexbor` functions:

- Parsing with a parser engine
  - document
  - fragment context-aware parsing
- streaming and chunk processing
- Serialization
- Sanitization
- CSS selectors search with cached CSS selectors parsing
- Support of `<template>` elements.
- Attribute search
- Collections and _exact string matching_:
- DOM manipulation
- DOM normalization with options (remove comments, whitespace, empty nodes)
- Pretty printing

## `lexbor` DOM memory management: Document Ownership and zero-copy functions

In `lexbor`, nodes belong to documents, and the document acts as the memory manager.

When a node is attached to a document (either directly or through a fragment that gets appended), the document owns it.

Every time you create a document, you need to call `destroyDocument()`: it automatically destroys ALL nodes that belong to it.

When a node is NOT attached to any document, you must manually destroy it.

Some functions borrow memory from `lexbor` for zero-copy operations: their result is consumed immediately.

We opted for the following convention: add `_zc` (for _zero_copy_) to the **non allocated** version of a function. For example, you can get the qualifiedName of an HTMLElement with the allocated version `qualifiedName(allocator, node)` or by mapping to `lexbor` memory with `qualifiedName_zc(node)`. The non-allocated must be consumed immediately whilst the allocated result can outlive the calling function.

## Examples

### Building a document & Parsing

You have several methods available.

The `parseString` creates a `<head>` and a `<body>` element and replaces BODY innerContent with the nodes created by the parsing of the given string.

```cpp
const z = @import("zhtml");

const doc: *HTMLDocument = try z.createDocument();
defer z.destroyDocument(doc);
try z.parseString(doc, "<div></div>");

const body: *DomNode = z.bodyNode(doc).?;
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

You have a shortcut to directly create and parse an HTML string with `createDocFromString`.

```cpp
const doc: *HTMLDocument = try z.createDocFromString("<div></div><p></p>");
defer z.destroyDocument(doc);

```

#### Processing streams

You receive chunks and build a document.

```c
const z = @import("zhtml");
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
    try z.prettyPrint(html_node);
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
  <img src="https://github.com/ndrean/z-html/blob/main/src/images/html-table.png" width="300"/>
  <img src="https://github.com/ndrean/z-html/blob/main/src/images/tree-table.png" width="300"/>
</p>

#### Building fragments

You can use the "parser engine" with `insertFragment`.

```c
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

    try z.prettyPrint(body);
}
```

<p align="center"><img src="https://github.com/ndrean/z-html/blob/main/src/images/parse-engine.png" width="300">
</p>

You can use `setInnerHTML`:

```c
test "setInnerHTML" {
  const doc = try z.createDocFromString("<div id=\"target\"></div>");
    defer z.destroyDocument(doc);

    const body = z.bodyNode(doc).?;
    const div = z.getElementById(body, "target").?;

    const new_div = try z.setInnerHTML(div, "<p class=\"new-content\">New Content</p>");

    try z.prettyPrint(new_div);
}
```

<p align="center" width="300">
  <img src="https://github.com/ndrean/z-html/blob/main/src/images/setinnerhtml.png">
</p>

### Security and parsing

#### Basic sanitation

The `parseString` and `setInnerHTML` provide some basic HTML escaping.

Suppose you have the following malicious HTML string:

```html
<script>alert('XSS')</script>
<img src=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\">
<p id=\"1\" phx-click=\"increment\" onclick=\"alert('XSS')\">Click me</p>
<a href=\"http://example.org/results?search=<img src=x onerror=alert('hello')>\">URL Escaped</a>
```

When you use `setInnerHTML` or `parseString`, you get this first barrier with escaped code:

```html
<script>alert('XSS')</script>
<img src=\"data:text/html,&lt;script&gt;alert('XSS')&lt;/script&gt;\" alt=\"escaped\">
<p id=\"1\" phx-click=\"increment\" onclick="alert('XSS')">Click me</p>
<a href=\"http://example.org/results?search=&lt;img src=x onerror=alert('hello')&gt;\">URL Escaped</a>
```

#### Enhanced sanitation

You can go one step further with nuanced parsing that comes in different flavours:  `setInnerSafeHTML`, `setInnerSafeHTMLStrict`, `setInnerSafeHTMLPermissive`.

Let's take a bigger HTML with `<svg>`, custom-elements with XSS injections coming mostly from `scr` and `href` attribute values.

```html
<div style="background: url(javascript:alert('css'))">
  <button disabled hidden onclick=\"alert('XSS')\" phx-click=\"increment\">Potentially dangerous</button>
  <!-- a malicious comment -->
  <div data-time=\"{@current}\"> The current value is: {@counter} </div>
  <a href=\"http://example.org/results?search=<img src=x onerror=alert('hello')>\">URL Escaped</a>
  <a href=\"javascript:alert('XSS')\">Dangerous, not escaped</a>
  <img src=\"javascript:alert('XSS')\" alt=\"not escaped\">
  <img src="https://example.com/image.jpg" alt="Safe image" onerror="alert('img')">
  <iframe src=\"javascript:alert('XSS')\" alt=\"not escaped\"></iframe>
  <a href=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\">Safe escaped</a>
  <a href="https://example.com" class="link">Good link</a>
  <img src=\"data:text/html,<script>alert('XSS')</script>\" alt=\"escaped\">
  <iframe src=\"data:text/html,<script>alert('XSS')</script>\" >Escaped</iframe>
  <iframe sandbox src="https://example.com" title"test iframe">Safe iframe</iframe>
  <img src=\"data:image/svg+xml,<svg onload=alert('XSS')\" alt=\"escaped\"></svg>\">
  <img src=\"data:image/svg+xml;base64,PHN2ZyBvbmxvYWQ9YWxlcnQoJ1hTUycpPjwvc3ZnPg==\" alt=\"potential dangerous b64\">
  <a href=\"data:text/html;base64,PHNjcmlwdD5hbGVydCgnWFNTJyk8L3NjcmlwdD4=\">Potential dangerous b64</a>
  <img src=\"data:text/html;base64,PHNjcmlwdD5hbGVydCgnWFNTJyk8L3NjcmlwdD4=\" alt=\"potential dangerous b64\">
  <a href=\"file:///etc/passwd\">Dangerous Local file access</a>
  <img src=\"file:///etc/passwd\" alt=\"dangerous local file access\">
  <p>Hello<i>there</i>, all<strong>good?</strong></p>
  <p>Visit this link: <a href=\"https://example.com\">example.com</a></p>
  <svg viewBox=\"0 0 100 100\" onclick=\"alert('svg-xss')\">
    <circle cx=\"50\" cy=\"50\" r=\"40\" fill=\"blue\"/>
    <script>alert('svg-script')</script>
    <foreignObject width=\"100\" height=\"100\">
      <div xmlns=\"http://www.w3.org/1999/xhtml\">Evil content</div>
    </foreignObject>
    <animate attributeName=\"opacity\" values=\"0;1\" dur=\"2s\" onbegin=\"alert('animate')\"/>
    <path d=\"M10 10 L90 90\" stroke=\"red\"/>
    <text x=\"50\" y=\"50\" href=\"javascript:alert('text')\">SVG Text</text>
  </svg>
  <phoenix-component phx-click=\"increment\" :if=\"show_component\" onclick=\"alert('custom')\">Phoenix LiveView Component</phoenix-component>
  <my-button @click=\"handleClick\" :disabled=\"isDisabled\" class=\"btn\">Custom Button</my-button>
  <vue-component v-if=\"showProfile\" data-user-id=\"123\">Vue Component</vue-component>
  <p> The <code>push()</code> method adds one or more elements to the end of an array<p/>
</div>
<link href=\"/shared-assets/misc/link-element-example.css\" rel=\"stylesheet\">
<script>console.log(\"hi\");</script>
<template><li id=\"{}\">Item-"\{}\"</li></li></template>
```

When you use `setInnerSafeHTML`, you remove the main source of XSS injection, like comments, `on`-listeners, unknown 

```html
<img alt="escaped">
<p id="1" phx-click="increment">Click me</p>
<a href="http://example.org/results?search=&lt;img src=x onerror=alert('hello')&gt;">URL Escaped</a>
```




### Serialize

You can also use `insertAdjacentHTML` to insert HTML fragments.. To serialize the DOM, you can use `innerHTML` or `outerHTML`.

```c
test "insertAdjacentHTML and serialize" {
  const allocator = std.testing.allocator;
  const doc = try z.createDocFromString(
    \\<div id="container">
    \\  <p id="target">Target</p>
    \\</div>
    ;
  );

  defer z.destroyDocument(doc);

  const body = z.bodyNode(doc).?;
  const target = z.getElementById(body, "target").?;

  try z.insertAdjacentHTML(
        allocator,
        target,
        .beforeend,
        "<span class=\"before end\"></span>",
        false,
  );

  try z.insertAdjacentHTML(
        allocator,
        target,
        .afterend,
        "<span class=\"after end\">After End</span>",
        false,
  );

  try z.insertAdjacentHTML(
        allocator,
        target,
        .afterbegin,
        "<span class=\"after begin\"></span>",
        false,
  );

  try z.insertAdjacentHTML(
        allocator,
        target,
        .beforebegin,
        "<span class=\"before begin\"></span>",
        false,
  );

  // serialize
  const html = try z.outerHTML(allocator, z.nodeToElement(body).?);
  defer allocator.free(html);


  // Normalize whitespace for easy comparison
  const clean_html = try z.normalizeText(allocator, html, .{});
  defer allocator.free(clean_html);

  const expected = "<body><div id=\"container\"><span class=\"before begin\"></span><p id=\"target\"><span class=\"after begin\"></span>Target<span class=\"before end\"></span></p><span class=\"after end\">After End</span></div></body>";

  std.debug.assert(std.mem.eql(u8, expected, clean_html) == true);

  try z.prettyPrint(z.elementToNode(body));
  print("{s}\n", .{clean_html});
}
```

<p align="center"><img src="https://github.com/ndrean/z-html/blob/main/src/images/insertadjacenthtml-all-positions.png" width="300"></p>

```txt
<body>
  <div id="container">
    <span class="before begin"></span>
    <p id="target">
      <span class="after begin"></span>Target<span class="before end"></span></p>
    <span class="after end">After End</span>
  </div>
</body>
```

### Pretty print & DOM structure utilities

From the HTML string:

```html
<body>
  <div>
    <button phx-click="increment">Click me</button>
    <p>Hello<i>there</i>, all <strong>good?</strong></p>
    <p>Visit this link: <a href="https://example.com">example.com</a></p> 
  </div>
</body>
```

You can output a nice colourful log with `prettyPrint`.

<img width="305" height="395" alt="Screenshot 2025-08-26 at 19 48 34" src="https://github.com/user-attachments/assets/4081b736-0015-4a8e-997f-a886912c0e7b" />

We introduced a sanitization tool

### CSS selectors and attributes

```cpp
  // continuation
  var engine = try z.CssSelectorEngine.init(allocator);
  defer engine.deinit();

  // Find the second li element using nth-child
  const second_li = try engine.querySelector(
      body_node,
      "ul > li:nth-child(2)",
  );
  if (second_li) |result| {
    const attribute = try z.getAttribute(
        allocator,
        z.nodeToElement(result).?,
        "data-id",
    );
    if (attribute) |attr| {
      defer allocator.free(attr);
      try testing.expectEqualStrings(attr, "2");
    }
  }
}
```

## Search examples

We have three types of search available, each with different behaviors and use cases:

### 1. Collection-based Search (Modern API)

```zig
// Search-on-demand collections (browser-like behavior)
var collection = try z.createCollectionByClassName(doc, "bold");
defer collection.deinit();
print("Found {} elements\n", .{collection.length()});
```

### 2. CSS Selector Search

```zig  
// Token-based, case-insensitive, most flexible
const css_results = try z.querySelectorAll(allocator, doc, ".bold");
defer allocator.free(css_results);
print("Found {} elements\n", .{css_results.len});
```

### 3. Attribute-based Search

```zig
// Manual traversal with hasClass checking  
var current_element = z.firstElementChild(body);
while (current_element) |element| {
    if (z.hasClass(element, "bold")) {
        // Found matching element
    }
    current_element = z.nextElementSibling(element);
}
```

### Live Comparison Test

We provide a comprehensive test that demonstrates all three search approaches:

**Test**: `"Comprehensive search comparison: Collection vs CSS vs Attributes"` in `src/modules/collection.zig`

When you run `zig build test`, you'll see output like:

```txt
=== Comprehensive Search Comparison ===
Testing search for class 'bold' using 3 different approaches:

1. Collection-based search (exact string matching):
   Found 1 elements with exact class='bold'

2. CSS Selector search (token-based, case-insensitive):  
   Found 10 elements matching CSS selector '.bold'

3. Attribute-based search (manual traversal with hasClass):
   Found 8 elements using hasClass('bold')
```

**Key Differences:**

- **Collection Search**: Exact string matching, finds only `class="bold"` exactly
- **CSS Selector**: Token-based, case-insensitive, finds `bold`, `BOLD`, `text bold`, etc.  
- **Attribute Search**: Token-based, case-sensitive, finds `bold` as class token in any position

This demonstrates why different search methods return different results for the same query.

## Chunk Parsing vs Fragment Parsing

HTML chunks are parsed as they stream into a full HTML document.

Fragment parsing handles templates and components (for template engines, component frameworks, server-side rendering).

| Feature | Fragment Parsing | Chunk Parsing |
|--|--|--|
| Purpose | Parse incomplete HTML snippets | Parse streaming into complete HTML |
| Input | Template fragments, components | Network streams, large files chunks |
| Context | Respects HTML parsing rules by context | Sequential document building |
| Output | Parsed fragment nodes | Complete document |
| Use Cases | Templates e.g. email, web components, component-based frameworks... | HTTP responses, file processing |

## Parsing string methods available

| Method | Context Awareness | Cross-Document | Memory Management | Use Case |
|--|--|--|--|---|
| `printDocStruct` | Full document | Single doc | Document owns all | Complete pages |
| `setInnerHTML` | Parent element context | Same document | Element cleanup | Content replacement |
| `parseFragment` | Explicit context | Cross-document via `parseFragmentInto` | Fragment result owns | Templates/components |

The _fragment parsing_ gives you _context-aware parsing_ - meaning `<tr>` elements are parsed differently when you specify a `.table` context vs. `.body` context.

- parse with context awareness:
  
```cpp
const result = try z.parseFragment(allocator, "<tr><td>Data</td></tr>", .table);
defer result.deinit();
```

- into an existing document:

```cpp
try z.parseFragmentInto(allocator, target_doc, container, "<p>Fragment</p>", .body);
```

- Cross-document node cloning to insert parsed fragments into target documents
- results handling `getElements()` and `serialize()`

## Project details

### How to use it

TODO

### File structure

- build.zig
- Makefile.lexbor   (`lexbor` build automation)
- lexbor_src        (local `lexbor` source code & built static file)
- src /
  - zhtml.zig
  - minimal.c
  - errors.zig
  - modules
    - html_tags.zig
    - node_types.zig
    - core.zig
    - chunks.zig
    - css_selectors.zig
    - attributes.zig
    - collection.zig
    - cleaner.zig
    - serializer.zig
    - class_list.zig
    - DOM_tree.zig
    - head / title.zig (TODO?)
  
  - main.zig (demo ? TODO:
    - URL fetch from internet
    - build from chunks
    - search for id attributes
    - develop stats on document with search)
  - examples (TODO)

### `lexbor` built with static linking

```sh
make -f Makefile.lexbor
```

### Run tests

The _build.zig_ file runs all the tests from _zhtml.zig_.
It imports all the submodules and runs the tests.

```sh
zig build test --summary all
```

## Build

```sh
zig build run -Doptimize=Debug
#
zig build run -Doptimize=ReleaseFast
```

### Source: `lexbor` examples

<https://github.com/lexbor/lexbor/tree/master/examples/lexbor>

### Notes: searching in the `lexbor` library

In the built static object _liblexbor_static.a_:

```sh
nm lexbor_src_2.4.0/build/liblexbor_static.a | grep -i "serialize"
```

In the source code:

```sh
find lexbor_src_2.4.0/source -name "*.c" | xargs grep -l "lxb_selectors_opt_set_noi"
```

or

```sh
grep -r -A 10 -B 5 "serialize" lexbor_src_2.4.0/source/lexbor/
```
