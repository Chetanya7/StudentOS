import 'package:flutter/material.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const StudentOS());
}

class StudentOS extends StatelessWidget {
  const StudentOS({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'StudentOS',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const LoginScreen(),
    );
  }
}
