//! Z-HTML: Zig HTML parsing and manipulation library

// Re-export all modules
pub const lexbor = @import("lexbor.zig");
pub const chunks = @import("chunks.zig");
pub const css = @import("css_selectors.zig");
pub const Err = @import("errors.zig").LexborError;

// Re-export commonly used types and functions
pub const HtmlDocument = lexbor.HtmlDocument;
pub const DomNode = lexbor.DomNode;
pub const DomElement = lexbor.DomElement;

// CSS selectors
pub const CssSelectorEngine = css.CssSelectorEngine;

// Chunk parsing
pub const ChunkParser = chunks.ChunkParser;

pub const createDocument = lexbor.createDocument;
pub const destroyDocument = lexbor.destroyDocument;
pub const parseHtml = lexbor.parseHtml;
pub const parseFragmentAsDocument = lexbor.parseFragmentAsDocument;
pub const parseDocument = lexbor.parseLxbDocument;

// DOM access and navigation
pub const getBodyElement = lexbor.getBodyElement;
pub const getDocumentNode = lexbor.getDocumentNode;
pub const elementToNode = lexbor.elementToNode;
pub const nodeToElement = lexbor.nodeToElement;
pub const objectToNode = lexbor.objectToNode;
pub const getFirstChild = lexbor.getFirstChild;
pub const getNextSibling = lexbor.getNextSibling;
pub const getNodeName = lexbor.getNodeName;
pub const getElementChildren = lexbor.getElementChildren;

// DOM manipulation
pub const removeWhitespaceOnlyTextNodes = lexbor.removeWhitespaceOnlyTextNodes;
pub const destroyNode = lexbor.destroyNode;
pub const isNodeEmpty = lexbor.isNodeEmpty;

// Serialization
pub const serializeTree = lexbor.serializeTree;
pub const serializeNode = lexbor.serializeNode;
pub const serializeElement = lexbor.serializeElement;

// Text content
pub const getNodeTextContent = lexbor.getNodeTextContent;
pub const isWhitepaceOnlyText = lexbor.isWhitepaceOnlyText;

// Node type detection
pub const NodeType = lexbor.NodeType;
pub const getNodeType = lexbor.getNodeType;
pub const isElementNode = lexbor.isElementNode;
pub const isTextNode = lexbor.isTextNode;
pub const isCommentNode = lexbor.isCommentNode;

// CSS selectors - unified top-level access
pub const findElements = css.findElements;

// Utility functions
pub const printDocumentStructure = lexbor.printDocumentStructure;
pub const walkTree = lexbor.walkTree;

//-------------------------------------------------------------------------------------
// HIGH-LEVEL CONVENIENCE FUNCTIONS
//-------------------------------------------------------------------------------------
/// Parse HTML and find elements by CSS selector in one call
// pub fn parseAndFind(allocator: std.mem.Allocator, html: []const u8, selector: []const u8) ![]*DomElement {
//     const doc = parseFragmentAsDocument(html) catch |err| {
//         return err;
//     };
//     defer destroyDocument(doc);
//     const elements = findElements(allocator, doc, selector) catch |err| {
//         destroyDocument(doc);
//         return err;
//     };
//     return elements;
// }
pub fn parseAndFind(allocator: std.mem.Allocator, html: []const u8, selector: []const u8) ![]*DomElement {
    const doc = try parseFragmentAsDocument(html);
    defer destroyDocument(doc);

    return try findElements(allocator, doc, selector);
}
/// Parse HTML and get all text content
pub fn parseAndGetText(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    const doc = try parseFragmentAsDocument(html);
    defer destroyDocument(doc);

    const body = getBodyElement(doc) orelse return try allocator.alloc(u8, 0);
    const body_node = elementToNode(body);

    return try getNodeTextContent(allocator, body_node);
}

/// Parse HTML, clean whitespace, and serialize
pub fn parseCleanAndSerialize(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    const doc = try parseFragmentAsDocument(html);
    defer destroyDocument(doc);

    const body = getBodyElement(doc) orelse return try allocator.alloc(u8, 0);
    const body_node = elementToNode(body);

    try removeWhitespaceOnlyTextNodes(allocator, body_node);

    return try serializeTree(allocator, body_node);
}

// ----------------------------------------------------------------------------
// includes all tests from imported modules
// ----------------------------------------------------------------------------
test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
