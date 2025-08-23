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
extern "c" fn lxb_dom_element_get_attribute(element: *z.HTMLElement, name: [*]const u8, name_len: usize, value_len: *usize) ?[*]const u8;
extern "c" fn lxb_dom_element_has_attributes(element: *z.HTMLElement) bool;
extern "c" fn lxb_dom_element_remove_attribute(element: *z.HTMLElement, qualified_name: [*]const u8, qn_len: usize) ?*anyopaque;
extern "c" fn lxb_dom_element_first_attribute_noi(element: *z.HTMLElement) ?*DomAttr;
extern "c" fn lxb_dom_element_next_attribute_noi(attr: *DomAttr) ?*DomAttr;
extern "c" fn lxb_dom_element_id_noi(element: *z.HTMLElement, len: *usize) [*]const u8;
extern "c" fn lxb_dom_element_class_noi(element: *z.HTMLElement, len: *usize) [*]const u8;
extern "c" fn lxb_dom_element_has_attribute(element: *z.HTMLElement, name: [*]const u8, name_len: usize) bool;
extern "c" fn lxb_dom_element_set_attribute(element: *z.HTMLElement, name: [*]const u8, name_len: usize, value: [*]const u8, value_len: usize) *DomAttr;
extern "c" fn lxb_dom_attr_qualified_name(attr: *DomAttr, length: *usize) [*]const u8;
extern "c" fn lxb_dom_attr_value_noi(attr: *DomAttr, length: *usize) [*]const u8;

/// [attributes] Get attribute value
///
/// Returns `null` if attribute doesn't exist, empty string `""` if attribute exists but has no value.
///
/// Caller needs to free the slice if not null
/// ## Example
/// ```
///  const element = try z.createElementAttr(doc, "div", &.{.{.name = "class", .value = "card"}});
/// const class = try getAttribute(allocator, element, "class");
/// defer if (class != null) |c| {
///     allocator.free(c);
/// };
/// try testing.expectEqualStrings("card", class.?);
/// ----
/// ```
pub fn getAttribute(allocator: std.mem.Allocator, element: *z.HTMLElement, name: []const u8) !?[]u8 {
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
pub fn getAttribute_zc(element: *z.HTMLElement, name: []const u8) ?[]const u8 {
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

/// [attributes] Check if element has a given attribute
///
/// ## Example
/// ```
/// const element = try z.createElementAttr(doc, "div", &.{.{.name = "class", .value = "card"}});
/// try testing.expect(z.hasAttribute(element, "class"));
/// ---
/// ```
pub fn hasAttribute(element: *z.HTMLElement, name: []const u8) bool {
    return lxb_dom_element_has_attribute(
        element,
        name.ptr,
        name.len,
    );
}

/// [attributes] Check if element has any attributes
pub fn hasAttributes(element: *z.HTMLElement) bool {
    return lxb_dom_element_has_attributes(element);
}

// ----------------------------------------------------------

/// [attributes] Set the attribute name/value as strings
pub fn setAttribute(element: *z.HTMLElement, name: []const u8, value: []const u8) void {
    _ = lxb_dom_element_set_attribute(
        element,
        name.ptr,
        name.len,
        value.ptr,
        value.len,
    );
}

/// [attributes] Set many attributes name/value pairs on element
///
/// ## Example
/// ```
/// const element = try z.createElementAttr(doc, "div", &.{});
/// try z.setAttributes(element, &.{
///     .{.name = "id", .value = "main"},
///     ?{.name = "id", .value = "main"}
/// });
/// try testing.expect(z.hasAttribute(element, "id"));
/// try testing.expectEqualStrings("main", z.getAttribute(element, "id"));
/// ---
/// ```
pub fn setAttributes(element: *z.HTMLElement, attrs: []const AttributePair) void {
    for (attrs) |attr| {
        const result = lxb_dom_element_set_attribute(
            element,
            attr.name.ptr,
            attr.name.len,
            attr.value.ptr,
            attr.value.len,
        );
        _ = result;
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

/// [attributes] Get attribute name as borrowed slice (zero-copy)
pub fn getAttributeName_zc(attr: *DomAttr) []const u8 {
    var name_len: usize = 0;
    const name_ptr = lxb_dom_attr_qualified_name(
        attr,
        &name_len,
    );
    return name_ptr[0..name_len];
}

/// [attributes] Get attribute value as borrowed slice (zero-copy)
pub fn getAttributeValue_zc(attr: *DomAttr) []const u8 {
    var value_len: usize = 0;
    const value_ptr = lxb_dom_attr_value_noi(
        attr,
        &value_len,
    );
    return value_ptr[0..value_len];
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
pub fn getFirstAttribute(element: *z.HTMLElement) ?*DomAttr {
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
/// ## Example
/// ```
/// test "getAttributes" {
///   const doc = try z.parseFromString("");
///   defer z.destroyDocument(doc);
///
///   const body = try z.bodyNode(doc);
///   const button = try z.createElementAttr(
///       doc,
///        "button",
///        &.{
///            .{ .name = "phx-click", .value = "increment" },
///            .{ .name = "hidden", .value = "" },
///        },
///    );
///    z.appendChild(body, z.elementToNode(button));
///
///    const allocator = testing.allocator;
///    const attrs = try z.getAttributes(allocator, button);
///    defer {
///        for (attrs) |attr| {
///            allocator.free(attr.name);
///            allocator.free(attr.value);
///        }
///        allocator.free(attrs);
///    }
///    try testing.expect(attrs.len == 2);
///    try testing.expectEqualStrings("phx-click", attrs[0].name);
///    try testing.expectEqualStrings("hidden", attrs[1].name);
///}
/// ```
///## Signature
pub fn getAttributes(allocator: std.mem.Allocator, element: *z.HTMLElement) ![]AttributePair {
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
pub fn removeAttribute(element: *z.HTMLElement, name: []const u8) !void {
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
pub fn getElementId(allocator: std.mem.Allocator, element: *z.HTMLElement) ![]u8 {
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
pub fn getElementId_zc(element: *z.HTMLElement) []const u8 {
    var id_len: usize = 0;
    const id_ptr = lxb_dom_element_id_noi(
        element,
        &id_len,
    );
    return id_ptr[0..id_len];
}

pub fn hasElementId(element: *z.HTMLElement, id: []const u8) bool {
    const id_value = z.getElementId_zc(element);
    if (id_value.len != id.len or id_value.len == 0) return false;
    return std.mem.eql(u8, id_value, id);
}

test "hasElementID" {
    const doc1 = try z.parseFromString("<p id=\"test\"></p><p id=\"\"></p>");
    defer z.destroyDocument(doc1);
    const body = try z.bodyNode(doc1);
    const p1 = z.firstChild(body);
    const p1_elt = z.nodeToElement(p1.?);
    const p2 = z.nextSibling(p1.?);
    const p2_elt = z.nodeToElement(p2.?);

    try testing.expect(hasElementId(p1_elt.?, "test"));
    try testing.expect(!hasElementId(p1_elt.?, "nope"));
    try testing.expect(!hasElementId(p2_elt.?, ""));
}

/// Compare two lexbor strings with case sensitivity.
pub fn compareStrings(first: []const u8, second: []const u8) bool {
    return std.mem.eql(u8, first, second);
}

// ----------------------------------------------------------}

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
}

test "attribute modification" {
    const allocator = testing.allocator;

    const html = "<p>Original content</p>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body_node = try z.bodyNode(doc);
    const p_node = z.firstChild(body_node).?;
    const p_element = z.nodeToElement(p_node).?;

    _ = z.setAttributes(
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
    _ = z.setAttributes(
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
    _ = z.setAttributes(div_element, &.{.{ .name = "new-empty", .value = "" }});
    try testing.expect(hasAttribute(div_element, "new-empty"));

    if (try getAttribute(
        allocator,
        div_element,
        "new-empty",
    )) |new_empty| {
        defer allocator.free(new_empty);
        try testing.expectEqualStrings("", new_empty);
    }
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
}
