import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_service.dart';
import '../core/app_theme.dart';
import '../core/auth_service.dart';
import '../models/task_model.dart';
import '../widgets/shimmer_card.dart';
import '../widgets/task_bottom_sheet.dart';
import '../widgets/task_card.dart';

/// Role-aware mobile work queue.
///
/// WORKER accounts receive manager-published tasks they are allowed to accept or
/// that are already assigned to them. OUTSIDER accounts receive tasks from work
/// offers they have claimed. The backend owns the authorization rules.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<TaskModel> _tasks = [];
  bool _loading = true;
  String? _error;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ApiService.instance.fetchTasks();
      final tasks = raw.map(TaskModel.fromJson).toList()
        ..sort((a, b) {
          const order = {'IN_PROGRESS': 0, 'SCHEDULED': 1, 'PENDING': 2, 'COMPLETED': 3};
          return (order[a.status] ?? 9).compareTo(order[b.status] ?? 9);
        });
      if (mounted) {
        setState(() {
          _tasks = tasks;
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

  void _openTaskSheet(TaskModel task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TaskBottomSheet(task: task, onStatusChanged: _loadTasks),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = AuthService.instance.displayName;
    final active = _tasks.where((task) => task.status == 'IN_PROGRESS').toList();
    final next = _tasks
        .where((task) => task.status == 'SCHEDULED' || task.status == 'PENDING')
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _loadTasks,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 130,
              pinned: true,
              backgroundColor: AppColors.background,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
                expandedTitleScale: 1.4,
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_greeting,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500)),
                    Text(name,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.5)),
                  ],
                ),
              ),
            ),
            if (_loading) ...[
              _sectionHeader('ACTIVE NOW'),
              const SliverToBoxAdapter(child: ShimmerList(count: 3)),
            ] else if (_error != null)
              SliverFillRemaining(child: _errorState())
            else if (_tasks.isEmpty)
              SliverFillRemaining(child: _emptyState())
            else ...[
              if (active.isNotEmpty) ...[
                _sectionHeader('ACTIVE NOW'),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 220,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: active.length,
                      itemBuilder: (_, index) => TaskCard(
                        task: active[index],
                        isCarousel: true,
                        onTap: () => _openTaskSheet(active[index]),
                      ),
                    ),
                  ),
                ),
              ],
              if (next.isNotEmpty) ...[
                _sectionHeader('UP NEXT — ${next.length} TASK${next.length == 1 ? '' : 'S'}'),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, index) => TaskCard(
                        task: next[index],
                        onTap: () => _openTaskSheet(next[index]),
                      ),
                      childCount: next.length,
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _sectionHeader(String title) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.textDisabled)),
        ),
      );

  Widget _emptyState() => const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.done_all_rounded, size: 72, color: AppColors.completed),
              SizedBox(height: 20),
              Text('All caught up!',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary)),
              SizedBox(height: 8),
              Text('No mobile work is currently assigned or available to you.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
            ],
          ),
        ),
      );

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 64, color: AppColors.offline),
              const SizedBox(height: 20),
              const Text('Unable to load work',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text(_error!.replaceFirst('Exception: ', ''),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _loadTasks();
                },
                style: AppTheme.pillButtonStyle(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}
