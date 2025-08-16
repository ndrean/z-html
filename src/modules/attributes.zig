//! HTMLElement Attribute functions
//! This module provides functions to manipulate and retrieve attributes from HTML elements.

const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

const testing = std.testing;
const print = std.debug.print;

pub const DomAttr = opaque {};
pub const DomCol = opaque {};

/// [attributes] Pair of attribute name and value
pub const AttributePair = struct {
    name: []const u8,
    value: []const u8,
};

// ----------------------------------------------------------
extern "c" fn lxb_dom_element_get_attribute(element: *z.DomElement, name: [*]const u8, name_len: usize, value_len: *usize) ?[*]const u8;
extern "c" fn lxb_dom_element_has_attributes(element: *z.DomElement) bool;
extern "c" fn lxb_dom_element_remove_attribute(element: *z.DomElement, qualified_name: [*]const u8, qn_len: usize) ?*anyopaque;
extern "c" fn lxb_dom_element_first_attribute_noi(element: *z.DomElement) ?*DomAttr;
extern "c" fn lxb_dom_element_next_attribute_noi(attr: *DomAttr) ?*DomAttr;
extern "c" fn lxb_dom_element_id_noi(element: *z.DomElement, len: *usize) [*]const u8;
extern "c" fn lxb_dom_element_class_noi(element: *z.DomElement, len: *usize) [*]const u8;
extern "c" fn lxb_dom_element_has_attribute(element: *z.DomElement, name: [*]const u8, name_len: usize) bool;
extern "c" fn lxb_dom_element_set_attribute(element: *z.DomElement, name: [*]const u8, name_len: usize, value: [*]const u8, value_len: usize) ?*anyopaque;
extern "c" fn lxb_dom_attr_qualified_name(attr: *DomAttr, length: *usize) [*]const u8;
extern "c" fn lxb_dom_attr_value_noi(attr: *DomAttr, length: *usize) [*]const u8;
extern "c" fn lxb_dom_element_qualified_name(element: *z.DomElement, len: *usize) [*:0]const u8;

// Fast DOM traversal for optimized ID search
extern "c" fn lxb_dom_node_simple_walk(root: *z.DomNode, walker_cb: *const fn (*z.DomNode, ?*anyopaque) callconv(.C) u32, ctx: ?*anyopaque) void;

// Walker callback return codes
const LEXBOR_ACTION_OK: u32 = 0;
const LEXBOR_ACTION_STOP: u32 = 1;

/// [attributes] Get attribute value
///
/// Returns null if attribute doesn't exist, empty string if attribute exists but has no value.
///
/// Caller needs to free the slice if not null
/// ## Example
/// ```
///  const element = try z.createElement(doc, "div", &.{.{.name = "class", .value = "card"}});
/// const class = try getAttribute(allocator, element, "class");
/// defer if (class != null) |c| {
///     allocator.free(c);
/// };
/// try testing.expectEqualStrings("card", c.?);
/// ```
///
pub fn getAttribute(allocator: std.mem.Allocator, element: *z.DomElement, name: []const u8) !?[]u8 {
    var value_len: usize = 0;
    const value_ptr = lxb_dom_element_get_attribute(
        element,
        name.ptr,
        name.len,
        &value_len,
    ) orelse return null;

    // If empty value, return empty string rather than null
    // This matches HTML behavior where attributes can have empty values
    const result = try allocator.alloc(u8, value_len);
    @memcpy(result, value_ptr[0..value_len]);
    return result;
}

// ----------------------------------------------------------

/// [attributes] Check if element has attribute
pub fn hasAttribute(element: *z.DomElement, name: []const u8) bool {
    return lxb_dom_element_has_attribute(
        element,
        name.ptr,
        name.len,
    );
}

/// [attributes] Attribute matcher function
pub fn matchesAttribute(element: *z.DomElement, attr_name: []const u8, attr_value: ?[]const u8) bool {
    if (!hasAttribute(element, attr_name)) return false;

    if (attr_value) |value| {
        const actual_value = elementGetNamedAttributeValue(element, attr_name) orelse return false;
        return std.mem.eql(u8, actual_value, value);
    }
    return true; // Just check for attribute existence
}

/// [attributes] Check if element has specific class ?????????????
pub fn hasClass(element: *z.DomElement, class_name: []const u8) bool {
    // Use a temporary allocator just for this check
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const temp_allocator = arena.allocator();

    // Get the class string using unified classList function
    const result = classList(temp_allocator, element, .string) catch return false;
    const class_attr = result.string orelse return false;

    // Search for the class name in the class list
    var iterator = std.mem.splitScalar(u8, class_attr, ' ');
    while (iterator.next()) |class| {
        // Trim whitespace and compare
        const trimmed_class = std.mem.trim(u8, class, " \t\n\r");
        if (std.mem.eql(u8, trimmed_class, class_name)) {
            return true;
        }
    }
    return false;
}

//  TO RE REMOVED
/// [attributes] Get all classes from element as an array - convenience wrapper
pub fn getClasses(allocator: std.mem.Allocator, element: *z.DomElement) ![][]u8 {
    const result = try classList(allocator, element, .array);
    return result.array;
}

// TO BE REMOVED
/// [utility] Get class string - convenience wrapper for backwards compatibility
pub fn getClassString(allocator: std.mem.Allocator, element: *z.DomElement) !?[]u8 {
    const result = try classList(allocator, element, .string);
    return result.string;
}

// ----------------------------------------------------------

/// [attributes] Set many attributes name/value on element
pub fn elementSetAttributes(element: *z.DomElement, attrs: []const AttributePair) !void {
    for (attrs) |attr| {
        const result = lxb_dom_element_set_attribute(
            element,
            attr.name.ptr,
            attr.name.len,
            attr.value.ptr,
            attr.value.len,
        );
        if (result == null) return Err.SetAttributeFailed;
    }
}

/// [attributes] Get attribute value as string
///
/// Consider using the "safe" `getAttribute`
///
/// ⚠️  WARNING: The returned slice points to lexbor's internal memory. (borrowed - don't free)
pub fn elementGetNamedAttributeValue(element: *z.DomElement, name: []const u8) ?[]const u8 {
    var value_len: usize = 0;
    const value_ptr = lxb_dom_element_get_attribute(
        element,
        name.ptr,
        name.len,
        &value_len,
    ) orelse return null;
    return value_ptr[0..value_len];
}

/// [attributes] Check if element has attributes
pub fn hasAttributes(element: *z.DomElement) bool {
    return lxb_dom_element_has_attributes(element);
}

// ----------------------------------------------------------

/// Get attribute name as owned string
///
/// Caller needs to free the slice
pub fn getAttributeName(allocator: std.mem.Allocator, attr: *DomAttr) ![]u8 {
    var name_len: usize = 0;
    const name_ptr = lxb_dom_attr_qualified_name(
        attr,
        &name_len,
    );

    const result = try allocator.alloc(u8, name_len);
    @memcpy(result, name_ptr[0..name_len]);
    return result;
}

/// [attributes] Get attribute value as owned string
///
/// Caller needs to free the slice
pub fn getAttributeValue(allocator: std.mem.Allocator, attr: *DomAttr) ![]u8 {
    var value_len: usize = 0;
    const value_ptr = lxb_dom_attr_value_noi(
        attr,
        &value_len,
    );

    const result = try allocator.alloc(u8, value_len);
    @memcpy(result, value_ptr[0..value_len]);
    return result;
}

/// [attributes] Collect all attributes from an element.
///
/// This function already includes an optimization: it uses getElementFirstAttribute()
/// which returns null for elements without any attributes, providing an early return.
/// This is equivalent to checking hasAttributes() first.
///
/// Caller needs to free the slice
pub fn getAttributes(allocator: std.mem.Allocator, element: *z.DomElement) ![]AttributePair {
    var attribute = getElementFirstAttribute(element);
    if (attribute == null) return &[_]AttributePair{}; // Early return for elements without attributes

    var attrs = std.ArrayList(AttributePair).init(allocator);
    defer attrs.deinit();

    while (attribute != null) {
        const name_copy = try getAttributeName(allocator, attribute.?);
        const value_copy = try getAttributeValue(allocator, attribute.?);

        try attrs.append(
            AttributePair{
                .name = name_copy,
                .value = value_copy,
            },
        );

        attribute = getElementNextAttribute(attribute.?);
    }

    return attrs.toOwnedSlice();
}

// ----------------------------------------------------------

/// [attributes] Remove attribute from element
///
/// Fails silently
pub fn removeAttribute(element: *z.DomElement, name: []const u8) !void {
    const result = lxb_dom_element_remove_attribute(
        element,
        name.ptr,
        name.len,
    );
    _ = result; // Ignore return.
}

// ----------------------------------------------------------

/// [attributes] Get first attribute of an HTMLElement
pub fn getElementFirstAttribute(element: *z.DomElement) ?*DomAttr {
    return lxb_dom_element_first_attribute_noi(element);
}

// ----------------------------------------------------------

/// [attributes] Get next attribute in the list gives an attribute
pub fn getElementNextAttribute(attr: *DomAttr) ?*DomAttr {
    return lxb_dom_element_next_attribute_noi(attr);
}

// ----------------------------------------------------------

/// [attributes] Get element ID as owned string
///
/// Caller needs to free the slice
pub fn getElementId(allocator: std.mem.Allocator, element: *z.DomElement) ![]u8 {
    var id_len: usize = 0;
    const id_ptr = lxb_dom_element_id_noi(
        element,
        &id_len,
    );

    const result = try allocator.alloc(u8, id_len);
    @memcpy(result, id_ptr[0..id_len]);
    return result;
}

/// Get the qualified name of an element (namespace:tagname or just tagname)
///
/// Get element's qualified name (allocating version)
///
/// This is useful for elements with namespaces like SVG or MathML.
/// Returns a newly allocated slice that the caller owns and must free.
///
/// **Use when:** You need to store the name beyond the element's lifetime
/// **Performance:** Slower (allocation + copy), but safe for long-term storage
///
/// ```zig
/// const name = try qualifiedName(allocator, element);
/// defer allocator.free(name); // You must free this
/// // Safe to use 'name' even after element is destroyed
/// ```
pub fn qualifiedName(allocator: std.mem.Allocator, element: *z.DomElement) ![]u8 {
    var name_len: usize = 0;
    const name_ptr = lxb_dom_element_qualified_name(element, &name_len);

    const result = try allocator.alloc(u8, name_len);
    @memcpy(result, name_ptr[0..name_len]);
    return result;
}

/// Get element's qualified name (zero-copy version)
///
/// Returns a slice directly into lexbor's internal memory - no allocation!
///
/// **Use when:** Processing immediately, element lifetime is guaranteed
/// **Performance:** Fastest (direct pointer access), but lifetime-bound
///
/// ⚠️  **LIFETIME WARNING:** The returned slice is only valid while:
/// - The element remains in the DOM tree
/// - The document is not destroyed
/// - No DOM modifications that might cause internal reallocation
///
/// ```zig
/// const name = qualifiedNameBorrow(element);
/// // Use immediately - don't store for later!
/// if (someCondition(name)) { ... }
/// ```
pub fn qualifiedNameBorrow(element: *z.DomElement) []const u8 {
    var name_len: usize = 0;
    const name_ptr = lxb_dom_element_qualified_name(element, &name_len);
    return name_ptr[0..name_len];
}

// /// Compare two lexbor strings with case sensitivity. Useless, Zig has built-in string comparison. !!!!!!!!!!!!!!!!!!!!!!!!!
// ///
// /// Useful for efficient string comparisons in DOM operations
pub fn compareStrings(first: []const u8, second: []const u8) bool {
    return std.mem.eql(u8, first, second);
}

// ----------------------------------------------------------

/// [attributes] Class list return type
pub const ClassListType = enum {
    string, // Return full class string
    array, // Return array of individual classes
};

/// [attributes] Class list enum result type.
///
/// Represents the two possible return types for the class list
/// (as a string or as an array)
pub const ClassListResult = union(ClassListType) {
    string: ?[]u8, // Full class string (null if no classes)
    array: [][]u8, // Array of individual classes (empty if no classes)
};

/// [attributes] Get element class as string or array - unified function
///
/// This is the primary class function that does everything:
/// - Copies to Zig-managed memory
/// - Can return either full string (option `.string`) or split array based on return_type
///
/// Caller needs to free the returned data appropriately
pub fn classList(allocator: std.mem.Allocator, element: *z.DomElement, return_type: ClassListType) !ClassListResult {
    var class_len: usize = 0;
    const class_ptr = lxb_dom_element_class_noi(
        element,
        &class_len,
    );

    // If no class or empty class
    if (class_len == 0) {
        return switch (return_type) {
            .string => ClassListResult{ .string = null },
            .array => ClassListResult{ .array = &[_][]u8{} },
        };
    }

    // Copy lexbor memory to Zig-managed memory
    const class_string = try allocator.alloc(u8, class_len);
    @memcpy(class_string, class_ptr[0..class_len]);

    return switch (return_type) {
        .string => ClassListResult{ .string = class_string },
        .array => blk: {
            // Split the string into array
            defer allocator.free(class_string); // Free the intermediate string

            var classes = std.ArrayList([]u8).init(allocator);
            defer classes.deinit();

            var iterator = std.mem.splitScalar(u8, class_string, ' ');
            while (iterator.next()) |class| {
                const trimmed_class = std.mem.trim(u8, class, " \t\n\r");
                if (trimmed_class.len > 0) {
                    const class_copy = try allocator.dupe(u8, trimmed_class);
                    try classes.append(class_copy);
                }
            }

            break :blk ClassListResult{ .array = try classes.toOwnedSlice() };
        },
    };
}

//=============================================================================
// OPTIMIZED DOM SEARCH USING WALKER CALLBACKS
//=============================================================================

/// Context for fast ID search using walker callback
const IdSearchContext = struct {
    target_id: []const u8,
    found_element: ?*z.DomElement,
};

/// Context for fast class search using walker callback
const ClassSearchContext = struct {
    target_class: []const u8,
    found_element: ?*z.DomElement,
};

/// Context for fast attribute search using walker callback
const AttributeSearchContext = struct {
    target_attr_name: []const u8,
    target_attr_value: ?[]const u8, // null means just check for attribute existence
    found_element: ?*z.DomElement,
};

/// Context for collecting multiple elements using walker callback
const MultiElementSearchContext = struct {
    target_attr_name: []const u8,
    target_attr_value: ?[]const u8, // null means just check for attribute existence
    target_class: ?[]const u8, // for class searches
    search_type: enum { attribute, class }, // what type of search we're doing
    allocator: std.mem.Allocator,
    results: std.ArrayList(*z.DomElement),
};

/// Fast walker callback for getElementById optimization
/// Returns LEXBOR_ACTION_STOP when ID is found, LEXBOR_ACTION_OK to continue
fn idWalkerCallback(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
    if (ctx == null) return LEXBOR_ACTION_OK;

    const search_ctx = @as(*IdSearchContext, @ptrCast(@alignCast(ctx.?)));

    // Only check element nodes
    if (!z.isTypeElement(node)) return LEXBOR_ACTION_OK;

    const element = z.nodeToElement(node) orelse return LEXBOR_ACTION_OK;

    // Check if this element has an ID attribute
    if (!hasAttribute(element, "id")) return LEXBOR_ACTION_OK;

    // Get the ID value (borrowed memory)
    const id_value = elementGetNamedAttributeValue(element, "id") orelse return LEXBOR_ACTION_OK;

    // Compare with target ID
    if (std.mem.eql(u8, id_value, search_ctx.target_id)) {
        search_ctx.found_element = element;
        return LEXBOR_ACTION_STOP; // Found it! Stop traversal
    }

    return LEXBOR_ACTION_OK; // Continue searching
}

/// Fast walker callback for class search optimization
/// Returns LEXBOR_ACTION_STOP when class is found, LEXBOR_ACTION_OK to continue
fn classWalkerCallback(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
    if (ctx == null) return LEXBOR_ACTION_OK;

    const search_ctx = @as(*ClassSearchContext, @ptrCast(@alignCast(ctx.?)));

    // Only check element nodes
    if (!z.isTypeElement(node)) return LEXBOR_ACTION_OK;

    const element = z.nodeToElement(node) orelse return LEXBOR_ACTION_OK;

    // Check if this element has a class attribute
    if (!hasAttribute(element, "class")) return LEXBOR_ACTION_OK;

    // Get the class value (borrowed memory)
    const class_value = elementGetNamedAttributeValue(element, "class") orelse return LEXBOR_ACTION_OK;

    // Search for the target class in the class list (space-separated)
    var iterator = std.mem.splitScalar(u8, class_value, ' ');
    while (iterator.next()) |class| {
        const trimmed_class = std.mem.trim(u8, class, " \t\n\r");
        if (std.mem.eql(u8, trimmed_class, search_ctx.target_class)) {
            search_ctx.found_element = element;
            return LEXBOR_ACTION_STOP; // Found it! Stop traversal
        }
    }

    return LEXBOR_ACTION_OK; // Continue searching
}

/// Fast walker callback for collecting multiple elements by attribute
/// Always returns LEXBOR_ACTION_OK to continue searching entire tree
fn multiElementAttributeWalkerCallback(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
    if (ctx == null) return LEXBOR_ACTION_OK;

    const search_ctx = @as(*MultiElementSearchContext, @ptrCast(@alignCast(ctx.?)));

    // Only check element nodes
    if (!z.isTypeElement(node)) return LEXBOR_ACTION_OK;

    const element = z.nodeToElement(node) orelse return LEXBOR_ACTION_OK;

    var matches = false;

    switch (search_ctx.search_type) {
        .attribute => {
            // Check if this element has the target attribute
            if (!hasAttribute(element, search_ctx.target_attr_name)) return LEXBOR_ACTION_OK;

            // If we only care about attribute existence (value is null), it matches
            if (search_ctx.target_attr_value == null) {
                matches = true;
            } else {
                // Otherwise, check the attribute value
                const attr_value = elementGetNamedAttributeValue(element, search_ctx.target_attr_name) orelse return LEXBOR_ACTION_OK;
                matches = std.mem.eql(u8, attr_value, search_ctx.target_attr_value.?);
            }
        },
        .class => {
            // Check if this element has a class attribute
            if (!hasAttribute(element, "class")) return LEXBOR_ACTION_OK;

            // Get the class value and search for the target class
            const class_value = elementGetNamedAttributeValue(element, "class") orelse return LEXBOR_ACTION_OK;

            var iterator = std.mem.splitScalar(u8, class_value, ' ');
            while (iterator.next()) |class| {
                const trimmed_class = std.mem.trim(u8, class, " \t\n\r");
                if (std.mem.eql(u8, trimmed_class, search_ctx.target_class.?)) {
                    matches = true;
                    break;
                }
            }
        },
    }

    if (matches) {
        // Add to results - ignore allocation errors to keep walking
        search_ctx.results.append(element) catch {};
    }

    return LEXBOR_ACTION_OK; // Always continue searching
}

/// Fast walker callback for attribute search optimization
/// Returns LEXBOR_ACTION_STOP when attribute is found, LEXBOR_ACTION_OK to continue
fn attributeWalkerCallback(node: *z.DomNode, ctx: ?*anyopaque) callconv(.C) u32 {
    if (ctx == null) return LEXBOR_ACTION_OK;

    const search_ctx = @as(*AttributeSearchContext, @ptrCast(@alignCast(ctx.?)));

    // Only check element nodes
    if (!z.isTypeElement(node)) return LEXBOR_ACTION_OK;

    const element = z.nodeToElement(node) orelse return LEXBOR_ACTION_OK;

    // Check if this element has the target attribute
    if (!hasAttribute(element, search_ctx.target_attr_name)) return LEXBOR_ACTION_OK;

    // If we only care about attribute existence (value is null), we found it
    if (search_ctx.target_attr_value == null) {
        search_ctx.found_element = element;
        return LEXBOR_ACTION_STOP;
    }

    // Otherwise, check the attribute value
    const attr_value = elementGetNamedAttributeValue(element, search_ctx.target_attr_name) orelse return LEXBOR_ACTION_OK;

    if (std.mem.eql(u8, attr_value, search_ctx.target_attr_value.?)) {
        search_ctx.found_element = element;
        return LEXBOR_ACTION_STOP; // Found it! Stop traversal
    }

    return LEXBOR_ACTION_OK; // Continue searching
}

/// [attributes] Fast getElementById using optimized DOM traversal
///
/// This is significantly faster than collection-based approaches because:
/// 1. Uses lxb_dom_node_simple_walk for efficient tree traversal
/// 2. Stops immediately when ID is found (early termination)
/// 3. Avoids collection allocation/deallocation overhead
/// 4. Direct memory comparison without intermediate allocations
///
/// Returns the first element with matching ID, or null if not found.
/// IDs should be unique in valid HTML, so first match is the correct result.
pub fn getElementByIdFast(doc: *z.HtmlDocument, id: []const u8) !?*z.DomElement {
    // Start search from document root to include head elements too
    const root_node = z.documentRoot(doc) orelse return null;

    var search_ctx = IdSearchContext{
        .target_id = id,
        .found_element = null,
    };

    // Walk the DOM tree with our callback
    lxb_dom_node_simple_walk(root_node, idWalkerCallback, &search_ctx);

    return search_ctx.found_element;
}

/// [attributes] Fast getElementByClass using optimized DOM traversal
///
/// Significantly faster than iterating through all elements and checking classes.
/// Uses the same optimization pattern as getElementByIdFast.
///
/// Returns the first element with matching class, or null if not found.
pub fn getElementByClassFast(doc: *z.HtmlDocument, class_name: []const u8) !?*z.DomElement {
    const root_node = z.documentRoot(doc) orelse return null;

    var search_ctx = ClassSearchContext{
        .target_class = class_name,
        .found_element = null,
    };

    lxb_dom_node_simple_walk(root_node, classWalkerCallback, &search_ctx);

    return search_ctx.found_element;
}

/// [attributes] Fast getElementByAttribute using optimized DOM traversal
///
/// Finds the first element with a specific attribute name and optionally a specific value.
/// If attr_value is null, only checks for attribute existence.
///
/// Returns the first matching element, or null if not found.
pub fn getElementByAttributeFast(doc: *z.HtmlDocument, attr_name: []const u8, attr_value: ?[]const u8) !?*z.DomElement {
    const root_node = z.documentRoot(doc) orelse return null;

    var search_ctx = AttributeSearchContext{
        .target_attr_name = attr_name,
        .target_attr_value = attr_value,
        .found_element = null,
    };

    lxb_dom_node_simple_walk(root_node, attributeWalkerCallback, &search_ctx);

    return search_ctx.found_element;
}

/// [attributes] Fast data attribute search - convenience wrapper
///
/// Searches for elements with data-* attributes (common in modern web development).
/// Example: getElementByDataAttributeFast(doc, "id", "123") finds elements with data-id="123"
pub fn getElementByDataAttributeFast(doc: *z.HtmlDocument, data_name: []const u8, value: ?[]const u8) !?*z.DomElement {
    // Build the full data attribute name
    var attr_name_buffer: [256]u8 = undefined;
    const attr_name = try std.fmt.bufPrint(attr_name_buffer[0..], "data-{s}", .{data_name});

    return getElementByAttributeFast(doc, attr_name, value);
}

//=============================================================================
// WALKER-BASED MULTIPLE RESULTS (Alternative to Collections)
//=============================================================================

/// [attributes] Find ALL elements with specific class using walker (alternative to collection)
///
/// This is a walker-based alternative to the collection-based getElementsByClassName.
/// Potentially faster for large DOMs as it avoids collection overhead.
///
/// Caller must free the returned slice.
pub fn getElementsByClassWalker(allocator: std.mem.Allocator, doc: *z.HtmlDocument, class_name: []const u8) ![]const *z.DomElement {
    const root_node = z.documentRoot(doc) orelse return &[_]*z.DomElement{};

    var search_ctx = MultiElementSearchContext{
        .target_attr_name = undefined, // Not used for class search
        .target_attr_value = undefined, // Not used for class search
        .target_class = class_name,
        .search_type = .class,
        .allocator = allocator,
        .results = std.ArrayList(*z.DomElement).init(allocator),
    };
    defer search_ctx.results.deinit();

    lxb_dom_node_simple_walk(root_node, multiElementAttributeWalkerCallback, &search_ctx);

    return search_ctx.results.toOwnedSlice();
}

/// [attributes] Find ALL elements with specific attribute using walker (alternative to collection)
///
/// This is a walker-based alternative to collection-based attribute searching.
/// Can search by attribute existence (attr_value = null) or specific values.
///
/// Caller must free the returned slice.
pub fn getElementsByAttributeWalker(allocator: std.mem.Allocator, doc: *z.HtmlDocument, attr_name: []const u8, attr_value: ?[]const u8) ![]const *z.DomElement {
    const root_node = z.documentRoot(doc) orelse return &[_]*z.DomElement{};

    var search_ctx = MultiElementSearchContext{
        .target_attr_name = attr_name,
        .target_attr_value = attr_value,
        .target_class = undefined, // Not used for attribute search
        .search_type = .attribute,
        .allocator = allocator,
        .results = std.ArrayList(*z.DomElement).init(allocator),
    };
    defer search_ctx.results.deinit();

    lxb_dom_node_simple_walk(root_node, multiElementAttributeWalkerCallback, &search_ctx);

    return search_ctx.results.toOwnedSlice();
}

/// [attributes] Find ALL elements with specific data-* attribute using walker
///
/// Convenience wrapper for data attribute searching.
/// Example: getElementsByDataAttributeWalker(allocator, doc, "category", "tech")
///          finds all elements with data-category="tech"
///
/// Caller must free the returned slice.
pub fn getElementsByDataAttributeWalker(allocator: std.mem.Allocator, doc: *z.HtmlDocument, data_name: []const u8, value: ?[]const u8) ![]const *z.DomElement {
    // Build the full data attribute name
    var attr_name_buffer: [256]u8 = undefined;
    const attr_name = try std.fmt.bufPrint(attr_name_buffer[0..], "data-{s}", .{data_name});

    return getElementsByAttributeWalker(allocator, doc, attr_name, value);
} // ----------------------------------------------------------
// TESTS
// ----------------------------------------------------------

test "element / attribute  name & value" {
    const allocator = testing.allocator;

    const html = "<div class='test' id='my-id' data-value='123' title='tooltip' hidden>Content</div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);
    const body_node = try z.bodyNode(doc);
    const div = z.firstChild(body_node).?;
    const div_elt = z.nodeToElement(div).?;

    // Get ID attribute from an element
    const id = try getElementId(allocator, div_elt);
    defer allocator.free(id);
    try testing.expectEqualStrings(id, "my-id");

    // Get class attribute from an element using unified classList
    const class_result = try classList(allocator, div_elt, .string);
    const class = class_result.string.?;
    defer allocator.free(class);
    try testing.expectEqualStrings(class, "test");

    // get attribute name and value
    const first = z.getElementFirstAttribute(div_elt).?;
    const name = try z.getAttributeName(allocator, first);
    defer allocator.free(name);
    try testing.expectEqualStrings(name, "class");
    const value = try z.getAttributeValue(allocator, first);
    defer allocator.free(value);
    try testing.expectEqualStrings("test", value);
}

test "collect  attributes" {
    const allocator = testing.allocator;

    const html = "<div class='test' id='my-id' data-value='123' title='tooltip' hidden>Content</div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);
    const body_node = try z.bodyNode(doc);
    const div = z.firstChild(body_node).?;
    const div_elt = z.nodeToElement(div).?;

    const attrs = try getAttributes(allocator, div_elt);
    defer {
        for (attrs) |attr| {
            allocator.free(attr.name);
            allocator.free(attr.value);
        }
        allocator.free(attrs);
    }

    const expected_names = [_][]const u8{ "class", "id", "data-value", "title", "hidden" };
    const expected_values = [_][]const u8{ "test", "my-id", "123", "tooltip", "" };

    for (attrs, 0..) |attr_pair, i| {
        _ = i; // Unused index
        // print("Attribute {}: {s} = {s}\n", .{ i, attr_pair.name, attr_pair.value });

        // Find this attribute in expected lists
        var found = false;
        for (expected_names, 0..) |expected_name, j| {
            if (std.mem.eql(u8, attr_pair.name, expected_name)) {
                try testing.expectEqualStrings(expected_values[j], attr_pair.value);
                found = true;
                break;
            }
        }
        try testing.expect(found);
    }
}

test "named attribute operations" {
    const allocator = testing.allocator;

    const html = "<div class='container test' id='main-div' data-value='123' title='tooltip'>Content</div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const body_node = z.elementToNode(body);
    const div_node = z.firstChild(body_node).?;
    const div_element = z.nodeToElement(div_node).?;

    // Test hasAttribute
    try testing.expect(z.hasAttribute(div_element, "class"));
    try testing.expect(z.hasAttribute(div_element, "id"));
    try testing.expect(z.hasAttribute(div_element, "data-value"));
    try testing.expect(!z.hasAttribute(div_element, "nonexistent"));

    // Test getAttribute (owned memory)
    if (try getAttribute(allocator, div_element, "class")) |class_value| {
        defer allocator.free(class_value);
        try testing.expectEqualStrings("container test", class_value);
    }

    if (try getAttribute(allocator, div_element, "id")) |id_value| {
        defer allocator.free(id_value);
        try testing.expectEqualStrings("main-div", id_value);
    }

    // Test borrowed attribute value
    if (try z.getAttribute(allocator, div_element, "data-value")) |data_value| {
        defer allocator.free(data_value);
        try testing.expectEqualStrings("123", data_value);
        // print("Data (borrowed): '{s}'\n", .{data_value});
    }

    // Test non-existent attribute
    const missing = try getAttribute(allocator, div_element, "missing");
    try testing.expect(missing == null);

    // print("✅ Named attribute operations work!\n", .{});
}

test "attribute modification" {
    const allocator = testing.allocator;

    const html = "<p>Original content</p>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body_node = try z.bodyNode(doc);
    const p_node = z.firstChild(body_node).?;
    const p_element = z.nodeToElement(p_node).?;

    try z.setAttribute(
        p_element,
        &.{
            .{ .name = "id", .value = "my-paragraph" },
            .{ .name = "class", .value = "content" },
            .{ .name = "data-test", .value = "example" },
        },
    );

    try testing.expect(z.hasAttribute(p_element, "id"));
    try testing.expect(z.hasAttribute(p_element, "class"));
    try testing.expect(z.hasAttribute(p_element, "data-test"));

    if (try getAttribute(allocator, p_element, "id")) |id| {
        defer allocator.free(id);
        try testing.expectEqualStrings("my-paragraph", id);
    }

    // Modify existing attribute
    try z.setAttribute(
        p_element,
        &.{
            .{ .name = "id", .value = "modified-paragraph" },
        },
    );

    if (try getAttribute(allocator, p_element, "id")) |modified_id| {
        defer allocator.free(modified_id);
        try testing.expectEqualStrings(
            "modified-paragraph",
            modified_id,
        );
    }

    // Remove attribute
    try z.removeAttribute(p_element, "class");
    try testing.expect(!z.hasAttribute(p_element, "class"));

    // Verify other attributes still exist
    try testing.expect(z.hasAttribute(p_element, "id"));
    try testing.expect(z.hasAttribute(p_element, "data-test"));

    // print("✅ Attribute modification works\n", .{});
}

test "attribute iteration" {
    const allocator = testing.allocator;

    const html = "<div class='test' id='main' data-value='123' title='tooltip' hidden>Content</div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body_node = try z.bodyNode(doc);
    const div_node = z.firstChild(body_node);
    const div_element = z.nodeToElement(div_node.?).?;

    // Manual check of expected attributes
    const expected_attrs = [_][]const u8{ "class", "id", "data-value", "title", "hidden" };
    var found_count: usize = 0;

    for (expected_attrs) |attr_name| {
        if (z.hasAttribute(div_element, attr_name)) {
            found_count += 1;

            if (try getAttribute(allocator, div_element, attr_name)) |value| {
                defer allocator.free(value);
                try testing.expectEqualStrings(
                    value,
                    elementGetNamedAttributeValue(
                        div_element,
                        attr_name,
                    ).?,
                );
            }
        }
    }

    try testing.expect(found_count == 5);
    // print("✅ Found attributes\n", .{});
}

test "ID and CLASS attribute getters" {
    const allocator = testing.allocator;

    const html = "<section class='main-section' id='content'>Section content</section>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body_node = try z.bodyNode(doc);
    const section_node = z.firstChild(body_node);
    const section_element = z.nodeToElement(section_node.?).?;

    // Test ID getter
    const id = try getElementId(allocator, section_element);
    defer allocator.free(id);
    try testing.expectEqualStrings("content", id);

    // Test class getter using unified classList
    const class_result = try classList(allocator, section_element, .string);
    const class = class_result.string.?;
    defer allocator.free(class);
    try testing.expectEqualStrings("main-section", class);

    // print("✅ ID and CLASS attribute getters\n", .{});
}

test "attribute edge cases" {
    const allocator = testing.allocator;

    const html = "<div data-empty='' title='  spaces  '>Content</div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const body_node = z.elementToNode(body);
    const div_node = z.firstChild(body_node).?;
    const div_element = z.nodeToElement(div_node).?;

    // print("\n=== Attribute Edge Cases ===\n", .{});

    // Empty attribute value
    if (try getAttribute(
        allocator,
        div_element,
        "data-empty",
    )) |empty_value| {
        defer allocator.free(empty_value);
        try testing.expectEqualStrings("", empty_value);
        // print("Empty attribute: '{s}' (length: {d})\n", .{ empty_value, empty_value.len });
    }

    // Attribute with spaces
    if (try getAttribute(
        allocator,
        div_element,
        "title",
    )) |title_value| {
        defer allocator.free(title_value);
        try testing.expectEqualStrings("  spaces  ", title_value);
        // print("Spaced attribute: '{s}' (length: {})\n", .{ title_value, title_value.len });
    }

    // Test setting empty value
    try z.setAttribute(div_element, &.{.{ .name = "new-empty", .value = "" }});
    try testing.expect(hasAttribute(div_element, "new-empty"));

    if (try getAttribute(
        allocator,
        div_element,
        "new-empty",
    )) |new_empty| {
        defer allocator.free(new_empty);
        try testing.expectEqualStrings("", new_empty);
    }

    // print("✅ Edge cases handled correctly!\n", .{});
}

test "optimized walker-based search functions" {
    // Create a comprehensive test document
    const html =
        \\<html>
        \\<head><title>Test Document</title></head>
        \\<body>
        \\  <div id="header" class="navigation top-level" data-section="header">
        \\    <nav class="menu">
        \\      <a href="/home" class="nav-link active" data-page="home">Home</a>
        \\      <a href="/about" class="nav-link" data-page="about">About</a>
        \\    </nav>
        \\  </div>
        \\  <main id="content" class="main-content" data-section="content">
        \\    <article class="post featured" data-id="123" data-category="tech">
        \\      <h1 class="title">Article Title</h1>
        \\      <p class="intro">Introduction paragraph</p>
        \\    </article>
        \\    <aside class="sidebar" data-widget="recent-posts">
        \\      <div class="widget" data-type="list">Widget Content</div>
        \\    </aside>
        \\  </main>
        \\  <footer id="footer" class="bottom-section" data-section="footer">
        \\    <span class="copyright">© 2025</span>
        \\  </footer>
        \\</body>
        \\</html>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Test 1: getElementByIdFast - should find elements by ID
    const header = try getElementByIdFast(doc, "header");
    try testing.expect(header != null);
    try testing.expectEqualStrings("DIV", z.tagNameBorrow(header.?));

    const content = try getElementByIdFast(doc, "content");
    try testing.expect(content != null);
    try testing.expectEqualStrings("MAIN", z.tagNameBorrow(content.?));

    const footer = try getElementByIdFast(doc, "footer");
    try testing.expect(footer != null);
    try testing.expectEqualStrings("FOOTER", z.tagNameBorrow(footer.?));

    // Test 2: getElementByClassFast - should find first element with class
    const nav_link = try getElementByClassFast(doc, "nav-link");
    try testing.expect(nav_link != null);
    try testing.expectEqualStrings("A", z.tagNameBorrow(nav_link.?));

    const post = try getElementByClassFast(doc, "post");
    try testing.expect(post != null);
    try testing.expectEqualStrings("ARTICLE", z.tagNameBorrow(post.?));

    const widget = try getElementByClassFast(doc, "widget");
    try testing.expect(widget != null);
    try testing.expectEqualStrings("DIV", z.tagNameBorrow(widget.?));

    // Test 3: getElementByAttributeFast - attribute existence only
    const href_element = try getElementByAttributeFast(doc, "href", null);
    try testing.expect(href_element != null);
    try testing.expectEqualStrings("A", z.tagNameBorrow(href_element.?));

    // Test 4: getElementByAttributeFast - attribute with specific value
    const home_link = try getElementByAttributeFast(doc, "href", "/home");
    try testing.expect(home_link != null);
    try testing.expectEqualStrings("A", z.tagNameBorrow(home_link.?));

    const about_link = try getElementByAttributeFast(doc, "href", "/about");
    try testing.expect(about_link != null);
    try testing.expectEqualStrings("A", z.tagNameBorrow(about_link.?));

    // Test 5: getElementByDataAttributeFast - data attributes
    const header_section = try getElementByDataAttributeFast(doc, "section", "header");
    try testing.expect(header_section != null);
    try testing.expectEqualStrings("DIV", z.tagNameBorrow(header_section.?));

    const home_page = try getElementByDataAttributeFast(doc, "page", "home");
    try testing.expect(home_page != null);
    try testing.expectEqualStrings("A", z.tagNameBorrow(home_page.?));

    const tech_article = try getElementByDataAttributeFast(doc, "category", "tech");
    try testing.expect(tech_article != null);
    try testing.expectEqualStrings("ARTICLE", z.tagNameBorrow(tech_article.?));

    // Test 6: Non-existent searches should return null
    const missing_id = try getElementByIdFast(doc, "nonexistent");
    try testing.expect(missing_id == null);

    const missing_class = try getElementByClassFast(doc, "nonexistent-class");
    try testing.expect(missing_class == null);

    const missing_attr = try getElementByAttributeFast(doc, "nonexistent-attr", "value");
    try testing.expect(missing_attr == null);

    const missing_data = try getElementByDataAttributeFast(doc, "nonexistent", "value");
    try testing.expect(missing_data == null);
}

test "walker-based search vs existing implementations comparison" {
    const allocator = testing.allocator;

    const html =
        \\<div class="container">
        \\  <p id="paragraph1" class="text intro">First paragraph</p>
        \\  <span class="text highlight" data-priority="high">Important text</span>
        \\  <div class="box" data-type="info">Info box</div>
        \\</div>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Compare ID search methods
    const element_fast = try getElementByIdFast(doc, "paragraph1");
    const element_collection = try z.getElementById(doc, "paragraph1");

    try testing.expect(element_fast != null);
    try testing.expect(element_collection != null);
    try testing.expect(element_fast.? == element_collection.?);

    // Test class search - walker vs manual iteration
    const class_fast = try getElementByClassFast(doc, "text");
    try testing.expect(class_fast != null);
    try testing.expectEqualStrings("P", z.tagNameBorrow(class_fast.?));

    // Verify the found element actually has the class
    try testing.expect(hasClass(class_fast.?, "text"));

    // Test data attribute search
    const data_element = try getElementByDataAttributeFast(doc, "priority", "high");
    try testing.expect(data_element != null);
    try testing.expectEqualStrings("SPAN", z.tagNameBorrow(data_element.?));

    // Verify the data attribute value using allocator
    if (try getAttribute(allocator, data_element.?, "data-priority")) |priority| {
        defer allocator.free(priority);
        try testing.expectEqualStrings("high", priority);
    }

    // Test content verification using allocator
    const content = try z.getTextContent(allocator, z.elementToNode(data_element.?));
    defer allocator.free(content);
    try testing.expectEqualStrings("Important text", content);
}

test "collection vs walker - when collections are still useful" {
    const allocator = testing.allocator;

    const html =
        \\<html><body>
        \\  <div data-id="42">Exact match</div>
        \\  <div data-id="142">Partial match</div>
        \\  <div data-id="420">Partial match</div>
        \\  <div data-category="electronics">Category</div>
        \\</body></html>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // std.debug.print("\n=== When Collections Excel ===\n", .{});

    // Test exact attribute value matching where collections work well
    const walker_data_42 = try getElementsByDataAttributeWalker(allocator, doc, "id", "42");
    defer allocator.free(walker_data_42);

    // For exact data-id matching, let's use getElementsByAttributePair directly
    const collection_data_42 = try z.getElementsByAttributePair(doc, .{ .name = "data-id", .value = "42" }, false);
    const collection_data_42_count = if (collection_data_42) |coll| blk: {
        defer z.destroyCollection(coll);
        break :blk z.collectionLength(coll);
    } else 0;

    // std.debug.print("Exact data-id='42' matching:\n", .{});
    // std.debug.print("  Walker: {} elements\n", .{walker_data_42.len});
    // std.debug.print("  Collection: {} elements\n", .{collection_data_42_count});

    // Both should find exactly 1 element
    try testing.expect(walker_data_42.len == 1);
    try testing.expect(collection_data_42_count == 1);

    // std.debug.print("\n📊 Summary:\n", .{});
    // std.debug.print("• Walker: Better for CSS classes (token-based)\n", .{});
    // std.debug.print("• Collection: Better for exact attribute values\n", .{});
    // std.debug.print("• Walker: Better for single-element searches (early exit)\n", .{});
    // std.debug.print("• Collection: Better for bulk operations on known large result sets\n", .{});
}
test "getElementById vs getElementByIdFast comparison" {
    const allocator = testing.allocator;

    const html = "<div><p id='test-element'>Hello World</p></div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Test that both methods find the same element
    const element_fast = try getElementByIdFast(doc, "test-element");
    const element_collection = try z.getElementById(doc, "test-element");

    try testing.expect(element_fast != null);
    try testing.expect(element_collection != null);

    // They should be the same element (same memory address)
    try testing.expect(element_fast.? == element_collection.?);

    // Verify content is correct
    const text = try z.getTextContent(allocator, z.elementToNode(element_fast.?));
    defer allocator.free(text);
    try testing.expectEqualStrings("Hello World", text);
}

test "getElementById performance comparison" {
    const allocator = testing.allocator;

    // Create a larger document with many elements to see performance difference
    var html_buffer = std.ArrayList(u8).init(allocator);
    defer html_buffer.deinit();

    const writer = html_buffer.writer();
    try writer.writeAll("<html><body>");

    // Add many elements before the target
    for (0..1000) |i| {
        try writer.print("<div class='element-{}'>Element {}</div>", .{ i, i });
    }

    // Add target element near the end
    try writer.writeAll("<p id='target-element'>This is the target</p>");

    // Add some more elements after target
    for (0..100) |i| {
        try writer.print("<span class='after-{}'>After {}</span>", .{ i, i });
    }

    try writer.writeAll("</body></html>");

    const html = try html_buffer.toOwnedSlice();
    defer allocator.free(html);

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Test both methods find the same element
    const fast_result = try getElementByIdFast(doc, "target-element");
    const collection_result = try z.getElementById(doc, "target-element");

    try testing.expect(fast_result != null);
    try testing.expect(collection_result != null);
    try testing.expect(fast_result.? == collection_result.?);

    // Verify we found the correct element
    const content = try z.getTextContent(allocator, z.elementToNode(fast_result.?));
    defer allocator.free(content);
    try testing.expectEqualStrings("This is the target", content);

    // print("✅ Both methods found the same element with {} total DOM nodes\n", .{1101});
}

test "elementHasNamedAttribute - isolated test" {
    const html = "<div id='test-div' class='example'>Simple content</div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const body_node = z.elementToNode(body);
    const div_node = z.firstChild(body_node).?;
    const div_element = z.nodeToElement(div_node).?;

    // print("\n=== Testing elementHasNamedAttribute in isolation ===\n", .{});

    // Test basic functionality
    // print("Testing 'id' attribute...\n", .{});
    const has_id = hasAttribute(div_element, "id");
    try testing.expect(has_id);
    // print("✅ Has 'id' attribute: {}\n", .{has_id});

    // print("Testing 'class' attribute...\n", .{});
    const has_class = hasAttribute(div_element, "class");
    try testing.expect(has_class);
    // print("✅ Has 'class' attribute: {}\n", .{has_class});

    // print("Testing 'missing' attribute...\n", .{});
    const has_missing = hasAttribute(div_element, "missing");
    try testing.expect(!has_missing);
    // print("✅ Has 'missing' attribute: {}\n", .{has_missing});

    // print("✅ elementHasNamedAttribute isolated test passed!\n", .{});
}

test "attribute error handling" {
    // you can't see attributes on text nodes (non-element node)
    const allocator = testing.allocator;

    const html = "<div>Test</div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body_node = try z.bodyNode(doc);
    const div_node = z.firstChild(body_node).?;
    const div_element = z.nodeToElement(div_node).?;

    // Test setting attribute on non-element node should return null
    const text_node = z.firstChild(div_node).?;
    const text_element = z.nodeToElement(text_node);

    // With our fix, nodeToElement should return null for text nodes
    try testing.expect(text_element == null);

    // Since text_element is null, we can't set attributes on it
    // This test now verifies that nodeToElement correctly returns null for text nodes

    // Test getting non-existent attribute returns NULL
    const missing_attr = try getAttribute(
        allocator,
        div_element,
        "missing",
    );
    try testing.expect(missing_attr == null);
    // print("✅ Error handling works!\n", .{});
}
