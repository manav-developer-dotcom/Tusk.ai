import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/tusk_theme.dart';
import '../mission/models/mission.dart';
import '../mission/services/mission_repository.dart';
import '../mission/mission_detail_screen.dart';

/// Projects & Missions screen for Tusk.ai.
///
/// Shows real persisted missions from [MissionRepository].
/// Missions are grouped by status and ordered by updatedAt descending.
/// No fake history or fabricated progress is displayed.
class ProjectsScreen extends StatefulWidget {
  final MissionRepository? missionRepository;

  const ProjectsScreen({super.key, this.missionRepository});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<Mission> _missions = [];

  @override
  void initState() {
    super.initState();
    _loadMissions();
  }

  @override
  void didUpdateWidget(ProjectsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadMissions();
  }

  void _loadMissions() {
    if (widget.missionRepository == null) return;
    setState(() {
      _missions = widget.missionRepository!.loadMissions();
    });
    if (widget.missionRepository!.hasRemoteBackend) {
      widget.missionRepository!.syncRemoteMissions().then((synced) {
        if (mounted) setState(() => _missions = synced);
      });
    }
  }

  void _openMission(Mission mission) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MissionDetailScreen(
          mission: mission,
          onApprove: () => _approveMission(mission),
          onCancel: () => _cancelMission(mission),
          onRetry: () => _retryMission(mission),
        ),
      ),
    ).then((_) => _loadMissions());
  }

  Future<void> _approveMission(Mission mission) async {
    await widget.missionRepository!.approveMission(mission.id);
    if (mounted) {
      Navigator.pop(context);
      _loadMissions();
    }
  }

  Future<void> _cancelMission(Mission mission) async {
    await widget.missionRepository!.updateStatus(
      mission.id,
      MissionStatus.cancelled,
      failureReason: 'Cancelled by user.',
    );
    if (mounted) {
      Navigator.pop(context);
      _loadMissions();
    }
  }

  Future<void> _retryMission(Mission mission) async {
    await widget.missionRepository!.updateStatus(
      mission.id,
      MissionStatus.readyForApproval,
    );
    if (mounted) {
      _loadMissions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? TuskColors.darkTextPrimary : TuskColors.lightTextPrimary;
    final textSecondary =
        isDark ? TuskColors.darkTextSecondary : TuskColors.lightTextSecondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Projects & Missions',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: SafeArea(
        child: _missions.isEmpty
            ? _EmptyState(
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                isDark: isDark,
              )
            : RefreshIndicator(
                onRefresh: () async => _loadMissions(),
                child: ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _missions.length,
                  itemBuilder: (context, index) {
                    final m = _missions[index];
                    return _MissionTile(
                      mission: m,
                      isDark: isDark,
                      onTap: () => _openMission(m),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _MissionTile extends StatelessWidget {
  final Mission mission;
  final bool isDark;
  final VoidCallback onTap;

  const _MissionTile({
    required this.mission,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary =
        isDark ? TuskColors.darkTextPrimary : TuskColors.lightTextPrimary;
    final textSecondary =
        isDark ? TuskColors.darkTextSecondary : TuskColors.lightTextSecondary;
    final textMuted =
        isDark ? TuskColors.darkTextMuted : TuskColors.lightTextMuted;
    final cardBg = isDark ? TuskColors.darkSurface : TuskColors.lightSurface;
    final border = isDark ? TuskColors.darkBorder : TuskColors.lightBorder;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        key: Key('mission_tile_${mission.id}'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _statusIcon(mission.status),
                  size: 18,
                  color: textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    mission.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                MissionStatusBadge(status: mission.status),
              ],
            ),
            if (mission.hasSteps) ...[
              const SizedBox(height: 10),
              _StepProgress(
                mission: mission,
                textMuted: textMuted,
                border: border,
                isDark: isDark,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _formatDate(mission.updatedAt),
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
    if (diff.inMinutes < 1) return 'Updated just now';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
    return 'Updated ${dt.day}/${dt.month}/${dt.year}';
  }

  IconData _statusIcon(MissionStatus s) {
    switch (s) {
      case MissionStatus.draft:
        return LucideIcons.filePlus2;
      case MissionStatus.needsClarification:
        return LucideIcons.helpCircle;
      case MissionStatus.readyForApproval:
        return LucideIcons.clipboardCheck;
      case MissionStatus.approved:
        return LucideIcons.checkCircle;
      case MissionStatus.running:
        return LucideIcons.loader;
      case MissionStatus.completed:
        return LucideIcons.checkCircle2;
      case MissionStatus.failed:
        return LucideIcons.alertCircle;
      case MissionStatus.cancelled:
        return LucideIcons.ban;
    }
  }
}

class _StepProgress extends StatelessWidget {
  final Mission mission;
  final Color textMuted;
  final Color border;
  final bool isDark;

  const _StepProgress({
    required this.mission,
    required this.textMuted,
    required this.border,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final total = mission.steps.length;
    final done = mission.completedStepCount;
    final fraction = total > 0 ? done / total : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 4,
            backgroundColor:
                isDark ? TuskColors.darkBorder : TuskColors.lightBorder,
            valueColor: AlwaysStoppedAnimation<Color>(
              isDark ? TuskColors.pureWhite : TuskColors.pureBlack,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$done / $total steps',
          style: TextStyle(fontSize: 12, color: textMuted),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final Color textPrimary;
  final Color textSecondary;
  final bool isDark;

  const _EmptyState({
    required this.textPrimary,
    required this.textSecondary,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? TuskColors.darkSurface
                    : TuskColors.lightSurface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark
                      ? TuskColors.darkBorder
                      : TuskColors.lightBorder,
                ),
              ),
              child: Icon(
                LucideIcons.folderGit2,
                size: 32,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No missions yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'When you describe a goal on the Home screen, '
              'your structured plan and step history will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
