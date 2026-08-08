import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/root_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Enable SQLite on Windows/Linux desktop for development/testing.
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await EasyLocalization.ensureInitialized();

  runApp(
    EasyLocalization(
      // Urdu used to be listed nowhere, so every translated string in ur.json
      // was unreachable no matter what the tailor did. Both languages are now
      // selectable from Settings.
      supportedLocales: const [Locale('en'), Locale('ur')],
      path: 'lib/l10n',
      fallbackLocale: const Locale('en'),
      // English on a fresh install; `saveLocale` means a tailor who switches to
      // Urdu stays in Urdu on every later launch.
      startLocale: const Locale('en'),
      saveLocale: true,
      child: const EzeeBookApp(),
    ),
  );
}

class EzeeBookApp extends StatelessWidget {
  const EzeeBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EzeeBook',
      debugShowCheckedModeBanner: false,
      // Urdu is right-to-left and needs its own font. Both follow from the
      // locale now — the app used to force LTR for everything, which would
      // have rendered Urdu backwards even if it had been reachable.
      theme: AppTheme.forLocale(context.locale),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: const RootGate(),
    );
  }
}
