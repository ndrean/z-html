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

/// [attributes] Get attribute value
///
/// Returns `null` if attribute doesn't exist, empty string `""` if attribute exists but has no value.
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
/// ----
/// ```
pub fn getAttribute(allocator: std.mem.Allocator, element: *z.DomElement, name: []const u8) !?[]u8 {
    var value_len: usize = 0;
    const value_ptr = lxb_dom_element_get_attribute(
        element,
        name.ptr,
        name.len,
        &value_len,
    ) orelse return null;

    // If empty value, return empty string rather than null (HTML behaviour)
    const result = try allocator.alloc(u8, value_len);
    @memcpy(result, value_ptr[0..value_len]);
    return result;
}

/// [attributes] Get attribute value as borrowed slice (zero-copy)
///
/// Returns a slice directly into lexbor's internal memory - no allocation!
///
///  ⚠️ pointing to lexbor memory. Short-lived uses only.
///
/// Use `getAttribute()` if you need to store the value.
pub fn getAttribute_zc(element: *z.DomElement, name: []const u8) ?[]const u8 {
    var value_len: usize = 0;
    const value_ptr = lxb_dom_element_get_attribute(
        element,
        name.ptr,
        name.len,
        &value_len,
    ) orelse return null;
    return value_ptr[0..value_len];
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

/// [attributes] Check if element has attributes
pub fn hasAttributes(element: *z.DomElement) bool {
    return lxb_dom_element_has_attributes(element);
}

// ----------------------------------------------------------

/// [attributes] Set many attributes name/value pairs on element
///
/// ## Example
/// ```
/// const element = try z.createElement(doc, "div", &.{});
/// try z.setAttributes(element, &.{
///     .{.name = "id", .value = "main"},
///     ?{.name = "id", .value = "main"}
/// });
/// try testing.expect(z.hasAttribute(element, "id"));
/// try testing.expectEqualStrings("main", z.getAttribute(element, "id"));
/// ---
/// ```
pub fn setAttributes(element: *z.DomElement, attrs: []const AttributePair) !void {
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

// ----------------------------------------------------------
// Reflexion function on the `DomAttr` struct
//
// and functions to iterate over attributes
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

/// [attributes] Get first attribute of an HTMLElement
///
/// Returns a DomAttr
pub fn getFirstAttribute(element: *z.DomElement) ?*DomAttr {
    return lxb_dom_element_first_attribute_noi(element);
}

// ----------------------------------------------------------

/// [attributes] Get next attribute in the list gives an attribute
///
/// Returns a DomAttr
pub fn getNextAttribute(attr: *DomAttr) ?*DomAttr {
    return lxb_dom_element_next_attribute_noi(attr);
}

/// [attributes] Collect all attributes from an element.
///
/// Caller needs to free the slice
pub fn getAttributes(allocator: std.mem.Allocator, element: *z.DomElement) ![]AttributePair {
    var attribute = getFirstAttribute(element);
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

        attribute = getNextAttribute(attribute.?);
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

/// [core] Get element ID as borrowed string for faster access
pub fn getElementId_zc(element: *z.DomElement) []const u8 {
    var id_len: usize = 0;
    const id_ptr = lxb_dom_element_id_noi(
        element,
        &id_len,
    );
    return id_ptr[0..id_len];
}

/// Compare two lexbor strings with case sensitivity.
pub fn compareStrings(first: []const u8, second: []const u8) bool {
    return std.mem.eql(u8, first, second);
}

// ----------------------------------------------------------
/// [attributes] Check if element has specific class
pub fn hasClass(element: *z.DomElement, class_name: []const u8) bool {
    // Quick check: does element have class attribute at all?
    if (!hasAttribute(element, "class")) return false;

    // Get class string directly from lexbor (zero-copy)
    const class_attr = getAttribute_zc(element, "class") orelse return false;

    // Search for the class name in the class list (space-separated)
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

/// [attributes] Class list return type
pub const ClassListType = enum { string, array };

/// [attributes] Class list enum result type.
///
/// Represents the two possible return types for the class list
/// - `string`: Full class string (empty string `""` if no classes)
/// - `array`: Array of individual classes (empty if no classes)
pub const ClassListResult = union(ClassListType) { string: []u8, array: [][]u8 };

/// [attributes] Get element class as string or array.
///
/// Return types for the class list
/// - `string`: Full class string (empty string `""` if no classes)
/// - `array`: Array of individual classes (empty `[]` if no classes)
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
            .string => ClassListResult{ .string = try allocator.dupe(u8, "") },
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

    try z.setAttributes(
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
    try z.setAttributes(
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
                    getAttribute_zc(
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
    const class = class_result.string;
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
    try z.setAttributes(div_element, &.{.{ .name = "new-empty", .value = "" }});
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
