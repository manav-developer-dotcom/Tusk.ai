import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:tusk_ai/core/theme/tusk_theme.dart';
import '../models/conversation.dart';

/// Mobile-first slide-out drawer sidebar for Tusk.ai.
/// Provides:
/// - New Task / conversation button
/// - Search past conversations with real-time filtering
/// - Recents list ordered by updatedAt
/// - Conversation selection (restores messages)
/// - Conversation rename & delete with confirmation
/// - Settings navigation
/// - Honest empty states for zero history and search misses
class ConversationSidebar extends StatefulWidget {
  final List<Conversation> conversations;
  final String? activeConversationId;
  final VoidCallback onNewTask;
  final ValueChanged<Conversation> onSelectConversation;
  final void Function(String id, String newTitle) onRenameConversation;
  final ValueChanged<String> onDeleteConversation;
  final VoidCallback onOpenSettings;

  const ConversationSidebar({
    super.key,
    required this.conversations,
    required this.activeConversationId,
    required this.onNewTask,
    required this.onSelectConversation,
    required this.onRenameConversation,
    required this.onDeleteConversation,
    required this.onOpenSettings,
  });

  @override
  State<ConversationSidebar> createState() => _ConversationSidebarState();
}

class _ConversationSidebarState extends State<ConversationSidebar> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Conversation> get _filteredConversations {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return widget.conversations;

    return widget.conversations.where((c) {
      final inTitle = c.title.toLowerCase().contains(query);
      final inMessages = c.messages.any((m) => m.text.toLowerCase().contains(query));
      return inTitle || inMessages;
    }).toList();
  }

  void _showRenameDialog(Conversation conversation) {
    final controller = TextEditingController(text: conversation.title);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? TuskColors.darkSurface : TuskColors.lightSurface,
        title: const Text('Rename task', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: TextField(
          key: const Key('rename_dialog_input'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter title',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('rename_dialog_confirm'),
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                widget.onRenameConversation(conversation.id, newTitle);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(Conversation conversation) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? TuskColors.darkSurface : TuskColors.lightSurface,
        title: const Text('Delete task?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: Text(
          'Are you sure you want to delete "${conversation.title}"? This cannot be undone.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('delete_dialog_confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: isDark ? TuskColors.pureWhite : TuskColors.pureBlack,
              foregroundColor: isDark ? TuskColors.pureBlack : TuskColors.pureWhite,
            ),
            onPressed: () {
              widget.onDeleteConversation(conversation.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? TuskColors.darkBackground : TuskColors.lightBackground;
    final textPrimary = isDark ? TuskColors.darkTextPrimary : TuskColors.lightTextPrimary;
    final textSecondary = isDark ? TuskColors.darkTextSecondary : TuskColors.lightTextSecondary;
    final textMuted = isDark ? TuskColors.darkTextMuted : TuskColors.lightTextMuted;
    final border = isDark ? TuskColors.darkBorder : TuskColors.lightBorder;
    final elevated = isDark ? TuskColors.darkSurfaceElevated : TuskColors.lightSurfaceElevated;

    final filtered = _filteredConversations;

    return Drawer(
      backgroundColor: bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with App Title & New Task Button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  const Text(
                    'TUSK',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const Key('sidebar_close_button'),
                    icon: Icon(LucideIcons.x, size: 20, color: textSecondary),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close sidebar',
                  ),
                ],
              ),
            ),

            // New Task Action Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  key: const Key('sidebar_new_task_button'),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onNewTask();
                  },
                  icon: Icon(LucideIcons.plus, size: 18, color: textPrimary),
                  label: Text(
                    'New Task',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Search input field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TextField(
                key: const Key('sidebar_search_input'),
                controller: _searchController,
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search tasks...',
                  prefixIcon: Icon(LucideIcons.search, size: 18, color: textSecondary),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(LucideIcons.x, size: 16, color: textSecondary),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Section Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0),
              child: Text(
                'RECENT TASKS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: textMuted,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Conversation List or Empty States
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _searchQuery.isNotEmpty ? LucideIcons.searchX : LucideIcons.messageSquare,
                              size: 28,
                              color: textMuted,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No matching tasks found'
                                  : 'No previous conversations',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final conv = filtered[index];
                        final isActive = conv.id == widget.activeConversationId;

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 2.0),
                          decoration: BoxDecoration(
                            color: isActive ? elevated : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListTile(
                            key: Key('conversation_tile_${conv.id}'),
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 2.0),
                            leading: Icon(
                              LucideIcons.messageSquare,
                              size: 16,
                              color: isActive ? textPrimary : textSecondary,
                            ),
                            title: Text(
                              conv.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                                color: textPrimary,
                              ),
                            ),
                            trailing: PopupMenuButton<String>(
                              key: Key('conversation_menu_${conv.id}'),
                              icon: Icon(LucideIcons.moreVertical, size: 16, color: textSecondary),
                              onSelected: (val) {
                                if (val == 'rename') {
                                  _showRenameDialog(conv);
                                } else if (val == 'delete') {
                                  _showDeleteDialog(conv);
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(
                                  value: 'rename',
                                  child: Row(
                                    children: [
                                      Icon(LucideIcons.edit2, size: 16),
                                      SizedBox(width: 10),
                                      Text('Rename'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(LucideIcons.trash2, size: 16),
                                      SizedBox(width: 10),
                                      Text('Delete'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              widget.onSelectConversation(conv);
                            },
                          ),
                        );
                      },
                    ),
            ),

            // Divider and Settings Entry
            Divider(color: isDark ? TuskColors.darkDivider : TuskColors.lightDivider),
            ListTile(
              key: const Key('sidebar_settings_button'),
              leading: Icon(LucideIcons.settings, size: 18, color: textSecondary),
              title: Text('Settings', style: TextStyle(fontSize: 14, color: textPrimary)),
              onTap: () {
                Navigator.pop(context);
                widget.onOpenSettings();
              },
            ),
          ],
        ),
      ),
    );
  }
}
