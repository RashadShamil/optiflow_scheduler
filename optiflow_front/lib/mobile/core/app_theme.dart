import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// OptiFlow Design System — "Airbnb-style" premium tokens
/// Every color, radius, shadow and text style lives here.
/// ─────────────────────────────────────────────────────────────────────────────
class AppColors {
  AppColors._();

  // ── Surfaces ────────────────────────────────────────────────────────────────
  static const Color background   = Color(0xFFF5F4FA); // Soft lavender-tinted white
  static const Color cardSurface  = Color(0xFFFFFFFF); // Floating card
  static const Color bottomSheet  = Color(0xFFFFFFFF);

  // ── Brand — muted purple/indigo matching the desktop + logo ─────────────────
  // Desktop uses #8B5CF6 (vibrant violet). We tone it down for mobile:
  // a slightly darker, more desaturated indigo that reads as "professional" not "neon".
  static const Color primary      = Color(0xFF7C5DBC); // Muted violet (logo purple, toned down)
  static const Color primaryLight = Color(0xFF9B7FD4); // Lighter tint for hover/accent
  static const Color primaryDark  = Color(0xFF5B3F99); // Deeper shade for pressed states

  // Gradient matching the logo swirl (purple → dusty rose-pink)
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF7C5DBC), Color(0xFFB85BA8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Text ────────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFF1A1730); // Deep navy (not pure black)
  static const Color textSecondary = Color(0xFF6B6882); // Muted slate-purple
  static const Color textDisabled  = Color(0xFFB0AEC4); // Light muted purple-grey

  // ── Status ──────────────────────────────────────────────────────────────────
  static const Color scheduled  = Color(0xFFF5A623); // Warm amber
  static const Color inProgress = Color(0xFF5B8DEF); // Softer blue
  static const Color completed  = Color(0xFF27AE72); // Muted emerald (matches desktop success)
  static const Color offline    = Color(0xFFE05252); // Muted rose-red

  // ── Borders / Dividers ──────────────────────────────────────────────────────
  static const Color divider = Color(0xFFE8E6F0); // Soft purple-tinted divider
}

class AppTheme {
  AppTheme._();

  static const double radiusCard   = 20.0;
  static const double radiusPill   = 32.0;
  static const double radiusSmall  = 12.0;

  /// The universal card shadow — blur 20, opacity 0.05 black
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.05),
      blurRadius: 20,
      spreadRadius: 0,
      offset: const Offset(0, 6),
    ),
  ];

  /// Floating card decoration
  static BoxDecoration cardDecoration({double? radius}) => BoxDecoration(
    color: AppColors.cardSurface,
    borderRadius: BorderRadius.circular(radius ?? radiusCard),
    boxShadow: cardShadow,
  );

  /// Pill-shaped elevated button style (primary purple — matches desktop + logo)
  static ButtonStyle pillButtonStyle({Color? bg, Color? fg}) =>
    ElevatedButton.styleFrom(
      backgroundColor: bg ?? AppColors.primary,
      foregroundColor: fg ?? Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusPill),
      ),
      elevation: 0,
      minimumSize: const Size(double.infinity, 60),
      textStyle: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700),
    );

  /// Soft purple tint decoration used for subtle highlight containers
  static BoxDecoration get primaryTintDecoration => BoxDecoration(
    color: AppColors.primary.withOpacity(0.08),
    borderRadius: BorderRadius.circular(radiusSmall),
  );

  /// Full app ThemeData
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      background: AppColors.background,
    ),
    textTheme: GoogleFonts.interTextTheme().copyWith(
      displayLarge: GoogleFonts.inter(
        fontSize: 36,
        fontWeight: FontWeight.w900,
        color: AppColors.textPrimary,
        letterSpacing: -1.5,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        letterSpacing: -0.5,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.cardSurface,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.textDisabled,
      showUnselectedLabels: false,
      elevation: 0,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable Status Badge Widget
// ─────────────────────────────────────────────────────────────────────────────
class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge({super.key, required this.status});

  Color get _color {
    switch (status.toUpperCase()) {
      case 'SCHEDULED':   return AppColors.scheduled;
      case 'IN_PROGRESS': return AppColors.inProgress;
      case 'COMPLETED':   return AppColors.completed;
      case 'OPEN':        return AppColors.completed;   // green — job is available
      case 'TAKEN':       return AppColors.scheduled;   // amber — job is claimed
      case 'OFFLINE':     return AppColors.offline;
      case 'DRAFT':       return AppColors.textDisabled;
      default:            return AppColors.textDisabled;
    }
  }

  String get _label {
    switch (status.toUpperCase()) {
      case 'TAKEN':       return 'CLAIMED';
      case 'IN_PROGRESS': return 'IN PROGRESS';
      default:            return status.replaceAll('_', ' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _label,
        style: TextStyle(
          color: _color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Pulsing Dot indicator for machine status
// ─────────────────────────────────────────────────────────────────────────────
class PulsingDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulsingDot({super.key, required this.color, this.size = 10});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color.withOpacity(_anim.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Sheet Drag Handle
// ─────────────────────────────────────────────────────────────────────────────
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
