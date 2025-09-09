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

## Examples


### Scrap the web and explore a page 

```c
test "scrap example.com" {
  const allocator = std.testing.allocator;

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
  std.debug.print("\n{s}\n", .{href_value});

  var css_content: []const u8 = undefined;
  const style_by_walker = z.getElementByTag(html, .style);
  if (style_by_walker) |style| {
      css_content = z.textContent_zc(z.elementToNode(style));
      print("\n{s}\n", .{css_content});
  }

  const style_by_css = try css_engine.querySelector(html, "style");

  if (style_by_css) |style| {
      const css_content_2 = z.textContent_zc(style);
      std.debug.assert(std.mem.eql(u8, css_content, css_content_2));
  }
}
```

<br>

You will get a colourful print in your terminal, where the attributes, values, html elements get coloured.

<details><summary> HTML content of example.com</summary>

<img width="965" height="739" alt="Screenshot 2025-09-09 at 13 54 12" src="https://github.com/user-attachments/assets/ff770cdb-95ab-468b-aa5e-5bbc30cf6649" />

</details>

You will also see the value of the `href` attribute of a the first `<>` link:

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

### Scan a page for potential malicious content

```html
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

```c
const doc = try z.createDocFromString(html_string);
defer z.destryDocument(doc);
```

We then print the HTML. The DOM is agressively cleaned (whitespace only text nodes and comments removed).

```c
const body = z.bodyNode(doc).?;
try z.prettyPrint(allocator, body);
```

> [!NOTE]
> The intent is to highlight potential XSS threats. It works by parsing the string into a fragment. When a HTMLElement gets an unknow attribute, its colour is white and the attribute value is highlighted in RED.

You get the following output in your terminal.

<br>
<img width="931" height="499" alt="Screenshot 2025-09-09 at 16 08 19" src="https://github.com/user-attachments/assets/45cfea8b-73d9-401e-8c23-457e0a6f92e1" />
<br>

We can then run a _sanitization_ process against the DOM, so you get a context where the attributes are whitelisted.

```c
try z.sanitizeNode(allocator, body, .permissive);
try z.prettyPrint(allocator, body);
```

The result is shown below.

<br>
<img width="900" height="500" alt="Screenshot 2025-09-09 at 16 11 30" src="https://github.com/user-attachments/assets/ff7fa678-328b-495a-8a81-2ff465141be3" />

<br>

The "normal" process is to use the "parser engine". It will create a document-fragment, sanitize this fragment, and insert into the document.

```c
const doc = try z.createDocFromString("");
const body = z.bodyNode(doc).?;

var parser = try z.Parser.init(testing.allocator);
defer parser.deinit();

try parser.insertFragment(body, html, .body, .none);
```

<hr>

### Building a document & Parsing

You have several methods available.

The `parseString` creates a `<head>` and a `<body>` element and replaces BODY innerContent with the nodes created by the parsing of the given string.

```c
const z = @import("zexplorer");

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

```c
const doc: *HTMLDocument = try z.createDocFromString("<div></div><p></p>");
defer z.destroyDocument(doc);

```

<hr>

### Processing streams

You receive chunks and build a document.

```c
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
  <img src="https://github.com/ndrean/z-html/blob/main/src/images/html-table.png" width="300" alt="image"/>
  <img src="https://github.com/ndrean/z-html/blob/main/src/images/tree-table.png" width="300" alt="image"/>
</p>

<hr>

### Search examples - TODO -

We have two types of search available, each with different behaviors and use cases:


1. CSS Selector Search

```zig  
// Token-based, case-insensitive, most flexible
const css_results = try z.querySelectorAll(allocator, doc, ".bold");
defer allocator.free(css_results);
print("Found {} elements\n", .{css_results.len});
```

2. Attribute-based Search

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

<hr>

### Other examples

The file _main.zig_ shows more use cases with parsing and serialization as well as the tests  (`setInnerHTML`, `setInenrSafeHTML`, `insertAdjacentElement` or `insertAdjacentHTML`...)

<hr>

## Building the lib

`lexbor` is built with static linking

```sh
make -f Makefile.lexbor
```


- tests: The _build.zig_ file runs all the tests from _root.zig_.It imports all the submodules and runs the tests.

```sh
zig build test --summary all
```

- demo: Build the __main.zig_ demo with:

```sh
zig build run -Doptimize=Debug
#
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

### Source: `lexbor` examples

<https://github.com/lexbor/lexbor/tree/master/examples/lexbor>


In the built static object _liblexbor_static.a_:

```sh
nm lexbor_src_2.5.0/build/liblexbor_static.a | grep -i "serialize"
```

In the source code:

```sh
find lexbor_src_2.5.0/source -name "*.h" | xargs grep -l "lxb_selectors_opt_set_noi"
```



