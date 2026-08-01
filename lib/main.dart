import 'dart:io';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
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
      supportedLocales: const [Locale('en')],
      path: 'lib/l10n',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
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
      theme: AppTheme.lightTheme,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: child!,
        );
      },
      home: const RootGate(),
    );
  }
}
