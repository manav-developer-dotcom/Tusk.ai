import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/network/api_client.dart';
import 'core/network/api_config.dart';
import 'core/theme/tusk_theme.dart';
import 'core/widgets/tusk_wordmark_shine.dart';
import 'features/onboarding/welcome_screen.dart';
import 'features/home/home_screen.dart';
import 'features/projects/projects_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/conversation/models/conversation.dart';
import 'features/conversation/services/conversation_repository.dart';
import 'features/conversation/widgets/conversation_sidebar.dart';
import 'features/mission/services/mission_api_service.dart';
import 'features/mission/services/mission_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final apiConfig = ApiConfig(prefs);
  final apiClient = ApiClient(config: apiConfig);
  final apiService = MissionApiService(apiClient);
  final convRepo = ConversationRepository(prefs);
  final missionRepo = MissionRepository(prefs, apiService: apiService);

  runApp(TuskApp(
    convRepository: convRepo,
    missionRepository: missionRepo,
    apiConfig: apiConfig,
  ));
}

class TuskApp extends StatefulWidget {
  final ConversationRepository? convRepository;
  final MissionRepository? missionRepository;
  final ApiConfig? apiConfig;

  const TuskApp({
    super.key,
    this.convRepository,
    this.missionRepository,
    this.apiConfig,
  });

  @override
  State<TuskApp> createState() => _TuskAppState();
}

class _TuskAppState extends State<TuskApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _updateThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tusk.ai',
      debugShowCheckedModeBanner: false,
      theme: TuskTheme.lightTheme(),
      darkTheme: TuskTheme.darkTheme(),
      themeMode: _themeMode,
      home: TuskRootNavigation(
        convRepository: widget.convRepository,
        missionRepository: widget.missionRepository,
        apiConfig: widget.apiConfig,
        currentThemeMode: _themeMode,
        onThemeChanged: _updateThemeMode,
      ),
    );
  }
}

class TuskRootNavigation extends StatefulWidget {
  final ConversationRepository? convRepository;
  final MissionRepository? missionRepository;
  final ApiConfig? apiConfig;
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  const TuskRootNavigation({
    super.key,
    this.convRepository,
    this.missionRepository,
    this.apiConfig,
    required this.currentThemeMode,
    required this.onThemeChanged,
  });

  @override
  State<TuskRootNavigation> createState() => _TuskRootNavigationState();
}

class _TuskRootNavigationState extends State<TuskRootNavigation> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _splashDone = false;
  bool _hasSeenWelcome = false;
  int _currentIndex = 0;

  late ConversationRepository _convRepo;
  late MissionRepository _missionRepo;
  ApiConfig? _apiConfig;

  List<Conversation> _conversations = [];
  Conversation? _activeConversation;

  @override
  void initState() {
    super.initState();
    _apiConfig = widget.apiConfig;
    _initRepositories();
  }

  void _initRepositories() {
    if (widget.convRepository != null && widget.missionRepository != null) {
      _convRepo = widget.convRepository!;
      _missionRepo = widget.missionRepository!;
      _loadConversations();
    } else {
      SharedPreferences.getInstance().then((prefs) {
        if (mounted) {
          final config = _apiConfig ?? ApiConfig(prefs);
          final apiClient = ApiClient(config: config);
          final apiService = MissionApiService(apiClient);
          setState(() {
            _apiConfig = config;
            _convRepo = ConversationRepository(prefs);
            _missionRepo = MissionRepository(prefs, apiService: apiService);
            _loadConversations();
          });
        }
      });
    }
  }

  void _loadConversations() {
    final list = _convRepo.loadConversations();
    if (mounted) {
      setState(() => _conversations = list);
    }
  }

  void _onSplashComplete() {
    if (mounted) setState(() => _splashDone = true);
  }

  void _onWelcomeDismissed() {
    setState(() => _hasSeenWelcome = true);
  }

  void _onNewTask() {
    setState(() {
      _activeConversation = null;
      _currentIndex = 0;
    });
  }

  void _onSelectConversation(Conversation conversation) {
    setState(() {
      _activeConversation = conversation;
      _currentIndex = 0;
    });
  }

  void _onRenameConversation(String id, String newTitle) async {
    await _convRepo.renameConversation(id, newTitle);
    _loadConversations();
    if (_activeConversation?.id == id) {
      setState(() => _activeConversation?.title = newTitle);
    }
  }

  Future<void> _onDeleteConversation(String id) async {
    // Detach missions from the conversation (preserves them, nulls conversationId)
    await _missionRepo.detachConversation(id);
    await _convRepo.deleteConversation(id);
    _loadConversations();
    if (_activeConversation?.id == id) {
      setState(() => _activeConversation = null);
    }
  }

  /// Handles both real user goals and internal system messages
  /// (prefixed with '__system__') from the mission flow.
  void _onSubmitGoal(String rawText) async {
    final now = DateTime.now();
    var conv = _activeConversation;

    // Create a new conversation if none is active
    if (conv == null) {
      final visibleText = rawText.startsWith('__system__')
          ? rawText.substring('__system__'.length)
          : rawText;
      final title = visibleText.length > 36
          ? '${visibleText.substring(0, 36)}...'
          : visibleText;
      conv = Conversation(
        id: 'conv_${now.millisecondsSinceEpoch}',
        title: title,
        createdAt: now,
        updatedAt: now,
      );
      if (mounted) setState(() => _activeConversation = conv);
    }

    // Determine message visibility and sender
    final isSystem = rawText.startsWith('__system__');
    final messageText =
        isSystem ? rawText.substring('__system__'.length) : rawText;

    if (messageText.isEmpty) {
      // Empty system message — just save conversation state
      await _convRepo.saveConversation(conv);
      _loadConversations();
      return;
    }

    conv.messages.add(Message(
      id: 'msg_${now.millisecondsSinceEpoch}_${conv.messages.length}',
      text: isSystem ? '__system__$messageText' : messageText,
      isUser: !isSystem,
      timestamp: now,
    ));

    conv.updatedAt = now;
    await _convRepo.saveConversation(conv);
    _loadConversations();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_splashDone) {
      return TuskSplashReveal(onComplete: _onSplashComplete);
    }
    if (!_hasSeenWelcome) {
      return WelcomeScreen(onGetStarted: _onWelcomeDismissed);
    }

    final screens = [
      HomeScreen(
        activeConversation: _activeConversation,
        onOpenSidebar: () => _scaffoldKey.currentState?.openDrawer(),
        onSubmitGoal: _onSubmitGoal,
        missionRepository: _missionRepo,
      ),
      ProjectsScreen(missionRepository: _missionRepo),
      SettingsScreen(
        currentThemeMode: widget.currentThemeMode,
        onThemeChanged: widget.onThemeChanged,
        apiConfig: _apiConfig,
      ),
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: ConversationSidebar(
        conversations: _conversations,
        activeConversationId: _activeConversation?.id,
        onNewTask: _onNewTask,
        onSelectConversation: _onSelectConversation,
        onRenameConversation: _onRenameConversation,
        onDeleteConversation: _onDeleteConversation,
        onOpenSettings: () => setState(() => _currentIndex = 2),
      ),
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(LucideIcons.compass, size: 20),
            activeIcon: Icon(LucideIcons.compass, size: 20),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(LucideIcons.folderGit2, size: 20),
            activeIcon: Icon(LucideIcons.folderGit2, size: 20),
            label: 'Projects',
          ),
          BottomNavigationBarItem(
            icon: Icon(LucideIcons.settings, size: 20),
            activeIcon: Icon(LucideIcons.settings, size: 20),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
