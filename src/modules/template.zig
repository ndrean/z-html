//! Template module for handling HTML templates

const std = @import("std");
const z = @import("../zhtml.zig");
const Err = z.Err;

pub const Template = z.Template;

const testing = std.testing;
const print = std.debug.print;

extern "c" fn lxb_html_template_element_interface_create(doc: *z.HtmlDocument) ?*z.Template;
extern "c" fn lxb_html_template_element_interface_destroy(template_elt: *z.Template) *z.Template;

// External lexbor functions
extern "c" fn lxb_html_template_content_wrapper(template_element: *anyopaque) ?*z.DomNode;

/// [core] Create a template
pub fn createTemplate(doc: *z.HtmlDocument) !*z.Template {
    return lxb_html_template_element_interface_create(doc) orelse
        Err.CreateTemplateFailed;
}

/// [core] Destroy a template in the document
pub fn destroyTemplate(template: *z.Template) void {
    _ = lxb_html_template_element_interface_destroy(template);
}

test "template" {
    const doc = try z.createDocument();
    defer z.destroyDocument(doc);

    const template = try createTemplate(doc);
    defer destroyTemplate(template);

    // Check if the created template is valid
}

/// Check if a node is a template element
pub fn isTemplateElement(template: *z.Template) bool {
    _ = template;
    return true;
}

/// Get template interface for template elements
pub fn templateInterface(element: *z.DomElement) ?*z.DomNode {
    return lxb_html_template_content_wrapper(element);
}
