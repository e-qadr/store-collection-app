import 'package:flutter/material.dart';
import 'package:store_collection_app/theme/app_theme.dart';

class TaskSummary extends StatelessWidget {
  const TaskSummary({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final action = data['action_label']?.toString().trim() ?? '';
    final reason = data['audience_reason']?.toString().trim() ?? '';
    final highPriority = data['priority']?.toString() == 'high';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: highPriority ? AppTheme.oliveSurface : AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highPriority ? AppTheme.primaryOlive : AppTheme.dividerColor,
        ),
      ),
      child: Row(
        children: [
          Icon(
            highPriority ? Icons.priority_high_rounded : Icons.task_alt_rounded,
            size: 19,
            color: AppTheme.primaryOlive,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.isEmpty ? 'مهمة تتطلب إجراءك' : action,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(reason, style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
