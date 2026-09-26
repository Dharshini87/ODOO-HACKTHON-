import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Core Surfaces matching UI designs
  static const Color canvas = Color(0xFFF8FAFC);
  static const Color panel = Color(0xFFFFFFFF);
  static const Color line = Color(0xFFE2E8F0);
  static const Color charcoal = Color(0xFF0F172A);

  // Dark Navy Hero & Header background (from UI/1.png, UI/8.png, UI/9.png)
  static const Color navyDark = Color(0xFF0C1830);
  static const Color navySurface = Color(0xFF132247);
  static const Color navyBorder = Color(0xFF1E356D);
  static const Color primaryNavy = Color(0xFF1E2B6F); // Primary Button in UI/1.png
  static const Color cardShadow = Color(0x0A0F172A);

  // Typography
  static const Color ink = Color(0xFF0F172A);
  static const Color inkSecondary = Color(0xFF64748B);
  static const Color inkTertiary = Color(0xFF94A3B8);
  static const Color textLight = Color(0xFFFFFFFF);

  // Brand Palette - Modern Teal & Navy (UI/1.png, UI/4.png, UI/8.png)
  static const Color brand = Color(0xFF0D9488);        // Vibrant Teal
  static const Color brandDark = Color(0xFF0F766E);    // Dark Teal
  static const Color brandLight = Color(0xFF14B8A6);   // Bright Teal Accent
  static const Color brandSubtle = Color(0xFFCCFBF1);  // Light Teal tint

  // Accent & Highlights
  static const Color amber = Color(0xFFF59E0B);
  static const Color amberLight = Color(0xFFFEF3C7);
  static const Color blueAccent = Color(0xFF2563EB);
  static const Color blueLight = Color(0xFFDBEAFE);

  // Status Colors (Matching UI status chips: In Stock, Ready, Done, Waiting, Canceled)
  static const Color statusDraft = Color(0xFF64748B);
  static const Color statusDraftBg = Color(0xFFF1F5F9);

  static const Color statusWaiting = Color(0xFFF59E0B);
  static const Color statusWaitingBg = Color(0xFFFEF3C7);

  static const Color statusReady = Color(0xFF0284C7);
  static const Color statusReadyBg = Color(0xFFE0F2FE);

  static const Color statusDone = Color(0xFF10B981);
  static const Color statusDoneBg = Color(0xFFD1FAE5);

  static const Color statusCancelled = Color(0xFFEF4444);
  static const Color statusCancelledBg = Color(0xFFFEE2E2);

  // Inventory Stock Metrics (Section 13 & UI/3.png)
  static const Color onHand = Color(0xFF0F172A);
  static const Color reserved = Color(0xFFF59E0B);
  static const Color freeToUse = Color(0xFF0D9488);

  // Ledger indicators
  static const Color ledgerIncoming = Color(0xFF10B981);
  static const Color ledgerOutgoing = Color(0xFFEF4444);
}
