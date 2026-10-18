import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/tusk_theme.dart';
import '../mission/models/mission.dart';

/// Displays a mission's full plan, step statuses, results, and actions.
///
/// This screen is the single source of truth for a mission's state.
/// It never fabricates progress, tool activity, or results.
///
/// Actions available per state:
///   readyForApproval → Approve Plan / Cancel
///   approved         → (future Phase 3: Start execution)
///   failed           → Retry (returns to readyForApproval)
///   running          → Cancel
///   completed/cancelled → read-only view
class MissionDetailScreen extends StatelessWidget {
  final Mission mission;
  final VoidCallback? onApprove;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;

  const MissionDetailScreen({
    super.key,
    required this.mission,
    this.onApprove,
    this.onCancel,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? TuskColors.darkTextPrimary : TuskColors.lightTextPrimary;
    final textSecondary =
        isDark ? TuskColors.darkTextSecondary : TuskColors.lightTextSecondary;
    final textMuted =
        isDark ? TuskColors.darkTextMuted : TuskColors.lightTextMuted;
    final surfaceBg = isDark ? TuskColors.darkSurface : TuskColors.lightSurface;
    final border = isDark ? TuskColors.darkBorder : TuskColors.lightBorder;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        title: Text(
          mission.title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: _StatusBadge(status: mission.status),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // ── Objective ──────────────────────────────────────────────
            _SectionHeader(label: 'OBJECTIVE', textMuted: textMuted),
            const SizedBox(height: 8),
            Text(
              mission.objective,
              style: TextStyle(
                fontSize: 16,
                height: 1.5,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 24),

            // ── Dev adapter notice ─────────────────────────────────────
            if (mission.status == MissionStatus.readyForApproval ||
                mission.status == MissionStatus.approved)
              _DevAdapterBanner(border: border, surfaceBg: surfaceBg,
                  textMuted: textMuted),

            // ── Plan steps ─────────────────────────────────────────────
            if (mission.hasSteps) ...[
              _SectionHeader(label: 'PLAN', textMuted: textMuted),
              const SizedBox(height: 8),
              ...mission.steps.asMap().entries.map((entry) {
                return _StepTile(
                  index: entry.key,
                  step: entry.value,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  textMuted: textMuted,
                  surfaceBg: surfaceBg,
                  border: border,
                  isDark: isDark,
                );
              }),
              const SizedBox(height: 24),
            ],

            // ── Result summary ─────────────────────────────────────────
            if (mission.resultSummary != null) ...[
              _SectionHeader(label: 'RESULT', textMuted: textMuted),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: surfaceBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: border),
                ),
                child: Text(
                  mission.resultSummary!,
                  style: TextStyle(fontSize: 14, height: 1.5, color: textPrimary),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ── Failure reason ─────────────────────────────────────────
            if (mission.failureReason != null) ...[
              _SectionHeader(label: 'WHAT WENT WRONG', textMuted: textMuted),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: surfaceBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.alertCircle,
                        size: 18, color: textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        mission.failureReason!,
                        style: TextStyle(
                            fontSize: 14, height: 1.45, color: textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ── Action buttons ─────────────────────────────────────────
            _ActionArea(
              mission: mission,
              onApprove: onApprove,
              onCancel: onCancel,
              onRetry: onRetry,
              isDark: isDark,
            ),

            const SizedBox(height: 32),

            // ── Timestamps ────────────────────────────────────────────
            Text(
              'Created ${_formatDate(mission.createdAt)}  ·  '
              'Updated ${_formatDate(mission.updatedAt)}',
              style: TextStyle(fontSize: 12, color: textMuted),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color textMuted;
  const _SectionHeader({required this.label, required this.textMuted});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        color: textMuted,
      ),
    );
  }
}

class _DevAdapterBanner extends StatelessWidget {
  final Color border;
  final Color surfaceBg;
  final Color textMuted;
  const _DevAdapterBanner(
      {required this.border,
      required this.surfaceBg,
      required this.textMuted});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surfaceBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 16, color: textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DEVELOPMENT ADAPTER',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Plan generated by local development adapter (rule-based planner) — not an AI service.',
                  style: TextStyle(fontSize: 12, color: textMuted, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final int index;
  final MissionStep step;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color surfaceBg;
  final Color border;
  final bool isDark;

  const _StepTile({
    required this.index,
    required this.step,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.surfaceBg,
    required this.border,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final icon = _stepIcon(step.status);
    final iconColor = _stepIconColor(step.status, isDark);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${index + 1}. ${step.title}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.description,
                  style: TextStyle(
                      fontSize: 13, height: 1.4, color: textSecondary),
                ),
                if (step.expectedOutput.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Expected: ${step.expectedOutput}',
                    style: TextStyle(fontSize: 12, color: textMuted),
                  ),
                ],
                if (step.resultText != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    step.resultText!,
                    style: TextStyle(fontSize: 13, color: textPrimary),
                  ),
                ],
                if (step.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(LucideIcons.alertCircle,
                          size: 14, color: textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          step.errorMessage!,
                          style:
                              TextStyle(fontSize: 12, color: textSecondary),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _stepIcon(StepStatus s) {
    switch (s) {
      case StepStatus.completed:
        return LucideIcons.checkCircle2;
      case StepStatus.running:
        return LucideIcons.loader;
      case StepStatus.failed:
        return LucideIcons.alertCircle;
      case StepStatus.skipped:
        return LucideIcons.skipForward;
      case StepStatus.pending:
        return LucideIcons.circle;
    }
  }

  Color _stepIconColor(StepStatus s, bool dark) {
    final muted = dark ? TuskColors.darkTextMuted : TuskColors.lightTextMuted;
    final secondary =
        dark ? TuskColors.darkTextSecondary : TuskColors.lightTextSecondary;
    final primary = dark ? TuskColors.darkTextPrimary : TuskColors.lightTextPrimary;
    switch (s) {
      case StepStatus.completed:
        return primary;
      case StepStatus.running:
        return secondary;
      case StepStatus.failed:
        return secondary;
      case StepStatus.skipped:
        return muted;
      case StepStatus.pending:
        return muted;
    }
  }
}

class _ActionArea extends StatelessWidget {
  final Mission mission;
  final VoidCallback? onApprove;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final bool isDark;

  const _ActionArea({
    required this.mission,
    this.onApprove,
    this.onCancel,
    this.onRetry,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final primaryFg = isDark ? TuskColors.pureBlack : TuskColors.pureWhite;
    final primaryBg = isDark ? TuskColors.pureWhite : TuskColors.pureBlack;
    final border = isDark ? TuskColors.darkBorder : TuskColors.lightBorder;
    final textPrimary =
        isDark ? TuskColors.darkTextPrimary : TuskColors.lightTextPrimary;

    switch (mission.status) {
      case MissionStatus.readyForApproval:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              key: const Key('mission_approve_button'),
              onPressed: onApprove,
              icon: const Icon(LucideIcons.check, size: 18),
              label: const Text('Approve Plan',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              style: FilledButton.styleFrom(
                backgroundColor: primaryBg,
                foregroundColor: primaryFg,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              key: const Key('mission_cancel_button'),
              onPressed: onCancel,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Cancel',
                  style: TextStyle(
                      color: textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 15)),
            ),
          ],
        );

      case MissionStatus.approved:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? TuskColors.darkSurface : TuskColors.lightSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: isDark ? TuskColors.darkBorder : TuskColors.lightBorder),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.clock, size: 18,
                  color: isDark
                      ? TuskColors.darkTextSecondary
                      : TuskColors.lightTextSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Plan approved. Execution will be available in Phase 3 when the backend is connected.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: isDark
                        ? TuskColors.darkTextSecondary
                        : TuskColors.lightTextSecondary,
                  ),
                ),
              ),
            ],
          ),
        );

      case MissionStatus.running:
        return OutlinedButton.icon(
          key: const Key('mission_cancel_running_button'),
          onPressed: onCancel,
          icon: Icon(LucideIcons.xSquare, size: 18),
          label: const Text('Cancel Mission',
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: border),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

      case MissionStatus.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              key: const Key('mission_retry_button'),
              onPressed: onRetry,
              icon: const Icon(LucideIcons.rotateCcw, size: 18),
              label: const Text('Retry',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              style: FilledButton.styleFrom(
                backgroundColor: primaryBg,
                foregroundColor: primaryFg,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        );

      case MissionStatus.completed:
      case MissionStatus.cancelled:
      case MissionStatus.draft:
      case MissionStatus.needsClarification:
        return const SizedBox.shrink();
    }
  }
}

/// Compact status badge used in appbar and list tiles.
class _StatusBadge extends StatelessWidget {
  final MissionStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? TuskColors.darkSurface : TuskColors.lightSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? TuskColors.darkBorder : TuskColors.lightBorder,
        ),
      ),
      child: Text(
        _label(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: isDark
              ? TuskColors.darkTextSecondary
              : TuskColors.lightTextSecondary,
        ),
      ),
    );
  }

  String _label(MissionStatus s) {
    switch (s) {
      case MissionStatus.draft:
        return 'Draft';
      case MissionStatus.needsClarification:
        return 'Clarifying';
      case MissionStatus.readyForApproval:
        return 'Review plan';
      case MissionStatus.approved:
        return 'Approved';
      case MissionStatus.running:
        return 'Running';
      case MissionStatus.completed:
        return 'Completed';
      case MissionStatus.failed:
        return 'Failed';
      case MissionStatus.cancelled:
        return 'Cancelled';
    }
  }
}

/// Public export so other widgets can use the badge.
class MissionStatusBadge extends StatelessWidget {
  final MissionStatus status;
  const MissionStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) => _StatusBadge(status: status);
}
