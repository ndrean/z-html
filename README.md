# z-html

Zig wrapper for [lexbor](https://github.com/lexbor/lexbor)

## Compile lexbor

```sh
make -f Makefile.lexbor
```

## Files

- _lexbor.zig_:
  - document and fragment parsing,
  - DOM navigation,
  - whitespace,
  - serialization
- _chunks_zig_
- _selectors.zig_ (work in progress)
  
## Run tests

The _build.zig_ file runs all the tests from the files _lexbor.zig_ and _chunks.zig_.

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
