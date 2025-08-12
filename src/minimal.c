#include <lexbor/html/html.h>
#include <lexbor/dom/dom.h>
#include <lexbor/html/serialize.h>

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
