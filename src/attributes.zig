//----------------------------------------------------------------------
// ATTRIBUTE FUNCTIONS
//----------------------------------------------------------------------

const std = @import("std");

const testing = std.testing;
const print = std.debug.print;

const lxb = @import("lexbor.zig");
const Err = @import("errors.zig").LexborError;

extern "c" fn lxb_dom_element_get_attribute(
    element: *lxb.DomElement,
    name: [*]const u8,
    name_len: usize,
    value_len: *usize,
) ?[*]const u8;

extern "c" fn lxb_dom_element_has_attribute(
    element: *lxb.DomElement,
    name: [*]const u8,
    name_len: usize,
) bool;

extern "c" fn lxb_dom_element_set_attribute(
    element: *lxb.DomElement,
    name: [*]const u8,
    name_len: usize,
    value: [*]const u8,
    value_len: usize,
) ?*anyopaque;

/// Get attribute value
pub fn getAttribute(
    allocator: std.mem.Allocator,
    element: *lxb.DomElement,
    name: []const u8,
) !?[]u8 {
    var value_len: usize = 0;
    const value_ptr = lxb_dom_element_get_attribute(
        element,
        name.ptr,
        name.len,
        &value_len,
    ) orelse return null;

    const result = try allocator.alloc(u8, value_len);
    @memcpy(result, value_ptr[0..value_len]);
    return result;
}

/// Check if element has attribute
pub fn hasAttribute(element: *lxb.DomElement, name: []const u8) bool {
    return lxb_dom_element_has_attribute(
        element,
        name.ptr,
        name.len,
    );
}

/// Set attribute on element
pub fn setAttribute(element: *lxb.DomElement, name: []const u8, value: []const u8) !void {
    const result = lxb_dom_element_set_attribute(
        element,
        name.ptr,
        name.len,
        value.ptr,
        value.len,
    );
    if (result == null) return Err.SetAttributeFailed;
}

/// Get attribute value as string (borrowed - don't free)
pub fn getAttributeValue(element: *lxb.DomElement, name: []const u8) ?[]const u8 {
    var value_len: usize = 0;
    const value_ptr = lxb_dom_element_get_attribute(
        element,
        name.ptr,
        name.len,
        &value_len,
    ) orelse return null;
    return value_ptr[0..value_len];
}

test "attribute management" {
    const allocator = testing.allocator;

    const html =
        \\<div>
        \\  <p id="para1" class="highlight important" data-value="123">Hello</p>
        \\  <span title="tooltip text" hidden>World</span>
        \\  <img src="image.jpg" alt="description" width="100" height="50">
        \\  <input type="text" name="username" value="" placeholder="Enter name">
        \\</div>
    ;

    const doc = try lxb.parseFragmentAsDocument(html);
    defer lxb.destroyDocument(doc);

    const body = lxb.getBodyElement(doc).?;
    const body_node = lxb.elementToNode(body);
    const div_node = lxb.getFirstChild(body_node).?;

    // Get all element children for testing
    const elements = try lxb.getElementChildren(allocator, div_node);
    defer allocator.free(elements);
    // print("{d}\n", .{elements.len});
    // for (elements) |element| {
    //     print("Element: {s}\n", .{getElementName(element)});
    // }

    try testing.expect(elements.len == 4); // p, span, img, input

    // Test 1: hasAttribute
    // print("\n=== Testing hasAttribute ===\n", .{});
    const p_element = elements[0];

    try testing.expect(hasAttribute(p_element, "id"));
    try testing.expect(hasAttribute(p_element, "class"));
    try testing.expect(hasAttribute(p_element, "data-value"));
    try testing.expect(!hasAttribute(p_element, "nonexistent"));

    // print("✅ hasAttribute tests passed\n", .{});

    // Test 2: getAttribute

    if (try getAttribute(allocator, p_element, "id")) |id_value| {
        defer allocator.free(id_value);
        try testing.expectEqualStrings("para1", id_value);
        // print("ID: '{s}'\n", .{id_value});
    } else {
        try testing.expect(false); // Should have ID
    }

    if (try getAttribute(allocator, p_element, "class")) |class_value| {
        defer allocator.free(class_value);
        try testing.expectEqualStrings("highlight important", class_value);
        // print("Class: '{s}'\n", .{class_value});
    }

    if (try getAttribute(allocator, p_element, "data-value")) |data_value| {
        defer allocator.free(data_value);
        try testing.expectEqualStrings("123", data_value);
        // print("Data: '{s}'\n", .{data_value});
    }

    // Non-existent attribute should return null
    const missing = try getAttribute(allocator, p_element, "missing");
    try testing.expect(missing == null);

    // Test 3: getAttributeValue - borrowed memory (faster)
    // print("\n=== Testing getAttributeValue (borrowed) ===\n", .{});

    if (getAttributeValue(p_element, "id")) |id_borrowed| {
        try testing.expectEqualStrings("para1", id_borrowed);
        // print("Borrowed ID: '{s}'\n", .{id_borrowed});
    }
    if (getAttributeValue(p_element, "data-value")) |data_value| {
        try testing.expectEqualStrings("123", data_value);
        // print("Borrowed Data: '{s}'\n", .{data_value});
    }

    // print("✅ getAttributeValue tests passed\n", .{});

    // Test 4: Test different element types
    // std.debug.print("\n=== Testing different elements ===\n", .{});

    const span_element = elements[1];
    const img_element = elements[2];
    const input_element = elements[3];

    // Span attributes
    if (getAttributeValue(span_element, "hidden")) |hidden_value| {
        try testing.expectEqualStrings("true", hidden_value);
        // print("Hidden: '{s}'\n", .{hidden_value});
    }
    if (getAttributeValue(span_element, "title")) |title| {
        // defer allocator.free(title);
        try testing.expectEqualStrings("tooltip text", title);
        // print("Span title: '{s}'\n", .{title});
    }

    try testing.expect(hasAttribute(span_element, "hidden"));

    // Image attributes
    if (try getAttribute(allocator, img_element, "src")) |src| {
        defer allocator.free(src);
        try testing.expectEqualStrings("image.jpg", src);
    }

    if (try getAttribute(allocator, img_element, "width")) |width| {
        defer allocator.free(width);
        try testing.expectEqualStrings("100", width);
    }

    // Input attributes
    if (try getAttribute(allocator, input_element, "type")) |input_type| {
        defer allocator.free(input_type);
        try testing.expectEqualStrings("text", input_type);
    }

    if (try getAttribute(allocator, input_element, "placeholder")) |placeholder| {
        defer allocator.free(placeholder);
        try testing.expectEqualStrings("Enter name", placeholder);
    }

    // print("✅ Different element tests passed\n", .{});
}

test "setAttribute functionality" {
    const allocator = testing.allocator;

    // Create a simple element to modify
    const html = "<div><p>Original content</p></div>";
    const doc = try lxb.parseFragmentAsDocument(html);
    defer lxb.destroyDocument(doc);

    const body = lxb.getBodyElement(doc).?;
    const body_node = lxb.elementToNode(body);
    const div_node = lxb.getFirstChild(body_node).?;
    const p_node = lxb.getFirstChild(div_node).?;
    const p_element = lxb.nodeToElement(p_node).?;

    // print("\n=== Testing setAttribute ===\n", .{});

    // Test 1: Add new attributes
    try setAttribute(p_element, "id", "new-id");
    try setAttribute(p_element, "class", "new-class");
    try setAttribute(p_element, "data-test", "test-value");

    // Verify attributes were set
    try testing.expect(hasAttribute(p_element, "id"));
    try testing.expect(hasAttribute(p_element, "class"));
    try testing.expect(hasAttribute(p_element, "data-test"));

    // Check values
    if (getAttributeValue(p_element, "id")) |id| {
        try testing.expectEqualStrings("new-id", id);
        // print("Set ID: '{s}'\n", .{id});
    }

    if (try getAttribute(allocator, p_element, "class")) |class| {
        defer allocator.free(class);
        try testing.expectEqualStrings("new-class", class);
        // print("Set class: '{s}'\n", .{class});
    }

    // Test 2: Modify existing attributes
    try setAttribute(p_element, "id", "modified-id");

    if (try getAttribute(allocator, p_element, "id")) |modified_id| {
        defer allocator.free(modified_id);
        try testing.expectEqualStrings("modified-id", modified_id);
        // print("Modified ID: '{s}'\n", .{modified_id});
    }

    // Test 3: Set empty value
    try setAttribute(p_element, "empty-attr", "");
    try testing.expect(hasAttribute(p_element, "empty-attr"));

    if (try getAttribute(allocator, p_element, "empty-attr")) |empty| {
        defer allocator.free(empty);
        try testing.expectEqualStrings("", empty);
    }

    // Test 4: Serialize to see the result
    const serialized = try lxb.serializeTree(allocator, div_node);
    defer allocator.free(serialized);

    // print("Final HTML: {s}\n", .{serialized});

    // Should contain our new attributes
    try testing.expect(std.mem.indexOf(u8, serialized, "id=\"modified-id\"") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "class=\"new-class\"") != null);
}

test "attribute edge cases" {
    const allocator = testing.allocator;

    const html = "<div><p>Test</p><img><input type='text'></div>";
    const doc = try lxb.parseFragmentAsDocument(html);
    defer lxb.destroyDocument(doc);

    const body = lxb.getBodyElement(doc).?;
    const body_node = lxb.elementToNode(body);
    const div_node = lxb.getFirstChild(body_node).?;

    var child = lxb.getFirstChild(div_node);
    var element_count: u32 = 0;

    // print("\n=== Testing edge cases ===\n", .{});

    while (child != null) {
        if (lxb.nodeToElement(child.?)) |element| {
            element_count += 1;
            // const element_name = getNodeName(child.?);
            // print("Testing element: {s}\n", .{element_name});

            // Test getting non-existent attributes
            const missing = try getAttribute(allocator, element, "does-not-exist");
            try testing.expect(missing == null);

            // Test setting attributes with special characters
            try setAttribute(element, "data-special", "value with spaces & symbols!");

            if (try getAttribute(allocator, element, "data-special")) |special| {
                defer allocator.free(special);
                try testing.expectEqualStrings("value with spaces & symbols!", special);
                // print("Special attribute: '{s}'\n", .{special});
            }
        }
        child = lxb.getNextSibling(child.?);
    }

    try testing.expect(element_count >= 3); // p, img, input
    // print("✅ Edge case tests passed\n", .{});
}
