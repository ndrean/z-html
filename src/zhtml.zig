//! Z-HTML: Zig wrapper of the C library  lexbor, HTML parsing and manipulation library

// Re-export all modules
const lxb = @import("lexbor.zig");
const chunks = @import("chunks.zig");
const css = @import("css_selectors.zig");
const attributes = @import("elements_attributes.zig");
const serialize = @import("serialize.zig");
const collection = @import("collection.zig");
const tag = @import("html_tags.zig");
const Type = @import("node_types.zig");

// Re-export commonly used types
pub const Err = @import("errors.zig").LexborError;
pub const HtmlDocument = lxb.HtmlDocument;
pub const DomNode = lxb.DomNode;
pub const DomElement = lxb.DomElement;
pub const DomCollection = lxb.DomCollection;
pub const DomAttr = attributes.DomAttr;
pub const HtmlTag = tag.HtmlTag;
pub const ElementTag = lxb.ElementTag;
pub const AttributePair = attributes.AttributePair;

pub const LXB_STATUS_OK: usize = 0;
// pub const lxb_char_t = u8;
// pub const lxb_status_t = usize;

// CSS selectors
pub const CssSelectorEngine = css.CssSelectorEngine;

// Chunk parsing
pub const ChunkParser = chunks.ChunkParser;
pub const HtmlParser = chunks.HtmlParser;

//----------------------------------------------------------------------------
// Core
pub const createDocument = lxb.createDocument;
pub const destroyDocument = lxb.destroyDocument;
pub const parseHtmlString = lxb.parseHtmlString;
pub const createElement = lxb.createElement;

// DOM access and navigation
pub const getDocumentBodyElement = lxb.getDocumentBodyElement;
pub const getDocumentBodyNode = lxb.getDocumentBodyNode;
pub const elementToNode = lxb.elementToNode;
pub const nodeToElement = lxb.nodeToElement;
pub const commentToNode = lxb.commentToNode;
pub const getNodeFirstChild = lxb.getNodeFirstChild;
pub const getNodeNextSibling = lxb.getNodeNextSibling;
pub const getNodeName = lxb.getNodeName;
pub const getElementName = lxb.getElementName;
pub const removeNode = lxb.removeNode;

pub const createComment = lxb.createComment;
pub const destroyComment = lxb.destroyComment;
pub const getCommentTextContent = lxb.getCommentTextContent;

// DOM Creation and manipulation
pub const createTextNode = lxb.createTextNode;
pub const createDocumentFragment = lxb.createDocumentFragment;
pub const insertNodeBefore = lxb.insertNodeBefore;
pub const insertNodeAfter = lxb.insertNodeAfter;
pub const appendChild = lxb.appendChild;
pub const appendChildren = lxb.appendChildren;
pub const appendFragment = lxb.appendFragment;

pub const getNodeChildrenElements = lxb.getNodeChildrenElements;

// Collection management
pub const createCollection = collection.createCollection;
pub const createDefaultCollection = collection.createDefaultCollection;
pub const createSingleElementCollection = collection.createSingleElementCollection;
pub const destroyCollection = collection.destroyCollection;
pub const clearCollection = collection.clearCollection;
pub const getCollectionLength = collection.getCollectionLength;
pub const getCollectionElementAt = collection.getCollectionElementAt;
pub const getFirstCollectionElement = collection.getCollectionFirstElement;
pub const getLastCollectionElement = collection.getCollectionLastElement;
pub const isCollectionEmpty = collection.isCollectionEmpty;
pub const appendElementToCollection = collection.appendElementToCollection;
pub const collectionIterator = collection.iterator;
pub const debugPrint = collection.debugPrint;
pub const collectionToSlice = collection.collectionToSlice;
pub const CollectionIterator = collection.CollectionIterator;

// Collection configuration
pub const setDefaultCapacity = collection.setDefaultCapacity;
pub const getDefaultCapacity = collection.getDefaultCapacity;
pub const resetDefaultCapacity = collection.resetDefaultCapacity;

// Element search functions

pub const getElementById = collection.getElementById;
pub const getElementsByAttributePair = collection.getElementsByAttributePair;
pub const getElementsByClassName = collection.getElementsByClassName;
pub const getElementsByAttributeName = collection.getElementsByAttributeName;
pub const getElementsByTagName = collection.getElementsByTagName;
pub const getElementsByName = collection.getElementsByName;

// DOM manipulation
pub const destroyNode = lxb.destroyNode;
pub const isNodeEmpty = lxb.isNodeEmpty;
pub const isSelfClosingNode = lxb.isSelfClosingNode;

// Serialization
pub const serializeTree = serialize.serializeTree;
pub const serializeNode = serialize.serializeNode;
pub const serializeElement = serialize.serializeElement;
pub const cleanDomTree = lxb.cleanDomTree;

// InnerHTML manipulation
pub const getElementInnerHTML = serialize.getElementInnerHTML;
pub const setElementInnerHTML = serialize.setElementInnerHTML;
pub const getElementHTMLAsString = serialize.serializeElement;

// Text content
pub const getNodeTextContentsOpts = lxb.getNodeTextContentsOpts;
pub const setOrReplaceNodeTextData = lxb.setOrReplaceNodeTextData;
pub const setNodeTextContent = lxb.setNodeTextContent;
// pub const getTextContentEscaped = lxb.getTextContentEscaped;

pub const isWhitepaceOnlyText = lxb.isWhitepaceOnlyText;
pub const isWhitespaceOnlyNode = lxb.isWhitespaceOnlyNode;
pub const isWhitespaceOnlyElement = lxb.isWhitespaceOnlyElement;

// NodeTypes
pub const NodeType = Type.NodeType;
pub const getNodeType = Type.getNodeType;
pub const getNodeTypeName = Type.getNodeTypeName;

pub const isNodeElementType = Type.isNodeElementType;
pub const isNodeTextType = Type.isNodeTextType;
pub const isNodeDocumentType = Type.isNodeDocumentType;
pub const isNodeCommentType = Type.isNodeCommentType;
pub const walkTreeWithTypes = Type.walkTreeWithTypes;

// CSS selectors - unified top-level access
pub const findElements = css.findElements;

// Attributes

pub const elementHasAnyAttribute = attributes.elementHasAnyAttribute;
pub const elementGetNamedAttribute = attributes.elementGetNamedAttribute;

pub const elementHasNamedAttribute = attributes.elementHasNamedAttribute;

pub const elementSetAttributes =
    attributes.elementSetAttributes;

pub const elementGetNamedAttributeValue =
    attributes.elementGetNamedAttributeValue;

pub const getAttributeName =
    attributes.getAttributeName;

pub const getAttributeValue =
    attributes.getAttributeValue;

pub const elementRemoveNamedAttribute =
    attributes.elementRemoveNamedAttribute;

pub const getElementFirstAttribute =
    attributes.getElementFirstAttribute;

pub const getElementNextAttribute =
    attributes.getElementNextAttribute;

pub const getElementClass =
    attributes.getElementClass;

pub const getElementId = attributes.getElementId;

pub const elementCollectAttributes = attributes.elementCollectAttributes;

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
// pub fn parseAndFind(
//     allocator: std.mem.Allocator,
//     html: []const u8,
//     selector: []const u8,
// ) ![]*DomElement {
//     const doc = try parseFragmentAsDocument(html);
//     defer destroyDocument(doc);

//     return try findElements(allocator, doc, selector);
// }
/// Parse HTML and get all text content
// pub fn parseAndGetText(
//     allocator: std.mem.Allocator,
//     html: []const u8,
// ) ![]u8 {
//     const doc = try parseFragmentAsDocument(html);
//     defer destroyDocument(doc);

//     const body = getBodyElement(doc) orelse return Err.NoBodyElement;
//     const body_node = elementToNode(body);

//     return try getNodeTextContentsOpts(allocator, body_node, .{});
// }

/// Parse HTML, clean whitespace, and serialize
// pub fn parseCleanAndSerialize(
//     allocator: std.mem.Allocator,
//     html: []const u8,
// ) ![]u8 {
//     const doc = try parseFragmentAsDocument(html);
//     defer destroyDocument(doc);

//     const body = getBodyElement(doc) orelse return Err.NoBodyElement;
//     const body_node = elementToNode(body);

//     try removeWhitespaceOnlyTextNodes(
//         allocator,
//         body_node,
//         .{},
//     );

//     return try serializeTree(allocator, body_node);
// }

//=============================================================================
// UTILITY FUNCTIONS
//=============================================================================

/// [lexbor] Debug: Walk and print DOM tree
pub fn walkTree(node: *DomNode, depth: u32) void {
    var child = getNodeFirstChild(node);
    while (child != null) {
        const name = getNodeName(child.?);
        const indent = switch (@min(depth, 10)) {
            0 => "",
            1 => "  ",
            2 => "    ",
            3 => "      ",
            4 => "        ",
            5 => "          ",
            else => "            ", // For deeper levels
        };
        print("{s}{s}\n", .{ indent, name });

        walkTree(child.?, depth + 1);
        child = getNodeNextSibling(child.?);
    }
}

/// [lexbor] Debug: print document structure (for debugging)
pub fn printDocumentStructure(doc: *HtmlDocument) !void {
    print("\n--- DOCUMENT STRUCTURE ----\n", .{});
    const root = try getDocumentBodyNode(doc);
    walkTree(root, 0);
}

/// [zhtml] Debug: Get only element children (filter out text/comment nodes)
pub fn getElementChildrenWithTypes(
    allocator: std.mem.Allocator,
    parent_node: *DomNode,
) ![]*DomElement {
    var elements = std.ArrayList(*DomElement).init(allocator);
    defer elements.deinit();

    var child = getNodeFirstChild(parent_node);
    while (child != null) {
        if (isNodeElementType(child.?)) {
            if (nodeToElement(child.?)) |element| {
                try elements.append(element);
            }
        }
        child = getNodeNextSibling(child.?);
    }

    return elements.toOwnedSlice();
}

// ----------------------------------------------------------------------------
// includes all tests from imported modules
// ----------------------------------------------------------------------------
test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
const writer = std.io.getStdOut().writer();

const print = std.debug.print;
const testing = std.testing;
