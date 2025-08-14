# z-html: `lexbor` in `Zig`

> [!WARNING]
> Work in progress

`zhtml` is a - thin -  wrapper of the `C` library [lexbor](https://github.com/lexbor/lexbor).

`lexbor` follows <https://dom.spec.whatwg.org/>.

We expose a significant subset of all available functions.

The naming follows mostly the `JavaScript` convention.

> We use `Zig` allocators instead of using `lexbor` internals for most functions returning slices. This probably trades a bit some performance for memory safety - returned strings are owned by your allocator rather than pointing to internal lexbor memory that could be invalidated.

**Features:**

- document and fragment parsing
- chunk parsing with `lexbor`'s "chunk_parser" engine
- node/element/fragment/document serialization
- DOM to DOM_tree and return: tuple and (todo) JSON format
- DOM cleaning with options (remove comments, whitespace, empty nodes)
- CSS selectors using `lexbor`'s "css_parser" engine
- HTML attributes and search
- DOM node manipulation
- Search by attribute with collections.

## Examples

Use `JavaScript` semantics on the server!

### Build a fragment, inject it and serialization

```c
const std = @import("std");
const z = @import("zhtml.zig");

test "Append JS fragment" {
  const allocator = std.testing.allocator;

  // create the skeleton <html><body></body></html>
  const doc = try parseFromString("");
  defer z.destroyDocument(doc);

  const body = try bodyNode(doc);

  const fragment = try z.createDocumentFragment(doc);
  defer destroyNode(fragment);

  // create with attributes
  const div_elt = try z.createElement(doc,"div",
      &.{.{ .name = "class", .value = "container-list" }},
  );

  const div = elementToNode(div_elt);
  defer destroyNode(div);
  const comment = try z.createComment(doc, "a comment");
  defer destroyComment(comment)
  z.appendChild(div, commentToNode(comment));

  const ul_elt = try z.createElement(doc, "ul", &.{});
  const ul = elementToNode(ul);

  for (1..4) |i| {
    // we use alternatively `innerHTML`
    const content = try std.fmt.allocPrint(allocator,
            "<li data-id=\"{d}\">Item {d}</li>",
            .{ i, i },
      );
    defer allocator.free(content);

    const temp_elt = try createElement(doc, "div", &.{});
    const temp_div = elementToNode(temp_elt);

    _ = try z.setInnerHTML(allocator, temp_elt, content,.{});

    if (firstChild(temp_div)) |li| 
          appendChild(ul, li);
      
    destroyNode(temp_div);
  }

  z.appendChild(div, ul);
  z.appendChild(fragment, div);
  z.appendFragment(body, fragment);

  const fragment_txt = try z.serializeTree(allocator, div);
  defer allocator.free(fragment_txt);

  const pretty_expected =
        \\<div class="container-list">
        \\  <!--a comment-->
        \\  <ul>
        \\      <li data-id="1">Item 1</li>
        \\      <li data-id="2">Item 2</li>
        \\      <li data-id="3">Item 3</li>
        \\  </ul>
        \\</div>
    ;

  const expected = try z.normalizeWhitespace(allocator, pretty_expected);
  defer allocator.free(expected);
  
  try testing.expectEqualStrings(expected,fragment_txt);
}
```

### DOM structure

```c
  // continue
  try z.debugDocumentStructure(doc)
```

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

```c
  // continue
  const tree = try z.documentToTupleTree(allocator, doc);
  defer z.freeHtmlTree(allocator, tree);

  for (tree) |node| {
    z.printNode(node, 0);
  }
```

```txt
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

```c
  const json_tree = try documentToJsonTree(allocator, doc);
  const json_string = try jsonNodeToString(allocator, json_tree[0]);
  print("{s}", .{json_string });
```

gives:

```txt
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

```c
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

## File structure

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

## `lexbor` built with static linking

```sh
make -f Makefile.lexbor
```

## Run tests

The _build.zig_ file runs all the tests from _zhtml.zig_.
It imports all the submodules and run the tests.

```sh
 zig build test --summary all -Doptimize=Debug
 ```

## Build

 ```sh
 zig build run -Doptimize=ReleaseFast #or Debug
 ```

## Source: `lexbor` examples

<https://github.com/lexbor/lexbor/tree/master/examples/lexbor>

## Notes: searching in the  `lexbor` library

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
grep -r -A 10 -B 5 "serialize" lexbor_src_2.4.0/source/
```

Test individual `Zig` files:

```sh
 zig test src/test_traversal.zig -I lexbor_src_2.4.0/source --library c lexbor_src_2.4.0/build/liblexbor_static.a src/minimal.c
 ```
