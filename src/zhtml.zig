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
// const smart_text = @import("modules/smart_text.zig");
const walker = @import("modules/search_attributes.zig");
const classes = @import("modules/class_list.zig");
const template = @import("modules/template.zig");
const norm = @import("modules/normalize.zig");
const text = @import("modules/text_content.zig");

// Re-export commonly used types
pub const Err = @import("errors.zig").LexborError;

// ==========================================================
pub const Action = walker.Action;

// =========================================================
// Status codes & constants

pub const LXB_STATUS_OK: usize = 0;
// from lexbor source: /tag/const.h
pub const LXB_TAG_TEMPLATE: u32 = 179; // From lexbor source
pub const LXB_TAG_STYLE: u32 = 171;
pub const LXB_TAG_SCRIPT: u32 = 162;

pub const LXB_DOM_NODE_TYPE_ELEMENT: u32 = 1;
pub const LXB_DOM_NODE_TYPE_TEXT: u32 = 3;
pub const LXB_DOM_NODE_TYPE_COMMENT: u32 = 8;

// Collection constant
pub var default_collection_capacity: u8 = 10;

pub const TextOptions = struct {
    escape: bool = false,
    remove_comments: bool = false,
    remove_empty_elements: bool = false,
    keep_new_lines: bool = false,
    allow_html: bool = true, // Security: explicitly allow HTML parsing
};

//=====================================
// Core
//=====================================
pub const HTMLDocument = opaque {};
pub const DomNode = opaque {};
pub const HTMLElement = opaque {};
pub const Comment: type = opaque {};

pub const createDocument = lxb.createDocument;
pub const destroyDocument = lxb.destroyDocument;

//=====================================
pub const parseFromString = lxb.parseFromString;
//=====================================

//=====================================
// Create / Destroy Node / Element
//=====================================
pub const createElement = lxb.createElement;
pub const createElementAttr = lxb.createElementAttr;
pub const createTextNode = lxb.createTextNode;

pub const removeNode = lxb.removeNode;
pub const destroyNode = lxb.destroyNode;
pub const destroyElement = lxb.destroyElement;

// DOM access
pub const documentRoot = lxb.documentRoot;
pub const ownerDocument = lxb.ownerDocument;
pub const bodyElement = lxb.bodyElement;
pub const bodyNode = lxb.bodyNode;

pub const cloneNode = lxb.cloneNode;
pub const importNode = lxb.importNode;

//====================================
// Node / Element conversions
//====================================
pub const elementToNode = lxb.elementToNode;
pub const nodeToElement = lxb.nodeToElement;
pub const objectToNode = lxb.objectToNode;

// ===================================
// Node and Element name functions (both safe and unsafe versions)
// ===================================
pub const nodeName = lxb.nodeName; // Allocated
pub const nodeName_zc = lxb.nodeName_zc; // Zero-copy
pub const tagName = lxb.tagName; // Allocated
pub const tagName_zc = lxb.tagName_zc; // Zero-copy
pub const qualifiedName = lxb.qualifiedName; // Allocated
pub const qualifiedName_zc = lxb.qualifiedName_zc; // Zero-copy

// ==================================
// Node Reflection functions
// ==================================
pub const isNodeEmpty = lxb.isNodeEmpty;
pub const isVoid = lxb.isVoid;
pub const isNodeTextEmpty = lxb.isTextNodeEmpty;
pub const isWhitespaceOnlyText = lxb.isWhitespaceOnlyText;

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
pub const WhitespacePreserveTagSet = tag.WhitespacePreserveTagSet;
pub const VoidTagSet = tag.VoidTagSet;
pub const NoEscapeTagSet = tag.NoEscapeTagSet;

// from lexbor source: /tag/const.h

pub const parseTag = tag.parseTag;
pub const matchesTagName = tag.matchesTagName;
pub const tagFromElement = tag.tagFromElement;
pub const isVoidTag = tag.isVoidTag;
pub const isVoidElement = tag.isVoidElement; // Change name
pub const isNoEscapeElement = tag.isNoEscapeElement; // change name
pub const isNoEscapeElementExtended = tag.isNoEscapeElementExtended; // For custom elements

// ===================================
// Comment
// ===================================
pub const commentToNode = lxb.commentToNode;
pub const nodeToComment = lxb.nodeToComment;
pub const createComment = lxb.createComment;
pub const destroyComment = lxb.destroyComment;

//=====================================
// Text  / comment content
//=====================================
pub const commentContent = text.commentContent;
pub const commentContent_zc = text.commentContent_zc;

pub const textContent = text.textContent;
pub const textContent_zc = text.textContent_zc;
pub const replaceText = text.replaceText;
pub const setTextContent = text.setTextContent;
pub const escapeHtml = text.escapeHtml;

// ====================================
// Normalize
// ====================================
pub const normalize = norm.normalize;
pub const normalizeWithOptions = norm.normalizeWithOptions;

//=====================================
// DOM navigation
//=====================================
pub const firstChild = lxb.firstChild;
pub const lastChild = lxb.lastChild;
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

pub const childNodes = lxb.childNodes;
pub const children = lxb.children;

// ============================================================
// Chunk processing
// ============================================================
pub const ChunkParser = chunks.ChunkParser;
pub const HtmlParser = chunks.HtmlParser;

// =============================================================
// Fragment & fragment parsing
// =============================================================
pub const DocumentFragment = opaque {};
pub const FragmentContext = tag.FragmentContext;

pub const FragmentResult = fragments.FragmentResult;
pub const fragmentToNode = fragments.fragmentToNode;
pub const createDocumentFragment = fragments.createDocumentFragment;
pub const appendFragment = fragments.appendFragment;

pub const parseFragment = fragments.parseFragment;
pub const parseFragmentSimple = fragments.parseFragmentSimple;
pub const parseFragmentInto = fragments.parseFragmentInto;

//=====================================
// Template element
//=====================================
pub const HTMLTemplateElement = opaque {};
pub const isTemplate = template.isTemplate;

pub const createTemplate = template.createTemplate;
pub const destroyTemplate = template.destroyTemplate;

pub const templateToNode = template.templateToNode;
pub const templateToElement = template.templateToElement;

pub const nodeToTemplate = template.nodeToTemplate;
pub const elementToTemplate = template.elementToTemplate;

pub const templateContent = template.templateContent;
pub const appendParsedContent = template.appendParsedContent;

// ===========================================================================
// DOM Traversal utilities
pub const collectChildItems = traverse.collectChildItems;
pub const collectChildElements = traverse.collectChildElements;
pub const elementMatchCollector = traverse.elementMatchCollector;
pub const nodeMatchCollector = traverse.nodeMatchCollector;

//=====================================
// DOM Tree representation utilities
//=====================================
pub const DomTreeNode = tree.HtmlNode;
pub const DomTreeArray = tree.HtmlTree;
pub const JsonTreeNode = tree.JsonNode;
pub const JsonTreeArray = tree.JsonTree;
pub const JsonAttribute = tree.JsonAttribute;

// conversion functions
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
pub const normalizeText = cleaner.normalizeText;

//=========================================
// CSS selectors
//=========================================
pub const CssSelectorEngine = css.CssSelectorEngine;
pub const CssParser = opaque {};
pub const CssSelectors = opaque {};
pub const CssSelectorList = opaque {};
pub const CssSelectorSpecificity = opaque {};
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

//=======================================
// ------- Search (simple walk)
// ======================================
pub const getElementById = walker.getElementById;
pub const getElementByTag = walker.getElementByTag;
pub const getElementByClass = walker.getElementByClass;
pub const getElementByAttribute = walker.getElementByAttribute;
pub const getElementByDataAttribute = walker.getElementByDataAttribute;
// multiple
pub const getElementsByClass = walker.getElementsByClass;
pub const getElementsByTag = walker.getElementsByTag;

//=========================================
// Collection based Elements Search
//=========================================
pub const getElementsByAttributePair = collection.getElementsByAttributePair;

pub const getElementsByClassName = collection.getElementsByClassName;
pub const getElementsByAttributeName = collection.getElementsByAttributeName;
pub const getElementsByTagName = collection.getElementsByTagName;
pub const getElementsByName = collection.getElementsByName;

//=========================================
// Class handling - DOMTokenList
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
pub fn getElementChildrenWithTypes(allocator: std.mem.Allocator, parent_node: *DomNode) ![]*HTMLElement {
    var elements = std.ArrayList(*HTMLElement).init(allocator);
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

// pub const leadingWhitespaceSize = smart_text.leadingWhitespaceSize;
// pub const isNoEscapeTextNode = smart_text.isNoEscapeTextNode;
// pub const escapeHtmlSmart = smart_text.escapeHtmlSmart;
// pub const processTextContentSmart = smart_text.processTextContentSmart;

// ***************************************************************************
// Test all imported modules
// ****************************************************************************

const std = @import("std");
const print = std.debug.print;
const testing = std.testing;

test {
    std.testing.refAllDecls(@This());
}
