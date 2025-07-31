const std = @import("std");
// const wrapper = @import("wrapper.zig");
const lexbor = @import("lexbor.zig");

const html =
    \\<html>
    \\  <body>
    \\    <div>Old text</div>
    \\    <div class="target">Replace me</div>
    \\  </body>
    \\</html>
;

const frag =
    \\<div>Fragment</div>
    \\<p>Another fragment</p>
;

// fn InjectText() !void {
//     const allocator = std.heap.page_allocator;

//     const modified = try wrapper.injectText(
//         allocator,
//         html,
//         "div.target", // CSS selector (simplified for demo)
//         "id",
//         "updated",
//         "New text!",
//     );
//     defer allocator.free(modified);

//     std.debug.print("Modified HTML:\n{s}\n", .{modified});
// }
pub fn main() !void {
    // const stdout_file = std.io.getStdOut().writer();
    // var bw = std.io.bufferedWriter(stdout_file);
    // const stdout = bw.writer();
    // try stdout.print("Parsing HTML...\n", .{});

    const doc = try lexbor.parseHtml(html);
    defer lexbor.lxb_html_document_destroy(doc);
    const doc_node = lexbor.getDocumentNode(doc);
    const name = try lexbor.getNodeName(doc_node);
    std.debug.print("Document Node: {s}\n", .{name});

    _ = lexbor.printDocumentStructure(doc);

    _ = try lexbor.demonstrateFragmentParsing(frag);

    // try bw.flush();
}
