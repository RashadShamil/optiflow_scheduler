import 'dart:io'; // To check platform
import 'package:flutter/material.dart';

// Placeholder screens (Your team will build these later)
class DesktopEntry extends StatelessWidget {
  const DesktopEntry({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text("Desktop Dashboard")));
}

class MobileEntry extends StatelessWidget {
  const MobileEntry({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text("Mobile Login")));
}

void main() {
  runApp(const MyApp());
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Opti',
      theme: ThemeData(primarySwatch: Colors.blue),
      // THE MAGIC SWITCH
      home: (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
          ? const DesktopEntry()
          : const MobileEntry(),
    );
  }
}