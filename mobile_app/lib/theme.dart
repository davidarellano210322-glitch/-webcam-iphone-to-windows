// ============================================================================
// TEMA NEOCAMO - Sistema de Diseño Profesional
// Paleta, tipografía, espaciado, sombras y utilidades de estilo
// Basado en: Material Design 3 + Diseño NeoCamo original
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ═════════════════════════════════════════════════════════════════════════════
// PALETA DE COLORES NEOCAMO (fiel al diseño original HTML)
// ═════════════════════════════════════════════════════════════════════════════
abstract class NC {
  // Fondos
  static const bg = Color(0xFF131315);
  static const surface = Color(0xFF131315);
  static const surfaceContainer = Color(0xFF1F1F21);
  static const surfaceContainerLow = Color(0xFF1B1B1D);
  static const surfaceContainerHigh = Color(0xFF2A2A2C);
  static const surfaceContainerHighest = Color(0xFF353437);
  static const surfaceBright = Color(0xFF39393B);
  static const surfaceContainerLowest = Color(0xFF0E0E10);
  static const surfaceVariant = Color(0xFF353437);

  // Primario (verde neón característico)
  static const primary = Color(0xFF55EE71);
  static const primaryGlow = Color(0x4055EE71);
  static const primaryContainer = Color(0xFF30D158);
  static const primaryFixed = Color(0xFF6CFF82);
  static const primaryFixedDim = Color(0xFF47E266);
  static const inversePrimary = Color(0xFF006E26);
  static const onPrimary = Color(0xFF003910);
  static const onPrimaryContainer = Color(0xFF00541B);
  static const onPrimaryFixed = Color(0xFF002106);
  static const onPrimaryFixedVariant = Color(0xFF00531A);

  // Secundario (azul claro)
  static const secondary = Color(0xFFAAC7FF);
  static const secondaryContainer = Color(0xFF3E90FF);
  static const secondaryFixed = Color(0xFFD6E3FF);
  static const secondaryFixedDim = Color(0xFFAAC7FF);
  static const onSecondary = Color(0xFF003064);
  static const onSecondaryContainer = Color(0xFF002957);
  static const onSecondaryFixed = Color(0xFF001B3E);
  static const onSecondaryFixedVariant = Color(0xFF00468D);

  // Terciario (salmón)
  static const tertiary = Color(0xFFFFC4BA);
  static const tertiaryContainer = Color(0xFFFF9C8C);
  static const tertiaryFixed = Color(0xFFFFDAD4);
  static const tertiaryFixedDim = Color(0xFFFFB4A8);
  static const onTertiary = Color(0xFF5A1B12);
  static const onTertiaryContainer = Color(0xFF783127);
  static const onTertiaryFixed = Color(0xFF3D0602);
  static const onTertiaryFixedVariant = Color(0xFF773026);

  // Errores
  static const error = Color(0xFFFFB4AB);
  static const errorContainer = Color(0xFF93000A);
  static const onError = Color(0xFF690005);
  static const onErrorContainer = Color(0xFFFFDAD6);
  static const red = Color(0xFFDC2626);
  static const redGlow = Color(0x80DC2626);

  // Texto / superficie
  static const onSurface = Color(0xFFE4E2E4);
  static const onSurfaceVariant = Color(0xFFBCCBB7);
  static const outline = Color(0xFF869583);
  static const outlineVariant = Color(0xFF3D4A3B);
  static const inverseOnSurface = Color(0xFF303032);
  static const inverseSurface = Color(0xFFE4E2E4);
  static const background = Color(0xFF131315);
  static const onBackground = Color(0xFFE4E2E4);

  // Blancos con opacidad
  static const white05 = Color(0x0DFFFFFF);
  static const white10 = Color(0x1AFFFFFF);
  static const white20 = Color(0x33FFFFFF);
  static const white40 = Color(0x66FFFFFF);

  // Sombra tint (para elevation)
  static const surfaceTint = Color(0xFF47E266);
}

// ═════════════════════════════════════════════════════════════════════════════
// TIPOGRAFÍA NEOCAMO (vía Google Fonts para compatibilidad)
// ═════════════════════════════════════════════════════════════════════════════
class NCTypography {
  // Hanken Grotesk → headlines, títulos
  static TextStyle displayLg = GoogleFonts.hankenGrotesk(
    fontSize: 48,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.02,
    height: 56 / 48,
    color: NC.onSurface,
  );
  static TextStyle headlineMd = GoogleFonts.hankenGrotesk(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.01,
    height: 32 / 24,
    color: NC.onSurface,
  );
  static TextStyle headlineSm = GoogleFonts.hankenGrotesk(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 28 / 20,
    color: NC.onSurface,
  );

  // Inter → cuerpo de texto
  static TextStyle bodyLg = GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    color: NC.onSurface,
  );
  static TextStyle bodySm = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    color: NC.onSurfaceVariant,
  );

  // Geist → mono-espaciado, etiquetas técnicas, telemetría
  static TextStyle monoLabel = GoogleFonts.getFont(
    'Geist',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.05,
    height: 16 / 12,
    color: NC.onSurfaceVariant,
  );
  static TextStyle monoS = GoogleFonts.getFont(
    'Geist',
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.05,
    height: 14 / 10,
    color: NC.onSurface,
  );
  static TextStyle monoXs = GoogleFonts.getFont(
    'Geist',
    fontSize: 9,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.02,
    color: NC.onSurfaceVariant,
  );
  static TextStyle monoXxs = GoogleFonts.getFont(
    'Geist',
    fontSize: 8,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.05,
    color: Colors.white38,
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// ESPACIADO Y RADIOS CONSTANTES
// ═════════════════════════════════════════════════════════════════════════════
class NCSpacing {
  static const unit = 4.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

class NCRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const full = 9999.0;
}

// ═════════════════════════════════════════════════════════════════════════════
// SOMBRAS Y EFECTOS DE CRISTAL (glassmorphism)
// ═════════════════════════════════════════════════════════════════════════════
class NCGlass {
  static BoxDecoration panel({
    Color bg = NC.surfaceContainerLow,
    double opacity = 0.7,
    double blur = 20.0,
    Color borderColor = NC.white10,
  }) {
    return BoxDecoration(
      color: bg.withOpacity(opacity),
      borderRadius: BorderRadius.circular(NCRadius.md),
      border: Border.all(color: borderColor),
    );
  }

  static BoxDecoration pill({
    Color bg = NC.surfaceContainerLow,
    double opacity = 0.6,
    Color borderColor = NC.white10,
  }) {
    return BoxDecoration(
      color: bg.withOpacity(opacity),
      borderRadius: BorderRadius.circular(NCRadius.full),
      border: Border.all(color: borderColor),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// BOTÓN DE BRILLO / GLOW (para botón REC, botones primarios)
// ═════════════════════════════════════════════════════════════════════════════
BoxShadow ncGlow(Color color, {double blur = 15, double opacity = 0.4}) {
  return BoxShadow(color: color.withOpacity(opacity), blurRadius: blur);
}
