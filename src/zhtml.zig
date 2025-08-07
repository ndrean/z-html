//! Z-HTML: Zig wrapper of the C library  lexbor, HTML parsing and manipulation library

// Re-export all modules
const lxb = @import("lexbor.zig");
const chunks = @import("chunks.zig");
const css = @import("css_selectors.zig");
const attributes = @import("attributes.zig");
const serialize = @import("serialize.zig");
const Tag = @import("tags.zig");
const Type = @import("node_types.zig");
pub const Err = @import("errors.zig").LexborError;

// Re-export commonly used types and functions
pub const HtmlDocument = lxb.HtmlDocument;
pub const DomNode = lxb.DomNode;
pub const DomElement = lxb.DomElement;
pub const DomAttr = attributes.DomAttr;

// CSS selectors
pub const CssSelectorEngine = css.CssSelectorEngine;

// Chunk parsing
pub const ChunkParser = chunks.ChunkParser;

// Tags
pub const HtmlTag = Tag.HtmlTag;
pub const ElementTag = lxb.ElementTag;

pub const createDocument = lxb.createDocument;
pub const destroyDocument = lxb.destroyDocument;
pub const parseHtml = lxb.parseHtml;
pub const parseFragmentAsDocument = lxb.parseFragmentAsDocument;
pub const parseDocHtml = lxb.parseDocHtml;
pub const createElement = lxb.createElement;

// DOM access and navigation
pub const getBodyElement = lxb.getBodyElement;
pub const getDocumentNode = lxb.getDocumentNode;
pub const elementToNode = lxb.elementToNode;
pub const nodeToElement = lxb.nodeToElement;
pub const objectToNode = lxb.objectToNode;
pub const getNodeFirstChildNode = lxb.getNodeFirstChildNode;
pub const getNodeNextSiblingNode = lxb.getNodeNextSiblingNode;
pub const getNodeName = lxb.getNodeName;
pub const getNodeChildrenElements = lxb.getNodeChildrenElements;

// DOM manipulation
pub const removeWhitespaceOnlyTextNodes = lxb.removeWhitespaceOnlyTextNodes;
pub const destroyNode = lxb.destroyNode;
pub const isNodeEmpty = lxb.isNodeEmpty;

// Serialization
pub const serializeTree = serialize.serializeTree;
pub const serializeNode = serialize.serializeNode;
pub const serializeElement = serialize.serializeElement;

// InnerHTML manipulation
pub const setElementInnerHTML = serialize.setElementInnerHTML;
pub const getElementHTMLAsString = serialize.serializeElement;

// Text content
pub const getNodeTextContentOpts = lxb.getNodeTextContentOpts;
// pub const getTextContentEscaped = lxb.getTextContentEscaped;
pub const isWhitepaceOnlyText = lxb.isWhitepaceOnlyText;

// NodeTypes
pub const NodeType = Type.NodeType;
pub const getNodeType = Type.getNodeType;
pub const getNodeTypeName = Type.getNodeTypeName;

pub const isElementNode = Type.isElementNode;
pub const isTextNode = Type.isTextNode;
pub const isDocumentNode = Type.isDocumentNode;
pub const isCommentNode = Type.isCommentNode;

// CSS selectors - unified top-level access
pub const findElements = css.findElements;

// Attributes
pub const getNamedAttributeFromElement = attributes.getNamedAttributeFromElement;

pub const elementHasNamedAttribute = attributes.elementHasNamedAttribute;

pub const setNamedAttributeValueToElement =
    attributes.setNamedAttributeValueToElement;

pub const getNamedAttributeValueFromElement =
    attributes.getNamedAttributeValueFromElement;

pub const getAttributeName =
    attributes.getAttributeName;

pub const getAttributeValue =
    attributes.getAttributeValue;

pub const removeNamedAttributeFromElement =
    attributes.removeNamedAttributeFromElement;

pub const getElementFirstAttribute =
    attributes.getElementFirstAttribute;

pub const getElementNextAttribute =
    attributes.getElementNextAttribute;

pub const getElementClass =
    attributes.getElementClass;

pub const getElementId =
    attributes.getElementId;

// Utility functions
pub const printDocumentStructure =
    lxb.printDocumentStructure;
pub const walkTree =
    lxb.walkTree;

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
pub fn parseAndFind(
    allocator: std.mem.Allocator,
    html: []const u8,
    selector: []const u8,
) ![]*DomElement {
    const doc = try parseFragmentAsDocument(html);
    defer destroyDocument(doc);

    return try findElements(allocator, doc, selector);
}
/// Parse HTML and get all text content
pub fn parseAndGetText(
    allocator: std.mem.Allocator,
    html: []const u8,
) ![]u8 {
    const doc = try parseFragmentAsDocument(html);
    defer destroyDocument(doc);

    const body = getBodyElement(doc) orelse return Err.NoBodyElement;
    const body_node = elementToNode(body);

    return try getNodeTextContentOpts(allocator, body_node, .{});
}

/// Parse HTML, clean whitespace, and serialize
pub fn parseCleanAndSerialize(
    allocator: std.mem.Allocator,
    html: []const u8,
) ![]u8 {
    const doc = try parseFragmentAsDocument(html);
    defer destroyDocument(doc);

    const body = getBodyElement(doc) orelse return Err.NoBodyElement;
    const body_node = elementToNode(body);

    try removeWhitespaceOnlyTextNodes(
        allocator,
        body_node,
        .{},
    );

    return try serializeTree(allocator, body_node);
}

// ----------------------------------------------------------------------------
// includes all tests from imported modules
// ----------------------------------------------------------------------------
test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
