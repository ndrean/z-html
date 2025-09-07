const std = @import("std");
const z = @import("src/zhtml.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    // Test form elements
    std.debug.print("=== Testing form elements ===\n", .{});
    {
        const doc = try z.createDocument();
        defer z.destroyDocument(doc);
        var parser = try z.FragmentParser.init(allocator);
        defer parser.deinit();
        
        try z.parseString(doc, "<form id='test-form'></form>");
        const body = z.bodyNode(doc).?;
        const form = z.getElementById(body, "test-form").?;
        const form_node = z.elementToNode(form);
        
        const form_html =
            \\<label for="email">Email:</label>
            \\<input type="email" id="email" name="email" required>
            \\<label for="password">Password:</label>
            \\<input type="password" id="password" name="password" required>
            \\<button type="submit">Login</button>
        ;
        
        try parser.insertFragment(form_node, form_html, .form, .permissive);
        const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
        defer allocator.free(result);
        
        std.debug.print("Form result: {s}\n", .{result});
        std.debug.print("Has type=\"email\": {}\n", .{std.mem.indexOf(u8, result, "type=\"email\"") != null});
        std.debug.print("Has for=\"email\": {}\n", .{std.mem.indexOf(u8, result, "for=\"email\"") != null});
    }
    
    // Test video/audio elements
    std.debug.print("\n=== Testing media elements ===\n", .{});
    {
        const doc = try z.createDocument();
        defer z.destroyDocument(doc);
        var parser = try z.FragmentParser.init(allocator);
        defer parser.deinit();
        
        try z.parseString(doc, "<div id='media-container'></div>");
        const body = z.bodyNode(doc).?;
        const container = z.getElementById(body, "media-container").?;
        const container_node = z.elementToNode(container);
        
        const media_html =
            \\<video id='demo' controls>
            \\  <source src="/video.webm" type="video/webm">
            \\  <source src="/video.mp4" type="video/mp4">
            \\  <track kind="captions" src="/captions.vtt" srclang="en" label="English">
            \\</video>
        ;
        
        try parser.insertFragment(container_node, media_html, .div, .permissive);
        const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
        defer allocator.free(result);
        
        std.debug.print("Media result: {s}\n", .{result});
        std.debug.print("Has src=\"/video.webm\": {}\n", .{std.mem.indexOf(u8, result, "src=\"/video.webm\"") != null});
        std.debug.print("Has type=\"video/webm\": {}\n", .{std.mem.indexOf(u8, result, "type=\"video/webm\"") != null});
        std.debug.print("Has kind=\"captions\": {}\n", .{std.mem.indexOf(u8, result, "kind=\"captions\"") != null});
    }
    
    // Test fieldset/legend
    std.debug.print("\n=== Testing fieldset/legend ===\n", .{});
    {
        const doc = try z.createDocument();
        defer z.destroyDocument(doc);
        var parser = try z.FragmentParser.init(allocator);
        defer parser.deinit();
        
        try z.parseString(doc, "<fieldset id='contact'></fieldset>");
        const body = z.bodyNode(doc).?;
        const fieldset = z.getElementById(body, "contact").?;
        const fieldset_node = z.elementToNode(fieldset);
        
        const fieldset_html =
            \\<legend>Contact Information</legend>
            \\<label for="name">Name:</label>
            \\<input type="text" id="name" name="name">
        ;
        
        try parser.insertFragment(fieldset_node, fieldset_html, .fieldset, .permissive);
        const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
        defer allocator.free(result);
        
        std.debug.print("Fieldset result: {s}\n", .{result});
        std.debug.print("Has <legend>: {}\n", .{std.mem.indexOf(u8, result, "<legend>Contact Information</legend>") != null});
        std.debug.print("Has type=\"text\": {}\n", .{std.mem.indexOf(u8, result, "type=\"text\"") != null});
    }
    
    // Test map/area elements
    std.debug.print("\n=== Testing map/area ===\n", .{});
    {
        const doc = try z.createDocument();
        defer z.destroyDocument(doc);
        var parser = try z.FragmentParser.init(allocator);
        defer parser.deinit();
        
        try z.parseString(doc, "<map id='imagemap' name='navigation'></map>");
        const body = z.bodyNode(doc).?;
        const map = z.getElementById(body, "imagemap").?;
        const map_node = z.elementToNode(map);
        
        const areas_html =
            \\<area shape="rect" coords="0,0,100,100" href="/section1" alt="Section 1">
            \\<area shape="circle" coords="150,75,50" href="/section2" alt="Section 2">
        ;
        
        try parser.insertFragment(map_node, areas_html, .map, .permissive);
        const result = try z.outerHTML(allocator, z.nodeToElement(body).?);
        defer allocator.free(result);
        
        std.debug.print("Map result: {s}\n", .{result});
        std.debug.print("Has shape=\"rect\": {}\n", .{std.mem.indexOf(u8, result, "shape=\"rect\"") != null});
        std.debug.print("Has coords=\"0,0,100,100\": {}\n", .{std.mem.indexOf(u8, result, "coords=\"0,0,100,100\"") != null});
    }
}