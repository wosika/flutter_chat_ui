import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:provider/provider.dart';

import 'widgets/composer_action_bar.dart';

class Pagination extends StatefulWidget {
  const Pagination({super.key});

  @override
  PaginationState createState() => PaginationState();
}

class PaginationState extends State<Pagination> {
  InMemoryChatController? _chatController;
  final _currentUser = const User(id: 'me');

  MessageID? _lastMessageId;
  MessageID? _firstMessageId;
  bool _hasMore = true;
  bool _hasNewer = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }
  
  Future<void> _initializeChat() async {
    // Load initial messages (most recent ones)
    final initialMessages = await MockDatabase.getOlderMessages(
      limit: 20,
      lastMessageId: null,
    );
    
    _chatController = InMemoryChatController(messages: initialMessages);
    
    if (initialMessages.isNotEmpty) {
      // For non-reversed list (ChatAnimatedList):
      // - First item (index 0) is the oldest message
      // - Last item is the newest message
      _lastMessageId = initialMessages.first.id;  // Oldest message for loading more old
      _firstMessageId = initialMessages.last.id;  // Newest message for loading more new
      
      // Check if we're already at the newest messages
      final newestId = int.parse(initialMessages.last.id);
      _hasNewer = newestId < 1000;  // Only has newer if not at message #1000
      
      // Check if there are older messages
      final oldestId = int.parse(initialMessages.first.id); 
      _hasMore = oldestId > 1;  // Only has more if not at message #1
    } else {
      _hasNewer = false;
      _hasMore = false;
    }
    
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _chatController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Show loading while initializing
    if (!mounted || _chatController == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pagination')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pagination')),
      body: Chat(
        builders: Builders(
          chatAnimatedListBuilder: (context, itemBuilder) {
            return ChatAnimatedList(
              itemBuilder: itemBuilder,
              onEndReached: _loadMore,
              onStartReached: _loadNewer,
            );
          },
          composerBuilder:
              (context) => CustomComposer(
                topWidget: ComposerActionBar(
                  buttons: [
                    ComposerActionButton(
                      icon: Icons.history,
                      title: 'Jump to #100',
                      onPressed: () => _scrollToMessage('100'),
                    ),
                    ComposerActionButton(
                      icon: Icons.search,
                      title: 'Jump to #500',
                      onPressed: () => _scrollToMessage('500'),
                    ),
                    ComposerActionButton(
                      icon: Icons.bookmark,
                      title: 'Jump to #800',
                      onPressed: () => _scrollToMessage('800'),
                    ),
                  ],
                ),
              ),
        ),
        chatController: _chatController!,
        currentUserId: _currentUser.id,
        resolveUser:
            (id) => Future.value(switch (id) {
              'me' => _currentUser,
              _ => null,
            }),
        theme: ChatTheme.fromThemeData(theme),
      ),
    );
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoading) return;

    _isLoading = true;

    final messages = await MockDatabase.getOlderMessages(
      limit: 20,
      lastMessageId: _lastMessageId,
    );

    if (messages.isEmpty) {
      _hasMore = false;
      _isLoading = false;
      return;
    }

    // Filter out messages that already exist
    final existingIds = _chatController!.messages.map((m) => m.id).toSet();
    final newMessages = messages.where((m) => !existingIds.contains(m.id)).toList();
    
    // Check if messages are now continuous (no gap between old and new messages)
    bool messagesAreContinuous = false;
    if (messages.isNotEmpty && newMessages.length < messages.length) {
      // Some messages were filtered out because they already exist
      // Check if the oldest loaded message connects with existing messages
      final oldestLoadedId = int.parse(messages.last.id);
      final currentOldestId = int.parse(_chatController!.messages.first.id);
      
      // Messages are continuous if there's no gap
      messagesAreContinuous = (currentOldestId - oldestLoadedId) <= 1;
    }
    
    if (newMessages.isNotEmpty) {
      // For non-reversed list: older messages go at the beginning (index 0)
      await _chatController!.insertAllMessages(newMessages, index: 0);
    }
    
    // Update state based on whether we have more messages to load
    if (messages.isEmpty || messagesAreContinuous) {
      // No more older messages to load
      _hasMore = false;
    } else {
      // Always update lastMessageId to the oldest message we tried to load
      if (messages.isNotEmpty) {
        _lastMessageId = messages.last.id;
      }
    }
    
    _isLoading = false;
  }

  Future<void> _loadNewer() async {
    if (!_hasNewer || _isLoading) return;

    _isLoading = true;

    // Get newer messages starting from the newest message ID
    // In a non-reversed list, the newest message is at the end (last)
    final currentNewestId = _chatController!.messages.isNotEmpty 
        ? _chatController!.messages.last.id 
        : '1000';
    
    // Check if we're already at the newest message
    if (int.parse(currentNewestId) >= 1000) {
      _hasNewer = false;
      _isLoading = false;
      return;
    }
    
    final messages = await MockDatabase.getNewerMessages(
      limit: 20,
      firstMessageId: currentNewestId,
    );

    if (messages.isEmpty) {
      _hasNewer = false;
      _isLoading = false;
      return;
    }

    // Filter out messages that already exist
    final existingIds = _chatController!.messages.map((m) => m.id).toSet();
    final newMessages = messages.where((m) => !existingIds.contains(m.id)).toList();
    
    // Check if messages are now continuous (no gap between old and new messages)
    bool messagesAreContinuous = false;
    if (messages.isNotEmpty && newMessages.length < messages.length) {
      // Some messages were filtered out because they already exist
      // Check if the newest loaded message connects with existing messages
      final newestLoadedId = int.parse(messages.first.id);
      final currentNewestId = int.parse(_chatController!.messages.last.id);
      
      // Messages are continuous if there's no gap
      messagesAreContinuous = (newestLoadedId - currentNewestId) <= 1;
    }
    
    if (newMessages.isNotEmpty) {
      // For non-reversed list: newer messages go at the end of the list
      await _chatController!.insertAllMessages(
        newMessages, 
        index: _chatController!.messages.length,
      );
    }
    
    // Update state based on whether we have more messages to load
    if (messages.isEmpty || messagesAreContinuous) {
      // No more newer messages to load
      _hasNewer = false;
    } else {
      // Always update firstMessageId to the newest message we tried to load
      if (messages.isNotEmpty) {
        _firstMessageId = messages.first.id;
      }
    }
    
    _isLoading = false;
  }

  /// Scrolls to a specific message ID, loading messages around it if needed
  Future<void> _scrollToMessage(MessageID messageId) async {
    // First check if the message is already loaded
    final messageExists = _chatController!.messages.any((m) => m.id == messageId);

    if (messageExists) {
      // Message is already loaded, scroll to it directly
      await _chatController!.scrollToMessage(messageId);
      return;
    }

    // Message is not loaded, show loading information
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('Loading message $messageId...'),
        duration: const Duration(seconds: 5),
      ),
    );

    // Load messages around the target message
    final messages = await MockDatabase.getMessagesAround(
      targetId: messageId,
      before: 20,
      after: 20,
    );
    
    if (messages.isEmpty) {
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Message not found'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    // Set the new messages
    await _chatController!.setMessages(messages);
    
    // Update pagination state
    if (messages.isNotEmpty) {
      // For non-reversed list: first item (index 0) is oldest, last item is newest
      _lastMessageId = messages.first.id;   // Oldest message
      _firstMessageId = messages.last.id;   // Newest message
      
      // Check if there are more messages to load in either direction
      final targetIndex = int.parse(messageId) - 1;
      _hasMore = targetIndex > 20; // Has older messages if we jumped far from start
      _hasNewer = targetIndex < 980; // Has newer messages if not at the end
    }

    // Dismiss loading information
    scaffoldMessenger.hideCurrentSnackBar();

    // Wait for the UI to update
    await Future.delayed(const Duration(milliseconds: 100));

    // Scroll to the target message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chatController!.scrollToMessage(messageId);
    });
  }
}

class MockDatabase {
  // Simulate a large database of 1000 messages
  static final List<Message> _allMessages = List.generate(1000, (i) {
    final random = Random();
    final numLines = random.nextInt(4) + 1;
    final text = List.generate(
      numLines,
      (lineIndex) => 'Message ${i + 1} - Line ${lineIndex + 1}',
    ).join('\n');
    return Message.text(
      id: (i + 1).toString(),
      authorId: i % 3 == 0 ? 'me' : 'other_user',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        1736893310000 + (i * 1000), // Messages are chronologically ordered
        isUtc: true,
      ),
      text: text,
    );
  });

  /// Get older messages before a given lastMessageId
  /// This simulates API: getMessages(beforeId: lastMessageId, limit: limit)
  static Future<List<Message>> getOlderMessages({
    required int limit,
    MessageID? lastMessageId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));

    int startIndex;
    if (lastMessageId == null) {
      // If no lastMessageId, start from the most recent messages
      startIndex = _allMessages.length - limit;
    } else {
      // Find the message and get older ones (lower indices)
      final lastIndex = _allMessages.indexWhere((m) => m.id == lastMessageId);
      if (lastIndex == -1) return [];
      startIndex = (lastIndex - limit).clamp(0, lastIndex);
    }

    if (startIndex < 0) return [];

    final endIndex = lastMessageId == null 
        ? _allMessages.length 
        : _allMessages.indexWhere((m) => m.id == lastMessageId);
    
    if (endIndex == -1) return [];

    // For ChatAnimatedList (non-reversed), return messages in chronological order
    // Oldest messages first, newest messages last
    return _allMessages.sublist(startIndex, endIndex).toList();
  }
  
  /// Get newer messages after a given firstMessageId
  /// This simulates API: getMessages(afterId: firstMessageId, limit: limit)
  static Future<List<Message>> getNewerMessages({
    required int limit,
    required MessageID firstMessageId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Find the index of the first message
    final firstIndex = _allMessages.indexWhere((m) => m.id == firstMessageId);
    if (firstIndex == -1 || firstIndex >= _allMessages.length - 1) return [];
    
    // Get newer messages (higher indices)
    final startIndex = firstIndex + 1;
    final endIndex = (startIndex + limit).clamp(startIndex, _allMessages.length);
    
    // For ChatAnimatedList (non-reversed), return messages in chronological order
    // Oldest messages first, newest messages last
    return _allMessages.sublist(startIndex, endIndex).toList();
  }
  
  /// Get messages around a specific messageId for jump functionality
  /// This simulates API: getMessagesAround(messageId: id, before: 10, after: 10)
  static Future<List<Message>> getMessagesAround({
    required MessageID targetId,
    int before = 10,
    int after = 10,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    
    final targetIndex = _allMessages.indexWhere((m) => m.id == targetId);
    if (targetIndex == -1) return [];
    
    final startIndex = (targetIndex - before).clamp(0, _allMessages.length);
    final endIndex = (targetIndex + after + 1).clamp(0, _allMessages.length);
    
    // For ChatAnimatedList (non-reversed), return messages in chronological order
    // Oldest messages first, newest messages last
    return _allMessages.sublist(startIndex, endIndex).toList();
  }
}

class CustomComposer extends StatefulWidget {
  final Widget topWidget;

  const CustomComposer({super.key, required this.topWidget});

  @override
  State<CustomComposer> createState() => _CustomComposerState();
}

class _CustomComposerState extends State<CustomComposer> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant CustomComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    final theme = context.select(
      (ChatTheme t) => (surfaceContainerLow: t.colors.surfaceContainerLow),
    );

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ClipRect(
        child: Container(
          key: _key,
          color: theme.surfaceContainerLow,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomSafeArea),
            child: widget.topWidget,
          ),
        ),
      ),
    );
  }

  void _measure() {
    if (!mounted) return;

    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final height = renderBox.size.height;
      final bottomSafeArea = MediaQuery.of(context).padding.bottom;

      context.read<ComposerHeightNotifier>().setHeight(height - bottomSafeArea);
    }
  }
}
