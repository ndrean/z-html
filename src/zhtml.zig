//! Z-HTML: Zig wrapper of the C library lexbor, HTML parsing and manipulation

// Re-export all modules
const lxb = @import("modules/core.zig");
const chunks = @import("modules/chunks.zig");
const fragments = @import("modules/fragments.zig");
const css = @import("modules/css_selectors.zig");
const attrs = @import("modules/attributes.zig");
const serialize = @import("modules/serializer.zig");
const collection = @import("modules/collection.zig");
const tag = @import("modules/html_tags.zig");
const Type = @import("modules/node_types.zig");
const tree = @import("modules/dom_tree.zig");
const traverse = @import("traverse.zig");
const cleaner = @import("modules/cleaner.zig");
const smart_text = @import("modules/smart_text.zig");

// Re-export commonly used types
pub const Err = @import("errors.zig").LexborError;

pub const LXB_STATUS_OK: usize = 0;
pub var default_collection_capacity: u8 = 10;
// pub const lxb_char_t = u8;
// pub const lxb_status_t = usize;

pub const TextOptions = struct {
    escape: bool = false,
    remove_comments: bool = false,
    remove_empty_elements: bool = false,
    keep_new_lines: bool = false,
    allow_html: bool = true, // Security: explicitly allow HTML parsing
};

// CSS selectors
pub const CssSelectorEngine = css.CssSelectorEngine;
pub const CssParser = opaque {};
pub const CssSelectors = opaque {};
pub const CssSelectorList = opaque {};
pub const CssSelectorSpecificity = opaque {};

// Chunk parsing
pub const ChunkParser = chunks.ChunkParser;
pub const HtmlParser = chunks.HtmlParser;

// Fragment parsing
pub const FragmentContext = fragments.FragmentContext;
pub const FragmentResult = fragments.FragmentResult;
pub const parseFragment = fragments.parseFragment;
pub const parseFragmentSimple = fragments.parseFragmentSimple;
pub const parseFragmentInto = fragments.parseFragmentInto;

//=====================================
// Core
//=====================================
pub const HtmlDocument = opaque {};
pub const DomNode = opaque {};
pub const DomElement = opaque {};
pub const Comment: type = opaque {};

pub const createDocument = lxb.createDocument;
pub const destroyDocument = lxb.destroyDocument;
pub const createElement = lxb.createElement;
pub const createTextNode = lxb.createTextNode;
pub const createComment = lxb.createComment;
pub const createDocumentFragment = lxb.createDocumentFragment;

//=====================================
pub const parseFromString = lxb.parseFromString;
//=====================================

//=====================================
// DOM destruction
//=====================================
pub const removeNode = lxb.removeNode;
pub const destroyComment = lxb.destroyComment;
pub const destroyNode = lxb.destroyNode;
pub const destroyElement = lxb.destroyElement;

// DOM access
pub const documentRoot = lxb.documentRoot;
pub const ownerDocument = lxb.ownerDocument;
pub const bodyElement = lxb.bodyElement;
pub const bodyNode = lxb.bodyNode;

//=====================================
// Node / Element / Comment conversions
//=====================================
pub const elementToNode = lxb.elementToNode;
pub const nodeToElement = lxb.nodeToElement;
pub const commentToNode = lxb.commentToNode;
pub const nodeToComment = lxb.nodeToComment;

// Node and Element name functions (both safe and unsafe versions)
pub const nodeName = lxb.nodeName; // Safe version
pub const nodeNameBorrow = lxb.nodeNameBorrow;
pub const tagName = lxb.tagName;
pub const tagNameBorrow = lxb.tagNameBorrow; // Safe
pub const qualifiedName = lxb.qualifiedName;
pub const qualifiedNameBorrow = lxb.qualifiedNameBorrow; // Zero-copy version

//===================
// NodeTypes
//===================
pub const NodeType = Type.NodeType;
pub const nodeType = Type.nodeType;
pub const nodeTypeName = Type.nodeTypeName;

pub const isTypeElement = Type.isTypeElement;
pub const isTypeComment = Type.isTypeComment;
pub const isTypeText = Type.isTypeText;
pub const isTypeDocument = Type.isTypeDocument;
pub const isTypeFragment = Type.isTypeFragment;

//=====================================
// HTML tags
//=====================================
pub const HtmlTag = tag.HtmlTag;
pub const parseTag = tag.parseTag;
pub const parseTagInsensitive = tag.parseTagInsensitive;
pub const fromQualifiedName = tag.fromQualifiedName; // NEW: Fast string→enum conversion
pub const isVoidElementFast = tag.isVoidElementFast; // RECOMMENDED: Fast enum-based
pub const isNoEscapeElementFast = tag.isNoEscapeElementFast; // RECOMMENDED: Fast enum-based
pub const isNoEscapeElementExtended = tag.isNoEscapeElementExtended; // For custom elements

//=====================================
// DOM navigation
//=====================================
pub const firstChild = lxb.firstChild;
pub const nextSibling = lxb.nextSibling;
pub const previousSibling = lxb.previousSibling;
pub const parentNode = lxb.parentNode;
pub const firstElementChild = lxb.firstElementChild;
pub const nextElementSibling = lxb.nextElementSibling;
pub const parentElement = lxb.parentElement;

// pub const insertNodeBefore = lxb.insertNodeBefore;
// pub const insertNodeAfter = lxb.insertNodeAfter;
pub const appendChild = lxb.appendChild;
pub const appendChildren = lxb.appendChildren;
pub const appendFragment = lxb.appendFragment;

pub const getChildNodes = lxb.getChildNodes;
pub const getChildren = lxb.getChildren;

//=====================================
// Template element support
//=====================================
pub const HtmlTemplate = opaque {};
pub const isTemplateElement = lxb.isTemplateElement;
pub const templateInterface = lxb.templateInterface;
pub const templateAwareFirstChild = lxb.templateAwareFirstChild;

// Experimental DOM Traversal utilities
pub const forEachChildNode = traverse.forEachChildNode;
pub const forEachChildElement = traverse.forEachChildElement;
pub const collectChildNodes = traverse.collectChildNodes;
pub const collectChildElements = traverse.collectChildElements;
pub const NodeCallback = traverse.NodeCallback;
pub const ElementCallback = traverse.ElementCallback;

//=====================================
// DOM Matcher utilities
pub const matchesTagName = lxb.matchesTagName;
pub const matchesAttribute = attrs.matchesAttribute;
pub const hasClass = attrs.hasClass;

//=====================================
// DOM Tree representation utilities (aliased to avoid conflicts)
//=====================================
pub const DomTreeNode = tree.HtmlNode;
// JsonTreeNode follows W3C DOM specification with nodeType, tagName, attributes, children
pub const DomTreeArray = tree.HtmlTree;
pub const JsonTreeNode = tree.JsonNode;
pub const JsonTreeArray = tree.JsonTree;
pub const JsonAttribute = tree.JsonAttribute;

pub const domNodeToTree = tree.domNodeToTree;
pub const documentToTupleTree = tree.documentToTupleTree;
// pub const fullDocumentToTupleTree = tree.fullDocumentToTupleTree;
pub const domNodeToJson = tree.domNodeToJson;
pub const documentToJsonTree = tree.documentToJsonTree;
pub const fullDocumentToJsonTree = tree.fullDocumentToJsonTree;
pub const freeHtmlTree = tree.freeHtmlTree;
pub const freeJsonTree = tree.freeJsonTree;
pub const printNode = tree.printNode;

//=====================================
// JSON serialization and parsing
pub const jsonNodeToString = tree.jsonNodeToString;
pub const jsonTreeToString = tree.jsonTreeToString;
pub const parseJsonString = tree.parseJsonString;
pub const parseJsonTreeString = tree.parseJsonTreeString;

pub const nodeToHtml = tree.nodeToHtml;
pub const treeToHtml = tree.treeToHtml;
pub const roundTripConversion = tree.roundTripConversion;
pub const freeDomTreeArray = tree.freeHtmlTree;
pub const freeDomTreeNode = tree.freeHtmlNode;
pub const freeJsonTreeArray = tree.freeJsonTree;
pub const freeJsonTreeNode = tree.freeJsonNode;

pub const printDocumentStructure = tree.printDocumentStructure;

//=====================================
// Collection management
//=====================================
pub const DomCollection = opaque {};
pub const createCollection = collection.createCollection;
pub const createDefaultCollection = collection.createDefaultCollection;
pub const createSingleElementCollection = collection.createSingleElementCollection;
pub const destroyCollection = collection.destroyCollection;
pub const clearCollection = collection.clearCollection;
pub const collectionLength = collection.collectionLength;
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

// Reflexion
pub const isNodeEmpty = lxb.isNodeEmpty;
pub const isSelfClosingNode = lxb.isSelfClosingNode;
pub const isWhitespaceOnlyText = lxb.isWhitespaceOnlyText;
pub const isWhitespaceOnlyNode = lxb.isWhitespaceOnlyNode;
pub const isWhitespaceOnlyElement = lxb.isWhitespaceOnlyElement;

//=====================================
// Serialization
//=====================================
pub const serializeToString = serialize.serializeToString;
pub const serializeNode = serialize.serializeNode;
pub const serializeElement = serialize.serializeElement;

//=====================================
// Inner / outer HTML manipulation
//=====================================
pub const innerHTML = serialize.innerHTML;
pub const setInnerHTML = serialize.setInnerHTML; // Security-first API with TextOptions
// pub const setInnerHTMLUnsafe = serialize.setInnerHTMLUnsafe; // Direct lexbor access
pub const outerHTML = serialize.outerHTML;

pub const cleanDomTree = cleaner.cleanDomTree;
pub const normalizeWhitespace = cleaner.normalizeWhitespace;

//=====================================
// Text content
//=====================================
pub const getCommentTextContent = lxb.getCommentTextContent;
pub const getTextContent = lxb.getTextContent; // DEPRECATED: Use getTextContentOptional or getTextContentOrEmpty
pub const getTextContentOptional = lxb.getTextContentOptional; // RECOMMENDED: Correct API
pub const getTextContentOrEmpty = lxb.getTextContentOrEmpty; // ALTERNATIVE: JavaScript-like behavior
pub const getTextContentBorrow = lxb.getTextContentBorrow; // FASTEST: Zero-copy version
pub const setOrReplaceText = lxb.setOrReplaceText;
pub const setTextContent = lxb.setTextContent;
pub const escapeHtml = lxb.escapeHtml;

//=========================================
// CSS selectors - unified top-level access
//=========================================
pub const querySelectorAll = css.querySelectorAll;
pub const querySelector = css.querySelector;

//=========================================
// Attributes
//=========================================
pub const DomAttr = attrs.DomAttr;
pub const AttributePair = attrs.AttributePair;
pub const hasAttributes = attrs.hasAttributes;

pub const elementGetNamedAttributeValue = attrs.elementGetNamedAttributeValue;

pub const getAttribute = attrs.getAttribute;
pub const setAttribute = attrs.elementSetAttributes;
pub const hasAttribute = attrs.hasAttribute;
pub const removeAttribute = attrs.removeAttribute;
pub const getElementId = attrs.getElementId;
pub const compareStrings = attrs.compareStrings;
pub const getAttributes = attrs.getAttributes;

//=========================================
// Element search functions
//=========================================
pub const getElementById = collection.getElementById;
pub const getElementByIdFast = attrs.getElementByIdFast; // Optimized version using DOM walker
pub const getElementByClassFast = attrs.getElementByClassFast; // Optimized class search using DOM walker
pub const getElementByAttributeFast = attrs.getElementByAttributeFast; // Optimized attribute search using DOM walker
pub const getElementByDataAttributeFast = attrs.getElementByDataAttributeFast; // Optimized data-* attribute search
pub const getElementsByAttributePair = collection.getElementsByAttributePair;
pub const getElementsByClassName = collection.getElementsByClassName;
pub const getElementsByAttributeName = collection.getElementsByAttributeName;
pub const getElementsByTagName = collection.getElementsByTagName;
pub const getElementsByName = collection.getElementsByName;

//=========================================
// Class handling - unified function and convenience wrappers
//=========================================
pub const ClassListType = attrs.ClassListType;
pub const ClassListResult = attrs.ClassListResult;
pub const classList = attrs.classList;
pub const getClasses = attrs.getClasses;
pub const getClassString = attrs.getClassString;

//=========================================
// Attribute struct reflexion
//=========================================
pub const getAttributeName =
    attrs.getAttributeName;

pub const getAttributeValue =
    attrs.getAttributeValue;

pub const getElementFirstAttribute =
    attrs.getElementFirstAttribute;

pub const getElementNextAttribute =
    attrs.getElementNextAttribute;

//=========================================
// UTILITY FUNCTIONS
//=========================================

/// [zhtml] Debug: Get only element children (filter out text/comment nodes)
pub fn getElementChildrenWithTypes(allocator: std.mem.Allocator, parent_node: *DomNode) ![]*DomElement {
    var elements = std.ArrayList(*DomElement).init(allocator);
    defer elements.deinit();

    var child = firstChild(parent_node);
    while (child != null) {
        if (isTypeElement(child.?)) {
            if (nodeToElement(child.?)) |element| {
                try elements.append(element);
            }
        }
        child = nextSibling(child.?);
    }

    return elements.toOwnedSlice();
}

// ----------------------------------------------------------------------------
// Smart Text Processing (LazyHTML-level improvements)
// ----------------------------------------------------------------------------

pub const leadingWhitespaceSize = smart_text.leadingWhitespaceSize;
pub const isNoEscapeTextNode = smart_text.isNoEscapeTextNode;
pub const escapeHtmlSmart = smart_text.escapeHtmlSmart;
pub const processTextContentSmart = smart_text.processTextContentSmart;

// ***************************************************************************
// Test all imported modules
// ****************************************************************************

const std = @import("std");
const print = std.debug.print;
const testing = std.testing;

test {
    std.testing.refAllDecls(@This());
}

test "new lexbor functions - getElementQualifiedName and compareStrings" {
    // Create a simple HTML document for testing
    const html = "<html><body><div id='test'>Hello</div></body></html>";
    const document = try parseFromString(html);
    defer destroyDocument(document);

    // Get the div element
    const body = try bodyElement(document);
    const body_node = elementToNode(body);
    const div_node = firstChild(body_node).?;
    const div_element = nodeToElement(div_node).?;

    // Test getElementQualifiedName
    const qualified_name = try qualifiedName(testing.allocator, div_element);
    defer testing.allocator.free(qualified_name);
    try testing.expect(qualified_name.len > 0);
    // Should be "div"
    try testing.expectEqualStrings("div", qualified_name);

    // Test compareStrings
    const str1 = "hello";
    const str2 = "hello";
    const str3 = "world";

    // Test equal strings
    try testing.expect(compareStrings(str1, str2));

    // Test different strings
    try testing.expect(!compareStrings(str1, str3));
}
