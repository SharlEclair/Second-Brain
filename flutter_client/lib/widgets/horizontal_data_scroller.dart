import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';

class HorizontalDataScroller extends StatefulWidget {
  final List<String> filters;
  final List<Widget> items;
  final Function(int)? onFilterChanged;

  const HorizontalDataScroller({
    super.key,
    required this.filters,
    required this.items,
    this.onFilterChanged,
  });

  @override
  State<HorizontalDataScroller> createState() => _HorizontalDataScrollerState();
}

class _HorizontalDataScrollerState extends State<HorizontalDataScroller> {
  int _activeFilterIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Top Section: Horizontally scrollable row of pill-shaped filter toggles
        if (widget.filters.isNotEmpty) ...[
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.filters.length,
              separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final isActive = _activeFilterIndex == index;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _activeFilterIndex = index;
                    });
                    if (widget.onFilterChanged != null) {
                      widget.onFilterChanged!(index);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.neonBlue
                          : AppColors.darkSurfaceSecondary,
                      borderRadius: BorderRadius.circular(50), // Pill-shape
                    ),
                    child: Center(
                      child: Text(
                        widget.filters[index],
                        style: TextStyle(
                          color: isActive
                              ? const Color(0xFF050505) // Dark text when active
                              : AppColors.darkTextSecondary,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // 2. Bottom Section: Horizontally scrollable actual data items
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.items.length,
            separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) {
              return widget.items[index];
            },
          ),
        ),
      ],
    );
  }
}
