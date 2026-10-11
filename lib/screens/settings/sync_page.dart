import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/l10n.dart';
import '../../layouts/ui_layout.dart';
import '../../models/media.dart';
import '../../state/app_state.dart';
import '../../state/sync_state.dart';
import '../../widgets/tv_text_field.dart';
import 'settings_widgets.dart';

/// Settings > Sync: the account on the sync server and what it keeps in step.
class SyncPage extends StatelessWidget {
  const SyncPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncState>();
    final muted = TextStyle(
        color: LayoutPalette.of(context).muted, fontSize: 13, height: 1.4);
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          tr('Keep your settings, My List, resume positions, profiles and saved sources the same on all your devices. '
              'This needs a StreamBoss sync server of your own (the server folder of the project has one that runs with Docker). '
              'Provider passwords and the playlist links that carry one never leave this device: enter them once on each device.'),
          style: muted,
        ),
      ),
      if (!sync.signedIn) ...[
        const SettingsHeader('Account'),
        if (sync.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(sync.error!,
                style: TextStyle(color: LayoutPalette.of(context).accent)),
          ),
        ActionRow(
          icon: Icons.login,
          title: tr('Sign in'),
          subtitle: tr('To an account you already have on your sync server'),
          onTap: sync.busy ? null : () => account(context, create: false),
        ),
        ActionRow(
          icon: Icons.person_add_alt,
          title: tr('Create an account'),
          subtitle:
              tr('On your own sync server; the first account is the owner'),
          onTap: sync.busy ? null : () => account(context, create: true),
        ),
      ] else ...[
        const SettingsHeader('Account'),
        InfoRow('E-mail', sync.email),
        InfoRow('Server', sync.server.replaceFirst(RegExp(r'^https?://'), '')),
        const SettingsHeader('Sync'),
        ActionRow(
          icon: sync.busy ? Icons.sync : Icons.sync_alt,
          title: sync.busy ? tr('Syncing…') : tr('Sync now'),
          subtitle: sync.error != null
              ? sync.error!
              : sync.lastSync == null
                  ? tr('Not synced yet')
                  : trf('Last synced {when}', {'when': _ago(sync.lastSync!)}),
          onTap: sync.busy ? null : () => sync.syncNow(),
        ),
        SwitchRow(
          icon: Icons.autorenew,
          title: tr('Sync by itself'),
          subtitle: tr(
              'When StreamBoss opens and closes, a little after you change something, and every few minutes'),
          value: sync.auto,
          onChanged: sync.setAuto,
        ),
        const SettingsHeader('Account'),
        ActionRow(
          icon: Icons.password,
          title: tr('Change password'),
          subtitle: tr('The other devices have to sign in again'),
          onTap: () => _changePassword(context),
        ),
        ActionRow(
          icon: Icons.logout,
          title: tr('Sign out'),
          subtitle: tr('This device keeps its data and stops syncing'),
          onTap: () async {
            if (await confirmDialog(context,
                title: tr('Sign out?'),
                body: tr(
                    'This device keeps everything it has and stops syncing. Other devices are not affected.'),
                confirm: tr('Sign out'))) {
              await sync.signOut();
            }
          },
        ),
        ActionRow(
          icon: Icons.delete_forever_outlined,
          title: tr('Delete the account'),
          subtitle: tr(
              'Removes your account and what the server holds. Your devices keep their data'),
          destructive: true,
          onTap: () => _delete(context),
        ),
      ],
      const SettingsHeader('What is synced'),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Text(
          tr('Synced: settings (not the ones that depend on the device, such as the screen size, the decoder and the layout), saved sources without their passwords, '
              'profiles and their PIN, My List, collections, watched marks, resume positions, edited channels and reminders. '
              'Not synced: passwords, the recently watched list, downloaded libraries and pictures.'),
          style: muted,
        ),
      ),
    ]);
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 45) return tr('just now');
    if (d.inMinutes < 60) return trf('{n} min ago', {'n': d.inMinutes});
    if (d.inHours < 24) return trf('{n} h ago', {'n': d.inHours});
    return trf('{n} days ago', {'n': d.inDays});
  }

  static Future<void> account(BuildContext context,
      {required bool create}) async {
    final sync = context.read<SyncState>();
    final server = TextEditingController(
        text: sync.server.replaceFirst(RegExp(r'^https://'), ''));
    final email = TextEditingController(text: sync.email);
    final pass = TextEditingController();
    var shown = false;
    String? problem;
    var working = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> go() async {
          set(() {
            working = true;
            problem = null;
          });
          final err = await sync.signIn(server.text, email.text, pass.text,
              create: create);
          if (!ctx.mounted) return;
          if (err == null) {
            Navigator.pop(ctx);
          } else {
            set(() {
              working = false;
              problem = err;
            });
          }
        }

        return AlertDialog(
          title: Text(create ? tr('Create an account') : tr('Sign in')),
          content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TvTextField(
                    controller: server,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                        labelText: tr('Server'), hintText: 'sync.example.com'),
                  ),
                  TvTextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(labelText: tr('E-mail')),
                  ),
                  TvTextField(
                    controller: pass,
                    obscureText: !shown,
                    decoration: InputDecoration(
                      labelText: tr('Password'),
                      helperText: create ? tr('At least 8 characters') : null,
                      suffixIcon: IconButton(
                        tooltip: tr('Show the password'),
                        icon: Icon(
                            shown ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => set(() => shown = !shown),
                      ),
                    ),
                  ),
                  if (problem != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(problem!,
                          style:
                              TextStyle(color: LayoutPalette.of(ctx).accent)),
                    ),
                ]),
          ),
          actions: [
            TextButton(
                onPressed: working ? null : () => Navigator.pop(ctx),
                child: Text(tr('Cancel'))),
            FilledButton(
                onPressed: working ? null : go,
                child: Text(working
                    ? tr('Working…')
                    : (create ? tr('Create account') : tr('Sign in')))),
          ],
        );
      }),
    );
  }

  static Future<void> _changePassword(BuildContext context) async {
    final sync = context.read<SyncState>();
    final old = TextEditingController();
    final fresh = TextEditingController();
    String? problem;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Change password')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TvTextField(
                  controller: old,
                  autofocus: true,
                  obscureText: true,
                  decoration:
                      InputDecoration(labelText: tr('Current password'))),
              TvTextField(
                  controller: fresh,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: tr('New password'),
                      helperText: tr('At least 8 characters'))),
              if (problem != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(problem!,
                        style: TextStyle(color: LayoutPalette.of(ctx).accent))),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
            FilledButton(
              onPressed: () async {
                final err = await sync.changePassword(old.text, fresh.text);
                if (!ctx.mounted) return;
                if (err == null) {
                  Navigator.pop(ctx);
                  toast(context, tr('Password changed'));
                } else {
                  set(() => problem = err);
                }
              },
              child: Text(tr('Change')),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _delete(BuildContext context) async {
    final sync = context.read<SyncState>();
    final pass = TextEditingController();
    String? problem;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Delete the account?')),
          content: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(
                      'Your account and everything the server keeps for it are deleted for good. Your devices keep their own data. Type your password to confirm.')),
                  TvTextField(
                      controller: pass,
                      autofocus: true,
                      obscureText: true,
                      decoration: InputDecoration(labelText: tr('Password'))),
                  if (problem != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(problem!,
                            style: TextStyle(
                                color: LayoutPalette.of(ctx).accent))),
                ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
            FilledButton(
              onPressed: () async {
                final err = await sync.deleteAccount(pass.text);
                if (!ctx.mounted) return;
                if (err == null) {
                  Navigator.pop(ctx);
                } else {
                  set(() => problem = err);
                }
              },
              child: Text(tr('Delete')),
            ),
          ],
        ),
      ),
    );
  }
}

/// A source that came from another device has no password here: ask for it and keep it on this device only.
Future<void> askSourcePassword(
    BuildContext context, AppState app, Source src) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(trf('Password for "{name}"', {'name': src.name})),
      content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(
                'Passwords are not synced. Enter this source\'s password to use it on this device.')),
            TvTextField(
                controller: c,
                autofocus: true,
                obscureText: true,
                decoration: InputDecoration(labelText: tr('Password'))),
          ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancel'))),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
      ],
    ),
  );
  if (ok == true && c.text.isNotEmpty) await app.setSourcePassword(src, c.text);
}
