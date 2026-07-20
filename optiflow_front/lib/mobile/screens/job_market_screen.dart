import 'package:flutter/material.dart';
import 'package:optiflow_scheduler/core/services/supabase_service.dart';
import '../core/app_theme.dart';
import '../models/job_model.dart';
import '../widgets/job_card.dart';
import '../widgets/shimmer_card.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// JobMarketScreen — "Job Market" Airbnb-style feed of OPEN print jobs.
/// ─────────────────────────────────────────────────────────────────────────────
class JobMarketScreen extends StatefulWidget {
  const JobMarketScreen({super.key});

  @override
  State<JobMarketScreen> createState() => _JobMarketScreenState();
}

class _JobMarketScreenState extends State<JobMarketScreen> {
  List<JobModel> _jobs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      // Fetch ALL jobs from Supabase including tasks.
      // We then filter to only OPEN jobs — those are the ones the manager
      // has published from the desktop app using the "Publish" button.
      final raw = await SupabaseService.instance.fetchJobsWithTasks();
      final jobs = raw
          .where((json) => json['status'] == 'OPEN')
          .map((json) {
            return JobModel.fromJson({
              ...json,
              // Expose task count for the job card
              'task_count': (json['tasks'] as List?)?.length ?? 0,
            });
          })
          .toList();
      if (mounted) setState(() { _jobs = jobs; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }


  void _openJobSheet(JobModel job) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => JobBottomSheet(
        job: job,
        onJobClaimed: _loadJobs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _loadJobs,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── AppBar ───────────────────────────────────────────────────────
            SliverAppBar(
              expandedHeight: 110,
              pinned: true,
              backgroundColor: AppColors.background,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
                expandedTitleScale: 1.3,
                title: const Text(
                  'Job Market',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),

            // ── Subtitle ─────────────────────────────────────────────────────
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Text(
                  'Unclaimed jobs available for the floor.',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),

            // ── Loading ──────────────────────────────────────────────────────
            if (_loading) const ShimmerList(count: 5, cardHeight: 140)

            // ── Error ────────────────────────────────────────────────────────
            else if (_error != null)
              SliverFillRemaining(
                child: _errorState(),
              )

            // ── Empty ────────────────────────────────────────────────────────
            else if (_jobs.isEmpty)
              SliverFillRemaining(
                child: _emptyState(),
              )

            // ── Job list ─────────────────────────────────────────────────────
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => JobCard(
                      job: _jobs[i],
                      onTap: () => _openJobSheet(_jobs[i]),
                    ),
                    childCount: _jobs.length,
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              color: AppColors.textDisabled.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.work_off_rounded,
                size: 44, color: AppColors.textDisabled),
          ),
          const SizedBox(height: 24),
          const Text('No Open Jobs',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Text(
            'All jobs have been claimed. Check\nback when new orders come in.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 15, height: 1.5),
          ),
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
          const Icon(Icons.cloud_off_rounded,
              size: 60, color: AppColors.textDisabled),
          const SizedBox(height: 20),
          const Text('Unable to load jobs',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text(_error!.replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, height: 1.5)),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _loadJobs,
            style: AppTheme.pillButtonStyle(),
            child: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}
