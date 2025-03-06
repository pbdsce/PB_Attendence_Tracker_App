import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/home_screen.dart';



void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Code Scanner',
      theme: ThemeData.light(useMaterial3: true), // Enable Material 3
      darkTheme: ThemeData.dark(useMaterial3: true), 
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}