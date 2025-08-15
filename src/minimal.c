#include <lexbor/html/html.h>
#include <lexbor/dom/dom.h>
#include <lexbor/html/serialize.h>
#include <lexbor/html/interfaces/template_element.h>
#include <lexbor/html/tree.h>

/**
 * Minimal C wrappers for lexbor functions that require access to
 * opaque struct internals. These enable Zig to work with lexbor
 * without exposing complex internal structures.
 */

lxb_dom_node_t *lexbor_dom_interface_node_wrapper(void *obj)
{
  return lxb_dom_interface_node(obj);
}

lxb_dom_element_t *lexbor_dom_interface_element_wrapper(lxb_dom_node_t *node)
{
  return lxb_dom_interface_element(node);
}

// Cross-document node cloning wrapper
lxb_dom_node_t *lexbor_clone_node_deep(lxb_dom_node_t *node, lxb_html_document_t *target_doc)
{
  return lxb_dom_document_import_node(lxb_dom_interface_document(target_doc), node, true);
}

// Wrapper for field access to get the owner document from a node
lxb_html_document_t *lexbor_node_owner_document(lxb_dom_node_t *node)
{
  return lxb_html_interface_document(node->owner_document);
}

// Wrapper for field access to destroy text with proper document
// Uses the _noi (no-inline) version for ABI compatibility
void lexbor_destroy_text_wrapper(lxb_dom_node_t *node, lxb_char_t *text)
{
  if (text != NULL)
    lxb_dom_document_destroy_text_noi(node->owner_document, text);
}

// Template element interface functions - simplified approach
// Check if a node has LXB_TAG_TEMPLATE tag
bool lxb_html_tree_node_is_wrapper(lxb_dom_node_t *node, lxb_tag_id_t tag_id)
{
  return lxb_html_tree_node_is(node, tag_id);
}

// Get template content - fallback implementation
lxb_dom_document_fragment_t *lxb_html_template_content_wrapper(lxb_html_template_element_t *template_element)
{
  // Fallback: template content access may not be available in this lexbor version
  // Return NULL for now - template detection still works via tag checking
  (void)template_element; // Suppress unused parameter warning
  return NULL;
}

// Template interface - simplified
void *lxb_html_interface_template_wrapper()
{
  return NULL; // Simplified for now - template detection works via tag check
}
