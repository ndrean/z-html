const std = @import("std");
const z = @import("zhtml.zig");
const builtin = @import("builtin");
// const wri/ter = std.io.getStdOut().writer();

// const writer = if (builtin.mode == .Debug)
//     std.debug
// else
//     std.io.getStdOut().writer();

// fn Context(comptime WriterType: type) type {
//     return struct {
//         writer: WriterType,
//     };
// }

fn Context(comptime WriterType: type) type {
    return struct {
        writer: WriterType,

        pub fn print(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
            try self.writer.print(fmt, args);
        }

        pub fn deinit(self: *@This()) void {
            if (@hasDecl(WriterType, "deinit")) {
                self.writer.deinit();
            } else {
                // assume no cleanup needed
            }
        }
    };
}

fn serialiazeAndClean(allocator: std.mem.Allocator, fragment: []const u8, ctx: anytype) !void {
    const doc = try z.parseFromString(fragment);
    defer z.destroyDocument(doc);

    const body_node = try z.bodyNode(doc);

    const html = try z.serializeToString(
        allocator,
        body_node,
    );
    defer allocator.free(html);

    try ctx.writer.print("\n\n---------HTML string to parse---------\n\n", .{});
    // try z.printDocumentStructure(doc);
    try ctx.writer.print("{s}\n\n", .{html});

    try z.cleanDomTree(
        allocator,
        body_node,
        .{ .remove_comments = true },
    );

    const new_html = try z.serializeToString(
        allocator,
        body_node,
    );
    defer allocator.free(new_html);

    try ctx.writer.print("\n\n ==== cleaned HTML =======\n\n", .{});
    try ctx.writer.print("{s}\n\n", .{new_html});
    try ctx.writer.print("\n\n---------DOCUMENT STRUCTURE---------\n\n", .{});
    // try z.printDocumentStructure(doc);

    // _ = try request(allocator, "https://google.com", "text/html");
}

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator, const is_debug = switch (builtin.mode) {
        .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
        .ReleaseFast, .ReleaseSmall => .{ std.heap.c_allocator, false },
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    const stdout_writer = std.io.getStdOut().writer();
    const DebugWriter = struct {
        pub fn print(_: @This(), comptime fmt: []const u8, args: anytype) !void {
            std.debug.print(fmt, args);
            return;
        }
    };

    const debug_writer = DebugWriter{};

    const writerType = if (builtin.mode == .Debug)
        @TypeOf(debug_writer)
    else
        @TypeOf(stdout_writer);

    const ctx = Context(writerType){
        .writer = if (builtin.mode == .Debug)
            debug_writer
        else
            stdout_writer,
    };

    const fragment =
        \\<div   class  =  " container test "   id  = "main"  >
        \\    
        \\    <p>   Hello     World   </p>
        \\    
        \\    <!-- Remove this comment -->
        \\    <span data-id = "123"></span>
        \\    <pre>    preserve    this    </pre>
        \\    
        \\    <p>  </p>
        \\
        \\   <br/> <!-- This should be removed -->
        \\
        \\    <img src = 'http://google.com' alt = 'my-image' data-value=''/> 
        \\
        \\     <script> const div  = document.querySelector('div'); </script>
        \\</div>
        \\<div data-empty='' title='  spaces  '>Content</div>
        \\<article>
        \\<h1>Title</h1><p>Para 1</p><p>Para 2</p>
        \\<footer>End</footer>
        \\</article>
    ;

    try ctx.writer.print("\n\n---------ELEMENTS---------\n\n", .{});
    try serialiazeAndClean(allocator, fragment, ctx);

    // Example menu system
    // try writer.print("\n=== Z-HTML Examples ===\n", .{});
    // try writer.print("Choose an example to run:\n", .{});
    // try writer.print("1. Basic Collection Example (getElementById, simple demos)\n", .{});
    // try writer.print("2. Comprehensive Collection Examples (all features, iterators, performance)\n", .{});
    // try writer.print("3. Skip examples\n", .{});
    // try writer.print("Enter choice (1-3): ", .{});

    // try writer.print("\n\n=== Running Basic Collection Example ===\n", .{});

    // try writer.print("\n\n=== Running Comprehensive Collection Examples ===\n", .{});
}
