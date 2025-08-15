//! Chunks processor

const std = @import("std");
const z = @import("zhtml.zig");

pub const HtmlParser = opaque {};

const Err = @import("errors.zig").LexborError;
const testing = std.testing;
const print = std.debug.print;

extern "c" fn lxb_html_parser_create() *z.HtmlParser;
extern "c" fn lxb_html_parser_init(*z.HtmlParser) usize;
extern "c" fn lxb_html_parser_destroy(parser: *HtmlParser) void;
extern "c" fn lxb_html_document_parse_chunk_begin(document: *z.HtmlDocument) usize;
extern "c" fn lxb_html_document_parse_chunk_end(document: *z.HtmlDocument) usize;
extern "c" fn lxb_html_document_parse_chunk(document: *z.HtmlDocument, chunk: [*:0]const u8, len: usize) usize;

/// [chunks] Chunk engine.
///
/// Exposes:
/// - `init`: create a new document
/// - `deinit`: destroy the document and parser
/// - `beginParsing`: start the parsing process
/// - `processChunk`: process a chunk of HTML
/// - `endParsing`: end the parsing process
/// - `getDocument`: get the underlying HTML document
pub const ChunkParser = struct {
    doc: *z.HtmlDocument,
    parser: *z.HtmlParser,
    allocator: std.mem.Allocator,
    parsing_active: bool = false,

    pub fn init(allocator: std.mem.Allocator) !ChunkParser {
        const doc = z.createDocument() catch return Err.DocCreateFailed;
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
        z.destroyDocument(self.doc);
    }

    pub fn beginParsing(self: *ChunkParser) !void {
        if (self.parsing_active) {
            return Err.ChunkBeginFailed;
        }

        if (lxb_html_document_parse_chunk_begin(self.doc) != 0) {
            return Err.ChunkBeginFailed;
        }
        self.parsing_active = true;
        if (lxb_html_parser_init(self.parser) != z.LXB_STATUS_OK) {
            return Err.ParserInitFailed;
        }
        self.parsing_active = true;
    }

    pub fn processChunk(self: *ChunkParser, html_chunk: []const u8) !void {
        if (!self.parsing_active) {
            return Err.ChunkProcessFailed;
        }

        const html_ptr = try self.allocator.dupeZ(u8, html_chunk);
        defer self.allocator.free(html_ptr);

        if (lxb_html_document_parse_chunk(
            self.doc,
            html_ptr,
            html_chunk.len,
        ) != 0) {
            return Err.ChunkProcessFailed;
        }
    }

    pub fn endParsing(self: *ChunkParser) !void {
        if (!self.parsing_active) {
            return Err.ChunkEndFailed;
        }

        if (lxb_html_document_parse_chunk_end(self.doc) != 0) {
            return Err.ChunkEndFailed;
        }
        self.parsing_active = false;
    }

    pub fn getDocument(self: *ChunkParser) *z.HtmlDocument {
        return self.doc;
    }

    // pub fn getHtmlDocument(self: *ChunkParser) z.HtmlDocument {
    //     return .{ .doc = self.doc };
    // }
};

test "chunks1" {
    const allocator = testing.allocator;
    var chunk_parser = try ChunkParser.init(allocator);
    defer chunk_parser.deinit();

    try chunk_parser.beginParsing();

    try chunk_parser.processChunk("<html><head><title");
    try chunk_parser.processChunk(">My Page</");
    try chunk_parser.processChunk("title></head>");
    try chunk_parser.processChunk("<body><h1>Hello</h1>");
    try chunk_parser.processChunk("<p>World!<");
    try chunk_parser.processChunk("/p></body></html>");

    try chunk_parser.endParsing();

    const doc = chunk_parser.getDocument();
    const body = try z.bodyElement(doc);
    const children = try z.getChildren(
        allocator,
        body,
    );
    defer allocator.free(children);

    try testing.expect(children.len > 0);
    try testing.expectEqualStrings(
        z.tagName(children[0]),
        "H1",
    );
    try testing.expectEqualStrings(
        z.tagName(children[1]),
        "P",
    );

    const html = try z.serializeToString(
        allocator,
        z.elementToNode(body),
    );
    defer allocator.free(html);

    try testing.expectEqualStrings(
        html,
        "<body><h1>Hello</h1><p>World!</p></body>",
    );

    // z.printDocumentStructure(doc);
}

test "chunk parsing comprehensive" {
    const allocator = testing.allocator;

    var chunk_parser = try ChunkParser.init(allocator);
    defer chunk_parser.deinit();

    try chunk_parser.beginParsing();

    // Parse HTML in chunks (simulating streaming)
    const chunks = [_][]const u8{
        "<html><head><title",
        ">My Page<",
        "/title></head><body>",
        "<h1>Hello",
        "</h1><p>World!</p>",
        "<span>Nested</span></",
        "div></body></html>",
    };

    for (chunks) |chunk| {
        try chunk_parser.processChunk(chunk);
    }

    try chunk_parser.endParsing();

    const doc = chunk_parser.getDocument();
    const body = try z.bodyElement(doc);

    const children = try z.getChildren(
        allocator,
        body,
    );
    defer allocator.free(children);

    try testing.expect(children.len == 3); // h1, p, div

    // Check element names
    try testing.expectEqualStrings(
        z.tagName(children[0]),
        "H1",
    );
    try testing.expectEqualStrings(
        z.tagName(children[1]),
        "P",
    );

    try testing.expectEqualStrings(
        z.tagName(children[2]),
        "SPAN",
    );

    // Test serialization
    const html = try z.serializeToString(
        allocator,
        z.elementToNode(body),
    );
    defer allocator.free(html);

    try testing.expectEqualStrings(
        html,
        "<body><h1>Hello</h1><p>World!</p><span>Nested</span></body>",
    );

    // Should contain all elements
    try testing.expect(
        std.mem.indexOf(u8, html, "<h1>Hello</h1>") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, html, "<p>World!</p>") != null,
    );
    try testing.expect(
        std.mem.indexOf(u8, html, "<span>Nested</span>") != null,
    );
}

test "chunk parsing error handling" {
    const allocator = testing.allocator;

    var chunk_parser = try ChunkParser.init(allocator);
    defer chunk_parser.deinit();

    // Test processing without beginning
    const result = chunk_parser.processChunk("<div>test</div>");
    try testing.expectError(Err.ChunkProcessFailed, result);

    // Test double begin
    try chunk_parser.beginParsing();
    const result2 = chunk_parser.beginParsing();
    try testing.expectError(Err.ChunkBeginFailed, result2);

    // Clean up
    try chunk_parser.endParsing();
}
