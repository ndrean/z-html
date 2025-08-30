//! Z-HTML: Zig wrapper of the C library lexbor, HTML parsing and manipulation

const log = @import("global_writer.zig");
const lxb = @import("modules/core.zig");
const css = @import("modules/css_selectors.zig");
const chunks = @import("modules/chunks.zig");
const fragments = @import("modules/fragments.zig");
const tag = @import("modules/html_tags.zig");
const Type = @import("modules/node_types.zig");
const tree = @import("modules/dom_tree.zig");
const collection = @import("modules/collection.zig");
const serialize = @import("modules/serializer.zig");
const cleaner = @import("modules/cleaner.zig");
const attrs = @import("modules/attributes.zig");
const walker = @import("modules/walker.zig");
const classes = @import("modules/class_list.zig");
const template = @import("modules/template.zig");
const norm = @import("modules/normalize.zig");
const text = @import("modules/text_content.zig");
const sanitize = @import("modules/sanitizer.zig");
const parser = @import("modules/parser.zig");
const colours = @import("modules/colours.zig");
const get = @import("modules/fetch.zig");

// Re-export commonly used types
pub const Err = @import("errors.zig").LexborError;
// pub const Writer = log.GlobalWriter;

pub const fetchTest = get.fetchTest;
// =========================================================
// General Status codes & constants & definitions
// =========================================================

pub const _CONTINUE: c_int = 0;
pub const _STOP: c_int = 1;
pub const _OK: usize = 0;

// from lexbor source: /tag/const.h
pub const LXB_TAG_TEMPLATE: u32 = 179; // From lexbor source
pub const LXB_TAG_STYLE: u32 = 171;
pub const LXB_TAG_SCRIPT: u32 = 162;

pub const LXB_DOM_NODE_TYPE_ELEMENT: u32 = 1;
pub const LXB_DOM_NODE_TYPE_TEXT: u32 = 3;
pub const LXB_DOM_NODE_TYPE_COMMENT: u32 = 8;

pub const LXB_DOM_NODE_TYPE_DOCUMENT = 9;
pub const LXB_DOM_NODE_TYPE_FRAGMENT = 11;
pub const LXB_DOM_NODE_TYPE_UNKNOWN = 0;

// Collection constant
pub var default_collection_capacity: u8 = 10;

pub const TextOptions = struct {
    escape: bool = false,
    remove_comments: bool = false,
    remove_empty_elements: bool = false,
    keep_new_lines: bool = false,
    allow_html: bool = true, // Security: explicitly allow HTML parsing
};

// =====================================
// Colouring and syntax highlighting
// =====================================
pub const ElementStyles = colours.ElementStyles;
pub const SyntaxStyle = colours.SyntaxStyle;
pub const Style = colours.Style;
pub const getStyleForElement = colours.getStyleForElement;
pub const isKnownAttribute = colours.isKnownAttribute;
pub const isDangerousAttributeValue = colours.isDangerousAttributeValue;

// ====================================
// Sanitizer
// ====================================

// ====================================
// Walker Search traversal functions
// ====================================
pub const simpleWalk = walker.simpleWalk;
pub const castContext = walker.castContext;
pub const genProcessAll = walker.genProcessAll;
pub const genSearchElement = walker.genSearchElement;
pub const genSearchElements = walker.genSearchElements;

//=====================================
// Main structs
//=====================================
pub const HTMLDocument = opaque {};
pub const DomNode = opaque {};
pub const HTMLElement = opaque {};
pub const Comment: type = opaque {};
pub const DocumentFragment = opaque {};

//=====================================
// Core
//=====================================
pub const createDocument = lxb.createDocument;
pub const destroyDocument = lxb.destroyDocument;

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

//=====================================
pub const cloneNode = lxb.cloneNode;
pub const importNode = lxb.importNode;

//=====================================
// Node / Element conversions=
//=====================================
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

pub const tagFromQualifiedName = tag.tagFromQualifiedName;
pub const tagFromElement = tag.tagFromElement;
pub const matchesTagName = tag.matchesTagName;
pub const isVoidName = tag.isVoidName;
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
pub const setContentAsText = text.setContentAsText;
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

//=====================================
// Parser
//=====================================

pub const HtmlTree = opaque {};
pub const parseFromString = parser.parseFromString;
// Parser engine
pub const Parser = parser.Parser;

// ============================================================
// Chunk processing engine
// ============================================================
pub const ChunkParser = chunks.ChunkParser;
pub const HtmlParser = chunks.HtmlParser;

// =============================================================
// Fragment & fragment parsing
// =============================================================
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
// ---
pub const templateContent = template.templateContent;
pub const useTemplate = template.useTemplate;

// ===========================================================================
// DOM Traversal utilities
// pub const collectChildItems = traverse.collectChildItems;
// pub const collectChildElements = traverse.collectChildElements;
// pub const elementMatchCollector = traverse.elementMatchCollector;
// pub const nodeMatchCollector = traverse.nodeMatchCollector;

//=====================================
// DOM Tree representation utilities
//=====================================
pub const TupleNode = tree.TupleNode;
pub const nodeTuple = tree.nodeTuple;
pub const toTuple = tree.toTuple;
pub const freeTupleTree = tree.freeTupleTree;
pub const freeTupleNode = tree.freeTupleNode;

// pub const DomTreeNode = tree.HtmlNode;
// pub const DomTreeArray = tree.HtmlTree;
// pub const JsonTreeNode = tree.JsonNode;
// pub const JsonTreeArray = tree.JsonTree;
// pub const JsonAttribute = tree.JsonAttribute;

// conversion functions
// pub const freeHtmlTree = tree.freeHtmlTree;
// pub const freeJsonTree = tree.freeJsonTree;
// pub const documentToJsonTree = tree.documentToJsonTree;
// pub const documentToTupleTree = tree.documentToTupleTree;

pub const printNode = tree.printNode;
// pub const jsonNodeToString = tree.jsonNodeToString;
// pub const jsonTreeToString = tree.jsonTreeToString;
// pub const parseJsonString = tree.parseJsonString;
// pub const parseJsonTreeString = tree.parseJsonTreeString;

// pub const nodeToHtml = tree.nodeToHtml;
// pub const treeToHtml = tree.treeToHtml;
// pub const freeDomTreeArray = tree.freeHtmlTree;
// pub const freeDomTreeNode = tree.freeHtmlNode;

//=====================================
// Sanitation / Serialization / Inner / outer HTML manipulation
//=====================================
pub const innerHTML = serialize.innerHTML;
pub const setInnerHTML = serialize.setInnerHTML; // Security-first API with TextOptions
pub const outerHTML = serialize.outerHTML;
pub const outerNodeHTML = serialize.outerNodeHTML;

pub const sanitizeNode = sanitize.sanitizeNode;
pub const sanitizeWithOptions = sanitize.sanitizeWithOptions;
pub const printDocStruct = tree.printDocStruct;
pub const prettyPrint = serialize.prettyPrint;

pub const cleanDomTree = cleaner.cleanDomTree;
pub const normalizeText = cleaner.normalizeText;

//=========================================
// CSS selectors
//=========================================
// pub const CssSelectorEngine = css.CssSelectorEngine;
// pub const CssParser = opaque {};
// pub const CssSelectors = opaque {};
// pub const CssSelectorList = opaque {};
// pub const CssSelectorSpecificity = opaque {};
// pub const querySelectorAll = css.querySelectorAll;
// pub const querySelector = css.querySelector;

//=========================================
// Class handling - DOMTokenList
//=========================================
pub const hasClass = classes.hasClass;
pub const classListAsString = classes.classListAsString;
pub const classListAsString_zc = classes.classListAsString_zc;

pub const DOMTokenList = classes.DOMTokenList;
pub const classList = classes.classList;

//=========================================
// Attributes
//=========================================
pub const DomAttr = attrs.DomAttr;
pub const AttributePair = attrs.AttributePair;
pub const hasAttributes = attrs.hasAttributes;

pub const getAttribute = attrs.getAttribute;
pub const getAttribute_zc = attrs.getAttribute_zc;
pub const setAttribute = attrs.setAttribute;

pub const getAttributes_bf = attrs.getAttributes_bf;
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

//=========================================
// Attribute struct reflexion
//=========================================

pub const getFirstAttribute = attrs.getFirstAttribute;
pub const getNextAttribute = attrs.getNextAttribute;

//=======================================
// ------- Search (simple walk)
// ======================================
pub const getElementById = attrs.getElementById;
pub const getElementByClass = attrs.getElementByClass;
pub const getElementByAttribute = attrs.getElementByAttribute;
pub const getElementByDataAttribute = attrs.getElementByDataAttribute;
pub const getElementByTag = attrs.getElementByTag; // multiple
pub const getElementsById = attrs.getElementsById; // multiple

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

//=========================================
// Collection based Elements Search
//=========================================
pub const getElementsByAttributePair = collection.getElementsByAttributePair;

pub const getElementsByClassName = collection.getElementsByClassName;
pub const getElementsByAttributeName = collection.getElementsByAttributeName;
pub const getElementsByTagName = collection.getElementsByTagName;
pub const getElementsByName = collection.getElementsByName;

// ***************************************************************************
// ***************************************************************************
// Test all imported modules
// ****************************************************************************

const std = @import("std");
const print = std.debug.print;
const testing = std.testing;

test {
    std.testing.refAllDecls(@This());
}
