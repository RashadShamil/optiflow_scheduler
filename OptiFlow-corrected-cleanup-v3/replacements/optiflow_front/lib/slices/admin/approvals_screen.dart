import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:optiflow_scheduler/core/services/api_service.dart';
import 'package:optiflow_scheduler/core/utils/app_colors.dart';

/// Manager queue for external machine-booking requests.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await ApiService.instance.fetchBookingRequests(status: 'PENDING');
      if (mounted) setState(() { _requests = rows; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(Map<String, dynamic> request, String status) async {
    try {
      await ApiService.instance.decideBooking(request['id'].toString(), status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking $status')));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));

    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Approvals', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
                Text('External machine bookings become scheduler blockers only after approval.', style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
          ],
        ),
        const SizedBox(height: 24),
        if (_requests.isEmpty)
          const Text('No pending machine booking requests.', style: TextStyle(color: AppColors.textSecondary))
        else
          ..._requests.map((request) {
            final start = DateTime.tryParse(request['start_time']?.toString() ?? '')?.toLocal();
            final end = DateTime.tryParse(request['end_time']?.toString() ?? '')?.toLocal();
            return Card(
              color: AppColors.surface,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const Icon(Icons.event_available_rounded, color: AppColors.primary),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(request['machine_name']?.toString() ?? 'Machine', style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('${request['requested_by_name'] ?? 'External user'} · Quote Rs. ${request['quoted_amount'] ?? 0}'),
                          if (start != null && end != null)
                            Text('${DateFormat('MMM d, h:mm a').format(start)} – ${DateFormat('h:mm a').format(end)}'),
                        ],
                      ),
                    ),
                    TextButton(onPressed: () => _decide(request, 'REJECTED'), child: const Text('Reject')),
                    const SizedBox(width: 8),
                    ElevatedButton(onPressed: () => _decide(request, 'APPROVED'), child: const Text('Approve')),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
