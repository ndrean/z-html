//! Manage CSS class lists as DomTokenList like and direct access utilities

// ---------------------------------------------------
// ClassList utilties
// ---------------------------------------------------

const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

const testing = std.testing;
const print = std.debug.print;

extern "c" fn lxb_dom_element_class_attribute_noi(element: *z.HTMLElement) *z.DomAttr;
extern "c" fn lxb_dom_element_class_noi(element: *z.HTMLElement, len: *usize) [*]const u8;

/// [classList] Get the raw class attribute value as a zero-copy slice.
pub fn classList_zc(element: *z.HTMLElement) []const u8 {
    var size: usize = 0;
    const class = lxb_dom_element_class_noi(element, &size);
    return class[0..size];
}

test "classList_zc" {
    const doc = try z.createDocFromString("<p id=\"1\" class= \"bold main\"></p><p id=\"2\"></p>");
    defer z.destroyDocument(doc);
    const element1 = z.getElementById(z.bodyNode(doc).?, "1");
    const class_list = classList_zc(element1.?);
    try testing.expectEqualStrings("bold main", class_list);

    const element2 = z.getElementById(z.bodyNode(doc).?, "2");
    const class_list2 = classList_zc(element2.?);
    try testing.expectEqualStrings("", class_list2);
}

// ====================================================================

/// [classList] Check if element has specific class without creating the classList
pub fn hasClass(element: *z.HTMLElement, class_name: []const u8) bool {
    // if (!z.hasAttribute(element, "class")) return false;

    const class_list = classList_zc(element); //orelse return false;
    return z.stringContains(class_list, class_name);

    // // Get class string directly from lexbor (zero-copy)
    // const class_attr = z.getAttribute_zc(element, "class") orelse return false;

    // // Search for the class name in the class list (space-separated)
    // var iterator = std.mem.splitScalar(u8, class_attr, ' ');
    // while (iterator.next()) |class| {
    //     // Trim whitespace and compare
    //     const trimmed_class = std.mem.trim(u8, class, " \t\n\r");
    //     if (std.mem.eql(u8, trimmed_class, class_name)) {
    //         return true;
    //     }
    // }
    // return false;
}

test "hasClass" {
    const doc = try z.createDocFromString("<p id=\"1\" class= \"bold main\"></p><p id=\"2\"></p>");
    defer z.destroyDocument(doc);
    const element1 = z.getElementById(z.bodyNode(doc).?, "1");
    try testing.expect(hasClass(element1.?, "bold"));
    try testing.expect(hasClass(element1.?, "main"));
    try testing.expect(!hasClass(element1.?, "italic"));

    const element2 = z.getElementById(z.bodyNode(doc).?, "2");
    try testing.expect(!hasClass(element2.?, "bold"));
}

/// [classList] Get class list as string without creating the classList
///
/// Caller owns the slice
pub fn classListAsString(allocator: std.mem.Allocator, element: *z.HTMLElement) ![]u8 {
    const class_list = classList_zc(element);

    if (class_list.len == 0) {
        return try allocator.dupe(u8, "");
    }

    // Copy lexbor -> Zig-managed memory
    const class_string = try allocator.alloc(u8, class_list.len);
    @memcpy(class_string, class_list.ptr[0..class_list.len]);
    return class_string;
}

test "classListAsString" {
    const allocator = testing.allocator;

    const doc = try z.createDocFromString("<p id=\"1\" class= \"bold main\"></p><p id=\"2\"></p>");
    defer z.destroyDocument(doc);
    const element1 = z.getElementById(z.bodyNode(doc).?, "1");
    const class_string = try classListAsString(allocator, element1.?);
    defer allocator.free(class_string);
    try testing.expectEqualStrings("bold main", class_string);

    const element2 = z.getElementById(z.bodyNode(doc).?, "2");
    const class_string2 = try classListAsString(allocator, element2.?);
    defer allocator.free(class_string2);
    try testing.expectEqualStrings("", class_string2);
}

// ===================================================================

/// [classList] DOMTTokenList Browser-like for clasees.
///
/// Caller must use `class_list.deinit()` to free the allocations.
///
///  Methods: `init`, `deinit`, `length`, `contains`, `add`, `remove`, `toggle`, `replace`, `clear`, `toString`, `toSlice`
pub const ClassList = struct {
    allocator: std.mem.Allocator,
    element: *z.HTMLElement,
    classes: std.StringHashMap(void),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, element: *z.HTMLElement) !Self {
        var token_list = Self{
            .allocator = allocator,
            .element = element,
            // build a SET of the classes as keys and use empty strings as values
            .classes = std.StringHashMap(void).init(allocator),
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
        const borrowed_classes = classList_zc(self.element);

        if (borrowed_classes.len == 0) return;

        // Parse and add classes to set
        var split_iterator = std.mem.splitScalar(
            u8,
            borrowed_classes,
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
    }

    /// Sync changes back to the DOM element
    fn sync(self: *Self) !void {
        var class_string: std.ArrayList(u8) = .empty;
        defer class_string.deinit(self.allocator);

        var iter = self.classes.iterator();
        var first = true;
        while (iter.next()) |entry| {
            if (!first) try class_string.append(self.allocator, ' ');
            first = false;
            try class_string.appendSlice(self.allocator, entry.key_ptr.*);
        }

        _ = z.setAttribute(
            self.element,
            "class",
            class_string.items,
        );
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
            return;
        }

        if (self.contains(class_name)) return;

        const class_copy = try self.allocator.dupe(u8, class_name);
        try self.classes.put(class_copy, {});
        try self.sync();
    }

    /// Remove a class
    // we must use `fetchRemove` to get the removed key to deallocate the key slice
    pub fn remove(self: *Self, class_name: []const u8) !void {
        if (self.classes.fetchRemove(class_name)) |removed| {
            self.allocator.free(removed.key);
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

    /// Replace one class with another
    pub fn replace(self: *Self, old_class: []const u8, new_class: []const u8) !bool {
        if (new_class.len == 0 or std.mem.indexOfAny(u8, new_class, " \t\n\r") != null) {
            return false;
        }

        if (!self.contains(old_class)) return false;

        try self.remove(old_class);
        try self.add(new_class);
        return true;
    }

    /// Clear all classes
    pub fn clear(self: *Self) !void {
        var iter = self.classes.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.classes.clearRetainingCapacity();
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
    pub fn toString(self: *const Self) ![]u8 {
        var class_string: std.ArrayList(u8) = .empty;
        defer class_string.deinit(self.allocator);

        var iter = self.classes.iterator();
        var first = true;
        while (iter.next()) |entry| {
            if (!first) try class_string.append(self.allocator, ' ');
            first = false;
            try class_string.appendSlice(self.allocator, entry.key_ptr.*);
        }

        return class_string.toOwnedSlice(self.allocator);
    }
};

/// Use a `ClassList` instance (eq DomTokenList) for an element with its methods.
///
/// - Use `class_list.init(allocator, elememnt)` to create a new instance.
///
/// - Use `class_list.deinit()` to free the allocations.
///
/// Caller must use `class_list.deinit()` to free the allocations.
///
/// To access the classList as a string, prefer `classListAsString` (or `classList_zc`).
///
/// The methods available on `classList` include:
/// - `add`: Add a class
/// - `remove`: Remove a class
/// - `toggle`: Toggle a class
/// - `replace`: Replace one class with another
/// - `clear`: Clear all classes
/// - `toString`: Get the classList as a string
/// - `toSlice`: Convert the classList to a slice
/// ## Example
/// ```
/// <p class="bold main"></p>
///
/// const class_list = try z.classList(allocator, p);
/// defer class_list.deinit();
/// std.debug.assert(class_list.contains("main"));
/// _ = try class_list.toggle("main");
/// std.debug.assert(!class_list.contains("main"));
/// class_list.add("container");
/// try class_list.replace("bold", "italic");
/// std.debug.assert(class_list.contains("italic"));
/// std.debug.assert(!class_list.contains("bold"));
/// ```
pub fn classList(allocator: std.mem.Allocator, element: *z.HTMLElement) !ClassList {
    return ClassList.init(allocator, element);
}

test "classList" {
    const allocator = testing.allocator;

    const doc = try z.createDocFromString("<p class=\"bold main\"></p>");
    const body = z.bodyNode(doc).?;
    const p = z.nodeToElement(z.firstChild(body).?).?;

    var class_list = try z.classList(allocator, p);
    defer class_list.deinit();

    std.debug.assert(class_list.contains("main"));
    _ = try class_list.toggle("main");
    std.debug.assert(!class_list.contains("main"));
    _ = try class_list.toggle("main");
    try testing.expect(class_list.contains("main"));
    _ = try class_list.add("container");
    try testing.expect(class_list.contains("container"));
    _ = try class_list.replace("bold", "italic");
    try testing.expect(class_list.contains("italic"));
    try testing.expect(!class_list.contains("bold"));
    const class_list_string = try class_list.toString();
    defer allocator.free(class_list_string);
    try testing.expect(std.mem.eql(u8, class_list_string, "container main italic"));
}

test "ClassList set operations" {
    const allocator = testing.allocator;

    const doc = try z.createDocFromString("<p></p>");
    const body = z.bodyNode(doc).?;
    const p = z.nodeToElement(z.firstChild(body).?).?;
    var token_list = try ClassList.init(
        allocator,
        p,
    );
    defer token_list.deinit();

    // Test basic operations
    try token_list.add("active");
    try token_list.add("button");
    try token_list.add("primary");
    try token_list.sync();

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

    try token_list.sync();

    const lxb_classes = classList_zc(p);
    const token_list_classes = try token_list.toString();
    defer allocator.free(token_list_classes);
    try testing.expectEqualStrings(lxb_classes, token_list_classes[0..token_list_classes.len]);

    // // Test replace
    // const replaced = try token_list.replace("active", "inactive");
    // try testing.expect(replaced == true);
    // try testing.expect(!token_list.contains("active"));
    // try testing.expect(token_list.contains("inactive"));
}

test "ClassList performance with lxb check" {
    const allocator = testing.allocator;

    const doc = try z.createDocFromString("<p></p>");
    const body = z.bodyNode(doc).?;
    const p = z.nodeToElement(z.firstChild(body).?).?;
    var token_list = try ClassList.init(
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

    const classes = classList_zc(p);

    // Test contains performance - O(1) lookups
    var found_count: usize = 0;
    var found_lxb_count: usize = 0;
    for (0..num_classes) |i| {
        const class_name = try std.fmt.allocPrint(allocator, "class-{}", .{i});
        defer allocator.free(class_name);
        if (token_list.contains(class_name)) {
            found_count += 1;
        }
        try testing.expect(hasClass(p, class_name));
        if (z.stringContains(classes, class_name)) {
            found_lxb_count += 1;
        }
    }

    try testing.expect(found_count == num_classes);
    try testing.expect(found_lxb_count == num_classes);
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

    const doc = try z.createDocFromString(html);
    defer z.destroyDocument(doc);

    const body_node = z.bodyNode(doc).?;
    var child = z.firstChild(body_node);

    // Test hasClass function and compare with existing classList
    while (child != null) {
        if (z.nodeToElement(child.?)) |element| {
            const element_name = z.tagName_zc(element);
            if (std.mem.eql(u8, element_name, "DIV")) {
                const text_content = z.textContent_zc(child.?);
                if (std.mem.eql(u8, text_content, "First div")) {
                    // First div should have three classes
                    try testing.expect(z.hasClass(element, "container"));
                    try testing.expect(z.hasClass(element, "main"));
                    try testing.expect(z.hasClass(element, "active"));
                    try testing.expect(!z.hasClass(element, "missing"));

                    var tokenList_1 = try z.ClassList.init(
                        allocator,
                        element,
                    );
                    defer tokenList_1.deinit();

                    try testing.expect(tokenList_1.length() == 3);
                    try testing.expect(tokenList_1.contains("container"));
                    try testing.expect(tokenList_1.contains("main"));
                    try testing.expect(tokenList_1.contains("active"));
                    try testing.expect(!tokenList_1.contains("missing"));

                    // Test new getClasses function - returns array of individual classes
                    const classes = try tokenList_1.toSlice(allocator);
                    // defer {
                    //     for (classes) |class| allocator.free(class);
                    //     allocator.free(classes);
                    // }
                    defer allocator.free(classes);
                    try testing.expect(classes.len == 3);
                    try testing.expect(tokenList_1.contains("container"));
                    try testing.expect(tokenList_1.contains("main"));
                    try testing.expect(tokenList_1.contains("active"));
                } else if (std.mem.eql(u8, text_content, "Second div")) {
                    // Second div should have container and secondary
                    try testing.expect(z.hasClass(element, "container"));
                } else if (std.mem.eql(u8, text_content, "No class div")) {
                    // Third div should have no classes
                    try testing.expect(!z.hasClass(element, "container"));
                    try testing.expect(!z.hasClass(element, "any"));

                    // classList should return null for elements with no class attribute
                    var tokenList_2 = try z.classList(
                        allocator,
                        element,
                    );
                    defer tokenList_2.deinit();
                    try testing.expect(tokenList_2.length() == 0);
                }
            } else if (std.mem.eql(u8, element_name, "SPAN")) {
                // Span should have active class
                try testing.expect(z.hasClass(element, "active"));
                try testing.expect(!z.hasClass(element, "container"));
                var tokenList_3 = try z.classList(
                    allocator,
                    element,
                );
                defer tokenList_3.deinit();
                try testing.expect(tokenList_3.length() == 1);
                try testing.expect(tokenList_3.contains("active"));
                try testing.expect(!tokenList_3.contains("container"));
            }
        }
        child = z.nextSibling(child.?);
    }
}
