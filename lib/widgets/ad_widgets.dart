// lib/widgets/ad_widgets.dart
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_manager.dart';

// ─────────────────────────────────────────────────────────────────
// BANNER AD WIDGET
// Drop this anywhere — shows banner if loaded, shrinks to 0 if not
// ─────────────────────────────────────────────────────────────────
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _checkReady();
  }

  void _checkReady() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _ready = AdManager.instance.bannerReady);
      if (!_ready) _checkReady(); // poll until ready
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || AdManager.instance.bannerAd == null) {
      return const SizedBox.shrink();
    }
    return Container(
      alignment: Alignment.center,
      color: Colors.grey.shade100,
      width: AdSize.banner.width.toDouble(),
      height: AdSize.banner.height.toDouble(),
      child: AdWidget(ad: AdManager.instance.bannerAd!),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// NATIVE AD WIDGET
// Shows native ad card inline (e.g. in DTC list or Live Data list)
// ─────────────────────────────────────────────────────────────────
class NativeAdWidget extends StatefulWidget {
  const NativeAdWidget({super.key});

  @override
  State<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends State<NativeAdWidget> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _checkReady();
  }

  void _checkReady() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _ready = AdManager.instance.nativeReady);
      if (!_ready) _checkReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || AdManager.instance.nativeAd == null) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      height: 85,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey.shade100,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AdWidget(ad: AdManager.instance.nativeAd!),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// REWARDED AD BUTTON
// Shows a button — tap it, watch ad, get reward (unlock feature)
// ─────────────────────────────────────────────────────────────────
class RewardedAdButton extends StatefulWidget {
  final String label;
  final String rewardLabel; // shown after reward earned
  final VoidCallback onReward;
  final Color color;

  const RewardedAdButton({
    super.key,
    required this.label,
    required this.rewardLabel,
    required this.onReward,
    this.color = const Color(0xFF1565C0),
  });

  @override
  State<RewardedAdButton> createState() => _RewardedAdButtonState();
}

class _RewardedAdButtonState extends State<RewardedAdButton> {
  bool _rewarded = false;

  void _onTap() {
    AdManager.instance.showRewarded(
      onReward: () {
        setState(() => _rewarded = true);
        widget.onReward();
      },
      onNotReady: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ad not ready yet, please try again in a moment'),
            duration: Duration(seconds: 2),
          ),
        );
        // Try to preload
        AdManager.instance.loadRewarded();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _rewarded ? null : _onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: _rewarded ? Colors.green : widget.color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: (_rewarded ? Colors.green : widget.color).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _rewarded ? Icons.check_circle : Icons.play_circle_filled,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              _rewarded ? widget.rewardLabel : widget.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// AD DIALOG — shown before a premium feature
// User must watch rewarded ad to unlock
// ─────────────────────────────────────────────────────────────────
class AdGateDialog extends StatelessWidget {
  final String featureName;
  final String featureDescription;
  final IconData featureIcon;
  final VoidCallback onUnlocked;

  const AdGateDialog({
    super.key,
    required this.featureName,
    required this.featureDescription,
    required this.featureIcon,
    required this.onUnlocked,
  });

  static Future<void> show(
    BuildContext context, {
    required String featureName,
    required String featureDescription,
    required IconData featureIcon,
    required VoidCallback onUnlocked,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdGateDialog(
        featureName: featureName,
        featureDescription: featureDescription,
        featureIcon: featureIcon,
        onUnlocked: () {
          Navigator.pop(context);
          onUnlocked();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(featureIcon, size: 40, color: Colors.blue.shade700),
          ),
          const SizedBox(height: 16),
          Text(
            featureName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            featureDescription,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          // Watch ad button
          RewardedAdButton(
            label: '▶  Watch Ad to Unlock (Free)',
            rewardLabel: '✅ Unlocked!',
            onReward: onUnlocked,
            color: Colors.blue.shade700,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Not now', style: TextStyle(color: Colors.grey.shade500)),
          ),
        ],
      ),
    );
  }
}