import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../core/app_theme.dart';
import '../models/job_model.dart';
import '../widgets/job_card.dart';
import '../widgets/shimmer_card.dart';

/// Paid work marketplace for OUTSIDER accounts.
///
/// The backend returns an empty list to internal workers, so external offers are
/// never exposed to roles that should not see them.
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ApiService.instance.fetchJobs(status: 'OPEN');
      final jobs = raw.map(JobModel.fromJson).toList();
      if (mounted) {
        setState(() {
          _jobs = jobs;
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

  void _openJobSheet(JobModel job) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => JobBottomSheet(job: job, onJobClaimed: _loadJobs),
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
            const SliverAppBar(
              expandedHeight: 110,
              pinned: true,
              backgroundColor: AppColors.background,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: EdgeInsets.only(left: 24, bottom: 16),
                expandedTitleScale: 1.3,
                title: Text('Job Market',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5)),
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Text(
                  'Paid manual work approved for external helpers.',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
            if (_loading)
              const ShimmerList(count: 5, cardHeight: 140)
            else if (_error != null)
              SliverFillRemaining(child: _errorState())
            else if (_jobs.isEmpty)
              SliverFillRemaining(child: _emptyState())
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, index) => JobCard(
                      job: _jobs[index],
                      onTap: () => _openJobSheet(_jobs[index]),
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

  Widget _emptyState() => const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.work_outline_rounded,
                  size: 72, color: AppColors.textDisabled),
              SizedBox(height: 20),
              Text('No Open Paid Work',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary)),
              SizedBox(height: 8),
              Text(
                'There are no approved external work offers for this account right now.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
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
              const Text('Unable to load paid work',
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
                onPressed: _loadJobs,
                style: AppTheme.pillButtonStyle(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}
