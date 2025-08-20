//! Z-HTML: Zig wrapper of the C library lexbor, HTML parsing and manipulation

const lxb = @import("modules/core.zig");
const css = @import("modules/css_selectors.zig");
const chunks = @import("modules/chunks.zig");
const fragments = @import("modules/fragments.zig");
const tag = @import("modules/html_tags.zig");
const Type = @import("modules/node_types.zig");
const traverse = @import("modules/traverse.zig");
const tree = @import("modules/dom_tree.zig");
const collection = @import("modules/collection.zig");
const serialize = @import("modules/serializer.zig");
const cleaner = @import("modules/cleaner.zig");
const attrs = @import("modules/attributes.zig");
const smart_text = @import("modules/smart_text.zig");
const walker = @import("modules/search_attributes.zig");
const classes = @import("modules/class_list.zig");
const template = @import("modules/template.zig");

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
pub const Template = opaque {};

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
pub const nodeName_zc = lxb.nodeName_zc;
pub const tagName = lxb.tagName;
pub const tagName_zc = lxb.tagName_zc; // Zero-copy version
pub const qualifiedName = lxb.qualifiedName;
pub const qualifiedName_zc = lxb.qualifiedName_zc; // Zero-copy version

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
pub const fromQualifiedName = tag.fromQualifiedName;
pub const matchesTagName = tag.matchesTagName;
pub const tagFromElement = tag.tagFromElement;
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

pub const insertBefore = lxb.insertBefore;
pub const insertAfter = lxb.insertAfter;
pub const InsertPosition = lxb.InsertPosition;
pub const insertAdjacentElement = lxb.insertAdjacentElement;
pub const insertAdjacentHTML = lxb.insertAdjacentHTML;
pub const appendChild = lxb.appendChild;
pub const appendChildren = lxb.appendChildren;
pub const appendFragment = lxb.appendFragment;

pub const getChildNodes = lxb.getChildNodes;
pub const getChildren = lxb.getChildren;

//=====================================
// Template element support
//=====================================
pub const HtmlTemplate = opaque {};
// Template
pub const createTemplate = template.createTemplate;
pub const destroyTemplate = template.destroyTemplate;

// ===========================================================================
// DOM Traversal utilities
pub const collectChildItems = traverse.collectChildItems;
pub const collectChildElements = traverse.collectChildElements;
pub const elementMatchCollector = traverse.elementMatchCollector;
pub const nodeMatchCollector = traverse.nodeMatchCollector;

//=====================================
// DOM Tree representation utilities (aliased to avoid conflicts)
//=====================================
pub const DomTreeNode = tree.HtmlNode;
pub const DomTreeArray = tree.HtmlTree;
pub const JsonTreeNode = tree.JsonNode;
pub const JsonTreeArray = tree.JsonTree;
pub const JsonAttribute = tree.JsonAttribute;

// Canonical conversion functions
pub const freeHtmlTree = tree.freeHtmlTree;
pub const freeJsonTree = tree.freeJsonTree;
pub const documentToJsonTree = tree.documentToJsonTree;
pub const documentToTupleTree = tree.documentToTupleTree;

// Pretty logging helpers
pub const printNode = tree.printNode;
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
pub const getTextContent = lxb.getTextContent;
pub const getTextContent_zc = lxb.getTextContent_zc; // Zero-copy version
pub const setOrReplaceText = lxb.setOrReplaceText;
pub const setTextContent = lxb.setTextContent;
pub const escapeHtml = lxb.escapeHtml;

//=========================================
// CSS selectors
//=========================================
pub const querySelectorAll = css.querySelectorAll;
pub const querySelector = css.querySelector;

//=========================================
// Attributes
//=========================================
pub const DomAttr = attrs.DomAttr;
pub const AttributePair = attrs.AttributePair;
pub const hasAttributes = attrs.hasAttributes;

pub const getAttribute = attrs.getAttribute;
pub const getAttribute_zc = attrs.getAttribute_zc;
pub const setAttribute = attrs.setAttribute;

pub const getAttributes = attrs.getAttributes;
pub const setAttributes = attrs.setAttributes;
pub const hasAttribute = attrs.hasAttribute;
pub const removeAttribute = attrs.removeAttribute;
pub const getElementId = attrs.getElementId;
pub const getElementId_zc = attrs.getElementId_zc;
pub const hasElementId = attrs.hasElementId;
pub const compareStrings = attrs.compareStrings;

pub const getAttributeValue_zc = attrs.getAttributeValue_zc;
pub const getAttributeValue = attrs.getAttributeValue;
pub const getAttributeName_zc = attrs.getAttributeName_zc;
pub const getAttributeName = attrs.getAttributeName;

// ------- Walker Search
pub const getElementById = walker.getElementById;
pub const getElementByTag = walker.getElementByTag;
pub const getElementByClass = walker.getElementByClass;
pub const getElementByAttribute = walker.getElementByAttribute;
pub const getElementByDataAttribute = walker.getElementByDataAttribute;
// multiple
pub const getElementsByClass = walker.getElementsByClass;
pub const getElementsByTag = walker.getElementsByTag;

//=========================================
// Element search functions
//=========================================
// pub const getElementById = collection.getElementById;
pub const getElementsByAttributePair = collection.getElementsByAttributePair;

pub const getElementsByClassName = collection.getElementsByClassName;
pub const getElementsByAttributeName = collection.getElementsByAttributeName;
pub const getElementsByTagName = collection.getElementsByTagName;
pub const getElementsByName = collection.getElementsByName;

//=========================================
// Class handling - unified function and convenience wrappers
//=========================================
pub const hasClass = classes.hasClass;
pub const classListAsString = classes.classListAsString;

pub const DOMTokenList = classes.DOMTokenList;
pub const classList = classes.classList;

//=========================================
// Attribute struct reflexion
//=========================================

pub const getFirstAttribute = attrs.getFirstAttribute;

pub const getNextAttribute = attrs.getNextAttribute;

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
