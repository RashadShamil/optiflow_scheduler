import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:optiflow_scheduler/slices/engine/dashboard/dashboard_screen.dart';

import '../core/app_theme.dart';
import '../core/auth_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'machine_market_screen.dart';
import 'requests_screen.dart';
import 'work_market_screen.dart';

/// Role gate shared by desktop and mobile.
///
/// MANAGER  -> desktop management dashboard/Gantt/approvals
/// WORKER   -> assigned production tasks
/// EXTERNAL -> paid human-work market + machine-booking market + claimed work
class MainHub extends StatelessWidget {
  const MainHub({super.key});

  @override
  Widget build(BuildContext context) {
    return switch (AuthService.instance.role) {
      'MANAGER' => const DashboardScreen(),
      'WORKER' => const _WorkerHub(),
      _ => const _ExternalHub(),
    };
  }
}

class _WorkerHub extends StatefulWidget {
  const _WorkerHub();

  @override
  State<_WorkerHub> createState() => _WorkerHubState();
}

class _WorkerHubState extends State<_WorkerHub> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [HomeScreen(), _ProfileScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.task_alt_outlined),
            selectedIcon: Icon(Icons.task_alt),
            label: 'My Work',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _ExternalHub extends StatefulWidget {
  const _ExternalHub();

  @override
  State<_ExternalHub> createState() => _ExternalHubState();
}

class _ExternalHubState extends State<_ExternalHub> {
  int _index = 0;

  void _scanMachine() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: _QrScanner(
          onMachineId: (machineId) {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MachineBookingPage(machineId: machineId),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          WorkMarketScreen(),
          MachineMarketScreen(),
          HomeScreen(),
          RequestsScreen(),
          _ProfileScreen(),
        ],
      ),
      floatingActionButton: _index == 1
          ? FloatingActionButton(
              onPressed: _scanMachine,
              child: const Icon(Icons.qr_code_scanner_rounded),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.work_outline),
            selectedIcon: Icon(Icons.work),
            label: 'Work',
          ),
          NavigationDestination(
            icon: Icon(Icons.precision_manufacturing_outlined),
            selectedIcon: Icon(Icons.precision_manufacturing),
            label: 'Machines',
          ),
          NavigationDestination(
            icon: Icon(Icons.task_alt_outlined),
            selectedIcon: Icon(Icons.task_alt),
            label: 'My Work',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Requests',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _QrScanner extends StatefulWidget {
  final ValueChanged<String> onMachineId;

  const _QrScanner({required this.onMachineId});

  @override
  State<_QrScanner> createState() => _QrScannerState();
}

class _QrScannerState extends State<_QrScanner> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            if (_handled || capture.barcodes.isEmpty) return;
            final value = capture.barcodes.first.rawValue;
            if (value == null || value.isEmpty) return;
            setState(() => _handled = true);
            widget.onMachineId(value);
          },
        ),
        const Positioned(
          top: 30,
          left: 0,
          right: 0,
          child: Text(
            'Scan machine QR code',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen();

  Future<void> _signOut(BuildContext context) async {
    await AuthService.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Profile'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            CircleAvatar(
              radius: 42,
              child: Text(
                auth.displayName.isEmpty
                    ? '?'
                    : auth.displayName[0].toUpperCase(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              auth.displayName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              auth.role,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => _signOut(context),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }
}
