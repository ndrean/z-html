# HTML Processing Phases in z-html

This document explains the three distinct phases of HTML processing in z-html and when to use `normalizer.zig` vs `smart_text.zig` vs `html_tags.zig`.

## 🔄 The Three Phases

### Phase 1: HTML String → DOM Parsing

```zig
const html = "<my-widget><script>alert('xss')</script></my-widget>";
const doc = try z.parseFromString(html);  // ← Lexbor parses structure
```

**What happens:**

- ✅ Lexbor creates DOM nodes from HTML string
- ✅ No security decisions made yet - just structural parsing
- ✅ `<script>` becomes a real DOM element with text content
- ⚠️ **Scripts don't execute in Zig** - but they will if sent to browser!

### Phase 2: DOM Normalization (normalizer.zig)

```zig
// Clean up EXISTING DOM structure
try normalizer.cleanDomTree(allocator, root_node, .{
    .remove_comments = true,
    .remove_empty_elements = true,
    .keep_new_lines = false
});
```

**Purpose:** Fix messy existing HTML structure

- 🧹 Remove comments, empty elements
- 🧹 Normalize whitespace in text nodes
- 🧹 Clean up malformed attributes
- ❌ **NO ESCAPING** - this is for existing parsed content

**Example:**

```html
<!-- Input DOM (already parsed) -->
<div   class=" test "  >
    <p>   Hello    World   </p>
    <!-- comment -->
    <span></span>
</div>

<!-- Output after normalization -->
<div class="test">
    <p>Hello World</p>
</div>
```

### Phase 3: DOM → HTML Serialization (smart_text.zig + html_tags.zig)

```zig
// When converting DOM back to HTML string for browser
if (isNoEscapeElementFastZeroCopy(element)) {
    // Don't escape: <script>, <style>, <iframe>
    output = raw_content;
} else {
    // DO escape: <my-widget>, <div>, custom elements
    output = try escapeHtmlSmart(allocator, raw_content);
}
```

**Purpose:** Safe HTML generation for browsers

- 🔒 **SECURITY CRITICAL** - decides what gets escaped
- 🔒 Standard tags (`<script>`) get raw content (functional)
- 🔒 Custom elements (`<my-widget>`) get escaped content (safe)

## 📚 Module Responsibilities

### `normalizer.zig` (formerly cleaner.zig)

- **When:** Working with existing DOM that's already parsed
- **Goal:** Clean up messy structure, normalize whitespace
- **Safety:** No escaping needed - content is already in DOM
- **Example:** CMS content cleanup, HTML tidy operations

```zig
// Normalize existing DOM structure
const messy_dom = parseFromString(user_uploaded_html);
try normalizer.cleanDomTree(allocator, messy_dom, .{
    .remove_comments = true,
    .remove_empty_elements = true
});
```

### `smart_text.zig`

- **When:** Inserting NEW content into DOM or serializing DOM to HTML
- **Goal:** Context-aware escaping for security
- **Safety:** Critical for preventing XSS when outputting to browsers
- **Example:** Template engines, user input insertion

```zig
// Safely insert new user content
const user_input = "<script>alert('xss')</script>";
const safe_content = try smart_text.escapeHtmlSmart(allocator, user_input);
// Result: "&lt;script&gt;alert('xss')&lt;/script&gt;"
```

### `html_tags.zig`

- **When:** Need to know how to handle specific HTML elements
- **Goal:** Provide element-specific behavior rules
- **Safety:** Guidance system for other modules
- **Example:** "Should this element's content be escaped?"

```zig
// Query element behavior
if (isNoEscapeElementFast("script")) {
    // Don't escape - JavaScript needs to work
} else if (isNoEscapeElementFast("my-widget")) {
    // DO escape - custom elements are safer escaped
}
```

## 🚨 Security Flow Example

```zig
// 1. USER SUBMITS DANGEROUS CONTENT
const user_input = "<my-widget><script>steal_cookies()</script></my-widget>";

// 2. PARSE TO DOM (Phase 1)
const doc = try parseFromString(user_input);
// ↳ Creates DOM structure, scripts don't execute in Zig

// 3. OPTIONAL: NORMALIZE DOM (Phase 2)
try normalizer.cleanDomTree(allocator, doc, .{ .remove_comments = true });
// ↳ Clean up structure, but no escaping

// 4. SERIALIZE FOR BROWSER (Phase 3) - CRITICAL SECURITY POINT
const html_output = try serializeWithEscaping(doc);
// ↳ Uses html_tags.zig + smart_text.zig for safe output

// 5. SEND TO BROWSER
// ✅ Safe: "<my-widget>&lt;script&gt;steal_cookies()&lt;/script&gt;</my-widget>"
// ❌ Dangerous: "<my-widget><script>steal_cookies()</script></my-widget>"
```

## 🎯 When to Use What

| Scenario | Module | Purpose |
|----------|--------|---------|
| Clean up uploaded HTML | `normalizer.zig` | Structure cleanup |
| Insert user comments | `smart_text.zig` | Safe text insertion |
| Template rendering | `smart_text.zig` | Context-aware escaping |
| Element behavior query | `html_tags.zig` | Get element rules |
| CMS content processing | `normalizer.zig` → `smart_text.zig` | Clean then safely output |

## 🔑 Key Insights

1. **Normalizer is for structure** - cleaning up DOM that's already safe to parse
2. **Smart text is for content** - making new content safe for browsers  
3. **HTML tags is for rules** - telling other modules how to handle elements
4. **Security happens at serialization** - not during parsing or normalization
5. **Scripts are dangerous in browsers** - not in your Zig server environment

The security boundary is **your server → browser**, not **input → your server**.
