// Zigler ArrayList of Terms:

const beam = @import("beam");
const std = @import("std");
const z = @import("zhtml");

pub fn dom_to_tuple(env: beam.env, doc: *z.HTMLDocument) beam.term {
    var arena = std.heap.ArenaAllocator.init(beam.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // ArrayList of Erlang terms
    var children: std.ArrayList(beam.term) = .empty;
    defer children.deinit(allocator);

    const root = z.documentRoot(doc).?;
    var child = z.firstChild(root);
    while (child != null) {
        const term = try node_to_term(env, allocator, child.?);
        try children.append(term);
        child = z.nextSibling(child.?);
    }

    // Convert ArrayList to Erlang list
    return beam.make_list(env, children.items);
}

fn node_to_term(env: beam.env, allocator: std.mem.Allocator, node: *z.DomNode) !beam.term {
    switch (z.nodeType(node)) {
        .element => {
            const element = z.nodeToElement(node).?;
            const tag_name = z.qualifiedName_zc(element);

            // Create tag binary
            const tag_term = beam.make_slice(env, tag_name);

            // Collect attributes in ArrayList
            var attrs = std.ArrayList(beam.term).init(allocator);
            defer attrs.deinit();

            // ... build attributes ...

            // Collect children recursively
            var children = std.ArrayList(beam.term).init(allocator);
            defer children.deinit();

            var child = z.firstChild(node);
            while (child != null) {
                try children.append(try node_to_term(env, allocator, child.?));
                child = z.nextSibling(child.?);
            }

            // Create {tag, attrs, children} tuple
            return beam.make_tuple(env, .{ tag_term, beam.make_list(env, attrs.items), beam.make_list(env, children.items) });
        },
        // ... other node types
    }
}
