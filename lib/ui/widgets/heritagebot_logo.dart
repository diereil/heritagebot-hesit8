import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class HeritageBotLogo extends StatelessWidget {
  final double size;
  final bool showName;
  final Color nameColor;
  final double nameFontSize;

  const HeritageBotLogo({
    super.key,
    this.size = 110,
    this.showName = true,
    this.nameColor = Colors.white,
    this.nameFontSize = 30,
  });

  @override
  Widget build(BuildContext context) {
    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/images/heritagebot_logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.clay,
            borderRadius: BorderRadius.circular(size * 0.22),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.auto_stories_rounded,
            size: size * 0.52,
            color: AppColors.deepBrown,
          ),
        ),
      ),
    );

    if (!showName) return logo;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        const SizedBox(height: 16),
        Text(
          'HeritageBot',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: nameColor,
            fontSize: nameFontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
