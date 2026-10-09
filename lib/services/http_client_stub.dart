import 'package:http/http.dart' as http;
import 'url_peek.dart';

/// The browser makes its own connections, so the default client is all we can use.
http.Client makeHttpClient() => http.Client();

Future<String> diagnoseConnection(Uri url, http.Client client) async =>
    'Not available in the browser: the browser makes these connections itself.';

/// Browsers cannot read another site's streams, so there is nothing to peek at.
Future<UrlPeek> peekUrl(Uri uri, Map<String, String> headers, Duration timeout) =>
    Future.error(UnsupportedError('Not available in a browser'));
