import 'package:flutter/material.dart';
import 'package:optiflow_scheduler/core/utils/app_colors.dart';

class Sidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  const Sidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
  });

  static const _items = [
    (Icons.dashboard_rounded, 'Dashboard'),
    (Icons.precision_manufacturing_rounded, 'Machines'),
    (Icons.inventory_2_rounded, 'Jobs'),
    (Icons.calendar_month_rounded, 'Schedule'),
    (Icons.people_rounded, 'Team'),
    (Icons.account_tree_rounded, 'Skills Matrix'),
    (Icons.approval_rounded, 'Approvals'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: AppColors.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Image.asset('assets/images/logo.png'),
                ),
                const SizedBox(width: 12),
                const Text(
                  'OptiFlow',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (_, index) {
                final item = _items[index];
                final selected = selectedIndex == index;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 3,
                  ),
                  child: ListTile(
                    selected: selected,
                    selectedTileColor: AppColors.surfaceLight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(
                      item.$1,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    title: Text(
                      item.$2,
                      style: TextStyle(
                        color: selected
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    onTap: () => onItemSelected(index),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
