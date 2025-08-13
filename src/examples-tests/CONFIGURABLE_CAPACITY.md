# Configurable Default Collection Capacity

The `CapacityOpt` system in z-html now supports configurable default capacity for DOM collections.

## Overview

Previously, the default collection capacity was hardcoded to 10. Now you can:

- **Set a global default** that affects all future collections created with `.default` capacity
- **Get the current default** capacity setting  
- **Reset to the original default** (10) at any time

## Configuration Functions

```zig
// Set global default capacity (affects all future .default collections)
z.setDefaultCapacity(50);

// Get current default capacity
const current = z.getDefaultCapacity(); // Returns u8

// Reset to original default (10)
z.resetDefaultCapacity();
```

## Capacity Options

When creating collections, you have three options:

```zig
// 1. Single element (always capacity 1) - good for getElementById-style searches
const single_collection = z.createCollection(doc, .single);

// 2. Default capacity (uses global configurable default) 
const default_collection = z.createCollection(doc, .default);

// 3. Custom explicit capacity
const custom_collection = z.createCollection(doc, .{ .custom = .{ .value = 100 } });
```

## Usage Examples

### Basic Configuration

```zig
// Check initial default
std.debug.print("Default capacity: {}\n", .{z.getDefaultCapacity()}); // 10

// Change default for larger documents
z.setDefaultCapacity(100);

// All subsequent .default collections now use capacity 100
const elements = try z.getElementsByClassName(doc, "item"); // Uses capacity 100
defer z.destroyCollection(elements);

// Reset when done
z.resetDefaultCapacity(); // Back to 10
```

### Context-Specific Tuning

```zig
// For large documents with many search results
z.setDefaultCapacity(200);
const all_divs = try z.getElementsByTagName(doc, "DIV");
defer z.destroyCollection(all_divs);

// For memory-constrained environments  
z.setDefaultCapacity(5);
const limited_search = try z.getElementsByClassName(doc, "small-set");
defer z.destroyCollection(limited_search);

// For specific high-capacity needs (overrides default)
const big_search = try z.getElementsByAttributeName(doc, "data-id", .{ .custom = .{ .value = 500 } });
defer z.destroyCollection(big_search);
```

### Functions That Use Default Capacity

These functions respect the configurable default when using `.default` capacity:

- `z.getElementsByAttributeName(doc, attr_name, .default)`
- `z.createDefaultCollection(doc)`
- `z.createCollection(doc, .default)`

## When to Use Different Capacities

### `.single` (capacity 1)

- `getElementById` style searches (expecting 0-1 results)
- Unique element lookups
- Memory-critical scenarios

### `.default` (configurable, initially 10)

- General purpose searches
- Most `getElementsBy*` operations
- When you want consistent, tunable behavior

### `.custom` (explicit capacity)

- Known large result sets
- Performance-critical code with measured requirements
- Specific memory constraints

## Best Practices

1. **Set capacity based on document size**: Large documents benefit from higher default capacity
2. **Use custom capacity for known scenarios**: If you know you'll get ~50 results, set capacity accordingly  
3. **Reset after context changes**: Use `resetDefaultCapacity()` to return to baseline
4. **Profile your usage**: Measure actual collection sizes to optimize capacity settings

## Memory Considerations

- Higher capacity = more upfront memory allocation
- Lower capacity = potential reallocation overhead if exceeded
- Balance based on your typical result set sizes
- Collections grow automatically if needed, but pre-sizing improves performance

## Thread Safety

⚠️ **Note**: The global default capacity is a shared global variable. If using multiple threads, ensure proper synchronization when changing the default capacity.
