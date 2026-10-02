// Gives `element` a datalist of `options` and returns what takes it away again. The list
// sits outside the page's own markup but in the field's tree, where its list id resolves.
export function attachList(element: HTMLInputElement, options: readonly string[]): () => void {
  const doc = element.ownerDocument;
  const list = doc.createElement("datalist");
  list.id = `prefill-${crypto.randomUUID()}`;
  list.append(
    ...options.map((value) => {
      const option = doc.createElement("option");
      option.value = value;
      return option;
    }),
  );
  const root = element.getRootNode();
  (root instanceof ShadowRoot ? root : doc.body).append(list);
  element.setAttribute("list", list.id);
  return () => {
    element.removeAttribute("list");
    list.remove();
  };
}
