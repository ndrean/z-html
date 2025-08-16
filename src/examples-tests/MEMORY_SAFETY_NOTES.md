# Memory Safety in z-html: lexbor Ownership vs Zig Ownership

## The Issue

```zig
// UNSAFE: Returns a slice pointing to lexbor's internal memory
pub fn tagName(element: *DomElement) []const u8 {
    const name_ptr = lxb_dom_node_name(node, null);  // C function returns [*:0]const u8
    return std.mem.span(name_ptr);                   // Converts to []const u8 but doesn't copy!
}
```

## The Problem

1. **lexbor owns the memory** - The C function `lxb_dom_node_name()` returns a pointer to lexbor's internal string storage
2. **Zig borrows the memory** - `std.mem.span()` creates a Zig slice but doesn't copy the data
3. **Dangling pointer risk** - If the node is destroyed or the DOM is modified, the returned slice becomes invalid

## Potential Failure Scenario

```zig
const element = try createElement(doc, "div", &.{});
const tag_name = tagName(element);  // Points to lexbor's memory
destroyNode(elementToNode(element));       // lexbor frees its memory
// tag_name is now a dangling pointer! 💥
println("{s}", .{tag_name}); // Undefined behavior
```

## The Solution

We now provide **both safe and unsafe versions**:

### Unsafe (Fast) - For Immediate Use

```zig
/// ⚠️ WARNING: Borrows lexbor's memory - use immediately, don't store
pub fn tagName(element: *DomElement) []const u8
```

**Use when:**

- Immediate comparisons: `if (std.mem.eql(u8, tagName(elem), "DIV"))`
- Immediate printing: `print("Tag: {s}", .{tagName(elem)})`
- Short-lived operations within the same function

### Safe (Allocating) - For Storage

```zig
/// ✅ SAFE: Copies to Zig-owned memory - caller must free
pub fn tagNameOwned(allocator: std.mem.Allocator, element: *DomElement) ![]u8
```

**Use when:**

- Storing tag names in data structures
- Passing tag names across function boundaries
- Any case where the tag name might outlive the DOM operation

## Usage Patterns

### ✅ Pattern 1: Immediate Comparison (Safe with fast version)

```zig
var child = firstElementChild(parent);
while (child) |element| {
    const tag = tagName(element);  // Safe: immediate use
    if (std.mem.eql(u8, tag, "P")) {
        count += 1;
    }
    child = nextElementSibling(element);
}
```

### ✅ Pattern 2: Collecting for Later Use (Must use owned version)

```zig
var tag_names = std.ArrayList([]u8).init(allocator);
defer {
    for (tag_names.items) |tag| allocator.free(tag);
    tag_names.deinit();
}

var child = firstElementChild(parent);
while (child) |element| {
    const owned_tag = try tagNameOwned(allocator, element);
    try tag_names.append(owned_tag);
    child = nextElementSibling(element);
}

// Safe to use tag_names.items later
```

### ✅ Pattern 3: Utility Functions (Safe with fast version)

```zig
pub fn matchesTagName(element: *DomElement, tag_name: []const u8) bool {
    const tag = tagName(element);  // Safe: immediate comparison
    return std.mem.eql(u8, tag, tag_name);
}
```

## Available Functions

| Function | Safety | Performance | Use Case |
|----------|--------|-------------|----------|
| `nodeName()` | ⚠️ Unsafe | Fast | Immediate use only |
| `tagName()` | ⚠️ Unsafe | Fast | Immediate use only |
| `nodeName()` | ✅ Safe | Slower (alloc) | Storage, passing around |
| `tagNameOwned()` | ✅ Safe | Slower (alloc) | Storage, passing around |

## Key Takeaways

1. **Default to the fast versions** for immediate comparisons and printing
2. **Use owned versions** when storing tag names or passing them across function boundaries  
3. **Most existing code is probably safe** since tag names are typically used immediately
4. **Be careful with** data structures that store tag name slices
5. **This applies to all C interop** - always consider who owns the returned memory!

## Memory Management Rule

> **"If you get a pointer/slice from C, assume it's borrowed unless explicitly documented otherwise."**

This is a fundamental principle when working with C libraries from Zig. Always consider:

- Who allocates the memory?
- Who is responsible for freeing it?
- How long is the data valid?
