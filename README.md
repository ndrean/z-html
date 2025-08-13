# z-html

> [!WARNING]
> Work in progress

`zhtml` is a `Zig` wrapper for the `C` library [lexbor](https://github.com/lexbor/lexbor).

`lexbor` follows <https://dom.spec.whatwg.org/>.

We expose a significant subset of all available functions.

We opted to use `Zig` allocators instead of using `lexbor` internals for most functions returning slices. This trades some performance for memory safety - returned strings are owned by your allocator rather than pointing to internal lexbor memory that could be invalidated.

**Features:**

- document and fragment parsing
- chunk parsing with the "chunk_parser" engine
- node/element/fragment/document serialization
- DOM to DOM_tree and return: tuple and (todo) JSON format
- DOM cleaning with HTML aware manipulation:
- CSS selectors using `lexbor`'s "css_parser" engine
- HTML attributes and search
- DOM node manipulation
- Search by attribute with collections.

## Quick start

The API closely follows JavaScript DOM conventions.

### Insert a document fragment and serialization

```c
const z = @import("zhtml.zig");

test "Append JS fragment" {
  const allocator = testing.allocator;

  const doc = try parseFromString("<html><body></body></html>");
  defer z.destroyDocument(doc);

  const body_node = try getBodyNode(doc);


  const fragment = try z.createDocumentFragment(doc);

  const div = try z.createElement(
      doc,
      "div",
      &.{.{ .name = "class", .value = "container-list" }},
  );

  const div_node = elementToNode(div);

  const ul = try z.createElement(doc, "ul", &.{});
  const ul_node = elementToNode(ul);

  for (1..4) |i| {
    // Convert integer to ASCII digit
    const digit_char = @as(u8, @intCast(i)) + '0';
    const value_str = &[_]u8{digit_char};

   const li = try z.createElement(
      doc,
      "li",
       &.{.{ .name = "data-id", .value = value_str }},
    );

    const li_node = elementToNode(li);

    const text_content = try std.fmt.allocPrint(
      testing.allocator,
      "Item {d}",
      .{i},
    );
    defer allocator.free(text_content);

    const text_node = try z.createTextNode(doc, text_content);
    z.appendChild(li_node, text_node);
    z.appendChild(ul_node, li_node);
  }

  z.appendChild(div_node, ul_node);
  z.appendChild(fragment, div_node);

  // batch it into the DOM
  z.appendFragment(body_node, fragment);

  const fragment_txt = try z.serializeTree(allocator, div_node);

  defer allocator.free(fragment_txt);

  const expected =
    "<div class=\"container-list\"><ul><li data-id=\"1\">Item 1</li><li data-id=\"2\">Item 2</li><li data-id=\"3\">Item 3</li></ul></div>";


  try testing.expectEqualStrings(expected,fragment_txt);
}
```

### DOM structure

```c
  // continue
  try z.printDocumentStructure(doc)
```

```txt
--- DOCUMENT STRUCTURE ----
DIV
  UL
    LI
      #text
    LI
      #text
    LI
      #text
```

### DOM tree

```c
  // continue
  const tree = try z.documentToTree(allocator, doc);
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

## Examples

### Cleaning HTML document

```c
const z = @import("zhtml");
const allocator = std.heap.c_allocator;
const writer = std.io.getStdOut().writer();


const fragment = 
  \\<body><div class=" container test " id="main">
  \\  
  \\ <p>   Hello     World   </p>
  \\  
  \\  <!-- Remove this comment -->
  \\  <span data-id="123"></span>
  \\  <pre>    preserve    this    </pre>
  \\  
  \\  <p>  </p>
  \\
  \\ <br> <!-- This should be removed -->
  \\
  \\ <img src="http://google.com" alt="my-image" data-value=""> 
  \\
  \\   <script> const div  = document.querySelector('div'); </script>
  \\</div>
  \\. <div data-empty="" title="  spaces  ">Content</div>
  \\ <article>
  \\ <h1>Title</h1><p>Para 1</p><p>Para 2</p>
  \\    <footer>End</footer>
  \\                   </article></body>
;


const doc = try z.parseFromString(fragment);
defer z.destroyDocument(doc);

try z.cleanDomTree(
  allocator,
  body_node.?,
  .{ .remove_comments = true },
);

const new_html = try z.serializeTree(
  allocator,
  body_node.?,
);
defer allocator.free(new_html);

try writer.print("{s}\n", .{new_html});
z.printDocumentStructure(doc);
```

```txt
<body>
<div class="container test" id="main">
<p>Hello World</p>
<span data-id="123"></span>
<pre>    preserve    this    </pre>
<p></p><br>
<img src="http://google.com" alt="my-image" data-value="">
<script> const div  = document.querySelector('div'); </script>
</div>
```

The new document structure is:

- cleaned from unwanted empty `#text` nodes,
- has preserved and cleaned attributes,
- left untouched special tags (`<pre>`, `<meta>`...),
- optionally removes comments,
- optionally can remove empty nodes if they don't contain any attribute.

```txt
--- DOCUMENT STRUCTURE ----
HTML
  HEAD
  BODY
    DIV
      P
        #text
      SPAN
      PRE
        #text
      P
      BR
      IMG
      SCRIPT
        #text
```

Examples in _main.zig_: TODO

- DOM_tree
- Serialization
- CSS selector
- Attributes
- Chunks

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
