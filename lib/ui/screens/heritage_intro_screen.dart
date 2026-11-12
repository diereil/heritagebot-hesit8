import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class HeritageIntroSlide {
  final String eyebrow;
  final String title;
  final String description;
  final String imageFileName;

  const HeritageIntroSlide({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.imageFileName,
  });

  String get imageUrl =>
      'https://commons.wikimedia.org/wiki/Special:FilePath/${Uri.encodeComponent(imageFileName)}';
}

class HeritageIntroScreen extends StatefulWidget {
  final Widget nextScreen;

  const HeritageIntroScreen({super.key, required this.nextScreen});

  @override
  State<HeritageIntroScreen> createState() => _HeritageIntroScreenState();
}

class _HeritageIntroScreenState extends State<HeritageIntroScreen> {
  final PageController _controller = PageController();
  int _page = 0;
  bool _finishing = false;

  static const List<HeritageIntroSlide> _slides = [
    HeritageIntroSlide(
      eyebrow: 'DISCOVER CEBU',
      title: 'History is closer than you think.',
      description:
          'Explore meaningful heritage places and understand the people, events, and memories that shaped Cebu.',
      imageFileName: 'Night shot of Casa Gorordo.jpg',
    ),
    HeritageIntroSlide(
      eyebrow: 'HEAR THE STORY',
      title: 'Let the past speak to you.',
      description:
          'HeritageBot turns verified historical information into clear AI-guided narratives in your preferred language.',
      imageFileName: 'Casa Gorordo Museum 10.jpg',
    ),
    HeritageIntroSlide(
      eyebrow: 'EXPLORE IN PLACE',
      title: 'Walk into Cebu’s living history.',
      description:
          'Use geolocation and in-app navigation to reach heritage sites, then unlock their stories when you arrive.',
      imageFileName: 'Fort San Pedro, Cebu City.jpg',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_page < _slides.length - 1) {
      await _controller.nextPage(
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    if (_finishing) return;
    setState(() => _finishing = true);

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, animation, __) =>
            FadeTransition(opacity: animation, child: widget.nextScreen),
      ),
    );
  }

  Future<void> _previous() async {
    if (_page == 0) return;
    await _controller.previousPage(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _controller,
        itemCount: _slides.length,
        onPageChanged: (value) => setState(() => _page = value),
        itemBuilder: (context, index) {
          final slide = _slides[index];
          final isLast = index == _slides.length - 1;

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                slide.imageUrl,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) {
                  return Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.brown, AppColors.deepBrown],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.account_balance_rounded,
                        color: AppColors.gold,
                        size: 90,
                      ),
                    ),
                  );
                },
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0x22000000),
                      Color(0x33000000),
                      Color(0xE6000000),
                    ],
                    stops: [0, 0.42, 1],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 48,
                        child: index == 0
                            ? const SizedBox.shrink()
                            : TextButton.icon(
                                onPressed: _previous,
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.zero,
                                ),
                                icon: const Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  size: 17,
                                ),
                                label: const Text(
                                  'Back',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.gold.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          slide.eyebrow,
                          style: const TextStyle(
                            color: AppColors.gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.25,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        slide.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          height: 1.08,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        slide.description,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          height: 1.55,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          ...List.generate(
                            _slides.length,
                            (dotIndex) => AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              width: dotIndex == index ? 28 : 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: 7),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(99),
                                color: dotIndex == index
                                    ? AppColors.gold
                                    : Colors.white38,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${index + 1}/${_slides.length}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _finishing ? null : _continue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            foregroundColor: AppColors.deepBrown,
                            disabledBackgroundColor: AppColors.gold.withValues(
                              alpha: 0.65,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _finishing
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: AppColors.deepBrown,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      isLast ? 'Start HeritageBot' : 'Continue',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      isLast
                                          ? Icons.travel_explore_rounded
                                          : Icons.arrow_forward_rounded,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
