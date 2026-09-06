import 'package:flutter/material.dart';
import 'package:optiflow_scheduler/core/services/api_service.dart';

import '../core/app_theme.dart';
import '../models/work_offer_model.dart';

/// External marketplace containing only manager-approved HUMAN tasks.
class WorkMarketScreen extends StatefulWidget {
  const WorkMarketScreen({super.key});

  @override
  State<WorkMarketScreen> createState() => _WorkMarketScreenState();
}

class _WorkMarketScreenState extends State<WorkMarketScreen> {
  List<WorkOfferModel> _offers = [];
  List<WorkOfferModel> _mine = [];
  bool _loading = true;
  String? _error;
  final Set<String> _claiming = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.instance.fetchOpenWorkOffers(),
        ApiService.instance.fetchMyWorkOffers(),
      ]);
      if (mounted) {
        setState(() {
          _offers = results[0].map(WorkOfferModel.fromJson).toList();
          _mine = results[1].map(WorkOfferModel.fromJson).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _claim(WorkOfferModel offer) async {
    setState(() => _claiming.add(offer.id));
    try {
      await ApiService.instance.claimWorkOffer(offer.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Work claimed. The manager must re-optimize the job before it receives a time slot.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _claiming.remove(offer.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text(
          'Work Market',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [Text(_error!, textAlign: TextAlign.center)],
      );
    }
    if (_offers.isEmpty && _mine.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: const [
          SizedBox(height: 120),
          Icon(
            Icons.work_off_outlined,
            size: 64,
            color: AppColors.textDisabled,
          ),
          SizedBox(height: 16),
          Text('No approved work available', textAlign: TextAlign.center),
        ],
      );
    }

    final cards = <Widget>[];
    if (_mine.isNotEmpty) {
      cards.add(
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            'CLAIMED BY ME',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textDisabled,
            ),
          ),
        ),
      );
      cards.addAll(
        _mine.map(
          (offer) => Card(
            child: ListTile(
              title: Text(offer.title),
              subtitle: Text(
                '${offer.jobTitle} · awaiting/using production schedule',
              ),
              trailing: Text(offer.status),
            ),
          ),
        ),
      );
      cards.add(const SizedBox(height: 18));
    }
    if (_offers.isNotEmpty) {
      cards.add(
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            'AVAILABLE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textDisabled,
            ),
          ),
        ),
      );
    }
    cards.addAll(
      _offers.map((offer) {
        final hours = offer.estimatedMinutes / 60.0;
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(20),
          decoration: AppTheme.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                offer.title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                offer.jobTitle,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text(offer.operation),
                  Text('${offer.quantity} units'),
                  Text('${hours.toStringAsFixed(1)} h'),
                  Text(
                    'Rs. ${offer.payAmount.toStringAsFixed(0)}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _claiming.contains(offer.id)
                      ? null
                      : () => _claim(offer),
                  child: _claiming.contains(offer.id)
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Claim Work'),
                ),
              ),
            ],
          ),
        );
      }),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: cards,
    );
  }
}
