// lib/services/ad_manager.dart
import 'dart:io';
import 'dart:ui';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────
// 🔴 REPLACE THESE WITH YOUR REAL ADMOB IDs BEFORE PUBLISHING
//    Get IDs from: apps.admob.com → Apps → Add App → Get Ad Unit
// ─────────────────────────────────────────────────────────────────
class AdIds {
  static const bool _useTestIds = true; // ← Set false when publishing

  // APP ID  → goes in AndroidManifest.xml  (not here)
  // For testing app id: ca-app-pub-3940256099942544~3347511713

  static String get banner {
    if (_useTestIds) return 'ca-app-pub-3940256099942544/6300978111';
    return Platform.isAndroid
        ? 'ca-app-pub-2221858776975716/5214654143'  // ← your banner id
        : 'ca-app-pub-2221858776975716/5214654143';
  }

  static String get rewarded {
    if (_useTestIds) return 'ca-app-pub-3940256099942544/5224354917';
    return Platform.isAndroid
        ? 'ca-app-pub-2221858776975716/5134763092'  // ← your rewarded id
        : 'ca-app-pub-2221858776975716/5134763092';
  }

  static String get interstitial {
    if (_useTestIds) return 'ca-app-pub-3940256099942544/1033173712';
    return Platform.isAndroid
        ? 'ca-app-pub-2221858776975716/6365606799'  // ← your interstitial id
        : 'ca-app-pub-2221858776975716/6365606799';
  }

  static String get native {
    if (_useTestIds) return 'ca-app-pub-3940256099942544/2247696110';
    return Platform.isAndroid
        ? 'ca-app-pub-2221858776975716/1548035590'  // ← your native id
        : 'ca-app-pub-2221858776975716/1548035590';
  }
}

// ─────────────────────────────────────────────────────────────────
// CENTRAL AD MANAGER — singleton
// ─────────────────────────────────────────────────────────────────
class AdManager {
  AdManager._();
  static final AdManager instance = AdManager._();

  BannerAd? _bannerAd;
  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  NativeAd? _nativeAd;

  bool _bannerReady = false;
  bool _interstitialReady = false;
  bool _rewardedReady = false;
  bool _nativeReady = false;

  bool get bannerReady => _bannerReady;
  bool get rewardedReady => _rewardedReady;
  bool get nativeReady => _nativeReady;

  BannerAd? get bannerAd => _bannerAd;
  NativeAd? get nativeAd => _nativeAd;

  // ── INIT ──────────────────────────────────────────────────────
  Future<void> initialize() async {
    await MobileAds.instance.initialize();
    // Load all ad types right away
    loadBanner();
    loadInterstitial();
    loadRewarded();
    loadNative();
  }

  // ── BANNER ────────────────────────────────────────────────────
  void loadBanner() {
    _bannerAd?.dispose();
    _bannerReady = false;
    _bannerAd = BannerAd(
      adUnitId: AdIds.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => _bannerReady = true,
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner failed: $error');
          ad.dispose();
          _bannerReady = false;
          // Retry after 30s
          Future.delayed(const Duration(seconds: 30), loadBanner);
        },
      ),
    )..load();
  }

  // ── INTERSTITIAL ──────────────────────────────────────────────
  void loadInterstitial() {
    _interstitialReady = false;
    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _interstitialReady = true;
          _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialReady = false;
              loadInterstitial(); // preload next
            },
            onAdFailedToShowFullScreenContent: (ad, _) {
              ad.dispose();
              _interstitialReady = false;
              loadInterstitial();
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint('Interstitial failed: $error');
          Future.delayed(const Duration(seconds: 30), loadInterstitial);
        },
      ),
    );
  }

  void showInterstitial() {
    if (_interstitialReady && _interstitialAd != null) {
      _interstitialAd!.show();
    }
  }

  // ── REWARDED ──────────────────────────────────────────────────
  void loadRewarded() {
    _rewardedReady = false;
    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _rewardedReady = true;
          _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _rewardedReady = false;
              loadRewarded(); // preload next
            },
            onAdFailedToShowFullScreenContent: (ad, _) {
              ad.dispose();
              _rewardedReady = false;
              loadRewarded();
            },
          );
        },
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded failed: $error');
          Future.delayed(const Duration(seconds: 30), loadRewarded);
        },
      ),
    );
  }

  // onReward → callback when user finishes watching
  void showRewarded({required VoidCallback onReward, VoidCallback? onNotReady}) {
    if (_rewardedReady && _rewardedAd != null) {
      _rewardedAd!.show(
        onUserEarnedReward: (_, reward) => onReward(),
      );
    } else {
      onNotReady?.call();
    }
  }

  // ── NATIVE ────────────────────────────────────────────────────
  void loadNative() {
    _nativeAd?.dispose();
    _nativeReady = false;
    _nativeAd = NativeAd(
      adUnitId: AdIds.native,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) => _nativeReady = true,
        onAdFailedToLoad: (ad, error) {
          debugPrint('Native failed: $error');
          ad.dispose();
          _nativeReady = false;
          Future.delayed(const Duration(seconds: 30), loadNative);
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: const Color(0xFFF5F5F5),
        cornerRadius: 12,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFFFFFFFF),
          backgroundColor: const Color(0xFF1565C0),
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFF000000),
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFF555555),
          style: NativeTemplateFontStyle.normal,
          size: 12,
        ),
      ),
    )..load();
  }

  void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
    _nativeAd?.dispose();
  }
}