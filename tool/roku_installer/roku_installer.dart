// StreamBoss Roku installer. Run it (double-click on Windows), answer two questions, and the channel is on the Roku.
import 'dart:io';
import 'roku.dart';

const _help = '''StreamBoss Roku installer

  Finds your Roku on the network, sends it the StreamBoss channel and starts it.

Usage: roku_installer [options]
  --ip ADDRESS      the Roku's address (skip the search)
  --password TEXT   the developer password you chose on the TV
  --zip FILE        install this channel file instead of downloading the newest release
  --no-launch       do not start the channel afterwards
  --help            this text
''';

String? _arg(List<String> a, String name) {
  final i = a.indexOf(name);
  return i >= 0 && i + 1 < a.length ? a[i + 1] : null;
}

String _ask(String question, {bool secret = false}) {
  stdout.write('$question ');
  if (secret) {
    try {
      stdin.echoMode = false;
    } catch (_) {}
  }
  final line = stdin.readLineSync() ?? '';
  if (secret) {
    try {
      stdin.echoMode = true;
    } catch (_) {}
    stdout.writeln();
  }
  return line.trim();
}

void _waitToClose() {
  if (stdin.hasTerminal) {
    stdout.write('\nPress Enter to close. ');
    stdin.readLineSync();
  }
}

Future<int> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.write(_help);
    return 0;
  }
  stdout.writeln('StreamBoss Roku installer\n');
  try {
    // 1. Which Roku.
    var host = _arg(args, '--ip');
    if (host == null) {
      stdout.writeln('Looking for Rokus on your network...');
      final hosts = await discoverHosts();
      final devices = <RokuDevice>[];
      for (final h in hosts) {
        final c = RokuClient(h);
        devices.add(await c.deviceInfo() ?? RokuDevice(h));
        c.close();
      }
      if (devices.isEmpty) {
        stdout.writeln(
            'None found. On the Roku: Settings > Network > About shows its address.');
        host = _ask('Roku address (for example 192.168.1.40):');
      } else if (devices.length == 1) {
        host = devices.first.host;
        stdout.writeln('Found ${devices.first.label}');
      } else {
        for (var i = 0; i < devices.length; i++) {
          stdout.writeln('  ${i + 1}. ${devices[i].label}');
        }
        final n = int.tryParse(_ask('Which one? (number)')) ?? 1;
        host = devices[(n - 1).clamp(0, devices.length - 1)].host;
      }
    }
    if (host.isEmpty) throw const RokuException('No address given.');
    final roku = RokuClient(host);

    // 2. Developer mode.
    if (!await roku.installerUp()) {
      stdout.writeln(
          '\nThe Roku\'s installer is not on, which means developer mode is off.');
      final go =
          _ask('Open the Developer Settings screen on the TV for me? (y/n)')
              .toLowerCase()
              .startsWith('y');
      if (go) {
        try {
          await roku.openDeveloperSettings();
          stdout.writeln(
              'Done. If the screen did not appear, do it by hand: on the remote press');
        } catch (_) {
          stdout.writeln(
              'The Roku did not accept that. Do it by hand: on the remote press');
        }
      } else {
        stdout.writeln('On the remote press');
      }
      stdout.writeln(
          '  Home 3 times, Up 2 times, then Right, Left, Right, Left, Right.');
      stdout.writeln(
          'Then on the TV: choose "Enable installer and restart", accept the licence,');
      stdout
          .writeln('choose a password (remember it) and let the Roku restart.');
      _ask('\nWhen the Roku is back, press Enter.');
      if (!await roku.installerUp()) {
        throw const RokuException(
            'The Roku\'s installer still does not answer. Check that developer mode is on and try again.');
      }
    }

    // 3. The channel file.
    List<int> zip;
    String label;
    final file = _arg(args, '--zip');
    if (file != null) {
      zip = File(file).readAsBytesSync();
      if (!looksLikeZip(zip)) throw RokuException('$file is not a zip file.');
      label = file;
    } else {
      stdout.writeln('Downloading the newest StreamBoss channel...');
      final d = await downloadLatest();
      zip = d.bytes;
      label = '${d.name} (${d.tag})';
    }

    // 4. Install.
    final password = _arg(args, '--password') ??
        _ask('Developer password you chose on the TV:', secret: true);
    stdout.writeln('Installing $label ...');
    final result = await roku.install(zip, password);
    stdout.writeln(result.message);
    if (!result.ok) return 1;
    if (!args.contains('--no-launch')) {
      try {
        await roku.launchDev();
        stdout.writeln('StreamBoss is starting on the Roku.');
      } catch (_) {
        stdout.writeln(
            'Open StreamBoss from the end of the Roku\'s home screen.');
      }
    }
    roku.close();
    stdout.writeln(
        '\nDone. Next: connect your provider in the channel (docs/ROKU.md has the steps).');
    _waitToClose();
    return 0;
  } on RokuException catch (e) {
    stderr.writeln('\n$e');
  } on SocketException catch (e) {
    stderr.writeln(
        '\nCould not reach the Roku (${e.message}). Check the address and that this computer is on the same network.');
  } on HttpException catch (e) {
    stderr.writeln('\nThe network stopped: ${e.message}');
  } on Exception catch (e) {
    stderr.writeln('\nSomething went wrong: $e');
  }
  _waitToClose();
  return 1;
}
