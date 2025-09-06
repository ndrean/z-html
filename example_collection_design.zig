//! Improved Collection Design - Self-contained struct with methods
//! This eliminates global state and provides cleaner encapsulation

const std = @import("std");
const z = @import("zhtml.zig");

/// Collection configuration - no more global variables!
pub const CollectionConfig = struct {
    default_capacity: u8 = 10,
    
    pub const DEFAULT = CollectionConfig{};
    pub const SINGLE = CollectionConfig{ .default_capacity = 1 };
    pub const LARGE = CollectionConfig{ .default_capacity = 50 };
};

/// Self-contained Collection with methods and proper RAII
pub const Collection = struct {
    raw_collection: *z.DomCollection,
    doc: *z.HTMLDocument, // Needed for cleanup
    config: CollectionConfig,
    
    // ========================================
    // Creation/Destruction (RAII pattern)
    // ========================================
    
    /// Initialize a new collection with configuration
    pub fn init(doc: *z.HTMLDocument, config: CollectionConfig) !Collection {
        const raw_collection = lxb_dom_collection_create(doc) orelse 
            return error.CollectionCreateFailed;
            
        const status = lxb_dom_collection_init(raw_collection, config.default_capacity);
        if (status != 0) {
            _ = lxb_dom_collection_destroy(raw_collection, true);
            return error.CollectionInitFailed;
        }
        
        return Collection{
            .raw_collection = raw_collection,
            .doc = doc,
            .config = config,
        };
    }
    
    /// Initialize with default configuration
    pub fn initDefault(doc: *z.HTMLDocument) !Collection {
        return init(doc, CollectionConfig.DEFAULT);
    }
    
    /// Initialize for single element operations
    pub fn initSingle(doc: *z.HTMLDocument) !Collection {
        return init(doc, CollectionConfig.SINGLE);
    }
    
    /// Clean up resources - can be called explicitly or via defer
    pub fn deinit(self: *Collection) void {
        _ = lxb_dom_collection_destroy(self.raw_collection, true);
        self.* = undefined; // Prevent use-after-free
    }
    
    // ========================================
    // Core Collection Methods
    // ========================================
    
    pub fn length(self: *const Collection) usize {
        return lxb_dom_collection_length_noi(self.raw_collection);
    }
    
    pub fn isEmpty(self: *const Collection) bool {
        return self.length() == 0;
    }
    
    pub fn get(self: *const Collection, index: usize) ?*z.HTMLElement {
        if (index >= self.length()) return null;
        return lxb_dom_collection_element_noi(self.raw_collection, index);
    }
    
    pub fn first(self: *const Collection) ?*z.HTMLElement {
        return self.get(0);
    }
    
    pub fn last(self: *const Collection) ?*z.HTMLElement {
        const len = self.length();
        if (len == 0) return null;
        return self.get(len - 1);
    }
    
    pub fn append(self: *Collection, element: *z.HTMLElement) !void {
        const status = lxb_dom_collection_append_noi(self.raw_collection, element);
        if (status != 0) return error.AppendFailed;
    }
    
    pub fn clear(self: *Collection) void {
        lxb_dom_collection_clean_noi(self.raw_collection);
    }
    
    // ========================================
    // Search Methods (Factory Methods)
    // ========================================
    
    /// Find elements by tag name - returns owned Collection
    pub fn findByTagName(doc: *z.HTMLDocument, tag_name: []const u8) !Collection {
        var collection = try Collection.initDefault(doc);
        errdefer collection.deinit();
        
        const root = z.bodyElement(doc) orelse return error.NoBodyElement;
        try collectElementsByTagName(root, &collection, tag_name);
        
        return collection;
    }
    
    /// Find element by ID - returns owned Collection (usually single element)
    pub fn findById(doc: *z.HTMLDocument, id: []const u8) !Collection {
        var collection = try Collection.initSingle(doc);
        errdefer collection.deinit();
        
        const root = z.bodyElement(doc) orelse return error.NoBodyElement;
        const status = lxb_dom_elements_by_attr(
            root, collection.raw_collection,
            "id".ptr, 2,
            id.ptr, id.len,
            false
        );
        
        if (status != 0) return error.SearchFailed;
        return collection;
    }
    
    // ========================================
    // Iterator Support
    // ========================================
    
    pub const Iterator = struct {
        collection: *const Collection,
        index: usize = 0,
        
        pub fn next(self: *Iterator) ?*z.HTMLElement {
            if (self.index >= self.collection.length()) return null;
            const element = self.collection.get(self.index);
            self.index += 1;
            return element;
        }
        
        pub fn reset(self: *Iterator) void {
            self.index = 0;
        }
    };
    
    pub fn iterator(self: *const Collection) Iterator {
        return Iterator{ .collection = self };
    }
    
    // ========================================
    // Convenience Methods
    // ========================================
    
    /// Convert to slice (allocates - caller owns)
    pub fn toSlice(self: *const Collection, allocator: std.mem.Allocator) ![]const *z.HTMLElement {
        const len = self.length();
        if (len == 0) return &[_]*z.HTMLElement{};
        
        var slice = try allocator.alloc(*z.HTMLElement, len);
        for (0..len) |i| {
            slice[i] = self.get(i).?; // Safe because we checked length
        }
        return slice;
    }
    
    /// Debug print collection contents
    pub fn debugPrint(self: *const Collection) void {
        std.debug.print("Collection: {} elements\n", .{self.length()});
        var iter = self.iterator();
        var i: usize = 0;
        while (iter.next()) |element| {
            const tag_name = z.tagName_zc(element);
            std.debug.print("  [{}]: <{}>\n", .{ i, tag_name });
            i += 1;
        }
    }
};

// ========================================
// Usage Examples
// ========================================

// Example 1: RAII pattern - automatic cleanup
fn exampleBasicUsage(doc: *z.HTMLDocument) !void {
    // Clean RAII pattern
    var collection = try Collection.findByTagName(doc, "div");
    defer collection.deinit(); // Automatic cleanup
    
    std.debug.print("Found {} div elements\n", .{collection.length()});
    
    // Method chaining style
    if (collection.first()) |first_div| {
        const tag = z.tagName_zc(first_div);
        std.debug.print("First div: <{}>\n", .{tag});
    }
}

// Example 2: Iterator usage
fn exampleIterator(doc: *z.HTMLDocument) !void {
    var collection = try Collection.findByTagName(doc, "p");
    defer collection.deinit();
    
    var iter = collection.iterator();
    while (iter.next()) |element| {
        // Process each element
        const tag = z.tagName_zc(element);
        std.debug.print("Processing: <{}>\n", .{tag});
    }
}

// Example 3: Configuration usage
fn exampleCustomConfig(doc: *z.HTMLDocument) !void {
    const custom_config = CollectionConfig{ .default_capacity = 100 };
    var large_collection = try Collection.init(doc, custom_config);
    defer large_collection.deinit();
    
    // Use for large searches...
}

// Helper function (can be private)
fn collectElementsByTagName(element: *z.HTMLElement, collection: *Collection, tag_name: []const u8) !void {
    const element_tag_name = z.tagName_zc(element);
    if (std.mem.eql(u8, element_tag_name, tag_name)) {
        try collection.append(element);
    }
    
    var child_element = z.firstElementChild(element);
    while (child_element) |child| {
        try collectElementsByTagName(child, collection, tag_name);
        child_element = z.nextElementSibling(child);
    }
}

// External C function declarations (same as current)
extern "c" fn lxb_dom_collection_create(doc: *z.HTMLDocument) ?*z.DomCollection;
extern "c" fn lxb_dom_collection_init(collection: *z.DomCollection, start_size: usize) usize;
extern "c" fn lxb_dom_collection_destroy(collection: *z.DomCollection, self_destroy: bool) ?*z.DomCollection;
extern "c" fn lxb_dom_collection_clean_noi(collection: *z.DomCollection) void;
extern "c" fn lxb_dom_collection_length_noi(collection: *z.DomCollection) usize;
extern "c" fn lxb_dom_collection_element_noi(collection: *z.DomCollection, idx: usize) ?*z.HTMLElement;
extern "c" fn lxb_dom_collection_append_noi(collection: *z.DomCollection, value: ?*anyopaque) usize;
extern "c" fn lxb_dom_elements_by_attr(
    root: *z.HTMLElement,
    collection: *z.DomCollection,
    qualified_name: [*]const u8,
    qname_len: usize,
    value: [*]const u8,
    value_len: usize,
    case_insensitive: bool,
) usize;