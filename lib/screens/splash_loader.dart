import 'dart:math' as math;
import 'package:flutter/material.dart';

class AppSplashLoader extends StatefulWidget {
  final Future<void> syncFuture;
  final VoidCallback onFinished;

  const AppSplashLoader({
    super.key,
    required this.syncFuture,
    required this.onFinished,
  });

  @override
  State<AppSplashLoader> createState() => _AppSplashLoaderState();
}

class _AppSplashLoaderState extends State<AppSplashLoader> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _expandController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _expandAnimation;
  
  bool _isExpanding = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _expandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _expandAnimation = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeInOutCubic,
    );

    _startSyncTimer();
  }

  void _startSyncTimer() async {
    final startTime = DateTime.now();
    
    // Wait for the sync to complete
    try {
      await widget.syncFuture.timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('Splash sync error/timeout: $e');
    }

    // Ensure splash is visible for at least 1.5 seconds for visual stability and premium feel
    final elapsed = DateTime.now().difference(startTime);
    final remaining = const Duration(milliseconds: 1500) - elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }

    if (mounted) {
      setState(() {
        _isExpanding = true;
      });
      _pulseController.stop();
      _expandController.forward().then((_) {
        widget.onFinished();
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _expandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Choose a premium pastel color from the palette, e.g. Lavender (0xFFCE93D8)
    const Color pastelBg = Color(0xFFCE93D8);
    const Color homeBg = Color(0xFFF8FAFC); // Matches HomeScreen background

    return Stack(
      children: [
        // Pastel background
        Container(
          color: pastelBg,
          width: double.infinity,
          height: double.infinity,
        ),
        
        // Expanding circle transition
        if (_isExpanding)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _expandAnimation,
              builder: (context, child) {
                return CustomPaint(
                  painter: CircleExpansionPainter(
                    progress: _expandAnimation.value,
                    circleColor: homeBg,
                  ),
                );
              },
            ),
          ),

        // Central loader (fade out when expanding)
        if (!_isExpanding)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(pastelBg),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Syncing your notes...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class CircleExpansionPainter extends CustomPainter {
  final double progress;
  final Color circleColor;

  CircleExpansionPainter({
    required this.progress,
    required this.circleColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = circleColor
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    // The maximum radius needed to cover the entire screen is the distance from center to any corner
    final double maxRadius = math.sqrt(size.width * size.width + size.height * size.height) / 2;
    final double radius = maxRadius * progress;

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant CircleExpansionPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.circleColor != circleColor;
  }
}
