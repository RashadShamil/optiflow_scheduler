import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../core/app_theme.dart';
import '../models/machine_model.dart';
import '../widgets/machine_card.dart';
import '../widgets/shimmer_card.dart';

/// Machine marketplace. The backend filters outsider accounts to bookable
/// machines while internal worker accounts can still inspect factory machines.
class MachineMarketScreen extends StatefulWidget {
  const MachineMarketScreen({super.key});

  @override
  State<MachineMarketScreen> createState() => MachineMarketScreenState();
}

class MachineMarketScreenState extends State<MachineMarketScreen> {
  List<MachineModel> _machines = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMachines();
  }

  Future<void> _loadMachines() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ApiService.instance.fetchMachines();
      final machines = raw.map(MachineModel.fromJson).toList();
      if (mounted) {
        setState(() {
          _machines = machines;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> openBookingSheetForId(String machineId) async {
    MachineModel? found;
    for (final machine in _machines) {
      if (machine.id == machineId) {
        found = machine;
        break;
      }
    }
    if (found == null) {
      final raw = await ApiService.instance.fetchMachineById(machineId);
      if (raw != null) found = MachineModel.fromJson(raw);
    }
    if (found != null && mounted) _openBookingSheet(found);
  }

  void _openBookingSheet(MachineModel machine) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MachineBookingSheet(
        machine: machine,
        onBookingDone: _loadMachines,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _loadMachines,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverAppBar(
              expandedHeight: 110,
              pinned: true,
              backgroundColor: AppColors.background,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: EdgeInsets.only(left: 24, bottom: 16),
                expandedTitleScale: 1.3,
                title: Text('Machine Shop',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5)),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Text('Reserve an available machine slot for your next run.',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
              ),
            ),
            if (_loading)
              const ShimmerGrid()
            else if (_error != null)
              SliverFillRemaining(child: _errorState())
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.82,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, index) => MachineCard(
                      machine: _machines[index],
                      onTap: () => _openBookingSheet(_machines[index]),
                    ),
                    childCount: _machines.length,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 60, color: AppColors.textDisabled),
              const SizedBox(height: 20),
              const Text('Unable to load machines',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text(_error!.replaceFirst('Exception: ', ''),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _loadMachines,
                style: AppTheme.pillButtonStyle(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}
