/// Independent product namespaces. A namespace is not a filesystem path.
///
/// Clients choose their own storage through a platform service; a shared package
/// must never import a client or infer a system directory.
enum ReaderProduct {
  novel('novel'),
  comic('comic');

  const ReaderProduct(this.namespace);

  final String namespace;
}
