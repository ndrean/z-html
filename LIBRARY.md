# Zexplorer Library Usage

A Zig wrapper for the lexbor HTML parsing library.

## Installation via Zig Package Manager

### 1. Add to your project

```bash
zig fetch --save https://github.com/ndrean/z-html/archive/main.tar.gz
```

### 2. In your `build.zig`

```zig
const zexplorer = b.dependency("zexplorer", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zexplorer", zexplorer.module("zexplorer"));
```

### 3. In your code

```zig
const z = @import("zexplorer");

const doc = try z.createDocFromString("<div>Hello</div>");
defer z.destroyDocument(doc);
```

## Alternative: Git Submodule (for development)

```bash
git submodule add https://github.com/ndrean/z-html.git deps/zexplorer
```

```zig
// In build.zig for local development
const zexplorer_module = b.addModule("zexplorer", .{
    .root_source_file = b.path("deps/zexplorer/src/root.zig"),
});

exe.root_module.addImport("zexplorer", zexplorer_module);
```

## Building from Source

If you want to build the library locally:

```bash
# Build lexbor dependency first
make -f Makefile.lexbor

# Create distribution structure
mkdir -p lexbor_master_dist/{lib,include}

# Copy static library and headers
cp lexbor_src_master/build/liblexbor_static.a lexbor_master_dist/lib/
cp -r lexbor_src_master/source/lexbor lexbor_master_dist/include/

# Build the Zig library
zig build

# Run tests
zig build test --summary all

# Run demo
zig build run --release=fast
```

## Requirements

- Zig 0.15.1 or later
- The library includes pre-built lexbor static library for common platforms
- For custom builds, you can rebuild lexbor using the included Makefile

## Features

- HTML parsing with lexbor backend
- DOM manipulation
- CSS selector support
- HTML normalization (string and DOM-based)
- Sanitization with multiple security levels
- Template element support
- Stream parsing for large documents
