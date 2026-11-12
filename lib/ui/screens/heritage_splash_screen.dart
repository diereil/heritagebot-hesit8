import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../widgets/heritagebot_logo.dart';
import 'heritage_intro_screen.dart';

class HeritageSplashScreen extends StatefulWidget {
  final Widget nextScreen;

  const HeritageSplashScreen({super.key, required this.nextScreen});

  @override
  State<HeritageSplashScreen> createState() => _HeritageSplashScreenState();
}

class _HeritageSplashScreenState extends State<HeritageSplashScreen> {
  int _stage = 0;

  @override
  void initState() {
    super.initState();
    _playIntroSequence();
  }

  Future<void> _playIntroSequence() async {
    await Future<void>.delayed(const Duration(milliseconds: 1050));
    if (!mounted) return;

    setState(() => _stage = 1);

    await Future<void>.delayed(const Duration(milliseconds: 1350));
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: HeritageIntroScreen(nextScreen: widget.nextScreen),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepBrown,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 650),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _stage == 0
            ? const _LogoSplash(key: ValueKey('logo'))
            : const _BrandSplash(key: ValueKey('brand')),
      ),
    );
  }
}

class _LogoSplash extends StatelessWidget {
  const _LogoSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFF160D08),
      alignment: Alignment.center,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.72, end: 1),
        duration: const Duration(milliseconds: 850),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) {
          return Transform.scale(scale: scale, child: child);
        },
        child: const HeritageBotLogo(size: 122, showName: false),
      ),
    );
  }
}

class _BrandSplash extends StatelessWidget {
  const _BrandSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('heritage-brand'),
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2B160C), AppColors.brown, Color(0xFF8A552F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -70,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withValues(alpha: 0.13),
              ),
            ),
          ),
          Positioned(
            bottom: -110,
            left: -70,
            child: Container(
              width: 290,
              height: 290,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 850),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 18 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HeritageBotLogo(
                      size: 118,
                      showName: true,
                      nameFontSize: 36,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'DISCOVER  •  LISTEN  •  REMEMBER',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3,
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
}
