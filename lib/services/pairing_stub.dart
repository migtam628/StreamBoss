import '../models/media.dart';

/// A short-lived way to enter a provider login from a phone (see pairing_io.dart).
abstract class PairingSession {
  /// What the phone should open, e.g. http://192.168.1.20:41234
  String get url;
  String get pin;
  Stream<Source> get sources;
  Future<void> close();
}

/// Browsers can't listen for connections, so pairing is native-only.
bool get pairingSupported => false;

Future<PairingSession?> startPairing({String? host}) async => null;
