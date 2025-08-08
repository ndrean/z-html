# z-html

`zhtml` is a `Zig` wrapper for the `C` library [lexbor](https://github.com/lexbor/lexbor).

`lexbor` follows <https://dom.spec.whatwg.org/>.

We expose a _small_ but significant subset of all available functions.Events are not wrapped.

**Features:**

- document and fragment and chunk parsing with the "chunk_parser" engine
- node/element/fragment/document serialization
- DOM cleaning with HTML aware manipulation:
  - optional comment removal
  - optional empty HTMLElement removal (preserves elements with attributes)
- CSS selectors using `lexbor`'s "css_parser" engine
- HTML attributes on an HTMLElement via a "name" or a `DomAttr`.
- DOM node manipulation

## File structure

- src /
  - __zhtml.zig__   # main module (re-exports all functionalities)
  - _minimal.c_     #`C` wrapper functions
  - _errors.zig_:   # Error types
  - _lexbor.zig_:   # Document parsing, DOM navigation, whitespace, escaping
  - _chunks.zig_        #chunk/streaming parsing
  - _css_selectors.zig_ # CSS selector engine
  - _node_types.zig_    # Node type definitions
  - _html_tags.zig_     # HTML tag enumerations
  - _attributes.zig_    # Element attribute operations

  - _serialize.zig_     # innerHTML, serialize nodes/HTMLElements
  - _title.zig_ (TODO)

  - _main.zig_ (demo TODO)
- __build.zig__     # Build configuration
- Makefile.lexbor   # `lexbor` build automation
- lexbor_src        # `lexbor` source code
  
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

```zig
const zhtml = @import("zhtml");

// Parse HTML
const fragment = "<p>Hello <strong>World</strong>!</p>"
const doc = try zhtml.parseFragmentAsDocument(fragment);
defer zhtml.destroyDocument(doc);

// Find elements with CSS
const elements = try zhtml.findElements(allocator, doc, "strong");
defer allocator.free(elements);

// Clean and serialize
try zhtml.cleanDomTree(allocator, root_node, .{ .remove_comments = true });
const clean_html = try zhtml.serializeTree(allocator, root_node);
defer allocator.free(clean_html);
```

Examples in __main.zig__: TODO

- Parsing a web document
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

## Searching in the  `lexbor` library

In the build static object _liblexbor_static.a_:

```sh
nm lexbor_src_2.4.0/build/liblexbor_static.a | grep -i "serialize"
```

In the source code:

```sh
grep -r -A 10 -B 5 "serialize" lexbor_src_2.4.0/source/
```
