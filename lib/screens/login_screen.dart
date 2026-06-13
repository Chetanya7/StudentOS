import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import '../services/google_auth_service.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.calendar_month,
                size: 80,
              ),

              const SizedBox(height: 20),

              const Text(
                "StudentOS",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 10),

              const Text(
                "Organize your academic life",
              ),

              const SizedBox(height: 40),

              ElevatedButton(
                  onPressed: () async {
                    print("Button Pressed");

                    final authService = GoogleAuthService();

                    final user = await authService.signIn();

                    print("User: $user");

                    if (user != null && context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DashboardScreen(
                            user: user,
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text(
                    "Sign in with Google",
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}