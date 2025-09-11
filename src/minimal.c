#include <lexbor/html/html.h>
#include <lexbor/dom/dom.h>
#include <lexbor/html/serialize.h>
#include <lexbor/html/interfaces/template_element.h>
#include <lexbor/html/tree.h>

/**
 * Minimal C wrappers for lexbor functions that require access to
 * opaque struct internals. This enables Zig to work with lexbor
 * without accessing internal structures.
 */

// Get the node from a generic object
lxb_dom_node_t *lexbor_dom_interface_node_wrapper(void *obj)
{
  return lxb_dom_interface_node(obj);
}

// node/element -> element
lxb_dom_element_t *lexbor_dom_interface_element_wrapper(lxb_dom_node_t *node)
{
  return lxb_dom_interface_element(node);
}

// template -> element
lxb_dom_element_t *lexbor_html_template_to_element_wrapper(lxb_html_template_element_t *template_element)
{
  return lxb_dom_interface_element(template_element);
}

// template -> node
lxb_dom_node_t *lexbor_html_template_to_node_wrapper(lxb_html_template_element_t *template_element)
{
  return lxb_dom_interface_node(template_element);
}

// Wrapper for checking if a node has a specific tag ID
bool lexbor_html_tree_node_is_wrapper(lxb_dom_node_t *node, lxb_tag_id_t tag_id)
{
  return lxb_html_tree_node_is(node, tag_id);
}

// Wrapper for field access to get the owner document from a node
lxb_html_document_t *lexbor_node_owner_document_wrapper(lxb_dom_node_t *node)
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

// TEMPLATE content access
lxb_dom_document_fragment_t *lexbor_html_template_content_wrapper(lxb_html_template_element_t *template_element)
{
  if (template_element == NULL)
  {
    return NULL;
  }

  // Access the content field directly from the template structure
  // In lexbor, template elements have a 'content' field
  return template_element->content;
}

// lxb_dom_node_t *lxb_html_template_to_node(lxb_html_template_element_t *template_element)
// {
//   return lxb_dom_interface_node(template_element);
// }

// Create a template element using the standard document interface which creates the Tag_id and content access.
lxb_html_template_element_t *lexbor_html_create_template_element_wrapper(lxb_html_document_t *document)
{
  // Create template element using the standard element creation method
  lxb_dom_element_t *element = lxb_dom_document_create_element(
      lxb_dom_interface_document(document),
      (const lxb_char_t *)"template",
      8,
      NULL);

  if (element == NULL)
  {
    return NULL;
  }

  // Cast to template interface
  return lxb_html_interface_template(element);
}

// Cast a DOM element to template interface (if it's a template)
lxb_html_template_element_t *lexbor_element_to_template_wrapper(lxb_dom_element_t *element)
{
  if (element == NULL)
  {
    return NULL;
  }

  // Verify it's actually a template element before casting
  lxb_dom_node_t *node = lxb_dom_interface_node(element);
  if (lxb_html_tree_node_is(node, LXB_TAG_TEMPLATE))
  {
    return lxb_html_interface_template(element);
  }

  return NULL;
}

// Cast a DOM node to template interface (if it's a template)
lxb_html_template_element_t *lexbor_node_to_template_wrapper(lxb_dom_node_t *node)
{
  if (node == NULL)
  {
    return NULL;
  }

  // Check if it's a template node
  if (lxb_html_tree_node_is(node, LXB_TAG_TEMPLATE))
  {
    lxb_dom_element_t *element = lxb_dom_interface_element(node);
    if (element)
    {
      return lxb_html_interface_template(element);
    }
  }

  return NULL;
}
