/// The start of what a URL returned: status, content type and the first chunk of the body.
class UrlPeek {
  final int status;
  final String contentType;
  final List<int> head;
  const UrlPeek(this.status, this.contentType, this.head);
}
