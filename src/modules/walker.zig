//! DOM Search Utilities Using `simple_Walk` Walker Callbacks

//======================================================================
// DOM SEARCH USING WALKER CALLBACKS
//=======================================================================

const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;
const print = std.debug.print;

const testing = std.testing;

// Fast DOM traversal for optimized search
extern "c" fn lxb_dom_node_simple_walk(
    root: *z.DomNode,
    walker_cb: *const fn (*z.DomNode, ?*anyopaque) callconv(.c) c_int,
    ctx: ?*anyopaque,
) void;

/// [walker] Traverse the DOM
pub fn simpleWalk(
    root: *z.DomNode,
    callback: *const fn (*z.DomNode, ?*anyopaque) callconv(.c) c_int,
    ctx: ?*anyopaque,
) void {
    lxb_dom_node_simple_walk(root, callback, ctx);
}

/// Helper to convert "aligned" `anyopaque` to the target pointer type `T`
/// ```
/// const my_ctx: *IdCtx = castCtx(MyCtx, ctx: ?*anyopaque);
/// ```
pub fn castContext(comptime T: type, ctx: ?*anyopaque) *T {
    return @as(*T, @ptrCast(@alignCast(ctx.?)));
}

pub fn toAnyOpaque(comptime T: type, ptr: *T) ?*anyopaque {
    return @as(?*anyopaque, @ptrCast(ptr));
}

/// [walker] Generic walker for _single matching element_ (stops at first match)
///
///
/// The `matcher` signature is `fn (*z.DomNode, ctx: ?*anyopaque) callconv(.c) c_int`.
///
/// It returns `z._CONTINUE = 0` to keep walking, or `z._STOP = 1` to stop.
///
/// 1. Define a context struct with at these two mandatory field names: `matcher` with the signature above, and `found_element: z.HTMLElement`.
/// Add an implementation and a target field (id, class, aria, data-attribute...)
/// 2. Instantiate a mutable instance of that struct and pass its address to `genSearchElement`.
/// ### Example:
/// ````
/// const IdContext = struct {
///    found_element: *z.HTMLElement = null,
///    matcher: *const fn (*z.DomNode, ctx: *@This()) c_int,
///    target_id: []const u8, // your field
///    fn implementation(node: *z.DomNode, ctx: *@This()) c_int {...} // your implementation
/// };
/// var id_context_instance = IdContext{
///   .target_id = id_argument, // your input
///   .matcher = IdContext.implementation,
/// };
/// genSearchElement(IdContext, root_node, &id_context_instance);
/// ```
pub fn genSearchElement(comptime ContextType: type, root_node: *z.DomNode, context: *ContextType) ?*z.HTMLElement {
    const finder = struct {
        fn cb(node: *z.DomNode, ctx: ?*anyopaque) callconv(.c) c_int {
            if (!z.isTypeElement(node)) return z._CONTINUE;
            const typed_ctx: *ContextType = @ptrCast(@alignCast(ctx.?));

            return typed_ctx.matcher(node, typed_ctx);
        }
    }.cb;

    simpleWalk(
        root_node,
        finder,
        @as(?*anyopaque, @ptrCast(context)),
    );
    return context.found_element;
}

/// [walker] Generic walker to find _multiple matching elements_ (continues until end)
///
/// The context holds the allocator and an ArrayList to collect results.
///
/// The mandatory field names are `matcher`, `results`. cf `genSearchElement` for details.
///
/// You can use this function to capture elements.
///
/// If you just want to run side-effects, use `genProcessAll`, for removal for example.
///
/// Notice that any DOM modification should be done in a post-processing step.
pub fn genSearchElements(comptime ContextType: type, root_node: *z.DomNode, context: *ContextType) ![]const *z.HTMLElement {
    const finder = struct {
        fn cb(node: *z.DomNode, ctx: ?*anyopaque) callconv(.c) c_int {
            if (!z.isTypeElement(node)) return z._CONTINUE;

            var typed_ctx = castContext(ContextType, ctx);
            return typed_ctx.matcher(node, typed_ctx);
        }
    }.cb;
    //
    simpleWalk(
        root_node,
        finder,
        toAnyOpaque(ContextType, context),
    );
    return context.results.toOwnedSlice(context.allocator);
}

/// [walker] Generic runtime walker to "process all elements" with a given `processor` function on the nodes.
///
/// Use this function to run side-effects, like removal. Notice that any DOM modification should be done in a post-processing step.
///
/// The `processor` signature is `fn (*z.DomNode, ctx: ?*anyopaque) c_int`. It returns `z._CONTINUE = 0` to keep walking, or `z._STOP = 1` to stop.
///
/// 1. Define a context struct with the mandatory field `processor` and any extra fields you need.
/// with the same signature.
/// 2. Take a mutable instance of that struct and pass it to `genProcessAll`.
/// ### Example:
/// ````
/// const MyContext = struct {
///    allocator: std.mem.Allocator,
///    processor: *const fn (*z.DomNode, ctx: *@This()) c_int,
///    extra_field: u32, // any extra fields you need
///    fn myProcessor(node: *z.DomNode, ctx: *@This()) c_int {...}
/// };
/// var my_context_instance = MyContext{
///   .allocator = allocator,
///   .processor = &MyContext.myProcessor,
///   .extra_field = 42,
///   .processor = &MyContext.myProcessor,
/// };
/// GenProcessAll(MyContext, root_node, &my_context_instance);
/// ```
///
/// `genProcessAll(MyContext, root_node, &my_context_instance)`.
pub fn genProcessAll(comptime ContextType: type, root_node: *z.DomNode, context: *ContextType) void {
    const processor = struct {
        fn cb(node: *z.DomNode, ctx: ?*anyopaque) callconv(.c) c_int {
            if (!z.isTypeElement(node)) return z._CONTINUE;
            var typed_ctx = castContext(ContextType, ctx);
            return typed_ctx.processor(node, typed_ctx);
        }
    }.cb;

    simpleWalk(
        root_node,
        processor,
        toAnyOpaque(ContextType, context),
    );
}
