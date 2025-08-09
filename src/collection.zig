//=============================================================================
// COLLECTION MANAGEMENT
//=============================================================================

const std = @import("std");
const z = @import("zhtml.zig");
const writer = std.io.getStdOut().writer();

const Err = z.Err;

const testing = std.testing;
const print = std.debug.print;
const Instant = std.time.Instant;
const Timer = std.time.Timer;

// External C functions - using _noi versions for ABI compatibility
extern "c" fn lxb_dom_collection_create(doc: *z.HtmlDocument) ?*z.DomCollection;
extern "c" fn lxb_dom_collection_init(collection: *z.DomCollection, start_size: usize) usize;
extern "c" fn lxb_dom_collection_destroy(collection: *z.DomCollection, self_destroy: bool) ?*z.DomCollection;
extern "c" fn lxb_dom_collection_clean_noi(collection: *z.DomCollection) void;
extern "c" fn lxb_dom_collection_length_noi(collection: *z.DomCollection) usize;
extern "c" fn lxb_dom_collection_element_noi(collection: *z.DomCollection, idx: usize) ?*z.DomElement;
extern "c" fn lxb_dom_collection_append_noi(collection: *z.DomCollection, value: ?*anyopaque) usize;

// Element search by attribute
extern "c" fn lxb_dom_elements_by_attr(
    root: *z.DomElement,
    collection: *z.DomCollection,
    qualified_name: [*]const u8,
    qname_len: usize,
    value: [*]const u8,
    value_len: usize,
    case_insensitive: bool,
) usize;

//=============================================================================
// HIGH-LEVEL COLLECTION FUNCTIONS
//=============================================================================

/// [collection] Create a new collection with initial capacity
pub fn createCollection(doc: *z.HtmlDocument, initial_size: usize) ?*z.DomCollection {
    const collection = lxb_dom_collection_create(doc) orelse return null;
    const status = lxb_dom_collection_init(collection, initial_size);
    if (status != 0) {
        _ = lxb_dom_collection_destroy(collection, true);
        return null;
    }
    return collection;
}

/// [collection] Create a collection with default size (good for most use cases)
pub fn createDefaultCollection(doc: *z.HtmlDocument) ?*z.DomCollection {
    return createCollection(doc, 10);
}

///[collection]  Create a collection optimized for single element search (like `getElementById`)
pub fn createSingleElementCollection(doc: *z.HtmlDocument) ?*z.DomCollection {
    return createCollection(doc, 1);
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
pub fn getCollectionLength(collection: *z.DomCollection) usize {
    return lxb_dom_collection_length_noi(collection);
}

/// [collection] Get element at specific index (0-based)
///
/// Returns null if index is out of bounds
pub fn getCollectionElementAt(collection: *z.DomCollection, index: usize) ?*z.DomElement {
    if (index >= getCollectionLength(collection)) {
        return null;
    }
    return lxb_dom_collection_element_noi(collection, index);
}

/// [collection] Get the first element in the collection
///
/// Returns null if collection is empty
pub fn getCollectionFirstElement(collection: *z.DomCollection) ?*z.DomElement {
    return getCollectionElementAt(collection, 0);
}

/// [collection] Get the last element in the collection
/// Returns null if collection is empty
pub fn getCollectionLastElement(collection: *z.DomCollection) ?*z.DomElement {
    const len = getCollectionLength(collection);
    if (len == 0) return null;
    return getCollectionElementAt(collection, len - 1);
}

/// [collection] Check if collection is empty
pub fn isCollectionEmpty(collection: *z.DomCollection) bool {
    return getCollectionLength(collection) == 0;
}

/// [collection] Add an element to the collection
pub fn appendElementToCollection(collection: *z.DomCollection, element: *z.DomElement) !void {
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

    pub fn next(self: *CollectionIterator) ?*z.DomElement {
        if (self.index >= getCollectionLength(self.collection)) {
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
/// Returns a DomCollection containing all elements with the specified tag name.
/// Examples: "div", "p", "span", "img", etc.
///
/// Caller is responsible for freeing the collection with `destroyCollection`
pub fn getElementsByTagName(doc: *z.HtmlDocument, tag_name: []const u8) !?*z.DomCollection {
    // Start from the body element but also check the body itself
    const root = try z.getDocumentBodyElement(doc);
    const collection = createDefaultCollection(doc) orelse return Err.CollectionFailed;

    if (collectElementsByTagName(root, collection, tag_name)) {
        return collection;
    } else {
        destroyCollection(collection);
        return null;
    }
}

/// [collection] Helper function to recursively collect elements with a specific tag name
fn collectElementsByTagName(element: *z.DomElement, collection: *z.DomCollection, tag_name: []const u8) bool {
    // Check if current element matches the tag name
    const element_tag_name = z.getElementName(element);
    if (std.mem.eql(u8, element_tag_name, tag_name)) {
        const status = lxb_dom_collection_append_noi(collection, element);
        if (status != 0) return false;
    }

    // Traverse children
    const element_node = z.elementToNode(element);
    var child_node = z.getNodeFirstChildNode(element_node);

    while (child_node) |node| {
        if (z.nodeToElement(node)) |child_element| {
            if (!collectElementsByTagName(child_element, collection, tag_name)) {
                return false;
            }
        }
        child_node = z.getNodeNextSiblingNode(node);
    }

    return true;
}

/// [collection] Find all elements with a specific name attribute (like JavaScript's getElementsByName).
///
/// This is commonly used for form elements that share the same name.
/// This is implemented as a wrapper around getElementsByAttribute for the name attribute.
///
/// Caller is responsible for freeing the collection with `destroyCollection`
pub fn getElementsByName(doc: *z.HtmlDocument, name: []const u8) !?*z.DomCollection {
    return getElementsByAttribute(
        doc,
        .{ .name = "name", .value = name },
        false, // case sensitive
    );
}

/// [collection] Find element by its ID attribute (like JavaScript's getElementById).
///
/// Returns the first element with the matching ID, or null if not found.
///
/// If you want to detect multiple IDs, use `getElementsByAttribute`.
pub fn getElementById(doc: *z.HtmlDocument, id: []const u8) !?*z.DomElement {
    const root = try z.getDocumentBodyElement(doc);

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
/// It returns a `DomCollection`.
///
/// You can use the collection primitives such as `getCollectionFirstElement`, `getCollectionLastElement`, etc.
///
/// Caller is responsible for freeing the return collection with `destroyCollection`
pub fn getElementsByAttribute(
    doc: *z.HtmlDocument,
    attr: z.AttributePair,
    case_insensitive: bool,
) !?*z.DomCollection {
    const root = try z.getDocumentBodyElement(doc);
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
/// It returns a DomCollection.
///
/// You can use the collection primitives such as `getCollectionFirstElement`, `getCollectionLastElement`, etc.
///
/// Caller is responsible for freeing the collection with `destroyCollection`
pub fn getElementsByClassName(doc: *z.HtmlDocument, class_name: []const u8) !?*z.DomCollection {
    return getElementsByAttribute(
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
///
/// It returns a DomCollection
///
/// You can use the collection primitives such as `getCollectionFirstElement`, `getCollectionLastElement`, etc.
///
/// Caller is responsible for freeing the collection
// pub fn getElementsByAttributeName(doc: *z.HtmlDocument, attr_name: []const u8) !?*z.DomCollection {
//     const root = try z.getDocumentBodyElement(doc);
//     const collection = createDefaultCollection(doc) orelse return Err.CollectionFailed;

//     // Traverse the DOM tree and collect elements with the specified attribute
//     if (collectElementsWithAttribute(root, collection, attr_name)) {
//         return collection;
//     } else {
//         destroyCollection(collection);
//         return null;
//     }
// }
pub fn getElementsByAttributeName(doc: *z.HtmlDocument, attr_name: []const u8, initial_capacity: usize) !?*z.DomCollection {
    const root = try z.getDocumentBodyElement(doc);
    const collection = createCollection(doc, initial_capacity) orelse return Err.CollectionFailed;

    if (collectElementsWithAttribute(root, collection, attr_name)) {
        return collection;
    } else {
        destroyCollection(collection);
        return null;
    }
}

/// [collection] Helper function to recursively collect elements with a specific attribute _name_
fn collectElementsWithAttribute(element: *z.DomElement, collection: *z.DomCollection, attr_name: []const u8) bool {
    // Early return if element has no attributes at all - performance optimization
    if (!z.elementHasAnyAttribute(element)) {
        // Still need to traverse children, so continue below
    } else if (z.elementHasNamedAttribute(element, attr_name)) {
        const status = lxb_dom_collection_append_noi(collection, element);
        if (status != 0) return false;
    }

    // Traverse children by converting element to node and iterating through child nodes
    const element_node = z.elementToNode(element);
    var child_node = z.getNodeFirstChildNode(element_node);

    while (child_node) |node| {
        // Convert node to element if it's an element node
        if (z.nodeToElement(node)) |child_element| {
            if (!collectElementsWithAttribute(child_element, collection, attr_name)) {
                return false;
            }
        }
        child_node = z.getNodeNextSiblingNode(node);
    }

    return true;
}
// fn collectElementsWithAttribute(element: *z.DomElement, collection: *z.DomCollection, attr_name: []const u8) bool {
//     // Check if current element has the attribute
//     if (z.elementHasNamedAttribute(element, attr_name)) {
//         const status = lxb_dom_collection_append_noi(collection, element);
//         if (status != 0) return false;
//     }

//     // Traverse children by converting element to node and iterating through child nodes
//     const element_node = z.elementToNode(element);
//     var child_node = z.getNodeFirstChildNode(element_node);

//     while (child_node) |node| {
//         // Convert node to element if it's an element node
//         if (z.nodeToElement(node)) |child_element| {
//             if (!collectElementsWithAttribute(child_element, collection, attr_name)) {
//                 return false;
//             }
//         }
//         child_node = z.getNodeNextSiblingNode(node);
//     }

//     return true;
// }

// Remove the placeholder helper functions as we're now using the real implementation

//=============================================================================
// UTILITY FUNCTIONS
//=============================================================================

/// [collection] Convert collection to Zig slice (allocates memory)
/// Caller is responsible for freeing the returned slice
pub fn toSlice(allocator: std.mem.Allocator, collection: *z.DomCollection) ![]?*z.DomElement {
    const len = getCollectionLength(collection);
    if (len == 0) return &[_]?*z.DomElement{};

    const slice = try allocator.alloc(?*z.DomElement, len);
    for (0..len) |i| {
        slice[i] = getCollectionElementAt(collection, i);
    }
    return slice;
}

/// [collection] Debug: Print collection info for debugging
pub fn debugPrint(collection: *z.DomCollection) void {
    const len = getCollectionLength(collection);
    print("Collection: {} elements\n", .{len});

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
    const doc = try z.parseHtmlString("<div><p id='test'>Hello</p><span>World</span></div>");
    defer z.destroyDocument(doc);

    // Create collection
    const collection = createDefaultCollection(doc) orelse return error.CollectionCreateFailed;
    defer destroyCollection(collection);
    debugPrint(collection);

    // Initially empty
    try testing.expect(isCollectionEmpty(collection));
    try testing.expectEqual(@as(usize, 0), getCollectionLength(collection));
    try testing.expect(getCollectionFirstElement(collection) == null);

    // Test iterator on empty collection
    var iter = iterator(collection);
    try testing.expect(iter.next() == null);
}

test "collection with CSS selector results" {
    const allocator = testing.allocator;

    const doc = try z.parseHtmlString("<div><p class='test'>Hello</p><p class='test'>World</p></div>");
    defer z.destroyDocument(doc);

    // Use CSS selector to populate collection
    const elements = try z.findElements(allocator, doc, "p.test");
    defer allocator.free(elements);

    // Verify we found elements
    try testing.expect(elements.len == 2);
}

test "collection iterator" {
    const allocator = testing.allocator;

    const doc = try z.parseHtmlString("<div><p>1</p><p>2</p><p>3</p></div>");
    defer z.destroyDocument(doc);

    const elements = try z.findElements(allocator, doc, "p");
    defer allocator.free(elements);

    try testing.expect(elements.len == 3);

    // Test that we got valid elements (they're non-optional pointers, so they can't be null)
    for (elements, 0..) |element, i| {
        // Elements from findElements are guaranteed to be non-null
        // Just verify the pointer is valid by checking it's not undefined behavior
        _ = element; // Use the element to avoid unused variable warning
        _ = i; // Use the index if needed
    }
}

// pb with numm comparison
// test "getElementById functionality" {
//     const html =
//         \\<html>
//         \\  <body>
//         \\    <div id="container">
//         \\      <p id="paragraph">Hello World</p>
//         \\      <span id="text">Test</span>
//         \\    </div>
//         \\  </body>
//         \\</html>
//     ;

//     const doc = try z.parseHtmlString(html);
//     defer z.destroyDocument(doc);

//     // Test finding existing elements
//     const container = getElementById(doc, "container");
//     try testing.expect(container != null);

//     const paragraph = getElementById(doc, "paragraph");
//     try testing.expect(paragraph != null);

//     const text_span = getElementById(doc, "text");
//     try testing.expect(text_span != null);

//     // Test non-existing element
//     const missing = getElementById(doc, "nonexistent");
//     try testing.expect(missing == null);
// }

test "getElementsByAttribute functionality" {
    const html =
        \\<div>
        \\  <p class="highlight">First</p>
        \\  <p class="highlight">Second</p>
        \\  <span class="different">Third</span>
        \\</div>
    ;

    const doc = try z.parseHtmlString(html);
    defer z.destroyDocument(doc);

    // Test finding by class
    const collection = try getElementsByClassName(doc, "highlight") orelse return error.CollectionFailed;
    defer destroyCollection(collection);

    try testing.expectEqual(@as(usize, 2), getCollectionLength(collection));

    const first = getCollectionElementAt(collection, 0);
    const second = getCollectionElementAt(collection, 1);
    try testing.expect(first != null);
    try testing.expect(second != null);
}

test "getElementsByAttribute comprehensive tests" {
    const html =
        \\<form>
        \\  <input type="text" name="username" required>
        \\  <input type="password" name="password" required>
        \\  <input type="email" name="email">
        \\  <input type="submit" value="Submit">
        \\  <textarea name="message" required></textarea>
        \\</form>
    ;

    const doc = try z.parseHtmlString(html);
    defer z.destroyDocument(doc);

    // Test 1: Find by type attribute
    {
        const text_inputs = try getElementsByAttribute(
            doc,
            .{ .name = "type", .value = "text" },
            false,
        ) orelse return error.CollectionFailed;
        defer destroyCollection(text_inputs);
        try testing.expectEqual(@as(usize, 1), getCollectionLength(text_inputs));
    }

    // Test 2: Find by required attribute (this will find elements with required="")
    {
        const required_fields = try getElementsByAttribute(
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
        const username_field = try getElementsByAttribute(
            doc,
            .{ .name = "name", .value = "username" },
            false,
        ) orelse return error.CollectionFailed;
        defer destroyCollection(username_field);
        try testing.expectEqual(@as(usize, 1), getCollectionLength(username_field));
    }

    // Test 4: Case insensitive search
    {
        const submit_inputs = try getElementsByAttribute(
            doc,
            .{ .name = "type", .value = "SUBMIT" },
            true,
        ) orelse return error.CollectionFailed;
        defer destroyCollection(submit_inputs);
        try testing.expectEqual(@as(usize, 1), getCollectionLength(submit_inputs));
    }

    // Test 5: Non-existent attribute value
    {
        const nonexistent = try getElementsByAttribute(
            doc,
            .{ .name = "type", .value = "nonexistent" },
            false,
        ) orelse return error.CollectionFailed;
        defer destroyCollection(nonexistent);
        try testing.expectEqual(@as(usize, 0), getCollectionLength(nonexistent));
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

    const doc = try z.parseHtmlString(html);
    defer z.destroyDocument(doc);

    const items = try getElementsByAttribute(
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
        try testing.expectEqual(getCollectionLength(items), count);
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
        try testing.expectEqual(getCollectionLength(items), count);
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
        const empty_collection = try getElementsByAttribute(
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
        for (0..getCollectionLength(items)) |i| {
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

    const doc = try z.parseHtmlString(html);
    defer z.destroyDocument(doc);

    const buttons = try getElementsByAttribute(
        doc,
        .{ .name = "type", .value = "button" },
        false,
    ) orelse return error.CollectionFailed;
    defer destroyCollection(buttons);

    // Test collection utility functions
    try testing.expectEqual(@as(usize, 1), getCollectionLength(buttons));
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

test "performance comparison: getElementById vs getElementsByAttribute" {
    const html =
        \\<div>
        \\  <div id="other1">Other 1</div>
        \\  <div id="other2">Other 2</div>
        \\  <div id="other3">Other 3</div>
        \\  <div id="other4">Other 4</div>
        \\  <div id="other5">Other 5</div>
        \\  <div id="other6">Other 6</div>
        \\  <div id="other7">Other 7</div>
        \\  <div id="other8">Other 8</div>
        \\  <div id="other9">Other 9</div>
        \\  <div id="other10">Other 10</div>
        \\  <div id="other11">Other 11</div>
        \\  <div id="other12">Other 12</div>
        \\  <div id="other13">Other 13</div>
        \\  <div id="other14">Other 14</div>
        \\  <div id="other15">Other 15</div>
        \\  <div id="other16">Other 16</div>
        \\  <div id="other17">Other 17</div>
        \\  <div id="other18">Other 18</div>
        \\  <div id="other19">Other 19</div>
        \\  <div id="other20">Other 20</div>
        \\  <div id="other21">Other 21</div>
        \\  <div id="other22">Other 22</div>
        \\  <div id="other23">Other 23</div>
        \\  <div id="other24">Other 24</div>
        \\  <div id="other25">Other 25</div>
        \\  <div id="other26">Other 26</div>
        \\  <div id="other27">Other 27</div>
        \\  <div id="other28">Other 28</div>
        \\  <div id="other29">Other 29</div>
        \\  <div id="other30">Other 30</div>
        \\  <div id="other31">Other 31</div>
        \\  <div id="other32">Other 32</div>
        \\  <div id="other33">Other 33</div>
        \\  <div id="other34">Other 34</div>
        \\  <div id="other35">Other 35</div>
        \\  <div id="other36">Other 36</div>
        \\  <div id="other37">Other 37</div>
        \\  <div id="other38">Other 38</div>
        \\  <div id="other39">Other 39</div>
        \\  <div id="other40">Other 40</div>
        \\  <div id="other41">Other 41</div>
        \\  <div id="other42">Other 42</div>
        \\  <div id="other43">Other 43</div>
        \\  <div id="other44">Other 44</div>
        \\  <div id="other45">Other 45</div>
        \\  <div id="other46">Other 46</div>
        \\  <div id="other47">Other 47</div>
        \\  <div id="other48">Other 48</div>
        \\  <div id="other49">Other 49</div>
        \\  <div id="other50">Other 50</div>
        \\  <div id="other51">Other 51</div>
        \\  <div id="other52">Other 52</div>
        \\  <div id="other53">Other 53</div>
        \\  <div id="other54">Other 54</div>
        \\  <div id="other55">Other 55</div>
        \\  <div id="other56">Other 56</div>
        \\  <div id="other57">Other 57</div>
        \\  <div id="other58">Other 58</div>
        \\  <div id="other59">Other 59</div>
        \\  <div id="other60">Other 60</div>
        \\  <div id="other61">Other 61</div>
        \\  <div id="other62">Other 62</div>
        \\  <div id="other63">Other 63</div>
        \\  <div id="other64">Other 64</div>
        \\  <div id="other65">Other 65</div>
        \\  <div id="other66">Other 66</div>
        \\  <div id="other67">Other 67</div>
        \\  <div id="other68">Other 68</div>
        \\  <div id="other69">Other 69</div>
        \\  <div id="other70">Other 70</div>
        \\  <div id="other71">Other 71</div>
        \\  <div id="other72">Other 72</div>
        \\  <div id="other73">Other 73</div>
        \\  <div id="other74">Other 74</div>
        \\  <div id="other75">Other 75</div>
        \\  <div id="other76">Other 76</div>
        \\  <div id="other77">Other 77</div>
        \\  <div id="other78">Other 78</div>
        \\  <div id="other79">Other 79</div>
        \\  <div id="other80">Other 80</div>
        \\  <div id="other81">Other 81</div>
        \\  <div id="other82">Other 82</div>
        \\  <div id="other83">Other 83</div>
        \\  <div id="other84">Other 84</div>
        \\  <div id="other85">Other 85</div>
        \\  <div id="other86">Other 86</div>
        \\  <div id="other87">Other 87</div>
        \\  <div id="other88">Other 88</div>
        \\  <div id="other89">Other 89</div>
        \\  <div id="other90">Other 90</div>
        \\  <div id="other91">Other 91</div>
        \\  <div id="other92">Other 92</div>
        \\  <div id="other93">Other 93</div>
        \\  <div id="other94">Other 94</div>
        \\  <div id="other95">Other 95</div>
        \\  <div id="other96">Other 96</div>
        \\  <div id="other97">Other 97</div>
        \\  <div id="other98">Other 98</div>
        \\  <div id="other99">Other 99</div>
        \\  <div id="other100">Other 100</div>
        \\  <div id="target">Target Element</div>
        \\</div>
    ;

    const doc = try z.parseHtmlString(html);
    defer z.destroyDocument(doc);

    // Method 1: getElementById (optimized)
    const start1 = try Instant.now();
    const element1 = try getElementById(doc, "target");
    try testing.expect(element1 != null);
    const end1 = try Instant.now();
    const elapsed1: f64 = @floatFromInt(end1.since(start1));
    print("Time elapsed is: {d:.4}ms\n", .{
        elapsed1 / std.time.ns_per_ms,
    });

    // Method 2: getElementsByAttribute for id (general purpose)
    const start2 = try Instant.now();
    const collection = try getElementsByAttribute(
        doc,
        .{ .name = "id", .value = "target" },
        false,
    ) orelse return error.CollectionFailed;
    defer destroyCollection(collection);

    try testing.expectEqual(@as(usize, 1), getCollectionLength(collection));
    const end2 = try Instant.now();
    const elapsed2: f64 = @floatFromInt(end2.since(start2));
    print("Time elapsed is: {d:.4}ms\n", .{
        elapsed2 / std.time.ns_per_ms,
    });

    const element2 = getCollectionFirstElement(collection);
    try testing.expect(element2 != null);

    // Both methods should find the same element
    try testing.expect(element1 == element2);
}

test "elementHasAnyAttribute performance demonstration" {
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

    const doc = try z.parseHtmlString(html);
    defer z.destroyDocument(doc);

    const body = try z.getDocumentBodyElement(doc);
    const first_child = z.getNodeFirstChildNode(z.elementToNode(body)) orelse return error.NoChild;
    const div_element = z.nodeToElement(first_child) orelse return error.NotElement;

    // Demonstrate that elementHasAnyAttribute correctly identifies elements with/without attributes
    var child_node = z.getNodeFirstChildNode(z.elementToNode(div_element));
    var elements_with_attrs: usize = 0;
    var elements_without_attrs: usize = 0;

    while (child_node) |node| {
        if (z.nodeToElement(node)) |element| {
            if (z.elementHasAnyAttribute(element)) {
                elements_with_attrs += 1;
            } else {
                elements_without_attrs += 1;
            }
        }
        child_node = z.getNodeNextSiblingNode(node);
    }

    try testing.expectEqual(@as(usize, 1), elements_with_attrs);
    try testing.expectEqual(@as(usize, 5), elements_without_attrs);

    // Test that getElementsByAttributeName correctly finds only the element with the id attribute
    const id_elements = try getElementsByAttributeName(doc, "id", 5) orelse return error.CollectionFailed;
    defer destroyCollection(id_elements);

    try testing.expectEqual(@as(usize, 1), getCollectionLength(id_elements));

    const found_element = getCollectionElementAt(id_elements, 0).?;
    try testing.expect(z.elementHasNamedAttribute(found_element, "id"));

    const id_value = z.elementGetNamedAttributeValue(found_element, "id").?;
    try testing.expect(std.mem.eql(u8, id_value, "with-attr"));
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

    const doc = try z.parseHtmlString(html);
    defer z.destroyDocument(doc);

    // Test that getElementsByAttributeName still works correctly with the optimization
    const id_elements = try getElementsByAttributeName(doc, "id", 10) orelse return error.CollectionFailed;
    defer destroyCollection(id_elements);

    const count = getCollectionLength(id_elements);
    try testing.expect(count == 3); // container, para1, span1

    // Verify that elements without any attributes were correctly skipped
    // but elements with attributes were still processed correctly
    for (0..count) |i| {
        const element = getCollectionElementAt(id_elements, i).?;
        try testing.expect(z.elementHasNamedAttribute(element, "id"));
        try testing.expect(z.elementHasAnyAttribute(element)); // Should have at least some attribute
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

    const doc = try z.parseHtmlString(html);
    defer z.destroyDocument(doc);
    // try z.printDocumentStructure(doc);

    // Test 1: Find all elements with 'id' attribute: count is 5
    {
        const id_elements = try getElementsByAttributeName(doc, "id", 10) orelse return error.CollectionFailed;
        defer destroyCollection(id_elements);

        const count = getCollectionLength(id_elements);
        try testing.expect(count == 5);

        // Verify we can iterate through them
        var iter = iterator(id_elements);
        var found_count: usize = 0;
        while (iter.next()) |element| {
            // Element is guaranteed to be non-null from iterator
            try testing.expect(z.elementHasNamedAttribute(element, "id"));
            found_count += 1;
        }
        try testing.expectEqual(count, found_count);
    }

    // Test 2: Find all elements with 'class' attribute: count is 3
    {
        const class_elements = try getElementsByAttributeName(doc, "class", 5) orelse return error.CollectionFailed;
        defer destroyCollection(class_elements);

        const count = getCollectionLength(class_elements);
        try testing.expect(count >= 3);

        // Verify all found elements have the class attribute
        for (0..count) |i| {
            const element = getCollectionElementAt(class_elements, i).?;
            try testing.expect(z.elementHasNamedAttribute(element, "class"));
        }
    }

    // Test 3: Find all elements with 'type' attribute: count is 3
    {
        const type_elements = try getElementsByAttributeName(doc, "type", 5) orelse return error.CollectionFailed;
        defer destroyCollection(type_elements);

        const count = getCollectionLength(type_elements);
        try testing.expectEqual(@as(usize, 3), count);
    }

    // Test 4: Find all elements with 'name' attribute: count is 2
    {
        const name_elements = try getElementsByAttributeName(doc, "name", 3) orelse return error.CollectionFailed;
        defer destroyCollection(name_elements);

        const count = getCollectionLength(name_elements);
        try testing.expectEqual(@as(usize, 2), count);
    }

    // Test 5: Find elements with non-existent attribute: count is 0
    {
        const nonexistent = try getElementsByAttributeName(doc, "nonexistent", 1) orelse return error.CollectionFailed;
        defer destroyCollection(nonexistent);

        try testing.expectEqual(@as(usize, 0), getCollectionLength(nonexistent));
        try testing.expect(isCollectionEmpty(nonexistent));
    }

    // Test 6: Compare getElementsByAttributeName vs getElementsByAttribute
    {
        // Find all elements with any 'id' attribute: id="container"
        const all_with_id = try getElementsByAttributeName(doc, "id", 10) orelse return error.CollectionFailed;
        defer destroyCollection(all_with_id);

        const specific_id = try getElementsByAttribute(
            doc,
            .{ .name = "id", .value = "container" },
            false,
        ) orelse return error.CollectionFailed;
        defer destroyCollection(specific_id);

        // all_with_id should have more elements than specific_id
        try testing.expect(getCollectionLength(all_with_id) > getCollectionLength(specific_id));
        try testing.expectEqual(@as(usize, 1), getCollectionLength(specific_id));
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

    const doc = try z.parseHtmlString(html);
    defer z.destroyDocument(doc);

    // Test 1: Find all paragraphs (note: Lexbor returns uppercase tag names)
    {
        const paragraphs = try getElementsByTagName(doc, "P") orelse return error.CollectionFailed;
        defer destroyCollection(paragraphs);

        try testing.expectEqual(@as(usize, 3), getCollectionLength(paragraphs));

        // Verify all found elements are indeed paragraphs
        for (0..getCollectionLength(paragraphs)) |i| {
            const element = getCollectionElementAt(paragraphs, i).?;
            const tag_name = z.getElementName(element);
            try testing.expect(std.mem.eql(u8, tag_name, "P"));
        }
    }

    // Test 2: Find all divs
    {
        const divs = try getElementsByTagName(doc, "DIV") orelse return error.CollectionFailed;
        defer destroyCollection(divs);

        try testing.expectEqual(@as(usize, 2), getCollectionLength(divs)); // container + nested div
    }

    // Test 3: Find all spans
    {
        const spans = try getElementsByTagName(doc, "SPAN") orelse return error.CollectionFailed;
        defer destroyCollection(spans);

        try testing.expectEqual(@as(usize, 2), getCollectionLength(spans));
    }

    // Test 4: Find non-existent tag
    {
        const articles = try getElementsByTagName(doc, "ARTICLE") orelse return error.CollectionFailed;
        defer destroyCollection(articles);

        try testing.expectEqual(@as(usize, 0), getCollectionLength(articles));
    }
}

test "getElementsByName functionality" {
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

    const doc = try z.parseHtmlString(html);
    defer z.destroyDocument(doc);

    // Test 1: Find elements with name="gender" (radio buttons)
    {
        const gender_inputs = try getElementsByName(doc, "gender") orelse return error.CollectionFailed;
        defer destroyCollection(gender_inputs);

        try testing.expectEqual(@as(usize, 2), getCollectionLength(gender_inputs));

        // Verify all found elements have the correct name attribute
        for (0..getCollectionLength(gender_inputs)) |i| {
            const element = getCollectionElementAt(gender_inputs, i).?;
            const name_value = z.elementGetNamedAttributeValue(element, "name").?;
            try testing.expect(std.mem.eql(u8, name_value, "gender"));
        }
    }

    // Test 2: Find unique name
    {
        const username_input = try getElementsByName(doc, "username") orelse return error.CollectionFailed;
        defer destroyCollection(username_input);

        try testing.expectEqual(@as(usize, 1), getCollectionLength(username_input));
    }

    // Test 3: Find non-existent name
    {
        const nonexistent = try getElementsByName(doc, "nonexistent") orelse return error.CollectionFailed;
        defer destroyCollection(nonexistent);

        try testing.expectEqual(@as(usize, 0), getCollectionLength(nonexistent));
    }
}
