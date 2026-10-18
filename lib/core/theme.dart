import 'package:flutter/material.dart';

/// Matcha palette from the original app.
class C {
  static const bg = Color(0xFFEDF1E1);
  static const bgDeep = Color(0xFFE1E8D0);
  static const well = Color(0xFFE3EAD3);
  static const card = [Color(0xFFFBFCF4), Color(0xFFEBF0DC)];
  static const matcha = [Color(0xFF9DBA72), Color(0xFF6F8F45)];
  static const matchaFlat = Color(0xFF7E9C54);
  static const matchaDeep = Color(0xFF4F6B2C);
  static const matchaInk = Color(0xFF34471D);
  static const mist = Color(0xFFDCE7C3);
  static const latte = Color(0xFFEADFC6);
  static const ink = Color(0xFF2A3320);
  static const mute = Color(0xFF7D8869);
  static const faint = Color(0xFFA7B190);
  static const shadow = Color(0xFF58703A);
  static const temp = Color(0xFFCF8A52);
  static const hum = Color(0xFF6E9EA3);
  static const soil = Color(0xFF5F7F3A);
  static const ok = Color(0xFF6F8F45);
  static const warn = Color(0xFFC98A3C);
  static const bad = Color(0xFFB45742);
  static const info = Color(0xFF6E9EA3);
}

/// Colour with a given opacity (0..1) without the deprecated withOpacity.
Color a(Color c, double o) => c.withAlpha((o.clamp(0.0, 1.0) * 255).round());

const _weights = {
  'reg': FontWeight.w500,
  'semi': FontWeight.w600,
  'bold': FontWeight.w700,
  'black': FontWeight.w800,
};

TextStyle ts(double s, [Color c = C.ink, String f = 'semi', double? ls, double? h]) => TextStyle(
      fontFamily: 'Nunito',
      fontSize: s,
      color: c,
      fontWeight: _weights[f] ?? FontWeight.w600,
      letterSpacing: ls,
      height: h,
    );

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      fontFamily: 'Nunito',
      scaffoldBackgroundColor: C.bg,
      colorScheme: ColorScheme.fromSeed(seedColor: C.matchaFlat, surface: C.bg),
      splashFactory: NoSplash.splashFactory,
      textSelectionTheme: const TextSelectionThemeData(cursorColor: C.matchaFlat),
    );
