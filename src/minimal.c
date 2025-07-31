#include <lexbor/html/html.h>
#include <lexbor/dom/dom.h>

// Keep only the wrappers we actually need:

lxb_dom_node_t *lexbor_dom_interface_node_wrapper(void *obj)
{
  return lxb_dom_interface_node(obj);
}

lxb_dom_element_t *lexbor_dom_interface_element_wrapper(lxb_dom_node_t *node)
{
  return lxb_dom_interface_element(node);
}

lxb_dom_collection_t *lexbor_collection_make_wrapper(lxb_html_document_t *doc, size_t size)
{
  return lxb_dom_collection_make(&doc->dom_document, size);
}

lxb_dom_element_t *lexbor_get_body_element_wrapper(lxb_html_document_t *doc)
{
  lxb_html_body_element_t *body = lxb_html_document_body_element(doc);
  if (body == NULL)
    return NULL;
  return lxb_dom_interface_element(body);
}

lxb_dom_element_t *lexbor_create_dom_element(lxb_html_document_t *doc, const lxb_char_t *tag_name, size_t tag_len)
{
  lxb_html_element_t *html_element = lxb_html_document_create_element(doc, tag_name, tag_len, NULL);
  return lxb_dom_interface_element(html_element);
}

lxb_html_document_t *lexbor_parse_fragment_as_document(const lxb_char_t *html, size_t html_len)
{
  lxb_html_document_t *frag_doc = lxb_html_document_create();
  if (frag_doc == NULL)
    return NULL;

  lxb_status_t status = lxb_html_document_parse(frag_doc, html, html_len);
  if (status != LXB_STATUS_OK)
  {
    lxb_html_document_destroy(frag_doc);
    return NULL;
  }

  return frag_doc;
}