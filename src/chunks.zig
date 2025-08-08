const std = @import("std");
const zhtml = @import("zhtml.zig");

pub const HtmlParser = opaque {};

const err = @import("errors.zig").LexborError;
const testing = std.testing;
const print = std.debug.print;

extern "c" fn lxb_html_parser_create() *zhtml.HtmlParser;
extern "c" fn lxb_html_parser_init(*zhtml.HtmlParser) usize;
extern "c" fn lxb_html_parser_destroy(parser: *HtmlParser) void;
extern "c" fn lxb_html_document_parse_chunk_begin(document: *zhtml.HtmlDocument) usize;
extern "c" fn lxb_html_document_parse_chunk_end(document: *zhtml.HtmlDocument) usize;
extern "c" fn lxb_html_document_parse_chunk(document: *zhtml.HtmlDocument, chunk: [*:0]const u8, len: usize) usize;

pub const ChunkParser = struct {
    doc: *zhtml.HtmlDocument,
    parser: *zhtml.HtmlParser,
    allocator: std.mem.Allocator,
    parsing_active: bool = false,

    pub fn init(allocator: std.mem.Allocator) !ChunkParser {
        const doc = zhtml.createDocument() catch return err.DocCreateFailed;
        return .{
            .doc = doc,
            .allocator = allocator,
            .parser = lxb_html_parser_create(),
        };
    }

    pub fn deinit(self: *ChunkParser) void {
        if (self.parsing_active) {
            _ = lxb_html_document_parse_chunk_end(self.doc);
            lxb_html_parser_destroy(self.parser);
        }
        zhtml.destroyDocument(self.doc);
    }

    pub fn beginParsing(self: *ChunkParser) !void {
        if (self.parsing_active) {
            return err.ChunkBeginFailed;
        }

        if (lxb_html_document_parse_chunk_begin(self.doc) != 0) {
            return err.ChunkBeginFailed;
        }
        self.parsing_active = true;
        if (lxb_html_parser_init(self.parser) != zhtml.LXB_STATUS_OK) {
            return err.ParserInitFailed;
        }
        self.parsing_active = true;
    }

    pub fn processChunk(self: *ChunkParser, html_chunk: []const u8) !void {
        // print("chunk: {s}\n", .{html_chunk});
        if (!self.parsing_active) {
            return err.ChunkProcessFailed;
        }

        const html_ptr = try self.allocator.dupeZ(u8, html_chunk);
        defer self.allocator.free(html_ptr);

        if (lxb_html_document_parse_chunk(self.doc, html_ptr, html_chunk.len) != 0) {
            return err.ChunkProcessFailed;
        }
    }

    pub fn endParsing(self: *ChunkParser) !void {
        if (!self.parsing_active) {
            return err.ChunkEndFailed;
        }

        if (lxb_html_document_parse_chunk_end(self.doc) != 0) {
            return err.ChunkEndFailed;
        }
        self.parsing_active = false;
    }

    pub fn getDocument(self: *ChunkParser) *zhtml.HtmlDocument {
        return self.doc;
    }

    pub fn getHtmlDocument(self: *ChunkParser) zhtml.HtmlDocument {
        return .{
            .doc = self.doc,
            // .allocator = self.allocator,
        };
    }
};

test "chunks1" {
    const allocator = testing.allocator;
    var chunk_parser = try ChunkParser.init(allocator);
    defer chunk_parser.deinit();
    try chunk_parser.beginParsing();
    try chunk_parser.processChunk("<html><head><title>");
    try chunk_parser.processChunk("My Page</");
    try chunk_parser.processChunk("title></head><body>");
    try chunk_parser.processChunk("<h1>Hello</h1>");
    try chunk_parser.processChunk("<p>World!</p>");
    try chunk_parser.processChunk("</body></html>");
    try chunk_parser.endParsing();

    const doc = chunk_parser.getDocument();
    const body = zhtml.getBodyElement(doc);
    const body_node = zhtml.elementToNode(body.?);
    const children = try zhtml.getNodeChildrenElements(
        allocator,
        body_node,
    );
    defer allocator.free(children);
    try testing.expect(children.len > 0);
    try testing.expectEqualStrings(
        zhtml.getElementName(children[0]),
        "H1",
    );
    try testing.expectEqualStrings(
        zhtml.getElementName(children[1]),
        "P",
    );

    const html = try zhtml.serializeTree(
        allocator,
        body_node,
    );
    defer allocator.free(html);
    try testing.expectEqualStrings(
        html,
        "<body><h1>Hello</h1><p>World!</p></body>",
    );

    // zhtml.printDocumentStructure(doc);
}

test "chunk parsing comprehensive" {
    const allocator = testing.allocator;

    var chunk_parser = try ChunkParser.init(allocator);
    defer chunk_parser.deinit();

    try chunk_parser.beginParsing();

    // Parse HTML in chunks (simulating streaming)
    const chunks = [_][]const u8{ "<html><head><title", ">My Page<", "/title></head><body>", "<h1>Hello", "</h1><p>World!</p>", "<span>Nested</span></", "div></body></html>" };

    for (chunks) |chunk| {
        try chunk_parser.processChunk(chunk);
    }

    try chunk_parser.endParsing();

    // Verify the parsed structure
    const doc = chunk_parser.getDocument();

    // zhtml.printDocumentStructure(doc);

    const body = zhtml.getBodyElement(doc).?;
    const body_node = zhtml.elementToNode(body);

    const children = try zhtml.getNodeChildrenElements(allocator, body_node);
    defer allocator.free(children);

    try testing.expect(children.len == 3); // h1, p, div

    // Check element names
    try testing.expectEqualStrings(zhtml.getElementName(children[0]), "H1");
    try testing.expectEqualStrings(zhtml.getElementName(children[1]), "P");

    try testing.expectEqualStrings(zhtml.getElementName(children[2]), "SPAN");

    // Test serialization
    const html = try zhtml.serializeTree(allocator, body_node);
    defer allocator.free(html);

    // print("Serialized: {s}\n", .{html});
    try testing.expectEqualStrings(
        html,
        "<body><h1>Hello</h1><p>World!</p><span>Nested</span></body>",
    );

    // Should contain all elements
    try testing.expect(std.mem.indexOf(u8, html, "<h1>Hello</h1>") != null);
    try testing.expect(std.mem.indexOf(u8, html, "<p>World!</p>") != null);
    try testing.expect(std.mem.indexOf(u8, html, "<span>Nested</span>") != null);
}

test "chunk parsing error handling" {
    const allocator = testing.allocator;

    var chunk_parser = try ChunkParser.init(allocator);
    defer chunk_parser.deinit();

    // Test processing without beginning
    const result = chunk_parser.processChunk("<div>test</div>");
    try testing.expectError(err.ChunkProcessFailed, result);

    // Test double begin
    try chunk_parser.beginParsing();
    const result2 = chunk_parser.beginParsing();
    try testing.expectError(err.ChunkBeginFailed, result2);

    // Clean up
    try chunk_parser.endParsing();
}
