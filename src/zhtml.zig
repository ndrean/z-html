//! Z-HTML: Zig wrapper of the C library lexbor, HTML parsing and manipulation

// Re-export all modules
const lxb = @import("core.zig");
const chunks = @import("chunks.zig");
const css = @import("css_selectors.zig");
const attrs = @import("attributes.zig");
const serialize = @import("serializer.zig");
const collection = @import("collection.zig");
const tag = @import("html_tags.zig");
const Type = @import("node_types.zig");
const tree = @import("dom_tree.zig");
const traverse = @import("traverse.zig");
const cleaner = @import("cleaner.zig");

// Re-export commonly used types
pub const Err = @import("errors.zig").LexborError;

pub const DomCollection = lxb.DomCollection;

pub const LXB_STATUS_OK: usize = 0;
pub var default_collection_capacity: u8 = 10;
// pub const lxb_char_t = u8;
// pub const lxb_status_t = usize;

// CSS selectors
pub const CssSelectorEngine = css.CssSelectorEngine;

// Chunk parsing
pub const ChunkParser = chunks.ChunkParser;
pub const HtmlParser = chunks.HtmlParser;

// HTML tags
pub const HtmlTag = tag.HtmlTag;
pub const parseTag = tag.parseTag;
pub const parseTagInsensitive = tag.parseTagInsensitive;
pub const isVoidElement = tag.isVoidElement;

//----------------------------------------------------------------------------
// Core
pub const HtmlDocument = lxb.HtmlDocument;
pub const DomNode = lxb.DomNode;
pub const DomElement = lxb.DomElement;
pub const Comment: type = lxb.Comment;
pub const createDocument = lxb.createDocument;
pub const destroyDocument = lxb.destroyDocument;
pub const parseFromString = lxb.parseFromString;
pub const createElement = lxb.createElement;

// DOM access and navigation
pub const ownerDocument = lxb.ownerDocument;
pub const getBodyElement = lxb.getBodyElement;
pub const getBodyNode = lxb.getBodyNode;
pub const elementToNode = lxb.elementToNode;
pub const nodeToElement = lxb.nodeToElement;
pub const commentToNode = lxb.commentToNode;
pub const firstChild = lxb.firstChild;
pub const nextSibling = lxb.nextSibling;
pub const parentNode = lxb.parentNode;
pub const firstElementChild = lxb.firstElementChild;
pub const nextElementSibling = lxb.nextElementSibling;
pub const parentElement = lxb.parentElement;

// Node and Element name functions (both safe and unsafe versions)
pub const getNodeName = lxb.getNodeName;
pub const getElementName = lxb.getElementName;
pub const getNodeNameOwned = lxb.getNodeNameOwned;
pub const getElementNameOwned = lxb.getElementNameOwned;

// Node content functions
pub const getNodeAllTextContent = lxb.getNodeAllTextContent;

// DOM Creation and manipulation
pub const createTextNode = lxb.createTextNode;
pub const createComment = lxb.createComment;
pub const createDocumentFragment = lxb.createDocumentFragment;
// pub const insertNodeBefore = lxb.insertNodeBefore;
// pub const insertNodeAfter = lxb.insertNodeAfter;
pub const appendChild = lxb.appendChild;
pub const appendChildren = lxb.appendChildren;
pub const appendFragment = lxb.appendFragment;

pub const getChildNodes = lxb.getChildNodes;
pub const getChildren = lxb.getChildren;

// Experimental DOM Traversal utilities
pub const forEachChildNode = traverse.forEachChildNode;
pub const forEachChildElement = traverse.forEachChildElement;
pub const collectChildNodes = traverse.collectChildNodes;
pub const collectChildElements = traverse.collectChildElements;
pub const NodeCallback = traverse.NodeCallback;
pub const ElementCallback = traverse.ElementCallback;

// DOM Matcher utilities
pub const matchesTagName = lxb.matchesTagName;
pub const matchesAttribute = attrs.matchesAttribute;
pub const hasClass = attrs.hasClass;

// DOM Tree representation utilities (aliased to avoid conflicts)
pub const dom_tree = @import("dom_tree.zig");
pub const DomTreeNode = dom_tree.HtmlNode;
pub const DomTreeArray = dom_tree.HtmlTree;
pub const JsonTreeNode = dom_tree.JsonNode;
pub const JsonTreeArray = dom_tree.JsonTree;

pub const domNodeToTree = dom_tree.domNodeToTree;
pub const documentToTree = dom_tree.documentToTree;
pub const fullDocumentToTree = dom_tree.fullDocumentToTree;
pub const domNodeToJson = dom_tree.domNodeToJson;
pub const documentToJsonTree = dom_tree.documentToJsonTree;
pub const fullDocumentToJsonTree = dom_tree.fullDocumentToJsonTree;
pub const freeHtmlTree = dom_tree.freeHtmlTree;
pub const printNode = dom_tree.printNode;

pub const nodeToHtml = dom_tree.nodeToHtml;
pub const treeToHtml = dom_tree.treeToHtml;
pub const roundTripConversion = dom_tree.roundTripConversion;
pub const freeDomTreeArray = dom_tree.freeHtmlTree;
pub const freeDomTreeNode = dom_tree.freeHtmlNode;
pub const freeJsonTreeArray = dom_tree.freeJsonTree;
pub const freeJsonTreeNode = dom_tree.freeJsonNode;

pub const printDocumentStructure = dom_tree.printDocumentStructure;

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

// DOM manipulation
pub const removeNode = lxb.removeNode;
pub const destroyComment = lxb.destroyComment;
pub const destroyNode = lxb.destroyNode;
pub const destroyElement = lxb.destroyElement;

// Reflexion
pub const documentRoot = lxb.documentRoot;
pub const isNodeEmpty = lxb.isNodeEmpty;
pub const isSelfClosingNode = lxb.isSelfClosingNode;
pub const isWhitepaceOnlyText = lxb.isWhitespaceOnlyText;
pub const isWhitespaceOnlyNode = lxb.isWhitespaceOnlyNode;
pub const isWhitespaceOnlyElement = lxb.isWhitespaceOnlyElement;

// Serialization
pub const serializeTree = serialize.serializeTree;
pub const serializeNode = serialize.serializeNode;
pub const serializeElement = serialize.serializeElement;

pub const cleanDomTree = cleaner.cleanDomTree;
pub const normalizeWhitespace = cleaner.normalizeWhitespace;

// InnerHTML manipulation
pub const innerHTML = serialize.innerHtml;
pub const setInnerHTML = serialize.setInnerHtml;
pub const getElementHTMLAsString = serialize.serializeElement;

// Text content
pub const getCommentTextContent = lxb.getCommentTextContent;
pub const getNodeTextContentsOpts = lxb.getNodeTextContentsOpts;
pub const setOrReplaceText = lxb.setOrReplaceText;
pub const setTextContent = lxb.setTextContent;

// NodeTypes
pub const NodeType = Type.NodeType;
pub const getType = Type.getType;
pub const getTypeName = Type.getTypeName;

pub const isElementType = Type.isElementType;
pub const isCommentType = Type.isCommentType;
pub const isTextType = Type.isTextType;
pub const isNodeDocumentType = Type.isNodeDocumentType;

// CSS selectors - unified top-level access
pub const querySelectorAll = css.querySelectorAll;
pub const querySelector = css.querySelector;

// Attributes
pub const DomAttr = attrs.DomAttr;
pub const AttributePair = attrs.AttributePair;
pub const hasAttributes = attrs.hasAttributes;

pub const elementGetNamedAttributeValue = attrs.elementGetNamedAttributeValue;

pub const getAttribute = attrs.getAttribute;
pub const setAttribute = attrs.elementSetAttributes;
pub const hasAttribute = attrs.hasAttribute;
pub const removeAttribute = attrs.removeAttribute;
pub const getElementId = attrs.getElementId;
pub const getAttributes = attrs.getAttributes;

// Element search functions
pub const getElementById = collection.getElementById;
pub const getElementsByAttributePair = collection.getElementsByAttributePair;
pub const getElementsByClassName = collection.getElementsByClassName;
pub const getElementsByAttributeName = collection.getElementsByAttributeName;
pub const getElementsByTagName = collection.getElementsByTagName;
pub const getElementsByName = collection.getElementsByName;

// Class handling - unified function and convenience wrappers
pub const ClassListType = attrs.ClassListType;
pub const ClassListResult = attrs.ClassListResult;
pub const classList = attrs.classList;
pub const getClasses = attrs.getClasses;
pub const getClassString = attrs.getClassString;

// Attribute struct reflexion
pub const getAttributeName =
    attrs.getAttributeName;

pub const getAttributeValue =
    attrs.getAttributeValue;

pub const getElementFirstAttribute =
    attrs.getElementFirstAttribute;

pub const getElementNextAttribute =
    attrs.getElementNextAttribute;

//=============================================================================
// UTILITY FUNCTIONS
//=============================================================================

// debug
pub const walkTreeWithTypes = Type.walkTreeWithTypes;

/// [zhtml] Debug: Get only element children (filter out text/comment nodes)
pub fn getElementChildrenWithTypes(allocator: std.mem.Allocator, parent_node: *DomNode) ![]*DomElement {
    var elements = std.ArrayList(*DomElement).init(allocator);
    defer elements.deinit();

    var child = firstChild(parent_node);
    while (child != null) {
        if (isElementType(child.?)) {
            if (nodeToElement(child.?)) |element| {
                try elements.append(element);
            }
        }
        child = nextSibling(child.?);
    }

    return elements.toOwnedSlice();
}

// ----------------------------------------------------------------------------
// Test all imported modules
// ----------------------------------------------------------------------------
test {
    std.testing.refAllDecls(@This());
}

const std = @import("std");

const print = std.debug.print;
const testing = std.testing;
