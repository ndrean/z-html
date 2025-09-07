//! This module provides functions to manipulate and retrieve _attributes_ from HTML elements.
//!
//! It contains  `getAttributes`, `setAttribute(s)`, `removeAttribute`, `hasAttribute(s)`, and element ID helper functions.
//! For DOM search functions like `getElementById`, `getElementByAttribute`, see simple_search.zig.

const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

const testing = std.testing;
const print = std.debug.print;

pub const DomAttr = z.DomAttr;

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
extern "c" fn lxb_dom_element_set_attribute(element: *z.HTMLElement, name: [*]const u8, name_len: usize, value: [*]const u8, value_len: usize) ?*DomAttr;
extern "c" fn lxb_dom_attr_qualified_name(attr: *DomAttr, length: *usize) [*]const u8;
extern "c" fn lxb_dom_attr_value_noi(attr: *DomAttr, length: *usize) [*]const u8;

// Lexbor string comparison functions for zero-copy operations
extern "c" fn lexbor_str_data_ncmp(first: [*c]const u8, sec: [*c]const u8, size: usize) bool;
extern "c" fn lexbor_str_data_ncmp_contain(where: [*c]const u8, where_size: usize, what: [*c]const u8, what_size: usize) bool;

// ===============================================================================

/// Fast string comparison using lexbor's optimized functions
///
/// Returns true if strings are equal
pub fn stringEquals(first: []const u8, second: []const u8) bool {
    if (first.len != second.len) return false;
    if (first.len == 0) return true;
    return lexbor_str_data_ncmp(first.ptr, second.ptr, first.len);
}

pub fn stringContains(where: []const u8, what: []const u8) bool {
    if (what.len == 0) return true;
    if (where.len == 0) return false;
    if (what.len > where.len) return false;
    return lexbor_str_data_ncmp_contain(where.ptr, where.len, what.ptr, what.len);
}

test "lexbor string functions" {
    // Test stringEquals only (stringEndsWith needs verification)
    try testing.expect(stringEquals("hello", "hello"));
    try testing.expect(!stringEquals("hello", "world"));
    try testing.expect(!stringEquals("hello", "hello2"));
    try testing.expect(stringEquals("", ""));

    // TODO: Fix stringEndsWith - the function signature or logic might be wrong
    try testing.expect(stringContains("hello world", "world"));
    try testing.expect(!stringContains("hello world", "planet"));
}

// ===============================================================================

/// [attributes] Get attribute value
///
/// Returns `null` if attribute doesn't exist, empty string `""` if attribute exists but has no value.
///
/// Caller needs to free the slice if not null
/// ## Example
/// ```
///  const element = try z.createElementWithAttrs(doc, "div", &.{.{.name = "class", .value = "card"}});
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

/// [attributes] Check if element has a given attribute
///
/// ## Example
/// ```
/// const element = try z.createElementWithAttrs(doc, "div", &.{.{.name = "class", .value = "card"}});
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

/// [attributes] Set the attribute name/value as strings
///
/// Returns the created DomAttr or null if the attribute could not be set (e.g., memory allocation failure)
pub fn setAttribute(element: *z.HTMLElement, name: []const u8, value: []const u8) ?*DomAttr {
    return lxb_dom_element_set_attribute(
        element,
        name.ptr,
        name.len,
        value.ptr,
        value.len,
    );
}

/// [attributes] Set many attributes name/value pairs on element
///
/// Returns null if any attribute could not be set
///
/// ## Example
/// ```
/// const element = try z.createElementWithAttrs(doc, "div", &.{});
/// z.setAttributes(element, &.{
///     .{.name = "id", .value = "main"},
///     .{.name = "class", .value = "test"}
/// }) orelse return error.AttributeSetFailed;
/// try testing.expect(z.hasAttribute(element, "id"));
/// try testing.expectEqualStrings("main", z.getAttribute(element, "id"));
/// ---
/// ```
pub fn setAttributes(element: *z.HTMLElement, attrs: []const AttributePair) ?void {
    for (attrs) |attr| {
        _ = lxb_dom_element_set_attribute(
            element,
            attr.name.ptr,
            attr.name.len,
            attr.value.ptr,
            attr.value.len,
        ) orelse return null;
    }
    return {};
}

// ----------------------------------------------------------

/// Get attribute name as owned string
///
/// Caller needs to free the slice
fn getAttributeName(allocator: std.mem.Allocator, attr: *DomAttr) ![]u8 {
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
fn getAttributeName_zc(attr: *DomAttr) []const u8 {
    var name_len: usize = 0;
    const name_ptr = lxb_dom_attr_qualified_name(
        attr,
        &name_len,
    );
    return name_ptr[0..name_len];
}

/// [attributes] Get attribute value as borrowed slice (zero-copy)
fn getAttributeValue_zc(attr: *DomAttr) []const u8 {
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
fn getAttributeValue(allocator: std.mem.Allocator, attr: *DomAttr) ![]u8 {
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
fn getFirstAttribute(element: *z.HTMLElement) ?*DomAttr {
    return lxb_dom_element_first_attribute_noi(element);
}

/// [attributes] Get next attribute in the list gives an attribute
///
/// Returns a DomAttr
fn getNextAttribute(attr: *DomAttr) ?*DomAttr {
    return lxb_dom_element_next_attribute_noi(attr);
}

// ----------------------------------------------------------
/// [attributes] _deprecated_ Collect all attributes from an element.
///
/// First version.
///
/// Caller needs to free the slice
/// ## Example
/// ```
/// test "getAttributes" {
///   const doc = try z.createDocFromString("");
///   defer z.destroyDocument(doc);
///
///   const body = z.bodyNode(doc).?;
///   const button = try z.createElementWithAttrs(
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
fn getAttributes(allocator: std.mem.Allocator, element: *z.HTMLElement) ![]AttributePair {
    var attribute = getFirstAttribute(element);
    if (attribute == null) return &[_]AttributePair{}; // Early return for elements without attributes

    var attrs: std.ArrayList(AttributePair) = .empty;
    defer attrs.deinit(allocator);

    while (attribute != null) {
        const name_copy = try getAttributeName(allocator, attribute.?);
        const value_copy = try getAttributeValue(allocator, attribute.?);

        try attrs.append(
            allocator,
            AttributePair{
                .name = name_copy,
                .value = value_copy,
            },
        );

        attribute = getNextAttribute(attribute.?);
    }

    return attrs.toOwnedSlice(allocator);
}

/// [attributes] Collect all attributes with stack buffer optimization (bf = buffered)
///
/// Uses zero-copy lexbor strings + stack buffer for small attribute sets.
/// Hard limit of 16 attributes.
///
/// Caller must free names/values/slice
/// ## Example
/// ```
/// const attrs = try getAttributes_bf(allocator, element);
/// defer {
///    for (attrs) |attr| {
///        allocator.free(attr.name);
///        allocator.free(attr.value);
///    }
///    allocator.free(attrs);
/// };
///```
pub fn getAttributes_bf(allocator: std.mem.Allocator, element: *z.HTMLElement) ![]AttributePair {
    var attribute = getFirstAttribute(element);
    if (attribute == null) return &[_]AttributePair{}; // Early return for elements without attributes

    // Stack buffer: most elements have < 16 attributes
    const MAX_STACK_ATTRS = 16;
    var stack_attrs: [MAX_STACK_ATTRS]AttributePair = undefined;
    var attr_count: usize = 0;

    // collect in stack buffer using zero-copy
    while (attribute != null and attr_count < MAX_STACK_ATTRS) {
        const name_zc = getAttributeName_zc(attribute.?);
        const value_zc = getAttributeValue_zc(attribute.?);

        // Copy zero-copy strings to owned memory (still required for caller)
        const name_copy = try allocator.dupe(u8, name_zc);
        const value_copy = try allocator.dupe(u8, value_zc);

        stack_attrs[attr_count] = AttributePair{
            .name = name_copy,
            .value = value_copy,
        };

        attr_count += 1;
        attribute = getNextAttribute(attribute.?);
    }

    // Fast path: all attributes fit in stack buffer

    const result = try allocator.alloc(AttributePair, attr_count);
    @memcpy(result, stack_attrs[0..attr_count]);
    return result;
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
    _ = result;
}

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
    return stringEquals(id_value, id);
}

//=============================================================================
// TESTS
//=============================================================================

test "stringEquals and stringContains" {
    try testing.expect(stringEquals("hello", "hello"));
    try testing.expect(!stringEquals("hello", "world"));
    try testing.expect(stringContains("hello world", "world"));
    try testing.expect(!stringContains("hello", "world"));
}

test "getAttribute and getAttribute_zc" {
    const allocator = testing.allocator;
    const doc = try z.createDocFromString("<div id=\"test\" class=\"main\">Hello</div>");
    defer z.destroyDocument(doc);
    const element = z.getElementById(z.bodyNode(doc).?, "test").?;

    // Test getAttribute (allocated)
    const id_alloc = try getAttribute(allocator, element, "id");
    defer if (id_alloc) |id| allocator.free(id);
    try testing.expect(id_alloc != null);
    try testing.expectEqualStrings("test", id_alloc.?);

    // Test getAttribute_zc (zero-copy)
    const id_zc = getAttribute_zc(element, "id");
    try testing.expect(id_zc != null);
    try testing.expectEqualStrings("test", id_zc.?);

    // Test non-existent attribute
    const missing = getAttribute_zc(element, "nonexistent");
    try testing.expect(missing == null);
}

test "hasAttribute and hasAttributes" {
    const doc = try z.createDocFromString("<div id=\"test\" class=\"main\">Hello</div>");
    defer z.destroyDocument(doc);
    const element = z.getElementById(z.bodyNode(doc).?, "test").?;

    try testing.expect(hasAttribute(element, "id"));
    try testing.expect(hasAttribute(element, "class"));
    try testing.expect(!hasAttribute(element, "nonexistent"));
    try testing.expect(hasAttributes(element));
}

test "setAttribute and setAttributes" {
    const doc = try z.createDocFromString("<div>Hello</div>");
    defer z.destroyDocument(doc);
    const element = z.firstElementChild(z.bodyElement(doc).?).?;

    // Test setAttribute
    const attr_result = setAttribute(element, "id", "newid");
    try testing.expect(attr_result != null); // Should succeed
    const id = getAttribute_zc(element, "id");
    try testing.expectEqualStrings("newid", id.?);

    // Test setAttributes
    const attrs = [_]AttributePair{
        .{ .name = "class", .value = "test-class" },
        .{ .name = "data-test", .value = "value" },
    };
    const attrs_result = setAttributes(element, &attrs);
    try testing.expect(attrs_result != null); // Should succeed

    const class_val = getAttribute_zc(element, "class");
    const data_val = getAttribute_zc(element, "data-test");
    try testing.expectEqualStrings("test-class", class_val.?);
    try testing.expectEqualStrings("value", data_val.?);
}

test "removeAttribute" {
    const doc = try z.createDocFromString("<div id=\"test\" class=\"main\">Hello</div>");
    defer z.destroyDocument(doc);
    const element = z.getElementById(z.bodyNode(doc).?, "test").?;

    try testing.expect(hasAttribute(element, "class"));
    try removeAttribute(element, "class");
    try testing.expect(!hasAttribute(element, "class"));
    try testing.expect(hasAttribute(element, "id")); // Should still have id
}

test "getElementId functions" {
    const allocator = testing.allocator;
    const doc = try z.createDocFromString("<div id=\"test123\">Hello</div>");
    defer z.destroyDocument(doc);
    const element = z.firstElementChild(z.bodyElement(doc).?).?;

    // Test getElementId (allocated)
    const id_alloc = try getElementId(allocator, element);
    defer allocator.free(id_alloc);
    try testing.expectEqualStrings("test123", id_alloc);

    // Test getElementId_zc (zero-copy)
    const id_zc = getElementId_zc(element);
    try testing.expectEqualStrings("test123", id_zc);

    // Test hasElementId
    try testing.expect(hasElementId(element, "test123"));
    try testing.expect(!hasElementId(element, "wrong"));
}

test "getAttributes_bf" {
    const allocator = testing.allocator;
    const doc = try z.createDocFromString("<div id=\"test\" class=\"main\" data-value=\"123\">Hello</div>");
    defer z.destroyDocument(doc);
    const element = z.getElementById(z.bodyNode(doc).?, "test").?;

    const attrs = try getAttributes_bf(allocator, element);
    defer {
        // Free individual attribute strings first
        for (attrs) |attr| {
            allocator.free(attr.name);
            allocator.free(attr.value);
        }
        allocator.free(attrs);
    }

    try testing.expect(attrs.len >= 3); // Should have at least id, class, data-value

    // Check that we got our expected attributes
    var found_id = false;
    var found_class = false;
    var found_data = false;

    for (attrs) |attr| {
        if (std.mem.eql(u8, attr.name, "id")) {
            found_id = true;
            try testing.expectEqualStrings("test", attr.value);
        } else if (std.mem.eql(u8, attr.name, "class")) {
            found_class = true;
            try testing.expectEqualStrings("main", attr.value);
        } else if (std.mem.eql(u8, attr.name, "data-value")) {
            found_data = true;
            try testing.expectEqualStrings("123", attr.value);
        }
    }

    try testing.expect(found_id);
    try testing.expect(found_class);
    try testing.expect(found_data);
}
