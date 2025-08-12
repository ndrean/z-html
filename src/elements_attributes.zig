//! HTMLElement Attribute functions
//! This module provides functions to manipulate and retrieve attributes from HTML elements.

const std = @import("std");
const z = @import("zhtml.zig");

const testing = std.testing;
const print = std.debug.print;

const Err = @import("errors.zig").LexborError;

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
/// Returns null if attribute doesn't exist, empty string if attribute exists but has no value.
///
/// Caller needs to free the slice if not null
pub fn elementGetNamedAttribute(allocator: std.mem.Allocator, element: *z.DomElement, name: []const u8) !?[]u8 {
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
pub fn elementHasNamedAttribute(element: *z.DomElement, name: []const u8) bool {
    return lxb_dom_element_has_attribute(
        element,
        name.ptr,
        name.len,
    );
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

/// [attributes] Get attribute value as string (borrowed - don't free)
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

// ----------------------------------------------------------

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

pub fn elementHasAnyAttribute(element: *z.DomElement) bool {
    return lxb_dom_element_has_attributes(element);
}

/// [attributes] Collect all attributes from an element.
///
/// This function already includes an optimization: it uses getElementFirstAttribute()
/// which returns null for elements without any attributes, providing an early return.
/// This is equivalent to checking elementHasAnyAttribute() first.
///
/// Caller needs to free the slice
pub fn attributes(allocator: std.mem.Allocator, element: *z.DomElement) ![]AttributePair {
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

/// Remove attribute from element
///
/// Fails silently
pub fn elementRemoveNamedAttribute(element: *z.DomElement, name: []const u8) !void {
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

/// Get next attribute in the list gives an attribute
pub fn getElementNextAttribute(attr: *DomAttr) ?*DomAttr {
    return lxb_dom_element_next_attribute_noi(attr);
}

// ----------------------------------------------------------

/// Get element ID as owned string
///
/// Caller needs to free the slice
pub fn elementId(allocator: std.mem.Allocator, element: *z.DomElement) ![]u8 {
    var id_len: usize = 0;
    const id_ptr = lxb_dom_element_id_noi(
        element,
        &id_len,
    );

    const result = try allocator.alloc(u8, id_len);
    @memcpy(result, id_ptr[0..id_len]);
    return result;
}

// ----------------------------------------------------------

/// [attributes] Get optional element class as owned string
///
/// Caller needs to free the slice if not null
pub fn classList(allocator: std.mem.Allocator, element: *z.DomElement) !?[]u8 {
    var class_len: usize = 0;
    const class_ptr = lxb_dom_element_class_noi(
        element,
        &class_len,
    );

    // If no class or empty class, return null
    if (class_len == 0) {
        return null;
    }

    const result = try allocator.alloc(u8, class_len);
    @memcpy(result, class_ptr[0..class_len]);
    return result;
}

// ----------------------------------------------------------
// TESTS
// ----------------------------------------------------------

test "element / attribute  name & value" {
    const allocator = testing.allocator;

    const html = "<div class='test' id='my-id' data-value='123' title='tooltip' hidden>Content</div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);
    const body_node = try z.getDocumentBodyNode(doc);
    const div = z.firstChild(body_node).?;
    const div_elt = z.nodeToElement(div).?;

    // Get ID attribute from an element
    const id = try elementId(allocator, div_elt);
    defer allocator.free(id);
    try testing.expectEqualStrings(id, "my-id");

    // Get class attribute from an element
    const class = try z.classList(allocator, div_elt);
    defer allocator.free(class.?);
    try testing.expectEqualStrings(class.?, "test");

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
    const body_node = try z.getDocumentBodyNode(doc);
    const div = z.firstChild(body_node).?;
    const div_elt = z.nodeToElement(div).?;

    const attrs = try attributes(allocator, div_elt);
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

    const body = try z.getDocumentBodyElement(doc);
    const body_node = z.elementToNode(body);
    const div_node = z.firstChild(body_node).?;
    const div_element = z.nodeToElement(div_node).?;

    // Test hasAttribute
    try testing.expect(z.hasAttribute(div_element, "class"));
    try testing.expect(z.hasAttribute(div_element, "id"));
    try testing.expect(z.hasAttribute(div_element, "data-value"));
    try testing.expect(!z.hasAttribute(div_element, "nonexistent"));

    // Test getAttribute (owned memory)
    if (try elementGetNamedAttribute(allocator, div_element, "class")) |class_value| {
        defer allocator.free(class_value);
        try testing.expectEqualStrings("container test", class_value);
    }

    if (try elementGetNamedAttribute(allocator, div_element, "id")) |id_value| {
        defer allocator.free(id_value);
        try testing.expectEqualStrings("main-div", id_value);
    }

    // Test borrowed attribute value
    if (z.getAttribute(div_element, "data-value")) |data_value| {
        try testing.expectEqualStrings("123", data_value);
        // print("Data (borrowed): '{s}'\n", .{data_value});
    }

    // Test non-existent attribute
    const missing = try elementGetNamedAttribute(allocator, div_element, "missing");
    try testing.expect(missing == null);

    // print("✅ Named attribute operations work!\n", .{});
}

test "attribute modification" {
    const allocator = testing.allocator;

    const html = "<p>Original content</p>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body_node = try z.getDocumentBodyNode(doc);
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

    if (try elementGetNamedAttribute(allocator, p_element, "id")) |id| {
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

    if (try elementGetNamedAttribute(allocator, p_element, "id")) |modified_id| {
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

    const body_node = try z.getDocumentBodyNode(doc);
    const div_node = z.firstChild(body_node);
    const div_element = z.nodeToElement(div_node.?).?;

    // Manual check of expected attributes
    const expected_attrs = [_][]const u8{ "class", "id", "data-value", "title", "hidden" };
    var found_count: usize = 0;

    for (expected_attrs) |attr_name| {
        if (z.hasAttribute(div_element, attr_name)) {
            found_count += 1;

            if (try elementGetNamedAttribute(allocator, div_element, attr_name)) |value| {
                defer allocator.free(value);
                try testing.expectEqualStrings(
                    value,
                    z.getAttribute(
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

    const body_node = try z.getDocumentBodyNode(doc);
    const section_node = z.firstChild(body_node);
    const section_element = z.nodeToElement(section_node.?).?;

    // Test ID getter
    const id = try elementId(allocator, section_element);
    defer allocator.free(id);
    try testing.expectEqualStrings("content", id);

    // Test class getter
    const class = try classList(allocator, section_element);
    defer allocator.free(class.?);
    try testing.expectEqualStrings("main-section", class.?);

    // print("✅ ID and CLASS attribute getters\n", .{});
}

test "attribute edge cases" {
    const allocator = testing.allocator;

    const html = "<div data-empty='' title='  spaces  '>Content</div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.getDocumentBodyElement(doc);
    const body_node = z.elementToNode(body);
    const div_node = z.firstChild(body_node).?;
    const div_element = z.nodeToElement(div_node).?;

    // print("\n=== Attribute Edge Cases ===\n", .{});

    // Empty attribute value
    if (try elementGetNamedAttribute(
        allocator,
        div_element,
        "data-empty",
    )) |empty_value| {
        defer allocator.free(empty_value);
        try testing.expectEqualStrings("", empty_value);
        // print("Empty attribute: '{s}' (length: {d})\n", .{ empty_value, empty_value.len });
    }

    // Attribute with spaces
    if (try elementGetNamedAttribute(
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
    try testing.expect(elementHasNamedAttribute(div_element, "new-empty"));

    if (try elementGetNamedAttribute(
        allocator,
        div_element,
        "new-empty",
    )) |new_empty| {
        defer allocator.free(new_empty);
        try testing.expectEqualStrings("", new_empty);
    }

    // print("✅ Edge cases handled correctly!\n", .{});
}

test "elementHasNamedAttribute - isolated test" {
    const html = "<div id='test-div' class='example'>Simple content</div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.getDocumentBodyElement(doc);
    const body_node = z.elementToNode(body);
    const div_node = z.firstChild(body_node).?;
    const div_element = z.nodeToElement(div_node).?;

    // print("\n=== Testing elementHasNamedAttribute in isolation ===\n", .{});

    // Test basic functionality
    // print("Testing 'id' attribute...\n", .{});
    const has_id = elementHasNamedAttribute(div_element, "id");
    try testing.expect(has_id);
    // print("✅ Has 'id' attribute: {}\n", .{has_id});

    // print("Testing 'class' attribute...\n", .{});
    const has_class = elementHasNamedAttribute(div_element, "class");
    try testing.expect(has_class);
    // print("✅ Has 'class' attribute: {}\n", .{has_class});

    // print("Testing 'missing' attribute...\n", .{});
    const has_missing = elementHasNamedAttribute(div_element, "missing");
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

    const body_node = try z.getDocumentBodyNode(doc);
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
    const missing_attr = try elementGetNamedAttribute(
        allocator,
        div_element,
        "missing",
    );
    try testing.expect(missing_attr == null);
    // print("✅ Error handling works!\n", .{});
}
