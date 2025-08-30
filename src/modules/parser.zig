const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

const testing = std.testing;
// const print = std.debug.print;
const print = z.Writer.print;

const HtmlParser = opaque {};
const HtmlTree = opaque {};
const LXB_HTML_SERIALIZE_OPT_UNDEF: c_int = 0x00;

extern "c" fn lxb_html_parser_create() *HtmlParser;
extern "c" fn lxb_html_parser_destroy(parser: *HtmlParser) *HtmlParser;
extern "c" fn lxb_html_parser_clean(parser: *HtmlParser) void;
extern "c" fn lxb_html_parser_init(parser: *HtmlParser) usize;

extern "c" fn lxb_html_parse(
    parser: *HtmlParser,
    html: [*:0]const u8,
    size: usize,
) *z.HTMLDocument;

extern "c" fn lxb_html_document_parse(
    doc: *z.HTMLDocument,
    html: [*]const u8,
    size: usize,
) usize;

extern "c" fn lxb_html_parse_fragment(
    parser: *HtmlParser,
    element: *z.HTMLElement,
    html: []const u8,
    size: usize,
) *z.DomNode;

extern "c" fn lxb_html_parser_tree_node(parser: *HtmlParser) *HtmlTree;
extern "c" fn lxb_html_parser_tree_node_init(parser: *HtmlParser) *HtmlTree;

pub const Parser = struct {
    doc: *z.HTMLDocument,
    status: c_int,
    parser: *HtmlParser,

    /// Create a new parser instance.
    pub fn init() !Parser {
        const new_doc = z.createDocument() catch return Err.DocCreateFailed;
        return .{
            .doc = new_doc,
            .status = z._OK,
            .parser = lxb_html_parser_create(),
        };
    }

    /// Parse HTML string into document.
    pub fn parse(self: *Parser, data: [*:0]const u8) !*z.HTMLDocument {
        if (self.status == z._OK and lxb_html_parser_init(self.parser) != z._OK) {
            self.status = z._STOP;
        } else self.status = z._OK;
        const len = std.mem.len(data);
        return lxb_html_parse(self.parser, data, len);
    }

    /// Deinitialize parser and free resources.
    pub fn deinit(self: *Parser) void {
        _ = lxb_html_parser_destroy(self.parser);
        z.destroyDocument(self.doc);
    }
};

// [core] Parse HTML string into document and creates a new document.
/// Returns a new document.
///
/// Tihs creates a new document. Caller must free with `destroyDocument()`.
///
/// ## Example
/// ```
/// const doc = try parseFromString("<!DOCTYPE html><html><body></body></html>");
/// defer destroyDocument(doc);
/// ---
/// ```
pub fn parseFromString(html: []const u8) !*z.HTMLDocument {
    const doc = z.createDocument() catch {
        return Err.DocCreateFailed;
    };
    const status = lxb_html_document_parse(doc, html.ptr, html.len);
    if (status != z._OK) return Err.ParseFailed;
    return doc;
}
