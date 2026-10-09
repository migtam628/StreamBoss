import 'package:http/http.dart' as http;
import 'http_client_stub.dart' if (dart.library.io) 'http_client_io.dart'
    as impl;

export 'http_client_stub.dart' if (dart.library.io) 'http_client_io.dart'
    show diagnoseConnection, makeHttpClient, peekUrl;

/// The one client the app uses for provider traffic. On native platforms it connects over
/// IPv4 first and reports the real failure (see http_client_io.dart).
final http.Client appHttp = impl.makeHttpClient();
