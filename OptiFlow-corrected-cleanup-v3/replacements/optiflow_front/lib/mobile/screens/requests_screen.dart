import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:optiflow_scheduler/core/services/api_service.dart';

import '../core/app_theme.dart';

/// External user's machine-booking request history.
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await ApiService.instance.fetchMyBookings();
      if (mounted) setState(() { _rows = rows; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('My Requests', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                children: _rows.isEmpty
                    ? const [Padding(padding: EdgeInsets.only(top: 120), child: Center(child: Text('No machine requests yet.')))]
                    : _rows.map((row) {
                        final machine = row['machine'] is Map ? row['machine'] as Map : const {};
                        final start = DateTime.tryParse(row['start_time']?.toString() ?? '')?.toLocal();
                        return Card(
                          child: ListTile(
                            title: Text(machine['name']?.toString() ?? 'Machine booking'),
                            subtitle: Text(start == null ? '' : DateFormat('MMM d, h:mm a').format(start)),
                            trailing: Text(row['status']?.toString() ?? 'PENDING'),
                          ),
                        );
                      }).toList(),
              ),
            ),
    );
  }
}
