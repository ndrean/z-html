//! Manage CSS class lists

// ---------------------------------------------------
// ClassList utilties
// ---------------------------------------------------

const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

const testing = std.testing;

extern "c" fn lxb_dom_element_class_noi(element: *z.DomElement, length: *usize) [*]const u8;

// ====================================================================

/// [classList] Check if element has specific class without creating the classList
pub fn hasClass(element: *z.DomElement, class_name: []const u8) bool {
    // Quick check: does element have class attribute at all?
    if (!z.hasAttribute(element, "class")) return false;

    // Get class string directly from lexbor (zero-copy)
    const class_attr = z.getAttribute_zc(element, "class") orelse return false;

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

/// [classList] Get the class attribute list as a borrowed string from lexbor
///
/// Unsafe: Use it only for parsing
fn classListAsString_zc(element: *z.DomElement) ?[]const u8 {
    if (!z.hasAttribute(element, "class")) return null;

    var class_len: usize = 0;
    const list = lxb_dom_element_class_noi(element, &class_len);
    return list[0..class_len];
}

/// [classList] Get class list as string without creating the classList
///
/// Return
/// Caller owns the slice
pub fn classListAsString(allocator: std.mem.Allocator, element: *z.DomElement) ![]u8 {
    var class_len: usize = 0;
    const class_ptr = lxb_dom_element_class_noi(
        element,
        &class_len,
    );

    // If no class or empty class
    if (class_len == 0) {
        return try allocator.dupe(u8, "");
    }

    // Copy lexbor memory to Zig-managed memory
    const class_string = try allocator.alloc(u8, class_len);
    @memcpy(class_string, class_ptr[0..class_len]);
    return class_string;
}

// ===================================================================

/// [classList] Browser-like DOMTokenList using StringHashMap as a set
pub const DOMTokenList = struct {
    allocator: std.mem.Allocator,
    element: *z.DomElement,
    classes: std.StringHashMap(void),
    dirty: bool = false,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, element: *z.DomElement) !Self {
        var token_list = Self{
            .allocator = allocator,
            .element = element,
            // build a SET of the classes as keys and use empty strings as values
            .classes = std.StringHashMap(void).init(allocator),
            .dirty = false,
        };

        try token_list.refresh();
        return token_list;
    }

    pub fn deinit(self: *Self) void {
        var iter = self.classes.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.classes.deinit();
    }

    /// Refresh classes from the DOM element
    fn refresh(self: *Self) !void {
        // Clear existing data
        var iter = self.classes.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.classes.clearRetainingCapacity();

        // Get class string from DOM
        const borrowed_classes = classListAsString_zc(self.element);

        if (borrowed_classes == null) return;

        // Parse and add classes to set
        var split_iterator = std.mem.splitScalar(
            u8,
            borrowed_classes.?,
            ' ',
        );
        // create owned copies
        while (split_iterator.next()) |class| {
            const trimmed_class = std.mem.trim(u8, class, " \t\n\r");
            if (trimmed_class.len > 0) {
                const class_copy = try self.allocator.dupe(u8, trimmed_class);
                try self.classes.put(class_copy, {});
            }
        }

        self.dirty = false;
    }

    /// Sync changes back to the DOM element
    fn sync(self: *Self) !void {
        if (!self.dirty) return;

        var class_string = std.ArrayList(u8).init(self.allocator);
        defer class_string.deinit();

        var iter = self.classes.iterator();
        var first = true;
        while (iter.next()) |entry| {
            if (!first) try class_string.append(' ');
            first = false;
            try class_string.appendSlice(entry.key_ptr.*);
        }

        _ = z.setAttribute(
            self.element,
            "class",
            class_string.items,
        );
        self.dirty = false;
    }

    /// Get the number of classes
    pub fn length(self: *const Self) usize {
        return self.classes.count();
    }

    /// Check if a class exists
    pub fn contains(self: *const Self, class_name: []const u8) bool {
        return self.classes.contains(class_name);
    }

    /// Add a class
    pub fn add(self: *Self, class_name: []const u8) !void {
        if (class_name.len == 0 or std.mem.indexOfAny(u8, class_name, " \t\n\r") != null) {
            return Err.InvalidClassName;
        }

        if (self.contains(class_name)) return;

        const class_copy = try self.allocator.dupe(u8, class_name);
        try self.classes.put(class_copy, {});
        self.dirty = true;
        try self.sync();
    }

    /// Remove a class
    // we must use `fetchRemove` to get the removed key to deallocate the key slice
    pub fn remove(self: *Self, class_name: []const u8) !void {
        if (self.classes.fetchRemove(class_name)) |removed| {
            self.allocator.free(removed.key);
            self.dirty = true;
            try self.sync();
        }
    }

    /// Toggle a class
    pub fn toggle(self: *Self, class_name: []const u8) !bool {
        if (self.contains(class_name)) {
            try self.remove(class_name);
            return false;
        } else {
            try self.add(class_name);
            return true;
        }
    }

    // /// Replace one class with another
    // pub fn replace(self: *Self, old_class: []const u8, new_class: []const u8) !bool {
    //     if (new_class.len == 0 or std.mem.indexOfAny(u8, new_class, " \t\n\r") != null) {
    //         return Err.InvalidClassName;
    //     }

    //     if (!self.contains(old_class)) return false;

    //     try self.remove(old_class);
    //     try self.add(new_class);
    //     return true;
    // }

    /// Clear all classes
    pub fn clear(self: *Self) !void {
        var iter = self.classes.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.classes.clearRetainingCapacity();
        self.dirty = true;
        try self.sync();
    }

    // /// Iterator over all classes
    // pub fn iterator(self: *const Self) ClassIterator {
    //     return ClassIterator{
    //         .map_iterator = self.classes.iterator(),
    //     };
    // }

    /// Convert to slice (useful for debugging or testing)
    pub fn toSlice(self: *const Self, allocator: std.mem.Allocator) ![][]const u8 {
        var result = try allocator.alloc([]const u8, self.length());

        var iter = self.classes.iterator();
        var i: usize = 0;
        while (iter.next()) |entry| {
            result[i] = entry.key_ptr.*;
            i += 1;
        }

        return result;
    }

    /// Get class string as it would appear in DOM
    pub fn toString(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        var class_string = std.ArrayList(u8).init(allocator);
        defer class_string.deinit();

        var iter = self.classes.iterator();
        var first = true;
        while (iter.next()) |entry| {
            if (!first) try class_string.append(' ');
            first = false;
            try class_string.appendSlice(entry.key_ptr.*);
        }

        return class_string.toOwnedSlice();
    }
};

/// Convenience function to get classList for an element
pub fn classList(allocator: std.mem.Allocator, element: *z.DomElement) !DOMTokenList {
    return DOMTokenList.init(allocator, element);
}

test "DOMTokenList set operations" {
    const allocator = testing.allocator;

    const doc = try z.parseFromString("<p></p>");
    const body = try z.bodyNode(doc);
    const p = z.nodeToElement(z.firstChild(body).?).?;
    var token_list = try DOMTokenList.init(
        allocator,
        p,
    );
    defer token_list.deinit();

    // Test basic operations
    try token_list.add("active");
    try token_list.add("button");
    try token_list.add("primary");

    try testing.expect(token_list.length() == 3);
    try testing.expect(token_list.contains("active"));
    try testing.expect(token_list.contains("button"));
    try testing.expect(token_list.contains("primary"));

    // Test duplicate add (should be ignored)
    try token_list.add("active");
    try testing.expect(token_list.length() == 3);

    // Test remove
    try token_list.remove("button");
    try testing.expect(!token_list.contains("button"));
    try testing.expect(token_list.length() == 2);

    // Test toggle
    const added = try token_list.toggle("new-class");
    try testing.expect(added == true);
    try testing.expect(token_list.contains("new-class"));

    const removed = try token_list.toggle("new-class");
    try testing.expect(removed == false);
    try testing.expect(!token_list.contains("new-class"));

    // // Test replace
    // const replaced = try token_list.replace("active", "inactive");
    // try testing.expect(replaced == true);
    // try testing.expect(!token_list.contains("active"));
    // try testing.expect(token_list.contains("inactive"));
}

test "DOMTokenList performance" {
    const allocator = testing.allocator;

    const doc = try z.parseFromString("<p></p>");
    const body = try z.bodyNode(doc);
    const p = z.nodeToElement(z.firstChild(body).?).?;
    var token_list = try DOMTokenList.init(
        allocator,
        p,
    );
    defer token_list.deinit();

    // Add many classes - should be fast
    const num_classes = 100;
    for (0..num_classes) |i| {
        const class_name = try std.fmt.allocPrint(allocator, "class-{}", .{i});
        defer allocator.free(class_name);
        try token_list.add(class_name);
    }

    // Test contains performance - O(1) lookups
    var found_count: usize = 0;
    for (0..num_classes) |i| {
        const class_name = try std.fmt.allocPrint(allocator, "class-{}", .{i});
        defer allocator.free(class_name);
        if (token_list.contains(class_name)) {
            found_count += 1;
        }
    }

    try testing.expect(found_count == num_classes);
    try testing.expect(token_list.length() == num_classes);
}

test "class search functionality" {
    const allocator = testing.allocator;

    // Create HTML with multiple classes
    const html =
        \\<div class="container main active">First div</div>
        \\<div class="container secondary">Second div</div>
        \\<span class="active">Span element</span>
        \\<div>No class div</div>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body_node = try z.bodyNode(doc);
    var child = z.firstChild(body_node);

    // Test hasClass function and compare with existing classList
    while (child != null) {
        if (z.nodeToElement(child.?)) |element| {
            const element_name = z.tagName_zc(element);
            if (std.mem.eql(u8, element_name, "div")) {
                const text_content = try z.getTextContent(allocator, child.?);
                defer allocator.free(text_content);
                if (std.mem.eql(u8, text_content, "First div")) {
                    // First div should have all three classes
                    try testing.expect(z.hasClass(element, "container"));
                    try testing.expect(z.hasClass(element, "main"));
                    try testing.expect(z.hasClass(element, "active"));
                    try testing.expect(!z.hasClass(element, "missing"));

                    // Test unified classList function - returns full class string
                    var tokenList_1 = try z.DOMTokenList.init(
                        allocator,
                        element,
                    );
                    defer tokenList_1.deinit();
                    try testing.expect(tokenList_1.length() == 4);
                    try testing.expect(tokenList_1.contains("container"));
                    try testing.expect(tokenList_1.contains("main"));
                    try testing.expect(tokenList_1.contains("active"));
                    try testing.expect(!tokenList_1.contains("missing"));

                    // Test new getClasses function - returns array of individual classes
                    const classes = try tokenList_1.toSlice(allocator);
                    defer {
                        for (classes) |class| allocator.free(class);
                        allocator.free(classes);
                    }
                    try testing.expect(classes.len == 4);
                    try testing.expect(std.mem.eql(u8, classes[0], "container"));
                    try testing.expect(std.mem.eql(u8, classes[1], "main"));
                    try testing.expect(std.mem.eql(u8, classes[2], "active"));
                } else if (std.mem.eql(u8, text_content, "Second div")) {
                    // Second div should have container and secondary
                    try testing.expect(z.hasClass(element, "container"));
                    try testing.expect(z.hasClass(element, "secondary"));
                    try testing.expect(!z.hasClass(element, "main"));
                    try testing.expect(!z.hasClass(element, "active"));
                } else if (std.mem.eql(u8, text_content, "No class div")) {
                    // Third div should have no classes
                    try testing.expect(!z.hasClass(element, "container"));
                    try testing.expect(!z.hasClass(element, "any"));

                    // classList should return null for elements with no class attribute
                    var tokenList_2 = try z.DOMTokenList.init(
                        allocator,
                        element,
                    );
                    defer tokenList_2.deinit();
                    try testing.expect(tokenList_2.length() == 0);
                }
            } else if (std.mem.eql(u8, element_name, "span")) {
                // Span should have active class
                try testing.expect(z.hasClass(element, "active"));
                try testing.expect(!z.hasClass(element, "container"));
                var tokenList_3 = try z.DOMTokenList.init(
                    allocator,
                    element,
                );
                defer tokenList_3.deinit();
                try testing.expect(tokenList_3.length() == 2);
                try testing.expect(tokenList_3.contains("active"));
                try testing.expect(!tokenList_3.contains("container"));
            }
        }
        child = z.nextSibling(child.?);
    }
}

// test "ID and CLASS attribute getters" {
//     const allocator = testing.allocator;

//     const html = "<section class='main-section' id='content'>Section content</section>";
//     const doc = try z.parseFromString(html);
//     defer z.destroyDocument(doc);

//     const body_node = try z.bodyNode(doc);
//     const section_node = z.firstChild(body_node);
//     const section_element = z.nodeToElement(section_node.?).?;

//     // Test ID getter
//     const id = try getElementId(allocator, section_element);
//     defer allocator.free(id);
//     try testing.expectEqualStrings("content", id);

//     // Test class getter using unified classList
//     const class_result = try classList(
//         allocator,
//         section_element,
//         .string,
//     );
//     const class = class_result.string;
//     defer allocator.free(class);
//     try testing.expectEqualStrings("main-section", class);

//     const class_result_bis = try classListBis(
//         allocator,
//         section_element,
//     );
//     defer allocator.free(class_result_bis);
//     try testing.expectEqualStrings(&.{"main-section"}, class_result_bis);

//     // print("✅ ID and CLASS attribute getters\n", .{});
// }
