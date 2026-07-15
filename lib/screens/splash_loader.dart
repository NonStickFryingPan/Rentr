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

class _AppSplashLoaderState extends State<AppSplashLoader> with SingleTickerProviderStateMixin {
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  
  bool _isExpanding = false;

  @override
  void initState() {
    super.initState();
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
      _expandController.forward().then((_) {
        widget.onFinished();
      });
    }
  }

  @override
  void dispose() {
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
