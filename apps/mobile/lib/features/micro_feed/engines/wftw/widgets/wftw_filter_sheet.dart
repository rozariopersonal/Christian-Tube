import 'package:flutter/material.dart';
import 'package:mobile/core/layout/adaptivity.dart';
import 'package:mobile/core/theme/app_tokens.dart';
import 'package:mobile/features/engines/scripture/services/book_name_service.dart';
import '../models/wftw_filter_state.dart';

class WftwFilterSheet extends StatelessWidget {
  final WftwFilterState currentState;
  final List<int> availableYears;
  final List<int> availableBooks;
  final ValueChanged<WftwFilterState> onApply;

  const WftwFilterSheet({
    super.key,
    required this.currentState,
    required this.availableYears,
    required this.availableBooks,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final screen = ScreenClass.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: screen.isCompact ? MediaQuery.of(context).size.height * 0.8 : 560,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: tokens.onSurfaceDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Flexible(
                child: Text(
                  'Filter & Sort Feed',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (currentState.yearFilter != null ||
                  currentState.bookFilter != null ||
                  currentState.sortBy != 'date')
                TextButton(
                  onPressed: () {
                    final cleared = currentState.copyWith(
                      clearYearFilter: true,
                      clearBookFilter: true,
                      sortBy: 'date',
                    );
                    onApply(cleared);
                    Navigator.pop(context);
                  },
                  child: Text(
                    'Reset',
                    style: TextStyle(color: tokens.accent),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Scrollable Body
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sort By
                  Text(
                    'SORT BY',
                    style: TextStyle(
                      color: tokens.onSurfaceMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Latest Date'),
                        selected: currentState.sortBy == 'date',
                        onSelected: (selected) {
                          if (selected) {
                            onApply(currentState.copyWith(sortBy: 'date'));
                            Navigator.pop(context);
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Canonical Book Order'),
                        selected: currentState.sortBy == 'book',
                        onSelected: (selected) {
                          if (selected) {
                            onApply(currentState.copyWith(sortBy: 'book'));
                            Navigator.pop(context);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Filter by Year
                  if (availableYears.isNotEmpty) ...[
                    Text(
                      'FILTER BY YEAR',
                      style: TextStyle(
                        color: tokens.onSurfaceMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('All Years'),
                          selected: currentState.yearFilter == null,
                          onSelected: (selected) {
                            if (selected) {
                              onApply(currentState.copyWith(clearYearFilter: true));
                              Navigator.pop(context);
                            }
                          },
                        ),
                        ...availableYears.map((yr) {
                          return ChoiceChip(
                            label: Text('$yr'),
                            selected: currentState.yearFilter == yr,
                            onSelected: (selected) {
                              onApply(
                                selected
                                    ? currentState.copyWith(yearFilter: yr)
                                    : currentState.copyWith(clearYearFilter: true),
                              );
                              Navigator.pop(context);
                            },
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Filter by Book
                  if (availableBooks.isNotEmpty) ...[
                    Text(
                      'FILTER BY BOOK',
                      style: TextStyle(
                        color: tokens.onSurfaceMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('All Books'),
                          selected: currentState.bookFilter == null,
                          onSelected: (selected) {
                            if (selected) {
                              onApply(currentState.copyWith(clearBookFilter: true));
                              Navigator.pop(context);
                            }
                          },
                        ),
                        ...availableBooks.map((bNum) {
                          final name = BookNameService.englishNameFor(bNum);
                          return ChoiceChip(
                            label: Text(name),
                            selected: currentState.bookFilter == bNum,
                            onSelected: (selected) {
                              onApply(
                                selected
                                    ? currentState.copyWith(bookFilter: bNum)
                                    : currentState.copyWith(clearBookFilter: true),
                              );
                              Navigator.pop(context);
                            },
                          );
                        }),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
