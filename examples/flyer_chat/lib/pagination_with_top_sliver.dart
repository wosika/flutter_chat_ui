import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:provider/provider.dart';

import 'pagination_mock_database.dart';
import 'widgets/composer_action_bar.dart';

/// A test page to verify pagination behavior with a large topSliver.
///
/// This demo validates that:
/// 1. Pagination triggers based on visible message indices, not scroll position
/// 2. The topSliver doesn't affect pagination timing
/// 3. Scroll position is maintained correctly after loading older messages
class PaginationWithTopSliver extends StatefulWidget {
  const PaginationWithTopSliver({super.key});

  @override
  PaginationWithTopSliverState createState() => PaginationWithTopSliverState();
}

class PaginationWithTopSliverState extends State<PaginationWithTopSliver> {
  final _chatController = InMemoryChatController(
    messages: List.from(MockDatabase.initialNewerMessages),
  );
  final _currentUser = const User(id: 'me');

  MessageID? _lastMessageId;
  bool _hasMore = true;
  bool _isLoading = false;

  // Debug info
  int _loadCount = 0;
  String _lastAnchorInfo = '';

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagination with TopSliver'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showDebugInfo,
          ),
        ],
      ),
      body: Chat(
        builders: Builders(
          chatAnimatedListBuilder: (context, itemBuilder) {
            return ChatAnimatedList(
              itemBuilder: itemBuilder,
              onEndReached: _loadOlderMessages,
              // Large topSliver to test pagination behavior
              topSlivers: [
                SliverToBoxAdapter(
                  child: Container(
                    height: 500,
                    color: theme.colorScheme.primaryContainer,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.photo_library,
                            size: 64,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Top Sliver (500px)',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'Scroll up to see how pagination triggers.\n'
                              'It should trigger based on visible messages,\n'
                              'not when scrolling through this area.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Load count: $_loadCount',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
          composerBuilder: (context) => CustomComposer(
            topWidget: ComposerActionBar(
              buttons: [
                ComposerActionButton(
                  icon: Icons.arrow_upward,
                  title: 'Scroll to 1',
                  onPressed: () => _scrollToMessage('1'),
                ),
                ComposerActionButton(
                  icon: Icons.arrow_upward,
                  title: 'Scroll to 40',
                  onPressed: () => _scrollToMessage('40'),
                ),
                ComposerActionButton(
                  icon: Icons.arrow_upward,
                  title: 'Scroll to 80',
                  onPressed: () => _scrollToMessage('80'),
                ),
                ComposerActionButton(
                  icon: Icons.keyboard_arrow_down,
                  title: 'Scroll to bottom',
                  onPressed: () => _chatController.scrollToBottom(),
                ),
                  ComposerActionButton(
                  icon: Icons.keyboard_arrow_up,
                  title: 'Scroll to up',
                  onPressed: () => _chatController.scrollToTop(),
                ),
              ],
            ),
          ),
        ),
        chatController: _chatController,
        currentUserId: _currentUser.id,
        resolveUser: (id) => Future.value(switch (id) {
          'me' => _currentUser,
          _ => null,
        }),
        theme: ChatTheme.fromThemeData(theme),
      ),
    );
  }

  Future<void> _loadOlderMessages() async {
    if (!_hasMore || _isLoading) {
      debugPrint(
        '[PaginationWithTopSliver] _loadOlderMessages skipped: '
        'hasMore=$_hasMore, isLoading=$_isLoading',
      );
      return;
    }

    _isLoading = true;
    _loadCount++;

    final messagesBefore = _chatController.messages.length;
    final firstMessageBefore = _chatController.messages.isNotEmpty
        ? _chatController.messages.first.id
        : 'none';

    debugPrint(
      '[PaginationWithTopSliver] ====== Load #$_loadCount Started ======',
    );
    debugPrint(
      '[PaginationWithTopSliver] Messages before: $messagesBefore, '
      'First message: $firstMessageBefore',
    );
    debugPrint(
      '[PaginationWithTopSliver] Last message ID for query: $_lastMessageId',
    );

    final messages = await MockDatabase.getOlderMessages(
      limit: 20,
      lastMessageId: _lastMessageId,
    );

    debugPrint(
      '[PaginationWithTopSliver] Received ${messages.length} messages from DB',
    );

    if (messages.isEmpty) {
      _hasMore = false;
      _isLoading = false;
      debugPrint('[PaginationWithTopSliver] No more messages available');
      return;
    }

    debugPrint(
      '[PaginationWithTopSliver] Message IDs: '
      '${messages.map((m) => m.id).join(", ")}',
    );

    await _chatController.insertAllMessages(
      messages,
      index: 0,
      animated: false,
    );

    final messagesAfter = _chatController.messages.length;
    final firstMessageAfter = _chatController.messages.first.id;

    _lastAnchorInfo =
        'Before: $messagesBefore msgs (first: $firstMessageBefore)\n'
        'After: $messagesAfter msgs (first: $firstMessageAfter)\n'
        'Added: ${messages.length} msgs';

    debugPrint(
      '[PaginationWithTopSliver] Messages after: $messagesAfter, '
      'First message: $firstMessageAfter',
    );
    debugPrint(
      '[PaginationWithTopSliver] ====== Load #$_loadCount Completed ======',
    );

    _lastMessageId = messages.first.id;
    _isLoading = false;

    // Update UI to show load count
    if (mounted) {
      setState(() {});
    }
  }

  void _showDebugInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Debug Info'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Total loads: $_loadCount'),
              const SizedBox(height: 8),
              Text('Messages in list: ${_chatController.messages.length}'),
              const SizedBox(height: 8),
              Text('Has more: $_hasMore'),
              const SizedBox(height: 8),
              Text('Is loading: $_isLoading'),
              const SizedBox(height: 16),
              const Text(
                'Last load info:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(_lastAnchorInfo.isEmpty ? 'No loads yet' : _lastAnchorInfo),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _scrollToMessage(MessageID messageId) async {
    var messageExists = _chatController.messages.any((m) => m.id == messageId);

    if (messageExists) {
      await _chatController.scrollToMessage(messageId, offset: 0);
      return;
    }

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('Loading message $messageId...'),
        duration: const Duration(minutes: 1),
      ),
    );

    while (!messageExists && _hasMore) {
      await _loadOlderMessages();
      messageExists = _chatController.messages.any((m) => m.id == messageId);
    }

    scaffoldMessenger.hideCurrentSnackBar();

    await _chatController.scrollToMessage(messageId, offset: 0);
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
