import 'package:flutter/material.dart';

class AppColors {
  // ── Brand ─────────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF8B5CF6); // Vibrant Purple
  static const Color secondary = Color(0xFFA78BFA); // Soft Purple

  // ── Precision SaaS Matte Accents ──────────────────────────────────────────
  /// ACTIVE machines / Success — Sage Green
  static const Color matteGreen = Color(0xFF5E8B7E);

  /// IDLE machines / Warning — Burnt Orange
  static const Color matteAmber = Color(0xFFA86946);

  /// Bottleneck / OFFLINE — Brick Red
  static const Color matteRed = Color(0xFFA34A4A);

  /// Scheduled / PENDING — Slate Blue
  static const Color matteBlue = Color(0xFF53687E);

  // ── Graphite Background System ────────────────────────────────────────────
  /// Base shell background
  static const Color background = Color(0xFF141518);

  /// Elevated panel/sidebar surface
  static const Color surface = Color(0xFF1A1B1E);

  /// Card / widget surface
  static const Color surfaceCard = Color(0xFF1C1C1E);

  /// Hover / active surface
  static const Color surfaceLight = Color(0xFF2C2C2E);

  /// Hairline 1px borders
  static const Color border = Color(0xFF2C2C2E);

  // ── Text ─────────────────────────────────────────────────────────────────
  /// High legibility primary text
  static const Color textPrimary = Color(0xFFF5F5F7);

  /// Standard secondary text (labels, subtitles)
  static const Color textSecondary = Color(0xFF8E8E93);

  /// Muted / disabled text
  static const Color textMuted = Color(0xFF636366);

  // ── Semantic Aliases ──────────────────────────────────────────────────────
  static const Color success = matteGreen;
  static const Color error = matteRed;
  static const Color warning = matteAmber;
  static const Color info = matteBlue;

  // ── Gradients ─────────────────────────────────────────────────────────────
  // (Removed neon gradients; using solid/matte colors or very subtle gradients)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, Color(0xFF4C55AC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Machine status color helper ───────────────────────────────────────────
  static Color machineStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        return matteGreen;
      case 'IDLE':
        return matteAmber;
      case 'OFFLINE':
        return matteRed;
      case 'MAINTENANCE':
        return matteBlue;
      default:
        return textSecondary;
    }
  }
}
