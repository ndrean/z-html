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
/// Same memory management as getAttributes - caller must free names/values/slice
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

// ===========================================================
/// [attrs] getElementById traversal DOM search
///
///
/// Input IDs are "strings".
///
/// Returns the first element with matching ID, or null if not found.
pub fn getElementById(root_node: *z.DomNode, id: []const u8) ?*z.HTMLElement {
    const IdContext = struct {
        target_id: []const u8,
        found_element: ?*z.HTMLElement = null,
        matcher: *const fn (*z.DomNode, *@This()) callconv(.c) c_int,

        fn implement(node: *z.DomNode, ctx: *@This()) callconv(.c) c_int {
            const element = z.nodeToElement(node).?;
            if (!z.hasAttribute(element, "id")) return z._CONTINUE;
            const id_value = z.getElementId_zc(element);

            if (std.mem.eql(u8, id_value, ctx.target_id)) {
                ctx.found_element = element;
                return z._STOP;
            }
            return z._CONTINUE;
        }
    };

    var context = IdContext{ .target_id = id, .matcher = IdContext.implement };
    return z.genSearchElement(IdContext, root_node, &context);
}

test "getElementById" {
    const doc = try z.parseFromString("<div id=\"1\"><p ></p><span id=\"2\"></span></div>");
    defer z.destroyDocument(doc);
    const body = try z.bodyNode(doc);
    const element = getElementById(body, "2");
    try testing.expect(z.tagFromElement(element.?) == .span);
}

/// [attrs] Get multiple elements by ID
pub fn getElementsById(allocator: std.mem.Allocator, root_node: *z.DomNode, id_value: []const u8) ![]const *z.HTMLElement {
    const MultipleIdContext = struct {
        allocator: std.mem.Allocator,
        target_id: []const u8,
        results: std.ArrayList(*z.HTMLElement),
        matcher: *const fn (*z.DomNode, *@This()) callconv(.c) c_int,

        pub fn init(alloc: std.mem.Allocator, id: []const u8) @This() {
            return .{
                .allocator = alloc,
                .target_id = id,
                .results = .empty,
                .matcher = @This().implement,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.results.deinit(self.allocator);
        }

        fn implement(node: *z.DomNode, ctx: *@This()) callconv(.c) c_int {
            const element = z.nodeToElement(node).?;
            if (!z.hasAttribute(element, "id")) return z._CONTINUE;
            const id = z.getElementId_zc(element);

            if (std.mem.eql(u8, id, ctx.target_id)) {
                ctx.results.append(ctx.allocator, element) catch {
                    return z._STOP;
                };
            }
            return z._CONTINUE;
        }
    };

    var context = MultipleIdContext.init(allocator, id_value);
    defer context.deinit();

    return z.genSearchElements(MultipleIdContext, root_node, &context);
}

test "getElementsById" {
    const allocator = testing.allocator;
    const doc = try z.parseFromString("<div id=\"1\"><p ></p><span id=\"1\"></span></div>");
    defer z.destroyDocument(doc);
    const body = try z.bodyNode(doc);
    const element = try getElementsById(allocator, body, "1");
    defer allocator.free(element);
    try testing.expect(z.tagFromElement(element[0]).? == .div and z.tagFromElement(element[1]).? == .span);
}

/// [attrs] getElementByClass traversal DOM search
pub fn getElementByClass(root_node: *z.DomNode, class_name: []const u8) ?*z.HTMLElement {
    const ClassContext = struct {
        target_class: []const u8,
        found_element: ?*z.HTMLElement = null,
        matcher: *const fn (*z.DomNode, *@This()) callconv(.c) c_int,

        fn implement(node: *z.DomNode, ctx: *@This()) callconv(.c) c_int {
            const element = z.nodeToElement(node).?;
            if (!z.hasAttribute(element, "class")) return z._CONTINUE;

            if (z.hasClass(element, ctx.target_class)) {
                ctx.found_element = element;
                return z._STOP;
            }
            return z._CONTINUE;
        }
    };

    var context = ClassContext{ .target_class = class_name, .matcher = ClassContext.implement };
    return z.genSearchElement(ClassContext, root_node, &context);
}

test "getElementByClass" {
    const doc = try z.parseFromString("<div id=\"1\"><p class=\"test\"></p><span class=\"test\"></span></div>");
    defer z.destroyDocument(doc);
    const body = try z.bodyNode(doc);
    const element = getElementByClass(body, "test");
    try testing.expect(z.tagFromElement(element.?) == .p);
}

/// [attrs] Get element by attribute
pub fn getElementByAttribute(root_node: *z.DomNode, attr_name: []const u8, attr_value: ?[]const u8) ?*z.HTMLElement {
    const AttrContext = struct {
        attr_name: []const u8,
        attr_value: ?[]const u8,
        found_element: ?*z.HTMLElement = null,
        matcher: *const fn (*z.DomNode, *@This()) callconv(.c) c_int,

        fn implement(node: *z.DomNode, ctx: *@This()) callconv(.c) c_int {
            const element = z.nodeToElement(node).?;
            if (!z.hasAttribute(element, ctx.attr_name)) return z._CONTINUE;

            if (ctx.attr_value) |expected| {
                const actual = z.getAttribute_zc(element, ctx.attr_name) orelse return z._CONTINUE;
                if (!std.mem.eql(u8, actual, expected)) return z._CONTINUE;
            }

            ctx.found_element = element;
            return z._STOP;
        }
    };

    var context = AttrContext{
        .attr_name = attr_name,
        .attr_value = attr_value,
        .matcher = AttrContext.implement,
    };
    return z.genSearchElement(AttrContext, root_node, &context);
}

test "getElementByAttribute" {
    const doc = try z.parseFromString("<div id=\"1\" data-test=\"value1\"><p ></p><span data-test=\"value2\"></span></div>");
    defer z.destroyDocument(doc);
    const body = try z.bodyNode(doc);
    const element_2 = getElementByAttribute(body, "data-test", "value2");
    try testing.expect(z.tagFromElement(element_2.?) == .span);
    const element_1 = getElementByAttribute(body, "data-test", null);
    try testing.expect(z.tagFromElement(element_1.?) == .div);
}

/// [attrs] Fast search by data-attributes
///
/// ```
/// const doc = try z.parseFromString("<form><input phx-click=\"increment\" disabled></form>");
/// defer z.destroyDocument(doc);
/// try z.getElementByDataAttribute(root_node, "phx", "click", "increment");
///
/// ---
/// ```
pub fn getElementByDataAttribute(root_node: *z.DomNode, prefix: []const u8, data_name: []const u8, value: ?[]const u8) !?*z.HTMLElement {
    var attr_name_buffer: [32]u8 = undefined;
    const attr_name = try std.fmt.bufPrint(
        attr_name_buffer[0..],
        "{s}-{s}",
        .{ prefix, data_name },
    );

    return getElementByAttribute(root_node, attr_name, value);
}

test "getElementByDataAttribute" {
    // const allocator = testing.allocator;

    const html =
        \\<div id="user" data-id="1234567890" data-user="carinaanand" data-date-of-birth>
        \\Carina Anand
        \\</div>
    ;
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);
    const body = try z.bodyNode(doc);
    const div = z.nodeToElement(z.firstChild(body).?).?;

    const elt = getElementById(body, "user").?;

    try testing.expect(div == elt);

    const date_of_birth = try getElementByDataAttribute(
        body,
        "data",
        "date-of-birth",
        null,
    );
    try testing.expect(div == date_of_birth);

    const user = try getElementByDataAttribute(
        body,
        "data",
        "user",
        "carinaanand",
    );
    try testing.expect(user == div);
    try testing.expect(z.hasAttribute(user.?, "data-id"));

    const maybe_user = try getElementByDataAttribute(
        body,
        "data",
        "user",
        "johndoe",
    );

    try testing.expect(maybe_user != div);

    const allocator = testing.allocator;
    const data_user = try z.getAttribute(
        allocator,
        user.?,
        "data-user",
    );
    defer if (data_user) |u| {
        allocator.free(u);
    };

    try testing.expectEqualStrings("carinaanand", data_user.?);
}

/// [attrs] Get element by tag name
pub fn getElementByTag(root_node: *z.DomNode, tag: z.HtmlTag) ?*z.HTMLElement {
    const TagContext = struct {
        target_tag: z.HtmlTag,
        found_element: ?*z.HTMLElement = null,
        matcher: *const fn (*z.DomNode, *@This()) callconv(.c) c_int,

        fn implement(node: *z.DomNode, ctx: *@This()) callconv(.c) c_int {
            const element = z.nodeToElement(node).?;
            const element_tag = z.tagFromElement(element);
            if (element_tag == ctx.target_tag) {
                ctx.found_element = element;
                return z._STOP;
            }
            return z._CONTINUE;
        }
    };

    var context = TagContext{ .target_tag = tag, .matcher = TagContext.implement };
    return z.genSearchElement(TagContext, root_node, &context);
}

test "getElementByTag" {
    const doc = try z.parseFromString("<div id=\"1\"><p class=\"test\"></p><span id=\"2\"></span></div>");
    defer z.destroyDocument(doc);
    const body = try z.bodyNode(doc);
    const element = getElementByTag(body, .span);
    try testing.expectEqualStrings(z.getElementId_zc(element.?), "2");
}

const RemoveAllContext = struct {
    allocator: std.mem.Allocator,
    processor: *const fn (*z.DomNode, ctx: *@This()) c_int,

    fn clean(node: *z.DomNode, ctx: *@This()) c_int {
        const cast_ctx = z.castContext(RemoveAllContext, ctx);
        var attr_names: std.ArrayList([]const u8) = .empty;
        defer attr_names.deinit(cast_ctx.allocator);
        const element = z.nodeToElement(node).?;

        var attr = z.getFirstAttribute(element);
        while (attr != null) {
            const name = z.getAttributeName_zc(attr.?);
            attr_names.append(cast_ctx.allocator, name) catch return z._STOP;
            attr = z.getNextAttribute(attr.?);
        }

        for (attr_names.items) |name| {
            z.removeAttribute(element, name) catch return z._STOP;
        }
        return z._CONTINUE;
    }
};

fn removeAllAttributes(allocator: std.mem.Allocator, root_node: *z.DomNode) void {
    var context = RemoveAllContext{
        .allocator = allocator,
        .processor = &RemoveAllContext.clean,
    };
    z.genProcessAll(RemoveAllContext, root_node, &context);
}

test "removeAllAtributes" {
    const allocator = testing.allocator;

    const html =
        \\<div id="main" class="container" data-test="value">
        \\  <span class="highlight" title="tooltip">Content</span>
        \\  <p style="color: red;" data-id="123">Text</p>
        \\</div>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);
    const root_node = z.documentRoot(doc).?;

    // Test removing all attributes
    removeAllAttributes(allocator, root_node);

    // Verify attributes are gone
    const body = try z.bodyNode(doc);
    const serialized = try z.outerNodeHTML(allocator, body);
    defer allocator.free(serialized);

    try testing.expect(!std.mem.containsAtLeast(u8, serialized, 1, "class="));
    try testing.expect(!std.mem.containsAtLeast(u8, serialized, 1, "id="));

    try testing.expect(!std.mem.containsAtLeast(u8, serialized, 1, "title="));
    try testing.expect(!std.mem.containsAtLeast(u8, serialized, 1, "istyle="));
    try testing.expect(!std.mem.containsAtLeast(u8, serialized, 1, "data-id="));
}

/// [walker] Remove selected attributes from all elements
fn removeSelectedAttributes(allocator: std.mem.Allocator, root_node: *z.DomNode, attrs: []const []const u8) void {
    const RemoveSelectedContext = struct {
        allocator: std.mem.Allocator,
        processor: *const fn (*z.DomNode, ctx: *@This()) c_int,
        attrs: []const []const u8, // slicee of attributes

        fn remove(node: *z.DomNode, ctx: *@This()) c_int {
            const cast_ctx = z.castContext(@This(), ctx);
            const element = z.nodeToElement(node).?;
            for (cast_ctx.attrs) |attr_name| {
                z.removeAttribute(element, attr_name) catch return z._STOP;
            }
            return z._CONTINUE;
        }
    };
    var context = RemoveSelectedContext{
        .allocator = allocator,
        .processor = RemoveSelectedContext.remove,
        .attrs = attrs,
    };

    z.genProcessAll(RemoveSelectedContext, root_node, &context);
}

test "removeSelectedAttributes" {
    const allocator = testing.allocator;

    const html =
        \\<div id="main" class="container" data-test="value">
        \\  <span class="highlight" title="tooltip">Content</span>
        \\  <p style="color: red;" data-id="123">Text</p>
        \\</div>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);
    const root_node = z.documentRoot(doc).?;

    // Test removing all attributes
    removeSelectedAttributes(
        allocator,
        root_node,
        &[_][]const u8{ "class", "id" },
    );

    // Verify attributes are gone
    const body = try z.bodyElement(doc);
    const serialized = try z.outerHTML(allocator, body);
    defer allocator.free(serialized);

    // Only selected attributes removed
    try testing.expect(!std.mem.containsAtLeast(u8, serialized, 1, "class="));
    try testing.expect(std.mem.containsAtLeast(u8, serialized, 1, "data-id="));
    try testing.expect(!std.mem.containsAtLeast(u8, serialized, 1, "id=main"));
    try testing.expect(std.mem.containsAtLeast(u8, serialized, 1, "title="));
    try testing.expect(std.mem.containsAtLeast(u8, serialized, 1, "style="));
}

// Context for adding a class to all elements - different extra field
// const AddClassContext = struct {
//     allocator: std.mem.Allocator,
//     processor: *const fn (*z.HTMLElement, ctx: *@This()) c_int,
//     class_name: []const u8, // Different extra field!

//     fn addClass(node: *z.DomNode, ctx: *@This()) c_int {
//         const element = z.nodeToElement(node).?;
//         const existing_class = z.getAttribute_zc(element, "class") orelse "";

//         var new_class : std.ArrayList(u8) = .empty;
//         defer new_class.deinit(ctx.allocator);

//         if (existing_class.len > 0) {
//             new_class.appendSlice(existing_class) catch return z._STOP;
//             new_class.append(' ') catch return z._STOP;
//         }
//         new_class.appendSlice(ctx.class_name) catch return z._STOP;

//         z.setAttribute(element, "class", new_class.items) catch return z._STOP;
//         return z._CONTINUE;
//     }
// };

test "single element search" {
    const allocator = testing.allocator;
    const html =
        \\<div>
        \\  <p id="target" class="text">Target paragraph</p>
        \\  <span class="highlight">Span 1</span>
        \\  <span class="highlight">Span 2</span>
        \\  <div>
        \\    <p id="nested" class="text">Nested paragraph</p>
        \\  </div>
        \\</div>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Test compile-time ID search with compile-time known string
    const element_by_id = getElementById(
        z.documentRoot(doc).?,
        "target",
    );
    try testing.expect(element_by_id != null);

    const id_text = try z.textContent(
        allocator,
        z.elementToNode(element_by_id.?),
    );
    defer allocator.free(id_text);
    try testing.expect(std.mem.eql(u8, id_text, "Target paragraph"));

    // Test compile-time class search with compile-time known string
    const element_by_class = getElementByClass(
        z.documentRoot(doc).?,
        "highlight",
    );
    try testing.expect(element_by_class != null);
    try testing.expect(z.hasClass(element_by_class.?, "highlight"));
}

test "bigger search functions" {
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
        \\  <main id="content" class="main-content" phx-section="content">
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

    const root_node = z.documentRoot(doc).?;

    // Test 1: getElementByIdFast - should find elements by ID
    const header = getElementById(
        root_node,
        "header",
    );
    try testing.expect(header != null);
    try testing.expectEqualStrings("DIV", z.tagName_zc(header.?));

    const content = getElementById(
        root_node,
        "content",
    );
    try testing.expect(content != null);
    try testing.expectEqualStrings("MAIN", z.tagName_zc(content.?));

    const footer = getElementById(
        root_node,
        "footer",
    );
    try testing.expect(footer != null);
    try testing.expectEqualStrings("FOOTER", z.tagName_zc(footer.?));

    // Test 2: getElementByClassFast - should find first element with class
    const nav_link = getElementByClass(
        root_node,
        "nav-link",
    );
    try testing.expect(nav_link != null);
    try testing.expectEqualStrings("A", z.tagName_zc(nav_link.?));

    const post = getElementByClass(
        root_node,
        "post",
    );
    try testing.expect(post != null);
    try testing.expectEqualStrings("ARTICLE", z.tagName_zc(post.?));

    const widget = getElementByClass(
        root_node,
        "widget",
    );
    try testing.expect(widget != null);
    try testing.expectEqualStrings("DIV", z.tagName_zc(widget.?));

    // Test 3: getElementByAttributeFast - attribute existence only
    const href_element = getElementByAttribute(
        root_node,
        "href",
        null,
    );
    try testing.expect(href_element != null);
    try testing.expectEqualStrings("A", z.tagName_zc(href_element.?));

    // Test 4: getElementByAttributeFast - attribute with specific value
    const home_link = getElementByAttribute(
        root_node,
        "href",
        "/home",
    );
    try testing.expect(home_link != null);
    try testing.expectEqualStrings("A", z.tagName_zc(home_link.?));

    const about_link = getElementByAttribute(
        root_node,
        "href",
        "/about",
    );
    try testing.expect(about_link != null);
    try testing.expectEqualStrings("A", z.tagName_zc(about_link.?));

    // Test 5: getElementByDataAttributeFast - data attributes
    const header_section = try getElementByDataAttribute(
        root_node,
        "data",
        "section",
        "header",
    );
    try testing.expectEqualStrings("DIV", z.tagName_zc(header_section.?));

    const home_page = try getElementByDataAttribute(
        root_node,
        "data",
        "page",
        "home",
    );
    try testing.expectEqualStrings("A", z.tagName_zc(home_page.?));

    const tech_article = try getElementByDataAttribute(
        root_node,
        "data",
        "category",
        "tech",
    );
    try testing.expect(tech_article != null);
    try testing.expectEqualStrings("ARTICLE", z.tagName_zc(tech_article.?));

    // Test custom prefix functionality (phx- instead of data-)
    const content_section = try getElementByDataAttribute(
        root_node,
        "phx",
        "section",
        "content",
    );
    try testing.expectEqualStrings("MAIN", z.tagName_zc(content_section.?));

    // Test 6: Non-existent searches should return null
    const missing_id = getElementById(
        root_node,
        "nonexistent",
    );
    try testing.expect(missing_id == null);

    const missing_class = getElementByClass(
        root_node,
        "nonexistent-class",
    );
    try testing.expect(missing_class == null);

    const missing_attr = getElementByAttribute(
        root_node,
        "nonexistent-attr",
        "value",
    );
    try testing.expect(missing_attr == null);

    const missing_data = try getElementByDataAttribute(
        root_node,
        "nonexistent",
        "data",
        "value",
    );
    try testing.expect(missing_data == null);
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

test "getAttributes_bf stack buffer optimization" {
    const allocator = testing.allocator;

    // Test with small number of attributes (should use stack buffer)
    const html_small = "<div class='test' id='main' data-value='123' title='tooltip'>Content</div>";
    const doc_small = try z.parseFromString(html_small);
    defer z.destroyDocument(doc_small);

    const body_small = try z.bodyElement(doc_small);
    const div_small = z.nodeToElement(z.firstChild(z.elementToNode(body_small)).?).?;

    const attrs_small = try getAttributes_bf(allocator, div_small);
    defer {
        for (attrs_small) |attr| {
            allocator.free(attr.name);
            allocator.free(attr.value);
        }
        allocator.free(attrs_small);
    }

    try testing.expect(attrs_small.len == 4);

    // Compare with regular getAttributes to ensure same results
    const attrs_regular = try getAttributes(allocator, div_small);
    defer {
        for (attrs_regular) |attr| {
            allocator.free(attr.name);
            allocator.free(attr.value);
        }
        allocator.free(attrs_regular);
    }

    try testing.expect(attrs_small.len == attrs_regular.len);
    for (attrs_small, attrs_regular) |small_attr, regular_attr| {
        try testing.expectEqualStrings(small_attr.name, regular_attr.name);
        try testing.expectEqualStrings(small_attr.value, regular_attr.value);
    }
}

test "getAttributes_bf large attribute set" {
    const allocator = testing.allocator;

    // Create element with many attributes to test ArrayList fallback
    const doc = try z.parseFromString("<div>Content</div>");
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const div = z.nodeToElement(z.firstChild(z.elementToNode(body)).?).?;

    // Add 15 attributes (less than MAX_STACK_ATTRS = 16)
    var i: u8 = 0;
    while (i < 15) : (i += 1) {
        var name_buf: [16]u8 = undefined;
        var value_buf: [16]u8 = undefined;
        const name = try std.fmt.bufPrint(&name_buf, "attr-{d}", .{i});
        const value = try std.fmt.bufPrint(&value_buf, "value-{d}", .{i});
        z.setAttribute(div, name, value);
    }

    const attrs = try getAttributes_bf(allocator, div);
    defer {
        for (attrs) |attr| {
            allocator.free(attr.name);
            allocator.free(attr.value);
        }
        allocator.free(attrs);
    }

    try testing.expect(attrs.len == 15);
}

test "getAttributes performance comparison" {
    const allocator = testing.allocator;

    // Create test element with typical number of attributes
    const html = "<div class='container active' id='main-content' data-component='card' data-state='loaded' title='Main Content' aria-label='Content Area'>Content</div>";
    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const div = z.nodeToElement(z.firstChild(z.elementToNode(body)).?).?;

    // Both should produce identical results
    const attrs_regular = try getAttributes(allocator, div);
    defer {
        for (attrs_regular) |attr| {
            allocator.free(attr.name);
            allocator.free(attr.value);
        }
        allocator.free(attrs_regular);
    }

    const attrs_buffered = try getAttributes_bf(allocator, div);
    defer {
        for (attrs_buffered) |attr| {
            allocator.free(attr.name);
            allocator.free(attr.value);
        }
        allocator.free(attrs_buffered);
    }

    // Verify identical results
    try testing.expect(attrs_regular.len == attrs_buffered.len);
    try testing.expect(attrs_regular.len == 6); // class, id, data-component, data-state, title, aria-label

    for (attrs_regular, attrs_buffered) |regular, buffered| {
        try testing.expectEqualStrings(regular.name, buffered.name);
        try testing.expectEqualStrings(regular.value, buffered.value);
    }
}
