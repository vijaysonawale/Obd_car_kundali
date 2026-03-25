// lib/widgets/exit_dialog.dart
//
// SETUP:
//   pubspec.yaml — add these if not already present:
//     in_app_review: ^2.0.9
//     share_plus: ^10.0.0        ← already used in trip_screen.dart ✅
//     url_launcher: ^6.3.0
//
//   Then run: flutter pub get
//
// USAGE — wrap your HomeScreen Scaffold with PopScope (see home_screen patch).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class ExitDialog {
  ExitDialog._();

  static const _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.nextintinc.car_kundali';

  static const _shareText =
      '🚗 Check out Car Kundali — the best OBD2 scanner app for your car!\n'
      'Read live engine data, scan fault codes, trip stats & more.\n'
      '👉 $_playStoreUrl';

  // ── Show the dialog. Returns true when user confirms exit. ──────
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (_) => const _ExitDialogWidget(),
    );
    return result ?? false;
  }

  // ── Rating ──────────────────────────────────────────────────────
  static Future<void> openRating() async {
    final review = InAppReview.instance;
    try {
      if (await review.isAvailable()) {
        await review.requestReview();
        return;
      }
    } catch (_) {}
    final url = Uri.parse(_playStoreUrl);
    if (await canLaunchUrl(url)) {
      launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // ── Share ───────────────────────────────────────────────────────
  static Future<void> shareApp() async {
    await Share.share(_shareText, subject: 'Car Kundali — OBD2 Scanner App');
  }
}

// ─────────────────────────────────────────────────────────────────
// DIALOG WIDGET
// ─────────────────────────────────────────────────────────────────
class _ExitDialogWidget extends StatefulWidget {
  const _ExitDialogWidget();
  @override
  State<_ExitDialogWidget> createState() => _ExitDialogWidgetState();
}

class _ExitDialogWidgetState extends State<_ExitDialogWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _scaleAnim =
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _fadeAnim =
        CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // Close dialog and return a value
  void _pop(bool exit) => Navigator.of(context, rootNavigator: true).pop(exit);

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: _buildCard(),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F0F28), Color(0xFF1C1C3A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          _buildDivider(),
          _buildActionButtons(),
          _buildDivider(),
          _buildExitCancelRow(),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      child: Column(
        children: [
          // Car icon with glow
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00B4FF).withOpacity(0.12),
              border: Border.all(
                  color: const Color(0xFF00B4FF).withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00B4FF).withOpacity(0.2),
                  blurRadius: 18,
                ),
              ],
            ),
            child: const Icon(Icons.directions_car_rounded,
                size: 34, color: Color(0xFF00B4FF)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Leaving so soon? 👋',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Before you go — help Car Kundali grow!',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 13,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Rate + Share buttons ────────────────────────────────────────
  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        children: [
          // ── RATE US ──
          _ActionTile(
            icon: Icons.star_rounded,
            iconColor: Colors.amber,
            bgColor: Colors.amber.withOpacity(0.12),
            borderColor: Colors.amber.withOpacity(0.3),
            title: 'Rate Car Kundali ⭐',
            subtitle: 'Takes 10 sec — helps us reach more drivers',
            onTap: () async {
              _pop(false); // keep app open
              await ExitDialog.openRating();
            },
          ),
          const SizedBox(height: 10),
          // ── SHARE APP ──
          _ActionTile(
            icon: Icons.share_rounded,
            iconColor: const Color(0xFF00FF9C),
            bgColor: const Color(0xFF00FF9C).withOpacity(0.10),
            borderColor: const Color(0xFF00FF9C).withOpacity(0.3),
            title: 'Share with Friends 🚀',
            subtitle: 'Recommend to other car owners',
            onTap: () async {
              _pop(false); // keep app open, share sheet opens
              await ExitDialog.shareApp();
            },
          ),
        ],
      ),
    );
  }

  // ── Exit / Cancel row ───────────────────────────────────────────
  Widget _buildExitCancelRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Row(
        children: [
          // Stay button
          Expanded(
            child: GestureDetector(
              onTap: () => _pop(false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_back_rounded,
                        color: Colors.white.withOpacity(0.7), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Stay',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Exit button
          Expanded(
            child: GestureDetector(
              onTap: () => _pop(true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.red.withOpacity(0.35)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.exit_to_app_rounded,
                        color: Colors.red.shade300, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Exit App',
                      style: TextStyle(
                        color: Colors.red.shade300,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() => Divider(
        height: 1,
        thickness: 1,
        color: Colors.white.withOpacity(0.06),
      );
}

// ─────────────────────────────────────────────────────────────────
// REUSABLE ACTION TILE
// ─────────────────────────────────────────────────────────────────
class _ActionTile extends StatefulWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final Color borderColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.borderColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _pressed
              ? widget.bgColor.withOpacity(0.4)
              : widget.bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: widget.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: widget.iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(widget.icon, color: widget.iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.white.withOpacity(0.2), size: 20),
          ],
        ),
      ),
    );
  }
}