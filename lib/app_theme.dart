import 'package:flutter/material.dart';

const _darkNavy = Color(0xFF080B10);
const _darkPanel = Color(0xFF1B2B40);
const _darkCard = Color(0xFF162438);
const _lightBackground = Color(0xFFCCD5DF);
const _lightPanel = Color(0xFFE7EDF3);
const _lightCard = Color(0xFFF9FBFD);

class DescentSpyTheme {
  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _darkNavy,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF55D6D2),
      brightness: Brightness.dark,
      surface: _darkPanel,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _darkNavy,
      foregroundColor: Colors.white,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _darkPanel,
      labelStyle: const TextStyle(color: Colors.white70, fontSize: 18),
      hintStyle: const TextStyle(color: Colors.white38),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF55D6D2), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    ),
  );

  static final ThemeData light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: _lightBackground,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF007F83),
      brightness: Brightness.light,
      surface: _lightPanel,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF17212F),
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _lightPanel,
      labelStyle: const TextStyle(color: Color(0xFF425466), fontSize: 18),
      hintStyle: const TextStyle(color: Color(0xFF667586)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF007F83), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    ),
  );
}

extension DescentSpyPalette on BuildContext {
  bool get isDarkPalette => Theme.of(this).brightness == Brightness.dark;

  Color get appBackground => isDarkPalette ? _darkNavy : _lightBackground;

  Color get appPanel => isDarkPalette ? _darkPanel : _lightPanel;

  Color get appCard => isDarkPalette ? _darkCard : _lightCard;

  Color get appAccent =>
      isDarkPalette ? const Color(0xFF55D6D2) : const Color(0xFF007F83);

  Color get appWarning =>
      isDarkPalette ? const Color(0xFFFFC857) : const Color(0xFF8B5C00);

  Color get appText => isDarkPalette ? Colors.white : const Color(0xFF17212F);

  Color get appSecondaryText =>
      isDarkPalette ? Colors.white70 : const Color(0xFF425466);

  Color get appMutedText =>
      isDarkPalette ? Colors.white60 : const Color(0xFF526273);

  Color get appFaintText =>
      isDarkPalette ? Colors.white54 : const Color(0xFF667586);

  Color get appHintText =>
      isDarkPalette ? Colors.white38 : const Color(0xFF8290A0);
}
