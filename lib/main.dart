import 'package:flutter/material.dart';
import 'package:mega_cut/screens/trim_screen.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: TrimScreen());
  }
}
