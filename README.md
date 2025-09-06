# z-html: a `lexbor` in `Zig` project

> [!WARNING]
> Work in progress

`zhtml` is a wrapper of the `C` library [lexbor](https://github.com/lexbor/lexbor), an HTML parser/DOM emulator.

This is useful for web scapping, email sanitization, test engine for integrated tests, SSR post-processing of fragments.

This binding stays as close as possible to `JavaScript` semantics.

**Features:**

This project exposes a significant / essential subset of all available `lexbor` functions:

- Parsing with a parser engine
  - document
  - fragment context-aware parsing
- streaming and chunk processing
- Serialization
- Sanitization (not)
- CSS selectors search with cached CSS selectors parsing
- Support of `<template>` elements.
- Attribute search
- Collections and _exact string matching_:
- DOM manipulation
- DOM normalization with options (remove comments, whitespace, empty nodes)
- Pretty printing

> [!NOTE]
> Some functions borrow memory from `lexbor` for zero-copy operations: their result is consumed immediately.
> We opted for the following convention: add `_zc` (for _zero_copy_) to the **non allocated** version. For example, `textContent_zc`, `qualifiedName_zc` or `nodeName_zc` or `tagName_zc`.
> With allocated versions, the data can outlive the current function.

## Examples

### Building a document & Parsing

You have several methods avialable:

```c
const z = @import("zhtml");

const doc = try z.createDocument();
defer z.destroyDocument(doc);
try z.parseString("<body></body>");
const body = z.bodyNode(doc);
const div = try z.createElement(doc, "div");
z.appendChild(body, div);
```

```c
const doc = try z.createDocFromString("<body><div></div></body>");
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
    const end_chunk = "</tbody></table></body></html>;";
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

and the HTML document:

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

<p align="center"><img src="https://github.com/ndrean/z-html/blob/main/src/images/parse-engine.png" with="300">
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
        "afterend",
        "<span class=\"after end\">After End</span>",
        false,
  );

  try z.insertAdjacentHTML(
        allocator,
        target,
        "afterbegin",
        "<span class=\"after begin\"></span>",
        false,
  );

  try z.insertAdjacentHTML(
        allocator,
        target,
        "beforebegin",
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

  try z.prettyPrint()
  print("{s}\n", .{clean_html});
}
```

<p align="center"><img src="https://github.com/ndrean/z-html/blob/main/src/images/insertadjacenthtml-all-positions.png" with="300"></p>

```txt
<body><div id="container"><span class="before begin"></span><p id="target"><span class="after begin"></span>Target<span class="before end"></span></p><span class="after end">After End</span></div></body>
```

### Pretty print & DOM structure utilities

From the HTML string:

```html
<body><div><button phx-click="increment">Click me</button> <p>Hello<i>there</i>, all<strong>good?</strong></p><p>Visit this link: <a href="https://example.com">example.com</a></p></div></body>
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

## `lexbor` DOM memory management: Document Ownership vs Manual Cleanup

In `lexbor`, nodes belong to documents, and the document acts as the memory manager.

When a node is attached to a document (either directly or through a fragment that gets appended), the document owns it.

When `destroyDocument()` is called, it automatically destroys ALL nodes that belong to it.

When a node is NOT attached to any document, you must manually destroy it.

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

## Search examples

We apply CSS selectors based search, token based search, full text search on the following HTML:

```cpp
const html =
        \\<div class="container main">Container element</div>
        \\<p class="text bold">Bold paragraph</p>
        \\<p class="text"><span class="text bold">Nested bold span</span></p>
        \\<span class="bold text-xs">Span with multiple classes</span>
        \\<div class="text-xs bold">Reversed class order</div>
        \\<section class="main">Another main section</section>
        \\<article class="container">Just container class</article>
        \\<p class="text">Simple text class</p>
        \\<div class="BOLD">Uppercase BOLD</div>
        \\<span class="text-bold">Hyphenated similar class</span>
        \\<div class="text bold extra">Three classes</div>
        \\<div class="BOLD text">Mix the classes BOLD</div>
        \\  <div class="bold text-xl">Bold and text-xl</div>
        \\  <div class="bold">bold alone</div>
        \\  <div class="text-xs">text-xs alone</div>
        \\  <div class="bold text">reversed
    ;
```

== Testing class: 'bold' ===
CSS Selector (.bold):     10 elements
Walker-based search:     8 elements
Collection-based:        1 elements
Manual hasClass walk:    7 elements
Note: Collection may differ for 'bold' due to exact string matching
Note: CSS selectors are case-insensitive, so 'BOLD' matches '.bold'

=== Testing class: 'text-xs' ===
CSS Selector (.text-xs):     3 elements
Walker-based search:     3 elements
Collection-based:        1 elements
Manual hasClass walk:    3 elements
Note: Collection won't find 'text-xs' in multi-class attributes due to exact matching

=== Testing class: 'main' ===
CSS Selector (.main):     2 elements
Walker-based search:     2 elements
Collection-based:        1 elements
Manual hasClass walk:    2 elements

=== Testing class: 'container' ===
CSS Selector (.container):     2 elements
Walker-based search:     2 elements
Collection-based:        1 elements
Manual hasClass walk:    2 elements

=== Testing class: 'text bold' ===
CSS Selector (.text bold):     0 elements
Walker-based search:     0 elements
Collection-based:        2 elements
Manual hasClass walk:    0 elements
Note: CSS found 0 - space in selector may not work as descendant selector here
Note: Collection found 2 - exact string matching finds class='text bold' attributes
Note: Walker/hasClass found 0 - they look for 'text bold' as a single class token

=== Testing class: 'nonexistent' ===
CSS Selector (.nonexistent):     0 elements
Walker-based search:     0 elements
Collection-based:        0 elements
Manual hasClass walk:    0 elements

=== CSS Selector Syntax Exploration ===
'.text .bold': 1 elements
'.text > .bold': 1 elements
'.text.bold': 5 elements
'p .bold': 1 elements
'p > .bold': 1 elements

=== Class Search Behavior Summary ===
• CSS Selectors: Token-based, order-independent, case-insensitive, handles multi-class correctly
• Walker Search: Token-based, order-independent, case-sensitive, handles multi-class correctly
• Collection Search: Exact string matching, order-dependent, case-sensitive, limited multi-class support
• hasClass Method: Token-based, order-independent, case-sensitive, handles multi-class correctly

For class='bold text-xs' vs class='text-xs bold':
• CSS/Walker/hasClass: Will find BOTH variations (order-independent)
• Collection: Will only find exact string matches

For class='BOLD' vs '.bold' CSS selector:
• CSS: Will match (case-insensitive)
• Walker/hasClass/Collection: Won't match (case-sensitive)

For 'text bold' search:
• CSS: Returns 0 - space in selector may be interpreted differently than expected
• Walker/hasClass: Find 0 - look for 'text bold' as single class token
• Collection: Finds elements with exact class='text bold' attribute value
• This demonstrates different handling of spaces: CSS selectors vs class tokens vs string matching

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
zig build run -Doptimize=ReleaseFast # or Debug
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
