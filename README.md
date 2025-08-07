# z-html

`zhtml` is a `Zig` wrapper of the `C` library [lexbor](https://github.com/lexbor/lexbor).

`lexbor` follows <https://dom.spec.whatwg.org/>

We expose a _small_ but significant subset of all available functions.

Eveents are not wrapped.

- document and fragment and chunk parsing
- node/element/fragment/document serialization including whitespace management
  - via HTML aware manipulations
  - via string transformations of the serialized fragment
- CSS selectors using `lexbor` "css_parser" engine
- HTML attributes on an HTMLElement via a "name" or a `DomAttr`.
- DOM node manipulation

## Files

- src /
  - __zhtml.zig__
  - _minimal.c_
  - _errors.zig_
  - _lexbor.zig_:
    - document and fragment parsing,
    - DOM navigation,
    - whitespace,
    - escaping
  - _chunks.zig_
  - _css_selectors.zig_
  - _HTMLelement_attributes.zig_
  - _serialize.zig_
    - innerHTML,
    - serialize nodes / HTMLElements
  - _title.zig_ (TODO)

  - demo in _main.zig_ (TODO)
- __build.zig__
- Makefile.lexbor
- lexbor_src
  
## `lexbor` built with static linking

```sh
make -f Makefile.lexbor
```

## Run tests

The _build.zig_ file runs all the tests from the _zhtml.zig_ file (which imports all the submodule and run the tests via `std.testing.refAllDecls`)

```sh
 zig build test --summary all -Doptimize=Debug
 ```

## Usage example demo

__main.zig__: TODO

 ```sh
 zig build run -Doptimize=Debug | ReleaseFast
 ```

## Source: `lexbor` examples

<https://github.com/lexbor/lexbor/tree/master/examples/lexbor>

## Searching in `lexbor` library

In the build static object _liblexbor_static.a_:

```sh
nm vendor/lexbor/build/liblexbor_static.a | grep -i "serialize"
```

In the source code:

```sh
grep -r -A 10 -B 5 "serialize" vendor/lexbor/source/
```
