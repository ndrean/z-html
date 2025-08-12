# z-html

> [!WARNING]
> Work in progress

`zhtml` is a `Zig` wrapper for the `C` library [lexbor](https://github.com/lexbor/lexbor).

`lexbor` follows <https://dom.spec.whatwg.org/>.

We expose a _small_ but significant subset of all available functions.

**Features:**

- document and fragment parsing
- chunk parsing with the "chunk_parser" engine
- node/element/fragment/document serialization
- DOM to DOM_tree and return: tuple and (todo) JSON format
- DOM cleaning with HTML aware manipulation:
  - optional comment removal
  - optional script removal
  - optional empty HTMLElement removal (preserves elements with attributes)
- CSS selectors using `lexbor`'s "css_parser" engine
- HTML attributes on an HTMLElement via a "name" or a `DomAttr`.
- DOM node manipulation
- Search by attribute with collections.

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
    - serialize.zig
    - tree.zig
    - title.zig (TODO?)

  - _main.zig_ (demo TODO?)

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

## Quick start

```c
const z = @import("zhtml.zig");
const allocator = std.heap.c_allocator;

const doc = try z.parseFromString("<p>Hello <strong>world</strong></p>");
defer z.destryoDocument(doc);

z.printDocumentStructure(doc);
```

gives you:

```txt
--- DOCUMENT STRUCTURE ----
HTML
  HEAD
  BODY
    P
      #text
      STRONG
        #text
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
