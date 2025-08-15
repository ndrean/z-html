# Zero-Copy vs Allocation Guidelines

## Quick Decision Matrix

### ✅ **USE Zero-Copy (`getTextContentBorrow`, `qualifiedNameBorrow`)** When:
- **Immediate processing** - text is used right away and discarded
- **Element lifetime guaranteed** - during DOM traversal loops
- **Performance-critical paths** - serialization, cleaning, comparison
- **No storage needed** - result doesn't outlive the function scope

### ❌ **DON'T USE Zero-Copy (use allocating versions)** When:
- **Long-term storage** - text becomes part of a data structure  
- **Return values** - function returns the text to caller
- **Async boundaries** - text crosses async/await boundaries
- **Processing needed** - text is modified, escaped, or transformed
- **Tree structures** - building JSON/tree representations

## Specific Function Analysis

### ✅ **Zero-Copy Functions (OPTIMIZED)**
```zig
// ✅ GOOD: Immediate processing, guaranteed element lifetime
pub fn isNoEscapeTextNode(node: *z.DomNode) bool {
    const parent = z.parentNode(node) orelse return false;
    if (z.nodeToElement(parent)) |parent_element| {
        const qualified_name = z.qualifiedNameBorrow(parent_element); // ✅ Zero-copy
        return z.isNoEscapeElementFast(qualified_name);
    }
    return false;
}

// ✅ GOOD: Immediate processing during serialization
pub fn appendNodeHtmlSmart(/*...*/) !void {
    if (z.getTextContentBorrow(node)) |text_content| { // ✅ Zero-copy
        // Process immediately during HTML generation
        try processTextImmediately(text_content);
    }
}

// ✅ GOOD: Immediate processing during cleaning
fn cleanNodeAdvanced(/*...*/) !void {
    if (z.getTextContentBorrow(node)) |text_content| { // ✅ Zero-copy
        const whitespace_size = leadingWhitespaceSize(text_content);
        // Immediate decision, no storage
    }
}
```

### ❌ **Allocating Functions (CORRECT CHOICE)**
```zig
// ❌ DON'T zero-copy: Returns owned string to caller
pub fn processTextContentSmart(allocator: std.mem.Allocator, node: *z.DomNode, skip_whitespace_only: bool) !?[]u8 {
    const text_content = try z.getTextContent(allocator, node); // ❌ Must allocate
    defer allocator.free(text_content);
    
    // ... processing ...
    return try allocator.dupe(u8, processed_text); // Returns owned string
}

// ❌ DON'T zero-copy: Text becomes part of tree structure
pub fn domNodeToTree(allocator: std.mem.Allocator, node: *z.DomNode) !HtmlNode {
    const text_content = try z.getTextContent(allocator, node); // ❌ Must allocate
    return HtmlNode{ .text = text_content }; // Text stored in tree
}

// ❌ DON'T zero-copy: Text needs processing and modification
fn maybeCleanOrRemoveTextNode(/*...*/) !bool {
    const text = try z.getTextContent(allocator, node); // ❌ Must allocate
    defer allocator.free(text);
    
    // Text is passed to normalizeWhitespace which needs to process it
    const cleaned = try normalizeWhitespace(allocator, text, options);
    // ...
}
```

## Performance Impact

### Zero-Copy Benefits:
- **No allocation overhead** - Direct memory access
- **No copy overhead** - Work with lexbor's buffers directly  
- **No deallocation** - No cleanup needed
- **Cache friendly** - Less memory churn

### Zero-Copy Risks:
- **Lifetime dependency** - Slice invalidated if DOM changes
- **Use-after-free** - If element is destroyed while holding slice
- **Memory corruption** - If lexbor reallocates internal buffers

## Best Practices

### 1. **DOM Traversal Loops** ✅
```zig
// ✅ PERFECT: Process nodes immediately during traversal
var child = z.firstChild(parent);
while (child != null) {
    if (z.getTextContentBorrow(child.?)) |text| {
        processImmediately(text); // Zero-copy safe
    }
    child = z.nextSibling(child.?);
}
```

### 2. **HTML Serialization** ✅  
```zig
// ✅ PERFECT: Generate HTML on-the-fly
fn nodeToHtmlWriter(node: HtmlNode, writer: anytype) !void {
    if (z.getTextContentBorrow(node)) |text| {
        try writer.writeAll(text); // Zero-copy safe
    }
}
```

### 3. **Tree Building** ❌
```zig
// ❌ WRONG: Don't use zero-copy for tree structures
fn buildTree(/*...*/) !Tree {
    const text = z.getTextContentBorrow(node); // ❌ BAD
    return Tree{ .content = text }; // ❌ Lifetime violation!
}

// ✅ CORRECT: Allocate for tree structures  
fn buildTree(/*...*/) !Tree {
    const text = try z.getTextContent(allocator, node); // ✅ GOOD
    return Tree{ .content = text }; // ✅ Safe, owned string
}
```

### 4. **Function Returns** ❌
```zig
// ❌ WRONG: Don't return borrowed slices
fn getText(node: *DomNode) []const u8 {
    return z.getTextContentBorrow(node) orelse ""; // ❌ Lifetime violation!
}

// ✅ CORRECT: Return owned strings
fn getText(allocator: Allocator, node: *DomNode) ![]u8 {
    return z.getTextContent(allocator, node); // ✅ Caller owns result
}
```

## Current Status

All z-html functions have been analyzed and optimized:

### ✅ **Optimized with Zero-Copy:**
- `isNoEscapeTextNode` (advanced_cleaner.zig)
- `isNoEscapeTextNode` (smart_text.zig) 
- `appendNodeHtmlSmart` (advanced_cleaner.zig)
- `appendRegularElementHtml` (advanced_cleaner.zig)
- `cleanNodeAdvanced` (advanced_cleaner.zig)

### ✅ **Correctly Using Allocation:**
- `processTextContentSmart` (smart_text.zig) - Returns owned strings
- `domNodeToTree` (dom_tree.zig) - Builds tree structures
- `domNodeToJson` (dom_tree.zig) - Builds JSON structures  
- `maybeCleanOrRemoveTextNode` (cleaner.zig) - Processes/modifies text
- `removeCommentWithSpacing` (cleaner.zig) - Builds new strings
- `setOrReplaceText` (core.zig) - Compares/processes text

## Rule of Thumb

**Ask yourself: "Does this text need to outlive the current function scope?"**
- **Yes** → Use allocating version (`getTextContent`, `qualifiedName`)
- **No** → Use zero-copy version (`getTextContentBorrow`, `qualifiedNameBorrow`)

The optimization provides significant performance gains for DOM processing while maintaining safety for data structures and return values.
