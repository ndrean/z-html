//! Z-HTML: Zig wrapper of the C library lexbor, HTML parsing and manipulation

const std = @import("std");
const builtin = @import("builtin");
const lxb = @import("modules/core.zig");
const css = @import("modules/css_selectors.zig");
const chunks = @import("modules/chunks.zig");
const tag = @import("modules/html_tags.zig");
const specs = @import("modules/html_spec.zig");
const Type = @import("modules/node_types.zig");
const search = @import("modules/simple_search.zig");
const serialize = @import("modules/serializer.zig");
const cleaner = @import("modules/cleaner.zig");
const attrs = @import("modules/attributes.zig");
const walker = @import("modules/walker.zig");
const classes = @import("modules/class_list.zig");
const frag_temp = @import("modules/fragment_template.zig");
const norm = @import("modules/normalize.zig");
const text = @import("modules/text_content.zig");
const sanitize = @import("modules/sanitizer.zig");
const parse = @import("modules/parsing.zig");
const colours = @import("modules/colours.zig");
const html_spec = @import("modules/html_spec.zig");

// Re-export commonly used types
pub const Err = @import("errors.zig").LexborError;

//=========================================================================================================
// General Status codes & constants & definitions

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

//=========================================================================================================
// Opaque lexbor structs

pub const HTMLDocument = opaque {};
pub const DomNode = opaque {};
pub const HTMLElement = opaque {};
pub const Comment: type = opaque {};
pub const DocumentFragment = opaque {};
pub const HTMLTemplateElement = opaque {};
pub const DomAttr = opaque {};
pub const DomCollection = opaque {};

pub const HtmlParser = opaque {};

pub const CssParser = opaque {};
pub const CssSelectors = opaque {};
pub const CssSelectorList = opaque {};
pub const CssSelectorSpecificity = opaque {};

//=========================================================================================================
// Core

pub const createDocument = lxb.createDocument;
pub const destroyDocument = lxb.destroyDocument;
pub const cleanDocument = lxb.cleanDocument;

//=========================================================================================================
// Create / Destroy Node / Element

pub const createElement = lxb.createElement;
pub const createElementWithAttrs = lxb.createElementWithAttrs;
pub const createTextNode = lxb.createTextNode;

pub const removeNode = lxb.removeNode;
pub const destroyNode = lxb.destroyNode;
// pub const destroyElement = lxb.destroyElement;

// DOM access
pub const documentRoot = lxb.documentRoot;
pub const ownerDocument = lxb.ownerDocument;
pub const bodyElement = lxb.bodyElement;
pub const bodyNode = lxb.bodyNode;

//=========================================================================================================
pub const cloneNode = lxb.cloneNode;
pub const importNode = lxb.importNode;

//=========================================================================================================
// Node / Element conversions=

pub const elementToNode = lxb.elementToNode;
pub const nodeToElement = lxb.nodeToElement;
pub const objectToNode = lxb.objectToNode;

//=========================================================================================================
// Node and Element name functions (both safe and unsafe versions)

pub const nodeName = lxb.nodeName; // Allocated
pub const nodeName_zc = lxb.nodeName_zc; // Zero-copy
pub const tagName = lxb.tagName; // Allocated
pub const tagName_zc = lxb.tagName_zc; // Zero-copy
pub const qualifiedName = lxb.qualifiedName; // Allocated
pub const qualifiedName_zc = lxb.qualifiedName_zc; // Zero-copy

//=========================================================================================================
// Node Reflection functions

pub const isNodeEmpty = lxb.isNodeEmpty;
pub const isVoid = lxb.isVoid;
pub const isNodeTextEmpty = lxb.isTextNodeEmpty;
pub const isWhitespaceOnlyText = lxb.isWhitespaceOnlyText;

//=========================================================================================================
// NodeTypes

pub const NodeType = Type.NodeType;
pub const nodeType = Type.nodeType;
pub const nodeTypeName = Type.nodeTypeName;

pub const isTypeElement = Type.isTypeElement;
pub const isTypeComment = Type.isTypeComment;
pub const isTypeText = Type.isTypeText;
pub const isTypeDocument = Type.isTypeDocument;
pub const isTypeFragment = Type.isTypeFragment;

//=========================================================================================================
// HTML tags & Html specs

pub const HtmlTag = tag.HtmlTag;
pub const WhitespacePreserveTagSet = tag.WhitespacePreserveTagSet;

// from lexbor source: /tag/const.h

pub const stringToEnum = tag.stringToEnum;
pub const tagFromQualifiedName = tag.tagFromQualifiedName;
pub const tagFromElement = tag.tagFromElement;
pub const tagFromAnyElement = tag.tagFromAnyElement;
pub const matchesTagName = tag.matchesTagName;

// pub const ElementSpec = specs.ElementSpec;
pub const ElementSpecMap = specs.ElementSpecMap;
pub const getElementSpecFromElement = specs.getElementSpecFromElement;
pub const isVoidElementFromSpec = specs.isVoidElementFromSpec;
pub const validateElementAttributeFromElement = specs.validateElementAttributeFromElement;
pub const getAllowedAttributesFromElement = specs.getAllowedAttributesFromElement;
pub const isAttributeAllowedFast = specs.isAttributeAllowedFast;
pub const getElementSpecFast = specs.getElementSpecFast;
pub const isVoidElementEnum = specs.isVoidElementEnum;
pub const isAttributeAllowedEnum = specs.isAttributeAllowedEnum;
pub const getElementSpecByEnum = specs.getElementSpecByEnum;

//=========================================================================================================
// Comment

pub const commentToNode = lxb.commentToNode;
pub const nodeToComment = lxb.nodeToComment;
pub const createComment = lxb.createComment;
// pub const destroyComment = lxb.destroyComment;

//=========================================================================================================
// Text  / comment content

pub const commentContent = text.commentContent;
pub const commentContent_zc = text.commentContent_zc;

pub const textContent = text.textContent;
pub const textContent_zc = text.textContent_zc;
pub const replaceText = text.replaceText;
pub const setContentAsText = text.setContentAsText;
pub const escapeHtml = text.escapeHtml;

//=========================================================================================================
// Normalize

// DOM based normalization
pub const isWhitespaceOnly = norm.isWhitespaceOnly;
pub const normalizeDOM = norm.normalizeDOM;
pub const normalizeDOMwithOptions = norm.normalizeDOMwithOptions;

pub const normalizeDOMForDisplay = norm.normalizeDOMForDisplay;

// String based normalization
pub const StringNormalizeOptions = cleaner.StringNormalizeOptions;

pub const normalizeHtmlString = cleaner.normalizeHtmlString;
pub const normalizeHtmlStringWithOptions = cleaner.normalizeHtmlStringWithOptions;

pub const normalizeText = cleaner.normalizeText;

//=========================================================================================================

// DOM navigation
pub const firstChild = lxb.firstChild;
pub const lastChild = lxb.lastChild;
pub const nextSibling = lxb.nextSibling;
pub const previousSibling = lxb.previousSibling;
pub const parentNode = lxb.parentNode;
pub const firstElementChild = lxb.firstElementChild;
pub const nextElementSibling = lxb.nextElementSibling;
pub const lastElementChild = lxb.lastElementChild;

pub const parentElement = lxb.parentElement;

pub const insertBefore = lxb.insertBefore;
pub const insertAfter = lxb.insertAfter;
pub const replaceAll = lxb.replaceAll;

pub const InsertPosition = lxb.InsertPosition;
pub const insertAdjacentElement = lxb.insertAdjacentElement;
pub const insertAdjacentHTML = lxb.insertAdjacentHTML;
pub const appendChild = lxb.appendChild;
pub const appendChildren = lxb.appendChildren;

pub const childNodes = lxb.childNodes;
pub const children = lxb.children;

//=========================================================================================================
// Stream parser for chunk processing

pub const Stream = chunks.Stream;

//=========================================================================================================
// Parser

// Direct access to parser functions
pub const parseString = parse.parseString;
pub const createDocFromString = parse.createDocFromString;

pub const setInnerHTML = parse.setInnerHTML;
pub const setInnerHTMLSafe = parse.setInnerHTMLSafe;

// Parser engine for fragment & template processing
pub const Parser = parse.Parser;

//=========================================================================================================
// Fragments & Template element

pub const FragmentContext = frag_temp.FragmentContext;

// fragments
pub const fragmentToNode = frag_temp.fragmentToNode;
pub const createDocumentFragment = frag_temp.createDocumentFragment;
pub const destroyDocumentFragment = frag_temp.destroyDocumentFragment;
pub const appendFragment = frag_temp.appendFragment;
// templates
pub const isTemplate = frag_temp.isTemplate;
pub const createTemplate = frag_temp.createTemplate;
pub const destroyTemplate = frag_temp.destroyTemplate;

pub const templateToNode = frag_temp.templateToNode;
pub const templateToElement = frag_temp.templateToElement;

pub const nodeToTemplate = frag_temp.nodeToTemplate;
pub const elementToTemplate = frag_temp.elementToTemplate;
// ---
pub const templateContent = frag_temp.templateContent;
pub const useTemplateElement = frag_temp.useTemplateElement;
pub const innerTemplateHTML = frag_temp.innerTemplateHTML;

//=========================================================================================================
// Sanitation / Serialization / Inner / outer HTML manipulation

pub const innerHTML = serialize.innerHTML;
pub const outerHTML = serialize.outerHTML;
pub const outerNodeHTML = serialize.outerNodeHTML;

// Debug printing utilities
pub const printDocStruct = serialize.printDocStruct;
pub const prettyPrint = serialize.prettyPrint;
//=========================================================================================================
// Colouring and syntax highlighting
pub const ElementStyles = colours.ElementStyles;
pub const SyntaxStyle = colours.SyntaxStyle;
pub const Style = colours.Style;
// pub const getStyleForElement = colours.getStyleForElement;
pub const getStyleForElementEnum = colours.getStyleForElementEnum;
pub const isKnownAttribute = colours.isKnownAttribute;
pub const isDangerousAttributeValue = colours.isDangerousAttributeValue;

//=========================================================================================================
// Sanitizer

pub const SanitizeOptions = sanitize.SanitizeOptions;
pub const SanitizerOptions = sanitize.SanitizerOptions;
pub const sanitizeNode = sanitize.sanitizeNode;
pub const sanitizeWithOptions = sanitize.sanitizeWithOptions;
pub const sanitizeStrict = sanitize.sanitizeStrict;
pub const sanitizePermissive = sanitize.sanitizePermissive;

// Unified HTML specification functions
pub const isElementAttributeAllowed = sanitize.isElementAttributeAllowed;

//=========================================================================================================
// Framework Attribute System

pub const FrameworkSpec = specs.FrameworkSpec;
pub const FRAMEWORK_SPECS = specs.FRAMEWORK_SPECS;
pub const isFrameworkAttribute = specs.isFrameworkAttribute;
pub const getFrameworkSpec = specs.getFrameworkSpec;
pub const isFrameworkAttributeSafe = specs.isFrameworkAttributeSafe;

//=========================================================================================================
// CSS selectors

pub const CssSelectorEngine = css.CssSelectorEngine;
pub const createCssEngine = css.createCssEngine;

pub const querySelectorAll = css.querySelectorAll;
pub const querySelector = css.querySelector;
pub const filter = css.filter;

//=========================================================================================================
// Class & ClassList

pub const hasClass = classes.hasClass;
pub const classList_zc = classes.classList_zc;
pub const classListAsString = classes.classListAsString;
// pub const classListAsString_zc = classes.classListAsString_zc;

pub const ClassList = classes.ClassList;
pub const classList = classes.classList;

//=========================================================================================================
// Attributes

pub const AttributePair = attrs.AttributePair;
pub const hasAttribute = attrs.hasAttribute;
pub const hasAttributes = attrs.hasAttributes;

pub const getAttribute = attrs.getAttribute;
pub const getAttribute_zc = attrs.getAttribute_zc;

pub const setAttribute = attrs.setAttribute;
pub const removeAttribute = attrs.removeAttribute;

pub const setAttributes = attrs.setAttributes;
pub const getAttributes_bf = attrs.getAttributes_bf;

pub const getElementId = attrs.getElementId;
pub const getElementId_zc = attrs.getElementId_zc;
pub const hasElementId = attrs.hasElementId;

//=========================================================================================================
// Single Element Search functions - Simple Walk

pub const getElementById = search.getElementById;
pub const getElementByTag = search.getElementByTag;
pub const getElementByClass = search.getElementByClass;
pub const getElementByAttribute = search.getElementByAttribute;
pub const getElementByDataAttribute = search.getElementByDataAttribute;

//=========================================================================================================
// Multiple Element Search Functions (Walker-based, returns slices)

pub const getElementsByClassName = search.getElementsByClassName;
pub const getElementsByTagName = search.getElementsByTagName;
pub const getElementsById = search.getElementsById;
pub const getElementsByAttribute = search.getElementsByAttribute;
pub const getElementsByName = search.getElementsByName;
pub const getElementsByAttributeName = search.getElementsByAttributeName;

//=========================================================================================================
// Walker Search traversal functions

pub const simpleWalk = walker.simpleWalk;
pub const castContext = walker.castContext;
pub const genProcessAll = walker.genProcessAll;
pub const genSearchElement = walker.genSearchElement;
pub const genSearchElements = walker.genSearchElements;

//=========================================================================================================
// Utilities
pub const stringContains = search.stringContains;
pub const stringEquals = search.stringEquals;

// ***************************************************************************
// Test all imported modules
// ****************************************************************************

const testing = std.testing;

test {
    std.testing.refAllDecls(@This());
}

pub fn get(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    var client: std.http.Client = .{
        .allocator = allocator,
    };
    defer client.deinit();

    const response = try client.fetch(.{
        .method = .GET,
        .location = .{ .url = url },
        .response_writer = &allocating.writer,
    });

    std.debug.assert(response.status == .ok);
    return allocating.toOwnedSlice();
}

// Simple conditional print - always use debug print for reliability
pub const print = switch (builtin.mode) {
    .Debug => std.debug.print,
    else => std.debug.print,
};
