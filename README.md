# z-html: a `lexbor` in `Zig` project

> [!WARNING]
> Work in progress

`zhtml` is a wrapper of the `C` library [lexbor](https://github.com/lexbor/lexbor), a browser engine.

In other words, you can use `JavaScript` semantics on the server with `Zig`.

`lexbor` follows <https://dom.spec.whatwg.org/>, and we follow  - mostly -  the `JavaScript` semantics.

**Features:**

This project exposes a significant subset of all available `lexbor` functions:

- Parsing:
  - document parsing: `parseFromString()`
  - chunk processing
  - fragment / context-aware parsing
  - `setInnerHTML()`
- Serialization: 
  - tree: `serializeToString()`
  - `innerHTML()`
- DOM_tree and back
  - compressed tuple: `DOM_toTuple()` and `Tuple_toDOM()`
  - W3C JSON: `DOM_toJSON()` and `JSON_toDOM()`
- CSS selectors search with cached CSS selectors parsing: `querySelector()` and `filter()`
- HTML attributes
  - fast "walker" search with _tokens_:
    - `getElementById()`
    - and derivatives class / data-attribute
  - Collections and search on _exact string matching_:
    - `getElementsById()`
    - "attribute-value" pairs
    - they use an iterator to extract from the results.
- DOM: nodes / elements / text / comment
  - create / destroy
  - node / element navigation
  - append / insert / remove
- DOM cleaning with options (remove comments, whitespace, empty nodes)

## Examples

### Build a fragment, inject it and serialization

We create a fragment, populate it and append it to a document.

We test the result with:

- a collection count as a result of a _search by attribute_
- string comparison using _serialization_

```cpp
const std = @import("std");
const z = @import("zhtml.zig");

test "Append fragment" {
  const allocator = std.testing.allocator;

  // create the skeleton <html><body></body></html>
  const doc = try parseFromString("");
  defer z.destroyDocument(doc);

  const body = try bodyNode(doc);

  const fragment = try z.createDocumentFragment(doc);

  // create with attributes
  const div_elt = try z.createElement(doc,"div",
      &.{.{ .name = "class", .value = "container-list" }},
  );

  const div = elementToNode(div_elt);
  const comment = try z.createComment(doc, "a comment");
  z.appendChild(div, commentToNode(comment));

  const ul_elt = try z.createElement(doc, "ul", &.{});
  const ul = elementToNode(ul);

  for (1..4) |i| {
    const content = try std.fmt.allocPrint(allocator,
            "<li data-id=\"{d}\">Item {d}</li>",
            .{ i, i },
      );
    defer allocator.free(content);

    const temp_elt = try createElement(doc, "div", &.{});
    const temp_div = elementToNode(temp_elt);

    // we inject the <li> string as innerHTML into the temp <div>
    _ = try z.setInnerHTML(allocator, temp_elt, content,.{});

    // and append the new <li> node to the <ul> node
    if (firstChild(temp_div)) |li| 
          appendChild(ul, li);
      
    destroyNode(temp_div);
  }

  z.appendChild(div, ul);
  z.appendChild(fragment, div);
  z.appendFragment(body, fragment);

  // first test: count check using collection
  const lis = try z.getElementsByTagName(doc, "LI");
  defer if (lis) |collection| {
        z.destroyCollection(collection);
    };

  const li_count = z.getCollectionLength(lis);
  try testing.expect(li_count == 3);

  // second test: we check that the full string is what we expect
  const serialized_fragment = try z.serializeTree(allocator, div);
  defer allocator.free(fragment_txt);

  const expected_fragment =
        \\<div class="container-list">
        \\  <!--a comment-->
        \\  <ul>
        \\      <li data-id="1">Item 1</li>
        \\      <li data-id="2">Item 2</li>
        \\      <li data-id="3">Item 3</li>
        \\  </ul>
        \\</div>
    ;

  const expected = try z.normalizeWhitespace(allocator, expected_fragment);
  defer allocator.free(expected);
  
  try testing.expectEqualStrings(expected, serialized_fragment);
}
```

### DOM structure

We can debug the document structure:

```cpp
  // continue
  try z.debugDocumentStructure(doc)
```

The output is:

```txt
--- DOCUMENT STRUCTURE ----
DIV
  #comment
  UL
    LI
      #text
    LI
      #text
    LI
      #text
```

### DOM tree: tuple and W3C JSON

- the tuple version: `{tagName, attributes, children}`

```cpp
  // continue
  const tree = try z.documentToTupleTree(allocator, doc);
  defer z.freeHtmlTree(allocator, tree);

  for (tree) |node| {
    z.printNode(node, 0);
  }
```

gives the compressed "tuple" representation:

```json
[
  {
    "DIV", 
    [{"class", "container-list"}], 
    [
      {"comment", "a comment"},
      {"UL", [], 
        [
          {"LI", [{"data-id", "1"}], ["Item 1"]}, 
          {"LI", [{"data-id", "2"}], ["Item 2"]},
          {"LI", [{"data-id", "3"}], ["Item 3"]}
        ]
      }
    ]
  }
]
```

- the JSON format: `{nodeType, tagName, attributes, children}` where element = 1, text = 3, comment = 8, document = 9, fragment = 11.

```cpp
  const json_tree = try documentToJsonTree(allocator, doc);
  const json_string = try jsonNodeToString(allocator, json_tree[0]);
  print("{s}", .{json_string });
```

gives the W3C JSON representation:

```json
{
  "nodeType": 1, 
  "tagName": "DIV", 
  "attributes": [
    {"name": "class", "value": "container-list"}
  ], 
  "children": [
    {"nodeType": 8, "data": "a comment"}, 
    {
      "nodeType": 1, 
      "tagName": "UL", 
      "attributes": [], 
      "children": [
        {
          "nodeType": 1, 
          "tagName": "LI", 
          "attributes": [{"name": "data-id", "value": "1"}], "children": [{"nodeType": 3, "data": "Item 1"}]
        }, 
        {
          "nodeType": 1, 
          "tagName": "LI", 
          "attributes": [{"name": "data-id", "value": "2"}], "children": [{"nodeType": 3, "data": "Item 2"}]
        },
        {
          "nodeType": 1, 
          "tagName": "LI", 
          "attributes": [{"name": "data-id", "value": "3"}], "children": [{"nodeType": 3, "data": "Item 3"}]
        }
      ]
    }
  ]
}
```

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
        nodeToElement(result).?,
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

> Very few functions that return strings point to internal `lexbor` memory. The `nodeName()` function can be usesd if it is immediately disposed. If you need to store it, use `nodeNameOwned()` instead.

## Chunk Parsing vs Fragment Parsing

HTML chunks are parsed as it streams into a full HTML document.

Fragmemnt parsing handles templates and components (for template engines, component frameworks, server-sde rendering).

| Feature | Fragment Parsing | Chunk Parsing |
|--|--|--|
| Purpose | Parse incomplete HTML snippets | Parse streaming into complete HTML |
| Input | Template fragments, components | Network streams, large files chunks |
| Context | Respects HTML parsing rules by context | Sequential document building |
| Output | Parsed fragment nodes | Complete document |
| Use Cases | Templates, components, HTMX, email | HTTP responses, file processing|

## Parsing strings methods available

| Method | Context Awareness | Cross-Document | Memory Management | Use Case |
|--|--|--|--|---|
| `parseFromString` | Full document | Single doc | Document owns all | Complete pages |
| `setInnerHTML` | Parent element context | Same document | Element cleanup | Content replacement |
| `parseFragment` | Explicit context | Cross-document via `parseFragmentInto` | Fragment result owns | Templates/components |

The _fragment parsing_ gives you _context-aware parsing_ - meaning `<tr>` elements are parsed differently when you specify a `.table` context vs `.body` context.

- parse with context awareness:
  
```cpp
const result = try z.parseFragment(allocator, "<tr><td>Data</td></tr>", .table);
defer result.deinit();
```

- into an existing document:

```cpp
try z.parseFragmentInto(allocator, target_doc, container, "<p>Fragment</p>", .body);
```

- Cross-document node cloning to inser parsed fragments into target documents
- results handling `getElements()` and `serialize()`

## Project details

### How to use it

TODO

### file structure

- build.zig
- Makefile.lexbor   # `lexbor` build automation
- lexbor_src        # local `lexbor` source code & built static file
- src /
  - zhtml.zig
  - minimal.c
  - modules
    - errors.zig
    - html_tags.zig
    - node_types.zig
    - core.zig
    - chunks.zig
    - css_selectors.zig
    - attributes.zig
    - collection.zig
    - cleaner.zig
    - serializer.zig
    - tree.zig
    - title.zig (TODO?)
    - head ?

  - main.zig (demo TODO?)
  - examples
    - todo

### `lexbor` built with static linking

```sh
make -f Makefile.lexbor
```

### Run tests

The _build.zig_ file runs all the tests from _zhtml.zig_.
It imports all the submodules and run the tests.

```sh
 zig build test --summary all
 ```

## Build

 ```sh
 zig build run -Doptimize=ReleaseFast #or Debug
 ```

### Source: `lexbor` examples

<https://github.com/lexbor/lexbor/tree/master/examples/lexbor>

### Notes: searching in the  `lexbor` library

In the build static object _liblexbor_static.a_:

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

Test individual `Zig` files:

```sh
 zig test src/test_traversal.zig -I lexbor_src_2.4.0/source --library c lexbor_src_2.4.0/build/liblexbor_static.a src/minimal.c
 ```

