import 'package:flutter/material.dart';

const ink = Color(0xFF141820);
const mutedInk = Color(0xFF687080);
const surface = Color(0xFFF5F6F8);
const accent = Color(0xFFF4B740);

IconData categoryIcon(String category) {
  return switch (category) {
    'GPUs' => Icons.videogame_asset_outlined,
    'CPUs' => Icons.memory,
    'Motherboards' => Icons.developer_board_outlined,
    'Memory' => Icons.storage,
    'Storage' => Icons.sd_storage_outlined,
    'Power Supplies' => Icons.bolt,
    _ => Icons.devices_other,
  };
}

final dataBeeTheme = ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: surface,
  colorScheme: ColorScheme.fromSeed(
    seedColor: ink,
    primary: ink,
    secondary: accent,
    surface: Colors.white,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: surface,
    foregroundColor: ink,
    elevation: 0,
    centerTitle: false,
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    margin: EdgeInsets.zero,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
);
