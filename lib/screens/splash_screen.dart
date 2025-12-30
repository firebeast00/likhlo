import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart'; // Import Hive
import 'home_screen.dart';
import 'onboarding_screen.dart'; // Import Onboarding Screen

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeIn)),
    );

    _slideUp = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 1.0, curve: Curves.easeOutQuart)),
    );

    _controller.forward();

    // Check First Time User Logic
    Timer(const Duration(milliseconds: 3000), () {
      if (mounted) {
        _checkFirstTime();
      }
    });
  }

  Future<void> _checkFirstTime() async {
    final box = Hive.box('preferences');
    bool hasOnboarded = box.get('has_onboarded', defaultValue: false);

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        // ✅ LOGIC: If onboarded -> Home, Else -> Onboarding
        pageBuilder: (_, __, ___) => hasOnboarded ? const HomeScreen() : const OnboardingScreen(),
        transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1E3A8A), // Deep Royal Blue
              Color(0xFF172554), // Dark Navy
              Color(0xFF0F172A), // Almost Black
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _logoScale,
              child: FadeTransition(
                opacity: _logoFade,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 30, spreadRadius: 5),
                      ]
                  ),
                  child: Image.asset(
                    'assets/app_logo.png',
                    width: 120,
                    height: 120,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),

            SlideTransition(
              position: _slideUp,
              child: FadeTransition(
                opacity: _logoFade,
                child: Column(
                  children: [
                    const Text(
                      "Likhlo",
                      style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.5,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 3,
                      width: 50,
                      decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          borderRadius: BorderRadius.circular(2)
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ✅ UPDATED FOOTER TEXT
                    Text(
                      "Made by Jawad Rajper",
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.7),
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w400
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}