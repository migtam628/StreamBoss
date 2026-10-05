import 'package:http/http.dart' as http;

/// The browser makes its own connections, so the default client is all we can use.
http.Client makeHttpClient() => http.Client();

Future<String> diagnoseConnection(Uri url, http.Client client) async =>
    'Not available in the browser: the browser makes these connections itself.';
