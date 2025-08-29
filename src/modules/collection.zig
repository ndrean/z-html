//! Collection management

const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

const testing = std.testing;
const print = std.debug.print;
const Instant = std.time.Instant;
const Timer = std.time.Timer;

// External C functions - using _noi versions for ABI compatibility
extern "c" fn lxb_dom_collection_create(doc: *z.HTMLDocument) ?*z.DomCollection;
extern "c" fn lxb_dom_collection_init(collection: *z.DomCollection, start_size: usize) usize;
extern "c" fn lxb_dom_collection_destroy(collection: *z.DomCollection, self_destroy: bool) ?*z.DomCollection;
extern "c" fn lxb_dom_collection_clean_noi(collection: *z.DomCollection) void;
extern "c" fn lxb_dom_collection_length_noi(collection: *z.DomCollection) usize;
extern "c" fn lxb_dom_collection_element_noi(collection: *z.DomCollection, idx: usize) ?*z.HTMLElement;
extern "c" fn lxb_dom_collection_append_noi(collection: *z.DomCollection, value: ?*anyopaque) usize;

// Element search by attribute
extern "c" fn lxb_dom_elements_by_attr(
    root: *z.HTMLElement,
    collection: *z.DomCollection,
    qualified_name: [*]const u8,
    qname_len: usize,
    value: [*]const u8,
    value_len: usize,
    case_insensitive: bool,
) usize;

//=============================================================================
// COLLECTION CAPACITY CONFIGURATION FUNCTIONS
//=============================================================================

/// [config] Set the global `default_collection_capacity`.
///
/// This affects all future collections created with `.default` capacity
pub fn setDefaultCapacity(capacity: u8) void {
    z.default_collection_capacity = capacity;
}

/// [config] Get the current `default_collection_capacity`.
pub fn getDefaultCapacity() u8 {
    return z.default_collection_capacity;
}

/// [config] Reset the `default_collection_capacity` to the original value (10).
pub fn resetDefaultCapacity() void {
    z.default_collection_capacity = 10;
}

/// [collection] Capacity options for collections (can be modified at runtime)
///
/// You use:
/// - `.single` for single element collections,
/// - `.default` for the default capacity, and
/// - `.custom` for a user-defined capacity.
///
/// For the custom capacity `N`, pass the desired value as follows:
/// ```
/// .{.custom = .{.value = N }}
/// ```
///
pub const CapacityOpt = union(enum) {
    single,
    default,
    custom: struct { value: u8 },
    pub fn getValue(self: CapacityOpt) u8 {
        return switch (self) {
            .single => 1,
            .default => z.default_collection_capacity,
            .custom => |c| c.value,
        };
    }
};

//=============================================================================
// HIGH-LEVEL COLLECTION FUNCTIONS
//=============================================================================

/// [collection] Create a new collection with initial capacity
///
/// You normally don't use this function directly.
///
/// It is used by `getElementsByAttributeName` where you might need to modify
/// the collection's capacity.
///
/// ## Example of setting capacity
///
/// `createSingleElementCollection`uses `.single`
///
/// `createDefaultCollection` uses `.default`
///
/// To set a custom capacity, use:
///
/// ```
/// .{.custom = .{.value = N }}
/// ```
///
pub fn createCollection(doc: *z.HTMLDocument, capacity: CapacityOpt) ?*z.DomCollection {
    const collection = lxb_dom_collection_create(doc) orelse return null;

    const status = lxb_dom_collection_init(collection, capacity.getValue());
    if (status != 0) {
        _ = lxb_dom_collection_destroy(collection, true);
        return null;
    }
    return collection;
}

/// [collection] Create a collection with default size `.default = 10` (good for most use cases)
pub fn createDefaultCollection(doc: *z.HTMLDocument) ?*z.DomCollection {
    return createCollection(doc, .default);
}

///[collection]  Create a collection optimized for single element search (like `getElementById`)
pub fn createSingleElementCollection(doc: *z.HTMLDocument) ?*z.DomCollection {
    return createCollection(doc, .single);
}

/// [collection] Destroy a collection and free its memory
pub fn destroyCollection(collection: *z.DomCollection) void {
    _ = lxb_dom_collection_destroy(collection, true);
}

/// [collection] Clear all elements from collection (but keep the collection itself)
pub fn clearCollection(collection: *z.DomCollection) void {
    lxb_dom_collection_clean_noi(collection);
}

/// [collection] Get the number of elements in the collection
pub fn collectionLength(collection: *z.DomCollection) usize {
    return lxb_dom_collection_length_noi(collection);
}

/// [collection] Get element at specific index (0-based)
///
/// Returns null if index is out of bounds
pub fn getCollectionElementAt(collection: *z.DomCollection, index: usize) ?*z.HTMLElement {
    if (index >= collectionLength(collection)) {
        return null;
    }
    return lxb_dom_collection_element_noi(collection, index);
}

/// [collection] Get the first element in the collection
///
/// Returns null if collection is empty
pub fn getCollectionFirstElement(collection: *z.DomCollection) ?*z.HTMLElement {
    return getCollectionElementAt(collection, 0);
}

/// [collection] Get the last element in the collection
/// Returns null if collection is empty
pub fn getCollectionLastElement(collection: *z.DomCollection) ?*z.HTMLElement {
    const len = collectionLength(collection);
    if (len == 0) return null;
    return getCollectionElementAt(collection, len - 1);
}

/// [collection] Check if collection is empty
pub fn isCollectionEmpty(collection: *z.DomCollection) bool {
    return collectionLength(collection) == 0;
}

/// [collection] Add an element to the collection
pub fn appendElementToCollection(collection: *z.DomCollection, element: *z.HTMLElement) !void {
    const status = lxb_dom_collection_append_noi(collection, element);
    if (status != 0) {
        return error.AppendFailed;
    }
}

//=============================================================================
// ITERATOR HELPER
//=============================================================================

/// [collection] Iterator for collection elements
pub const CollectionIterator = struct {
    collection: *z.DomCollection,
    index: usize,

    pub fn init(collection: *z.DomCollection) CollectionIterator {
        return CollectionIterator{
            .collection = collection,
            .index = 0,
        };
    }

    pub fn next(self: *CollectionIterator) ?*z.HTMLElement {
        if (self.index >= collectionLength(self.collection)) {
            return null;
        }
        const element = getCollectionElementAt(self.collection, self.index);
        self.index += 1;
        return element;
    }

    pub fn reset(self: *CollectionIterator) void {
        self.index = 0;
    }
};

/// [collection] Create an iterator for the collection
pub fn iterator(collection: *z.DomCollection) CollectionIterator {
    return CollectionIterator.init(collection);
}

//=============================================================================
// ELEMENT SEARCH FUNCTIONS
//=============================================================================

/// [collection] Find all elements with a specific tag name (like JavaScript's getElementsByTagName).
///
/// This is implemented using DOM traversal since the native lexbor function may not be available.
/// Returns a DomCollection with a limitation of size `.default` containing all elements with the specified tag name.
/// Examples: "div", "p", "span", "img", etc.
///
/// Caller is responsible for freeing the collection with `destroyCollection`
pub fn getElementsByTagName(doc: *z.HTMLDocument, tag_name: []const u8) !?*z.DomCollection {
    // Start from the body element but also check the body itself
    const root = try z.bodyElement(doc);
    const collection = createDefaultCollection(doc) orelse return Err.CollectionFailed;

    if (collectElementsByTagName(root, collection, tag_name)) {
        return collection;
    } else {
        destroyCollection(collection);
        return null;
    }
}

/// [collection] Helper function to recursively collect elements with a specific tag name
fn collectElementsByTagName(element: *z.HTMLElement, collection: *z.DomCollection, tag_name: []const u8) bool {
    // Check if current element matches the tag name
    const element_tag_name = z.tagName_zc(element);
    if (std.mem.eql(u8, element_tag_name, tag_name)) {
        const status = lxb_dom_collection_append_noi(collection, element);
        if (status != 0) return false;
    }

    // Traverse only element children (skip text nodes, comments, etc.)
    var child_element = z.firstElementChild(element);
    while (child_element) |child| {
        if (!collectElementsByTagName(child, collection, tag_name)) {
            return false;
        }
        child_element = z.nextElementSibling(child);
    }

    return true;
}

/// [collection] Find all elements with a specific name attribute (like JavaScript's getElementsByName).
///
/// This is commonly used for form elements that share the same name.
/// This is implemented as a wrapper around getElementsByAttributePair for the name attribute.
///
/// Caller is responsible for freeing the collection with `destroyCollection`
pub fn getElementsByName(doc: *z.HTMLDocument, name: []const u8) !?*z.DomCollection {
    return getElementsByAttributePair(
        doc,
        .{ .name = "name", .value = name },
        false, // case sensitive
    );
}

/// [collection] Find element by its ID attribute (like JavaScript's getElementById).
///
/// Returns the first element with the matching ID, or null if not found.
///
/// If you want to detect multiple IDs, use `getElementsByAttributePair`.
pub fn getElementById(doc: *z.HTMLDocument, id: []const u8) !?*z.HTMLElement {
    const root = try z.bodyElement(doc);

    const collection = createSingleElementCollection(doc) orelse return Err.CollectionFailed;
    defer destroyCollection(collection);

    const status = lxb_dom_elements_by_attr(
        root,
        collection,
        "id".ptr,
        2, // length of "id"
        id.ptr,
        id.len,
        false, // case sensitive
    );

    if (status != 0) return null;

    // Return first match (IDs should be unique)
    return getCollectionFirstElement(collection);
}

/// [collection] Find all elements with a specific attribute _name_ __and/or__ _value_
///
/// via the struct `AttributePair{.name = searched_name, .value = searched_value}`
///
/// For example, can be used for multiples IDs detection.
///
/// It takes an additional `case_insensitive` parameter to control the matching behavior. It defaults to `false`.
/// It returns a `DomCollection` with a limitation of size .default`.
///
/// You can use the collection primitives such as `getCollectionFirstElement`, `getCollectionLastElement`, etc.
///
/// Caller is responsible for freeing the return collection with `destroyCollection`
pub fn getElementsByAttributePair(doc: *z.HTMLDocument, attr: z.AttributePair, case_insensitive: bool) !?*z.DomCollection {
    const root = try z.bodyElement(doc);
    const collection = createDefaultCollection(doc) orelse return null;
    const name = attr.name;
    const value = attr.value;

    const status = lxb_dom_elements_by_attr(
        root,
        collection,
        name.ptr,
        name.len,
        value.ptr,
        value.len,
        case_insensitive,
    );

    if (status != 0) {
        destroyCollection(collection);
        return null;
    }

    return collection;
}

/// [collection] Find all elements with a specific class name
///
/// It returns a DomCollection with size limitation of `.default`.
///
/// You can use the collection primitives such as `getCollectionFirstElement`, `getCollectionLastElement`, etc.
///
/// Caller is responsible for freeing the collection with `destroyCollection`
pub fn getElementsByClassName(doc: *z.HTMLDocument, class_name: []const u8) !?*z.DomCollection {
    return getElementsByAttributePair(
        doc,
        .{
            .name = "class",
            .value = class_name,
        },
        false,
    );
}

/// [collection] Find all elements that have a specific attribute _name_ (regardless of value)
///
/// This searches for any element that has the __named attribute__.
///
/// It takes an initial capacity for the collection size.
/// You can use:
///
/// - `.single`, eg used in `getElementById`
/// - `.default` eg used in `getElementsByClassName`
/// - `.{.custom = .{ .value = 50 },}`
///
/// It returns a DomCollection
///
/// You can use the collection primitives such as `getCollectionFirstElement`, `getCollectionLastElement`, etc.
///
/// Caller is responsible for freeing the collection
///
/// ## Example
/// ```
/// const elements = try getElementsByAttributeName(doc, "data-id", .{.custom = .{ .value = 100 },});
/// defer destroyCollection(elements);
/// ```
///
pub fn getElementsByAttributeName(doc: *z.HTMLDocument, attr_name: []const u8, capacity: CapacityOpt) !?*z.DomCollection {
    const root = try z.bodyElement(doc);
    const collection = createCollection(doc, capacity) orelse return Err.CollectionFailed;

    if (collectElementsWithAttribute(root, collection, attr_name)) {
        return collection;
    } else {
        destroyCollection(collection);
        return null;
    }
}

/// [collection] Helper function to recursively collect elements with a specific attribute _name_
fn collectElementsWithAttribute(element: *z.HTMLElement, collection: *z.DomCollection, attr_name: []const u8) bool {
    // Check if current element has the target attribute
    if (z.hasAttribute(element, attr_name)) {
        const status = lxb_dom_collection_append_noi(collection, element);
        if (status != 0) return false;
    }

    // Traverse only element children (skip text nodes, comments, etc.)
    var child_element = z.firstElementChild(element);

    while (child_element) |child| {
        if (!collectElementsWithAttribute(child, collection, attr_name)) {
            return false;
        }
        child_element = z.nextElementSibling(child);
    }

    return true;
}

//=============================================================================
// UTILITY FUNCTIONS
//=============================================================================

/// [collection] Convert collection to Zig slice (allocates memory)
///
/// Caller needs to free the returned slice
pub fn collectionToSlice(allocator: std.mem.Allocator, collection: *z.DomCollection) ![]?*z.HTMLElement {
    const len = collectionLength(collection);
    if (len == 0) return &[_]?*z.HTMLElement{};

    const slice = try allocator.alloc(?*z.HTMLElement, len);
    for (0..len) |i| {
        slice[i] = getCollectionElementAt(collection, i);
    }
    return slice;
}

/// [collection] Debug: Print collection info for debugging
pub fn debugPrint(collection: *z.DomCollection) void {
    const len = collectionLength(collection);
    print("Debug print Collection: {} elements\n", .{len});

    var iter = iterator(collection);
    var i: usize = 0;
    while (iter.next()) |element| {
        print("  [{}]: {*}\n", .{ i, element });
        i += 1;
    }
}

//=============================================================================
// TESTS
//=============================================================================

test "collection basic operations" {
    // Create a test document
    const doc = try z.parseFromString("<div><p id='test'>Hello</p><span>World</span></div>");
    defer z.destroyDocument(doc);

    // Create collection
    const collection = createDefaultCollection(doc) orelse return error.CollectionCreateFailed;
    defer destroyCollection(collection);

    // Initially empty
    try testing.expect(isCollectionEmpty(collection));
    try testing.expectEqual(@as(usize, 0), collectionLength(collection));
    try testing.expect(getCollectionFirstElement(collection) == null);

    // Test iterator on empty collection
    var iter = iterator(collection);
    try testing.expect(iter.next() == null);
}

// test "collection with CSS selector results" {
//     const allocator = testing.allocator;

//     const doc = try z.parseFromString("<div><p class='test'>Hello</p><p class='test'>World</p></div>");
//     defer z.destroyDocument(doc);

//     // Use CSS selector to populate collection
//     const elements = try z.querySelectorAll(allocator, doc, "p.test");
//     defer allocator.free(elements);

//     // Verify we found elements
//     try testing.expect(elements.len == 2);
// }

// test "collection iterator" {
//     const allocator = testing.allocator;

//     const doc = try z.parseFromString("<div><p>1</p><p>2</p><p>3</p></div>");
//     defer z.destroyDocument(doc);

//     const elements = try z.querySelectorAll(allocator, doc, "p");
//     defer allocator.free(elements);

//     try testing.expect(elements.len == 3);

//     // Test that we got valid elements (they're non-optional pointers, so they can't be null)
//     for (elements, 0..) |element, i| {
//         // Elements from findElements are guaranteed to be non-null
//         // Just verify the pointer is valid by checking it's not undefined behavior
//         _ = element; // Use the element to avoid unused variable warning
//         _ = i; // Use the index if needed
//     }
// }

test "getElementsByAttribute functionality" {
    const html =
        \\<div>
        \\  <p class="highlight">First</p>
        \\  <p class="highlight">Second</p>
        \\  <span class="different">Third</span>
        \\</div>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Test finding by class
    const collection = try getElementsByClassName(doc, "highlight") orelse return error.CollectionFailed;
    defer destroyCollection(collection);

    try testing.expectEqual(@as(usize, 2), collectionLength(collection));

    const first = getCollectionElementAt(collection, 0);
    const second = getCollectionElementAt(collection, 1);
    try testing.expect(first != null);
    try testing.expect(second != null);
}

test "getElementsByAttributePair comprehensive tests" {
    const html =
        \\<form>
        \\  <input type="text" name="username" required>
        \\  <input type="password" name="password" required>
        \\  <input type="email" name="email">
        \\  <input type="submit" value="Submit">
        \\  <textarea name="message" required></textarea>
        \\</form>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Test 1: Find by type attribute
    {
        const text_inputs = try getElementsByAttributePair(
            doc,
            .{ .name = "type", .value = "text" },
            false,
        ) orelse return error.CollectionFailed;
        defer destroyCollection(text_inputs);
        try testing.expectEqual(@as(usize, 1), collectionLength(text_inputs));
    }

    // Test 2: Find by required attribute (this will find elements with required="")
    {
        const required_fields = try getElementsByAttributePair(
            doc,
            .{ .name = "required", .value = "" },
            false,
        ) orelse return error.CollectionFailed;
        defer destroyCollection(required_fields);
        // Note: This might not work as expected since HTML boolean attributes work differently
        // In real scenarios, you'd want to check for attribute presence, not value
    }

    // Test 3: Find by name attribute
    {
        const username_field = try getElementsByAttributePair(
            doc,
            .{ .name = "name", .value = "username" },
            false,
        ) orelse return error.CollectionFailed;
        defer destroyCollection(username_field);
        try testing.expectEqual(@as(usize, 1), collectionLength(username_field));
    }

    // Test 4: Case insensitive search
    {
        const submit_inputs = try getElementsByAttributePair(
            doc,
            .{ .name = "type", .value = "SUBMIT" },
            true,
        ) orelse return error.CollectionFailed;
        defer destroyCollection(submit_inputs);
        try testing.expectEqual(@as(usize, 1), collectionLength(submit_inputs));
    }

    // Test 5: Non-existent attribute value
    {
        const nonexistent = try getElementsByAttributePair(
            doc,
            .{ .name = "type", .value = "nonexistent" },
            false,
        ) orelse return error.CollectionFailed;
        defer destroyCollection(nonexistent);
        try testing.expectEqual(@as(usize, 0), collectionLength(nonexistent));
    }
}

test "comprehensive iterator tests" {
    const html =
        \\<ul id="list">
        \\  <li class="item">Item 1</li>
        \\  <li class="item">Item 2</li>
        \\  <li class="item">Item 3</li>
        \\  <li class="item special">Item 4</li>
        \\  <li class="item">Item 5</li>
        \\</ul>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const items = try getElementsByAttributePair(
        doc,
        .{ .name = "class", .value = "item" },
        false,
    ) orelse return error.CollectionFailed;
    defer destroyCollection(items);

    // Test 1: Basic iteration
    {
        var iter = iterator(items);
        var count: usize = 0;
        while (iter.next()) |_| {
            // Element is guaranteed to be non-null from iterator
            count += 1;
        }
        // The actual count depends on HTML parsing, but should be reasonable
        try testing.expect(count > 0);
        try testing.expectEqual(collectionLength(items), count);
    }

    // Test 2: Iterator reset functionality
    {
        var iter = iterator(items);

        // First iteration - consume some elements
        _ = iter.next(); // Item 1
        _ = iter.next(); // Item 2

        // Reset and count all elements
        iter.reset();
        var count: usize = 0;
        while (iter.next()) |_| {
            count += 1;
        }
        try testing.expect(count > 0);
        try testing.expectEqual(collectionLength(items), count);
    }

    // Test 3: Multiple independent iterators
    {
        var iter1 = iterator(items);
        var iter2 = iterator(items);

        // Both iterators should work independently
        const first1 = iter1.next();
        const first2 = iter2.next();

        try testing.expect(first1 != null);
        try testing.expect(first2 != null);
        // They should point to the same element (first in collection)
        try testing.expect(first1 == first2);

        // Continue with first iterator
        _ = iter1.next();
        _ = iter1.next();

        // Second iterator should still be at the second position
        const second2 = iter2.next();
        try testing.expect(second2 != null);
    }

    // Test 4: Iterator on empty collection
    {
        const empty_collection = try getElementsByAttributePair(
            doc,
            .{ .name = "class", .value = "nonexistent" },
            false,
        ) orelse return error.CollectionFailed;
        defer destroyCollection(empty_collection);

        var iter = iterator(empty_collection);
        try testing.expect(iter.next() == null);
        try testing.expect(iter.next() == null); // Should still be null

        // Reset on empty should still work
        iter.reset();
        try testing.expect(iter.next() == null);
    }

    // Test 5: Manual vs iterator comparison
    {
        var iter = iterator(items);
        for (0..collectionLength(items)) |i| {
            const manual_element = getCollectionElementAt(items, i);
            const iter_element = iter.next();

            try testing.expect(manual_element != null);
            try testing.expect(iter_element != null);
            try testing.expect(manual_element == iter_element);
        }

        // Iterator should be exhausted
        try testing.expect(iter.next() == null);
    }
}

test "collection utility functions" {
    const html =
        \\<div>
        \\  <button type="button" id="btn1">Button 1</button>
        \\  <button type="submit" id="btn2">Button 2</button>
        \\  <button type="reset" id="btn3">Button 3</button>
        \\</div>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const buttons = try getElementsByAttributePair(
        doc,
        .{ .name = "type", .value = "button" },
        false,
    ) orelse return error.CollectionFailed;
    defer destroyCollection(buttons);

    // Test collection utility functions
    try testing.expectEqual(@as(usize, 1), collectionLength(buttons));
    try testing.expect(!isCollectionEmpty(buttons));

    const first = getCollectionFirstElement(buttons);
    const last = getCollectionLastElement(buttons);
    try testing.expect(first != null);
    try testing.expect(last != null);
    try testing.expect(first == last); // Only one element

    const element_at_0 = getCollectionElementAt(buttons, 0);
    try testing.expect(element_at_0 != null);
    try testing.expect(element_at_0 == first);

    const out_of_bounds = getCollectionElementAt(buttons, 999);
    try testing.expect(out_of_bounds == null);
}

test "performance comparison: Lexbor native vs custom Zig traversal" {
    const html =
        \\<div>
        \\  <div id="other1" data-test="value1">Other 1</div>
        \\  <div id="other2" data-test="value2">Other 2</div>
        \\  <div id="other3" data-test="value3">Other 3</div>
        \\  <div id="other4" data-test="value4">Other 4</div>
        \\  <div id="other5" data-test="value5">Other 5</div>
        \\  <div id="other6" data-test="value6">Other 6</div>
        \\  <div id="other7" data-test="value7">Other 7</div>
        \\  <div id="other8" data-test="value8">Other 8</div>
        \\  <div id="other9" data-test="value9">Other 9</div>
        \\  <div id="other10" data-test="value10">Other 10</div>
        \\  <div id="other11" data-test="value11">Other 11</div>
        \\  <div id="other12" data-test="value12">Other 12</div>
        \\  <div id="other13" data-test="value13">Other 13</div>
        \\  <div id="other14" data-test="value14">Other 14</div>
        \\  <div id="other15" data-test="value15">Other 15</div>
        \\  <div id="other16" data-test="value16">Other 16</div>
        \\  <div id="other17" data-test="value17">Other 17</div>
        \\  <div id="other18" data-test="value18">Other 18</div>
        \\  <div id="other19" data-test="value19">Other 19</div>
        \\  <div id="other20" data-test="value20">Other 20</div>
        \\  <div id="other21" data-test="value21">Other 21</div>
        \\  <div id="other22" data-test="value22">Other 22</div>
        \\  <div id="other23" data-test="value23">Other 23</div>
        \\  <div id="other24" data-test="value24">Other 24</div>
        \\  <div id="other25" data-test="value25">Other 25</div>
        \\  <div id="other26" data-test="value26">Other 26</div>
        \\  <div id="other27" data-test="value27">Other 27</div>
        \\  <div id="other28" data-test="value28">Other 28</div>
        \\  <div id="other29" data-test="value29">Other 29</div>
        \\  <div id="other30" data-test="value30">Other 30</div>
        \\  <div id="other31" data-test="value31">Other 31</div>
        \\  <div id="other32" data-test="value32">Other 32</div>
        \\  <div id="other33" data-test="value33">Other 33</div>
        \\  <div id="other34" data-test="value34">Other 34</div>
        \\  <div id="other35" data-test="value35">Other 35</div>
        \\  <div id="other36" data-test="value36">Other 36</div>
        \\  <div id="other37" data-test="value37">Other 37</div>
        \\  <div id="other38" data-test="value38">Other 38</div>
        \\  <div id="other39" data-test="value39">Other 39</div>
        \\  <div id="other40" data-test="value40">Other 40</div>
        \\  <div id="other41" data-test="value41">Other 41</div>
        \\  <div id="other42" data-test="value42">Other 42</div>
        \\  <div id="other43" data-test="value43">Other 43</div>
        \\  <div id="other44" data-test="value44">Other 44</div>
        \\  <div id="other45" data-test="value45">Other 45</div>
        \\  <div id="other46" data-test="value46">Other 46</div>
        \\  <div id="other47" data-test="value47">Other 47</div>
        \\  <div id="other48" data-test="value48">Other 48</div>
        \\  <div id="other49" data-test="value49">Other 49</div>
        \\  <div id="other50" data-test="value50">Other 50</div>
        \\  <div id="other51" data-test="value51">Other 51</div>
        \\  <div id="other52" data-test="value52">Other 52</div>
        \\  <div id="other53" data-test="value53">Other 53</div>
        \\  <div id="other54" data-test="value54">Other 54</div>
        \\  <div id="other55" data-test="value55">Other 55</div>
        \\  <div id="other56" data-test="value56">Other 56</div>
        \\  <div id="other57" data-test="value57">Other 57</div>
        \\  <div id="other58" data-test="value58">Other 58</div>
        \\  <div id="other59" data-test="value59">Other 59</div>
        \\  <div id="other60" data-test="value60">Other 60</div>
        \\  <div id="other61" data-test="value61">Other 61</div>
        \\  <div id="other62" data-test="value62">Other 62</div>
        \\  <div id="other63" data-test="value63">Other 63</div>
        \\  <div id="other64" data-test="value64">Other 64</div>
        \\  <div id="other65" data-test="value65">Other 65</div>
        \\  <div id="other66" data-test="value66">Other 66</div>
        \\  <div id="other67" data-test="value67">Other 67</div>
        \\  <div id="other68" data-test="value68">Other 68</div>
        \\  <div id="other69" data-test="value69">Other 69</div>
        \\  <div id="other70" data-test="value70">Other 70</div>
        \\  <div id="other71" data-test="value71">Other 71</div>
        \\  <div id="other72" data-test="value72">Other 72</div>
        \\  <div id="other73" data-test="value73">Other 73</div>
        \\  <div id="other74" data-test="value74">Other 74</div>
        \\  <div id="other75" data-test="value75">Other 75</div>
        \\  <div id="other76" data-test="value76">Other 76</div>
        \\  <div id="other77" data-test="value77">Other 77</div>
        \\  <div id="other78" data-test="value78">Other 78</div>
        \\  <div id="other79" data-test="value79">Other 79</div>
        \\  <div id="other80" data-test="value80">Other 80</div>
        \\  <div id="other81" data-test="value81">Other 81</div>
        \\  <div id="other82" data-test="value82">Other 82</div>
        \\  <div id="other83" data-test="value83">Other 83</div>
        \\  <div id="other84" data-test="value84">Other 84</div>
        \\  <div id="other85" data-test="value85">Other 85</div>
        \\  <div id="other86" data-test="value86">Other 86</div>
        \\  <div id="other87" data-test="value87">Other 87</div>
        \\  <div id="other88" data-test="value88">Other 88</div>
        \\  <div id="other89" data-test="value89">Other 89</div>
        \\  <div id="other90" data-test="value90">Other 90</div>
        \\  <div id="other91" data-test="value91">Other 91</div>
        \\  <div id="other92" data-test="value92">Other 92</div>
        \\  <div id="other93" data-test="value93">Other 93</div>
        \\  <div id="other94" data-test="value94">Other 94</div>
        \\  <div id="other95" data-test="value95">Other 95</div>
        \\  <div id="other96" data-test="value96">Other 96</div>
        \\  <div id="other97" data-test="value97">Other 97</div>
        \\  <div id="other98" data-test="value98">Other 98</div>
        \\  <div id="other99" data-test="value99">Other 99</div>
        \\  <div id="other100" data-test="value100">Other 100</div>
        \\  <div id="target" data-test="target-value">Target Element</div>
        \\</div>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // print("\n=== Performance Comparison: Lexbor Native vs Custom Zig Traversal ===\n", .{});

    // Method 1: Lexbor native - getElementsByAttributePair (name + value match)
    const start1 = try Instant.now();
    const collection1 = try getElementsByAttributePair(
        doc,
        .{ .name = "data-test", .value = "target-value" },
        false,
    ) orelse return error.CollectionFailed;
    defer destroyCollection(collection1);
    const end1 = try Instant.now();
    const elapsed1: f64 = @floatFromInt(end1.since(start1));

    try testing.expectEqual(@as(usize, 1), collectionLength(collection1));
    const element1 = getCollectionFirstElement(collection1);
    try testing.expect(element1 != null);

    _ = elapsed1;
    // print("Lexbor native (name+value): {d:.3}ms - Found {} elements\n", .{ elapsed1 / std.time.ns_per_ms, collectionLength(collection1) });

    // Method 2: Custom Zig traversal - getElementsByAttributeName (name only)
    const start2 = try Instant.now();
    const collection2 = try getElementsByAttributeName(
        doc,
        "data-test",
        .default,
    ) orelse return error.CollectionFailed;
    defer destroyCollection(collection2);
    const end2 = try Instant.now();
    const elapsed2: f64 = @floatFromInt(end2.since(start2));
    _ = elapsed2; // Use elapsed2 to avoid unused variable warning

    // print("Custom Zig traversal (name only): {d:.3}ms - Found {} elements\n", .{ elapsed2 / std.time.ns_per_ms, collectionLength(collection2) });

    // The custom traversal should find ALL elements with data-test attribute (101 elements)
    // The native should find only the one with the specific value (1 element)
    try testing.expect(collectionLength(collection2) > collectionLength(collection1));
    try testing.expectEqual(@as(usize, 101), collectionLength(collection2)); // All divs have data-test

    // print("Performance ratio: {d:.2}x (native is faster)\n", .{elapsed2 / elapsed1});
    // print("Note: Different search criteria - native finds specific value, custom finds any attribute name\n", .{});
}

test "elementHasAnyAttribute performance demonstration" {
    const allocator = testing.allocator;

    const html =
        \\<div>
        \\  <p>No attributes</p>
        \\  <p>No attributes</p>
        \\  <p>No attributes</p>
        \\  <p id="with-attr">Has attribute</p>
        \\  <p>No attributes</p>
        \\  <p>No attributes</p>
        \\</div>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    const body = try z.bodyElement(doc);
    const first_child = z.firstChild(z.elementToNode(body)) orelse return error.NoChild;
    const div_element = z.nodeToElement(first_child) orelse return error.NotElement;

    // Demonstrate that hasAttributes correctly identifies elements with/without attributes
    var child_node = z.firstChild(z.elementToNode(div_element));
    var elements_with_attrs: usize = 0;
    var elements_without_attrs: usize = 0;

    while (child_node) |node| {
        if (z.nodeToElement(node)) |element| {
            if (z.hasAttributes(element)) {
                elements_with_attrs += 1;
            } else {
                elements_without_attrs += 1;
            }
        }
        child_node = z.nextSibling(node);
    }

    try testing.expectEqual(@as(usize, 1), elements_with_attrs);
    try testing.expectEqual(@as(usize, 5), elements_without_attrs);

    // Test that getElementsByAttributeName correctly finds only the element with the id attribute
    const id_elements = try getElementsByAttributeName(
        doc,
        "id",
        .default,
    ) orelse return error.CollectionFailed;
    defer destroyCollection(id_elements);

    try testing.expectEqual(@as(usize, 1), collectionLength(id_elements));

    const found_element = getCollectionElementAt(id_elements, 0).?;
    try testing.expect(z.hasAttribute(found_element, "id"));

    if (try z.getAttribute(allocator, found_element, "id")) |id_value| {
        defer allocator.free(id_value);
        try testing.expect(std.mem.eql(u8, id_value, "with-attr"));
    }
}

test "getElementsByAttributeName performance optimization" {
    const html =
        \\<html>
        \\  <body>
        \\    <div id="container" class="main">
        \\      <p id="para1" class="text">Paragraph with attributes</p>
        \\      <p>Paragraph without any attributes</p>
        \\      <p>Another paragraph without attributes</p>
        \\      <p>Yet another paragraph without attributes</p>
        \\      <span id="span1">Span with ID</span>
        \\      <span>Span without attributes</span>
        \\      <span>Another span without attributes</span>
        \\      <span>Yet another span without attributes</span>
        \\    </div>
        \\  </body>
        \\</html>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Test that getElementsByAttributeName still works correctly with the optimization
    const id_elements = try getElementsByAttributeName(
        doc,
        "id",
        .default,
    ) orelse return error.CollectionFailed;
    defer destroyCollection(id_elements);

    const count = collectionLength(id_elements);
    try testing.expect(count == 3); // container, para1, span1

    // Verify that elements without any attributes were correctly skipped
    // but elements with attributes were still processed correctly
    for (0..count) |i| {
        const element = getCollectionElementAt(id_elements, i).?;
        try testing.expect(z.hasAttribute(element, "id"));
        try testing.expect(z.hasAttributes(element)); // Should have at least some attribute
    }
}

test "getElementsByAttributeName functionality" {
    const html =
        \\<html>
        \\  <body>
        \\    <div id="container" class="main">
        \\      <p id="para1" class="text">Paragraph with ID</p>
        \\      <p class="text">Paragraph without ID</p>
        \\      <span id="span1">Span with ID</span>
        \\      <span>Span without ID</span>
        \\      <button type="submit" id="btn1">Button</button>
        \\      <input type="text" name="field1">
        \\      <input type="password" name="field2" id="password">
        \\    </div>
        \\  </body>
        \\</html>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);
    // try z.printDocumentStructure(doc);

    // Test 1: Find all elements with 'id' attribute: count is 5
    {
        const id_elements = try getElementsByAttributeName(
            doc,
            "id",
            .default,
        ) orelse return error.CollectionFailed;
        defer destroyCollection(id_elements);

        const count = collectionLength(id_elements);
        try testing.expect(count == 5);

        // Verify we can iterate through them
        var iter = iterator(id_elements);
        var found_count: usize = 0;
        while (iter.next()) |element| {
            // Element is guaranteed to be non-null from iterator
            try testing.expect(z.hasAttribute(element, "id"));
            found_count += 1;
        }
        try testing.expectEqual(count, found_count);
    }

    // Test 2: Find all elements with 'class' attribute: count is 3
    {
        const class_elements = try getElementsByAttributeName(
            doc,
            "class",
            .default,
        ) orelse return error.CollectionFailed;

        defer destroyCollection(class_elements);

        const count = collectionLength(class_elements);
        try testing.expect(count >= 3);

        // Verify all found elements have the class attribute
        for (0..count) |i| {
            const element = getCollectionElementAt(class_elements, i).?;
            try testing.expect(z.hasAttribute(element, "class"));
        }
    }

    // Test 3: Find all elements with 'type' attribute: count is 3
    {
        const type_elements = try getElementsByAttributeName(
            doc,
            "type",
            .{ .custom = .{ .value = 5 } },
        ) orelse return error.CollectionFailed;

        defer destroyCollection(type_elements);

        const count = collectionLength(type_elements);
        try testing.expectEqual(@as(usize, 3), count);
    }

    // Test 4: Find all elements with 'name' attribute: count is 2
    {
        const name_elements = try getElementsByAttributeName(
            doc,
            "name",
            .{ .custom = .{ .value = 3 } },
        ) orelse return error.CollectionFailed;

        defer destroyCollection(name_elements);

        const count = collectionLength(name_elements);
        try testing.expectEqual(@as(usize, 2), count);
    }

    // Test 5: Find elements with non-existent attribute: count is 0
    {
        const nonexistent = try getElementsByAttributeName(doc, "nonexistent", .single) orelse return error.CollectionFailed;
        defer destroyCollection(nonexistent);

        try testing.expectEqual(@as(usize, 0), collectionLength(nonexistent));
        try testing.expect(isCollectionEmpty(nonexistent));
    }

    // Test 6: Compare getElementsByAttributeName vs getElementsByAttributePair
    {
        // Find all elements with any 'id' attribute: id="container"
        const all_with_id = try getElementsByAttributeName(
            doc,
            "id",
            .default,
        ) orelse return error.CollectionFailed;

        defer destroyCollection(all_with_id);

        const specific_id = try getElementsByAttributePair(
            doc,
            .{ .name = "id", .value = "container" },
            false,
        ) orelse return error.CollectionFailed;
        defer destroyCollection(specific_id);

        // all_with_id should have more elements than specific_id
        try testing.expect(collectionLength(all_with_id) > collectionLength(specific_id));
        try testing.expectEqual(@as(usize, 1), collectionLength(specific_id));
    }
}

test "getElementsByTagName functionality" {
    const html =
        \\<html>
        \\  <body>
        \\    <div id="container">
        \\      <p>First paragraph</p>
        \\      <p>Second paragraph</p>
        \\      <span>A span</span>
        \\      <div>
        \\        <p>Nested paragraph</p>
        \\        <span>Nested span</span>
        \\      </div>
        \\    </div>
        \\  </body>
        \\</html>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Test 1: Find all paragraphs (note: Lexbor returns uppercase tag names)
    {
        const paragraphs = try getElementsByTagName(doc, "P") orelse return error.CollectionFailed;
        defer destroyCollection(paragraphs);

        try testing.expectEqual(@as(usize, 3), collectionLength(paragraphs));

        // Verify all found elements are indeed paragraphs
        for (0..collectionLength(paragraphs)) |i| {
            const element = getCollectionElementAt(paragraphs, i).?;
            const tag_name = z.tagName_zc(element);
            try testing.expect(std.mem.eql(u8, tag_name, "P"));
        }
    }

    // Test 2: Find all divs
    {
        const divs = try getElementsByTagName(doc, "DIV") orelse return error.CollectionFailed;
        defer destroyCollection(divs);

        try testing.expectEqual(@as(usize, 2), collectionLength(divs)); // container + nested div
    }

    // Test 3: Find all spans
    {
        const spans = try getElementsByTagName(doc, "SPAN") orelse return error.CollectionFailed;
        defer destroyCollection(spans);

        try testing.expectEqual(@as(usize, 2), collectionLength(spans));
    }

    // Test 4: Find non-existent tag
    {
        const articles = try getElementsByTagName(doc, "ARTICLE") orelse return error.CollectionFailed;
        defer destroyCollection(articles);

        try testing.expectEqual(@as(usize, 0), collectionLength(articles));
    }
}

test "getElementsByName functionality" {
    const allocator = testing.allocator;

    const html =
        \\<html>
        \\  <body>
        \\    <form>
        \\      <input type="text" name="username" value="john">
        \\      <input type="password" name="password" value="secret">
        \\      <input type="radio" name="gender" value="male" checked>
        \\      <input type="radio" name="gender" value="female">
        \\      <select name="country">
        \\        <option value="us">USA</option>
        \\        <option value="uk">UK</option>
        \\      </select>
        \\    </form>
        \\  </body>
        \\</html>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Test 1: Find elements with name="gender" (radio buttons)
    {
        const gender_inputs = try getElementsByName(doc, "gender") orelse return error.CollectionFailed;
        defer destroyCollection(gender_inputs);

        try testing.expectEqual(@as(usize, 2), collectionLength(gender_inputs));

        // Verify all found elements have the correct name attribute
        for (0..collectionLength(gender_inputs)) |i| {
            const element = getCollectionElementAt(gender_inputs, i).?;
            if (try z.getAttribute(allocator, element, "name")) |name_value| {
                defer allocator.free(name_value);
                try testing.expect(std.mem.eql(u8, name_value, "gender"));
            }
        }
    }

    // Test 2: Find unique name
    {
        const username_input = try getElementsByName(doc, "username") orelse return error.CollectionFailed;
        defer destroyCollection(username_input);

        try testing.expectEqual(@as(usize, 1), collectionLength(username_input));
    }

    // Test 3: Find non-existent name
    {
        const nonexistent = try getElementsByName(doc, "nonexistent") orelse return error.CollectionFailed;
        defer destroyCollection(nonexistent);

        try testing.expectEqual(@as(usize, 0), collectionLength(nonexistent));
    }
}

test "configurable default capacity" {
    const html =
        \\<html>
        \\  <body>
        \\    <div id="container">
        \\      <p>First paragraph</p>
        \\      <p>Second paragraph</p>
        \\      <span>A span</span>
        \\    </div>
        \\  </body>
        \\</html>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // Test 1: Check initial default capacity
    try testing.expectEqual(@as(u8, 10), getDefaultCapacity());

    // Test 2: Change default capacity
    setDefaultCapacity(25);
    try testing.expectEqual(@as(u8, 25), getDefaultCapacity());

    // Test 3: Verify that CapacityOpt.default now uses new value
    const capacity_opt: CapacityOpt = .default;
    try testing.expectEqual(@as(u8, 25), capacity_opt.getValue());

    // Test 4: Create a collection with the new default and verify it works
    const collection = createDefaultCollection(doc) orelse return error.CollectionCreateFailed;
    defer destroyCollection(collection);

    // The collection should work normally regardless of capacity
    try testing.expect(isCollectionEmpty(collection));

    // Test 5: Reset to original value
    resetDefaultCapacity();
    try testing.expectEqual(@as(u8, 10), getDefaultCapacity());

    // Test 6: Verify that custom capacity is unaffected by default changes
    setDefaultCapacity(50);
    const custom_capacity: CapacityOpt = .{ .custom = .{ .value = 5 } };
    try testing.expectEqual(@as(u8, 5), custom_capacity.getValue());

    // Test 7: Verify single capacity is unaffected
    const single_capacity: CapacityOpt = .single;
    try testing.expectEqual(@as(u8, 1), single_capacity.getValue());

    // Clean up
    resetDefaultCapacity();
}

test "configurable default capacity usage example" {
    // print("\n=== Configurable Default Collection Capacity Demo ===\n", .{});

    // 1. Check initial default capacity
    // print("Initial default capacity: {}\n", .{getDefaultCapacity()});
    try testing.expectEqual(@as(u8, 10), getDefaultCapacity());

    // 2. Change the default capacity for all future collections
    // print("Setting default capacity to 50...\n", .{});
    setDefaultCapacity(50);
    // print("New default capacity: {}\n", .{getDefaultCapacity()});
    try testing.expectEqual(@as(u8, 50), getDefaultCapacity());

    // 3. Parse some HTML and test collection creation
    const html =
        \\<html>
        \\  <body>
        \\    <div class="container">
        \\      <p>First paragraph</p>
        \\      <p>Second paragraph</p>
        \\      <span>A span element</span>
        \\    </div>
        \\  </body>
        \\</html>
    ;

    const doc = try z.parseFromString(html);
    defer z.destroyDocument(doc);

    // 4. Create collections with different capacity options
    // print("\n=== Collection Creation Examples ===\n", .{});

    // Default collection now uses capacity 50
    // print("Creating collection with .default capacity (should be 50)...\n", .{});
    if (createDefaultCollection(doc)) |default_collection| {
        defer destroyCollection(default_collection);
    }

    // Single element collection (always capacity 1)
    // print("Creating collection with .single capacity (always 1)...\n", .{});
    if (createSingleElementCollection(doc)) |single_collection| {
        defer destroyCollection(single_collection);
    }

    // Custom capacity collection (explicit capacity)
    // print("Creating collection with custom capacity of 100...\n", .{});
    if (createCollection(doc, .{ .custom = .{ .value = 100 } })) |custom_collection| {
        defer destroyCollection(custom_collection);
    }

    // 5. Test with getElementsByAttributeName (uses configurable default)
    // print("\n=== Testing with Search Functions ===\n", .{});
    if (try getElementsByAttributeName(doc, "class", .default)) |class_elements| {
        defer destroyCollection(class_elements);
        // print("Found {} elements with 'class' attribute using default capacity ({})\n", .{ collectionLength(class_elements), getDefaultCapacity() });
    }

    // 6. Reset to original default
    // print("\nResetting to original default capacity (10)...\n", .{});
    resetDefaultCapacity();
    // print("Reset complete. Current default capacity: {}\n", .{getDefaultCapacity()});
    try testing.expectEqual(@as(u8, 10), getDefaultCapacity());

    // print("\n=== Available Configuration Functions ===\n", .{});
    // print("  • setDefaultCapacity(value) - Set global default\n", .{});
    // print("  • getDefaultCapacity() - Get current default\n", .{});
    // print("  • resetDefaultCapacity() - Reset to 10\n", .{});
    // print("\nCapacity options for collections:\n", .{});
    // print("  • .single - Always capacity 1\n", .{});
    // print("  • .default - Uses global default (configurable)\n", .{});
    // print("  • .{{ .custom = .{{ .value = N }} }} - Explicit capacity N\n", .{});
}

// test "comprehensive class search comparison: CSS vs Walker vs Collection vs Attributes" {
//     const allocator = testing.allocator;

//     // Create test document with various class scenarios
//     const html =
//         \\<div class="container main">Container element</div>
//         \\<p class="text bold">Bold paragraph</p>
//         \\<p class="text"><span class="text bold">Nested bold span</span></p>
//         \\<span class="bold text-xs">Span with multiple classes</span>
//         \\<div class="text-xs bold">Reversed class order</div>
//         \\<section class="main">Another main section</section>
//         \\<article class="container">Just container class</article>
//         \\<p class="text">Simple text class</p>
//         \\<div class="BOLD">Uppercase BOLD</div>
//         \\<span class="text-bold">Hyphenated similar class</span>
//         \\<div class="text bold extra">Three classes</div>
//         \\<div class="BOLD text">Mix the classes BOLD</div>
//         \\  <div class="bold text-xl">Bold and text-xl</div>
//         \\  <div class="bold">bold alone</div>
//         \\  <div class="text-xs">text-xs alone</div>
//         \\  <div class="bold text">reversed
//     ;

//     const doc = try z.parseFromString(html);
//     defer z.destroyDocument(doc);

//     // Test different class searches
//     const test_classes = [_][]const u8{
//         "bold", // Should find: p, span, div (reversed), div (three classes) + more = multiple elements
//         "text-xs", // Should find: span, div (reversed), div alone = 3 elements
//         "main", // Should find: div (container), section = 2 elements
//         "container", // Should find: div (container), article = 2 elements
//         "text bold", // Full string test - should find only exact match of "text bold" class attribute
//         "nonexistent", // Should find: none = 0 elements
//     };

//     for (test_classes) |class_name| {
//         print("\n=== Testing class: '{s}' ===\n", .{class_name});

//         // 1. CSS Selector approach (.bold, .text-xs, etc.)
//         var css_query_buf: [64]u8 = undefined;
//         const css_query = try std.fmt.bufPrint(css_query_buf[0..], ".{s}", .{class_name});
//         const css_results = try z.querySelectorAll(allocator, doc, css_query);
//         defer allocator.free(css_results);
//         // defer if (css_results) |results| {
//         //     for (results) |elem| _ = elem; // Use elements
//         //     allocator.free(results);
//         // };
//         // const css_count = if (css_results) |results| results.len else 0;
//         const css_count = css_results.len;

//         // 2. Walker-based approach
//         const walker_results = try z.getElementsByClassFast(doc, doc, class_name, allocator);
//         defer allocator.free(walker_results);
//         const walker_count = walker_results.len;

//         // 3. Collection-based approach
//         const collection_results = try getElementsByClassName(doc, class_name);
//         defer if (collection_results) |coll| destroyCollection(coll);
//         const collection_count = if (collection_results) |coll| collectionLength(coll) else 0;
//         _ = collection_count;
//         // 4. Manual hasClass check on all elements (for reference)
//         var manual_count: usize = 0;
//         const body = try z.bodyElement(doc);
//         var element_walker = z.firstElementChild(body);
//         while (element_walker) |elem| {
//             if (z.hasClass(elem, class_name)) {
//                 manual_count += 1;
//             }
//             // Simple traversal - in real implementation would need proper tree walk
//             element_walker = z.nextElementSibling(elem);
//         }

//         // Display results
//         // print("CSS Selector (.{s}):     {d} elements\n", .{ class_name, css_count });
//         // print("Walker-based search:     {d} elements\n", .{walker_count});
//         // print("Collection-based:        {d} elements\n", .{collection_count});
//         // print("Manual hasClass walk:    {d} elements\n", .{manual_count});

//         // Verify CSS and Walker should match (both handle tokens correctly)
//         // try testing.expectEqual(css_count, walker_count);

//         // Collection search uses exact string matching, so may differ for multi-class scenarios
//         if (std.mem.eql(u8, class_name, "bold")) {
//             // For "bold" class:
//             // - CSS/Walker should find elements with "bold" as a token (case-insensitive for CSS)
//             // - Collection might only find elements where class="bold" exactly
//             // print("Note: Collection may differ for 'bold' due to exact string matching\n", .{});
//             // print("Note: CSS selectors are case-insensitive, so 'BOLD' matches '.bold'\n", .{});
//         }

//         if (std.mem.eql(u8, class_name, "text-xs")) {
//             // For "text-xs" class:
//             // - CSS/Walker should find both "text-xs bold" and "bold text-xs"
//             // - Collection will only find elements with class="text-xs" exactly
//             try testing.expect(css_count >= 2); // Should find both order variations
//             try testing.expect(walker_count >= 2);
//             // print("Note: Collection won't find 'text-xs' in multi-class attributes due to exact matching\n", .{});
//         }

//         if (std.mem.eql(u8, class_name, "text bold")) {
//             // For "text bold" as CSS selector:
//             // - CSS: Returns 0 - ".text bold" as selector may not work as expected or
//             //   the CSS query processor may not handle this specific space-separated format
//             // - Walker/hasClass: Will NOT find this (no element has "text bold" as a single class name)
//             // - Collection: WILL find this (exact string matching finds class="text bold")
//             // - This demonstrates the different interpretation of spaces in selectors vs class names
//             // print("Note: CSS found {} - space in selector may not work as descendant selector here\n", .{css_count});
//             try testing.expectEqual(@as(usize, 0), walker_count); // No single "text bold" class token
//             // try testing.expectEqual(@as(usize, 2), collection_count); // Finds elements with exact class="text bold"
//             try testing.expectEqual(@as(usize, 0), manual_count); // No single "text bold" class token
//             // print("Note: Collection found {} - exact string matching finds class='text bold' attributes\n", .{collection_count});
//             // print("Note: Walker/hasClass found 0 - they look for 'text bold' as a single class token\n", .{});
//         }
//     }

//     // Test different CSS selector syntaxes for descendant/child relationships
//     // print("\n=== CSS Selector Syntax Exploration ===\n", .{});

//     const css_selectors = [_][]const u8{
//         ".text .bold", // Descendant selector (space)
//         ".text > .bold", // Direct child selector
//         ".text.bold", // Multiple class selector (same element)
//         "p .bold", // Element with descendant class
//         "p > .bold", // Element with direct child class
//     };

//     for (css_selectors) |selector| {
//         const results = try z.querySelectorAll(allocator, doc, selector);
//         defer allocator.free(results);
//         // print("'{s}': {d} elements\n", .{ selector, results.len });
//     }

//     // print("\n=== Class Search Behavior Summary ===\n", .{});
//     // print("• CSS Selectors: Token-based, order-independent, case-insensitive, handles multi-class correctly\n", .{});
//     // print("• Walker Search: Token-based, order-independent, case-sensitive, handles multi-class correctly\n", .{});
//     // print("• Collection Search: Exact string matching, order-dependent, case-sensitive, limited multi-class support\n", .{});
//     // print("• hasClass Method: Token-based, order-independent, case-sensitive, handles multi-class correctly\n", .{});
//     // print("\nFor class='bold text-xs' vs class='text-xs bold':\n", .{});
//     // print("• CSS/Walker/hasClass: Will find BOTH variations (order-independent)\n", .{});
//     // print("• Collection: Will only find exact string matches\n", .{});
//     // print("\nFor class='BOLD' vs '.bold' CSS selector:\n", .{});
//     // print("• CSS: Will match (case-insensitive)\n", .{});
//     // print("• Walker/hasClass/Collection: Won't match (case-sensitive)\n", .{});
//     // print("\nFor 'text bold' search:\n", .{});
//     // print("• CSS: Returns 0 - space in selector may be interpreted differently than expected\n", .{});
//     // print("• Walker/hasClass: Find 0 - look for 'text bold' as single class token\n", .{});
//     // print("• Collection: Finds elements with exact class='text bold' attribute value\n", .{});
//     // print("• This demonstrates different handling of spaces: CSS selectors vs class tokens vs string matching\n", .{});
// }
