import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api/client.dart';
import 'api/share_source.dart';
import 'l10n/app_localizations.dart';
import 'screens/home_screen.dart';

class PravdomerApp extends StatelessWidget {
  const PravdomerApp({super.key, required this.client, this.shareSource});

  final PravdomerClient client;
  final ShareSource? shareSource;

  static ThemeData _theme(Brightness b) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF3E6A6B),
      brightness: b,
    ),
    useMaterial3: true,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (c) => AppLocalizations.of(c).appTitle,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomeScreen(client: client, shareSource: shareSource),
    );
  }
}
