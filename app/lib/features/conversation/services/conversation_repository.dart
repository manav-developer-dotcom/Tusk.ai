import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation.dart';

/// Genuine local persistence for Tusk.ai conversations using SharedPreferences.
/// Stores conversation list and message history across app restarts.
class ConversationRepository {
  static const String _storageKey = 'tusk_conversations_v1';
  final SharedPreferences _prefs;

  ConversationRepository(this._prefs);

  static Future<ConversationRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return ConversationRepository(prefs);
  }

  /// Load all conversations, ordered by updatedAt descending.
  List<Conversation> loadConversations() {
    final rawJson = _prefs.getString(_storageKey);
    if (rawJson == null || rawJson.trim().isEmpty) {
      return [];
    }

    try {
      final List<dynamic> decoded = jsonDecode(rawJson) as List<dynamic>;
      final list = decoded
          .map((item) => Conversation.fromMap(item as Map<String, dynamic>))
          .toList();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Save the entire conversation list to disk.
  Future<void> saveConversations(List<Conversation> conversations) async {
    final mapped = conversations.map((c) => c.toMap()).toList();
    await _prefs.setString(_storageKey, jsonEncode(mapped));
  }

  /// Upsert a conversation.
  Future<void> saveConversation(Conversation conversation) async {
    final current = loadConversations();
    final index = current.indexWhere((c) => c.id == conversation.id);
    if (index >= 0) {
      current[index] = conversation;
    } else {
      current.insert(0, conversation);
    }
    await saveConversations(current);
  }

  /// Delete a conversation by ID.
  Future<void> deleteConversation(String id) async {
    final current = loadConversations();
    current.removeWhere((c) => c.id == id);
    await saveConversations(current);
  }

  /// Rename a conversation.
  Future<void> renameConversation(String id, String newTitle) async {
    final current = loadConversations();
    final index = current.indexWhere((c) => c.id == id);
    if (index >= 0) {
      current[index].title = newTitle;
      current[index].updatedAt = DateTime.now();
      await saveConversations(current);
    }
  }

  /// Search conversations by query against title and message text.
  List<Conversation> search(String query) {
    final all = loadConversations();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all;

    return all.where((c) {
      final titleMatch = c.title.toLowerCase().contains(q);
      final messageMatch = c.messages.any((m) => m.text.toLowerCase().contains(q));
      return titleMatch || messageMatch;
    }).toList();
  }
}
