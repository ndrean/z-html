# Zexplorer Library Usage

## Build Library
```bash
zig build
```

## Use in Your Project

### 1. Add as Git Submodule
```bash
git submodule add https://github.com/your-repo/z-html.git deps/z-html
```

### 2. In your `build.zig`
```zig
const zhtml_dep = b.dependency("zexplorer", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zexplorer", zhtml_dep.module("zexplorer"));
```

### 3. In your code
```zig
const z = @import("zexplorer");

const doc = try z.createDocFromString("<div>Hello</div>");
defer z.destroyDocument(doc);
```

## Local Development
```bash
# Add to build.zig
const zhtml_module = b.addModule("zhtml", .{
    .root_source_file = b.path("path/to/z-html/src/root.zig"),
});

exe.root_module.addImport("zhtml", zhtml_module);
```