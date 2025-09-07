const std = @import("std");
const z = @import("src/zhtml.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);
    
    var parser = try z.FragmentParser.init(allocator);
    defer parser.deinit();
    
    try z.parseString(doc, "<select id='countries'></select>");
    const body = z.bodyNode(doc).?;
    const select = z.getElementById(body, "countries").?;
    const select_node = z.elementToNode(select);
    
    const options_html =
        \\<option value="us">United States</option>
        \\<option value="ca">Canada</option>
        \\<optgroup label="Europe">
        \\  <option value="uk">United Kingdom</option>
        \\  <option value="fr">France</option>
        \\</optgroup>
    ;
    
    std.debug.print("Inserting options HTML: {s}\n", .{options_html});
    
    try parser.insertFragment(select_node, options_html, .select, .permissive);
    
    const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
    defer allocator.free(result);
    
    std.debug.print("Final result: {s}\n", .{result});
    
    // Check what we're looking for
    const has_united_states = std.mem.indexOf(u8, result, "United States") != null;
    const has_optgroup = std.mem.indexOf(u8, result, "optgroup") != null;
    const has_uk = std.mem.indexOf(u8, result, "United Kingdom") != null;
    
    std.debug.print("Has 'United States': {}\n", .{has_united_states});
    std.debug.print("Has 'optgroup': {}\n", .{has_optgroup});
    std.debug.print("Has 'United Kingdom': {}\n", .{has_uk});
    
    // Let's also try with .none sanitization to see if it's a sanitization issue
    const doc2 = try z.createDocument();
    defer z.destroyDocument(doc2);
    
    var parser2 = try z.FragmentParser.init(allocator);
    defer parser2.deinit();
    
    try z.parseString(doc2, "<select id='countries2'></select>");
    const body2 = z.bodyNode(doc2).?;
    const select2 = z.getElementById(body2, "countries2").?;
    const select_node2 = z.elementToNode(select2);
    
    std.debug.print("\n--- Testing with .none sanitization ---\n", .{});
    try parser2.insertFragment(select_node2, options_html, .select, .none);
    
    const result2 = try z.outerHTML(allocator, z.nodeToElement(body2).?);
    defer allocator.free(result2);
    
    std.debug.print("Result with .none: {s}\n", .{result2});
}