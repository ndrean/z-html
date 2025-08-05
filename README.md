# z-html

`zhtml` is a `Zig` wrapper for [lexbor](https://github.com/lexbor/lexbor)

## First step: compile `lexbor` with static linking

```sh
make -f Makefile.lexbor
```

## Files

- src /
  - __zhtml.zig__
  - _minimal.c_
  - _errors.zig_
  - _lexbor.zig_:
    - document and fragment parsing,
    - DOM navigation,
    - whitespace,
    - serialization
  - _chunks.zig_
  - _selectors.zig_

  - demo in _main.zig_ (TODO)
- __build.zig__
- Makefile.lexbor
- vendor/lexbor
  
## Run tests

The _build.zig_ file runs all the tests from the _zhtml.zig_ file (which imports all the submodule and run the tests via `std.testing.refAllDecls`)

```sh
 zig build test --summary all -Doptimize=Debug
 ```

## Searching in `lexbor` library

In the build static object _liblexbor_static.a_:

```sh
nm vendor/lexbor/build/liblexbor_static.a | grep -i "serialize"
```

In the source code:

```sh
grep -r -A 10 -B 5 "serialize" vendor/lexbor/source/
```
