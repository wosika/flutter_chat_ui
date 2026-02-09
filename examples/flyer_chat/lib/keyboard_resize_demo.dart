import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:provider/provider.dart';

import 'pagination_mock_database.dart';
import 'widgets/composer_action_bar.dart';

/// Custom ScrollPosition that keeps bottom content visible when viewport shrinks.
/// This makes a forward list behave like a reversed list during keyboard resize.
class _BottomKeepingScrollPosition extends ScrollPositionWithSingleContext {
  double? _previousViewportDimension;
  bool keepBottomOnResize = true;

  _BottomKeepingScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    super.initialPixels,
  });

  @override
  bool applyViewportDimension(double viewportDimension) {
    final previous = _previousViewportDimension;
    _previousViewportDimension = viewportDimension;

    final result = super.applyViewportDimension(viewportDimension);

    if (keepBottomOnResize &&
        previous != null &&
        previous != viewportDimension) {
      final delta = previous - viewportDimension;
      correctBy(delta);
    }

    return result;
  }
}

/// Custom ScrollController that creates _BottomKeepingScrollPosition.
class BottomKeepingScrollController extends ScrollController {
  bool _keepBottomOnResize = true;

  set keepBottomOnResize(bool value) {
    _keepBottomOnResize = value;
    for (final position in positions) {
      if (position is _BottomKeepingScrollPosition) {
        position.keepBottomOnResize = value;
      }
    }
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _BottomKeepingScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      initialPixels: initialScrollOffset,
    )..keepBottomOnResize = _keepBottomOnResize;
  }
}

class KeyboardResizeDemo extends StatefulWidget {
  const KeyboardResizeDemo({super.key});

  @override
  State<KeyboardResizeDemo> createState() => _KeyboardResizeDemoState();
}

class _KeyboardResizeDemoState extends State<KeyboardResizeDemo>
    with WidgetsBindingObserver {
  final _chatController = InMemoryChatController(
    messages: List.from(MockDatabase.initialNewerMessages),
  );
  final _scrollController = BottomKeepingScrollController();
  final _focusNode = FocusNode();

  static const double _bottomThreshold = 10.0;

  final _currentUser = const User(id: 'me');

  bool _isAtBottom = true;
  bool _lockedIsAtBottom = true;
  bool _isKeyboardVisible = false;

  MessageID? _lastMessageId;
  bool _hasMore = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScrollChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    _focusNode.dispose();
    _chatController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final bottomInset = WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .first
        .viewInsets
        .bottom;
    final keyboardVisible = bottomInset > 0;

    if (keyboardVisible && !_isKeyboardVisible) {
      _isKeyboardVisible = true;
      _lockedIsAtBottom = _isAtBottom;
      _scrollController.keepBottomOnResize = _isAtBottom;
    } else if (!keyboardVisible && _isKeyboardVisible) {
      _isKeyboardVisible = false;
      _scrollController.keepBottomOnResize = _isAtBottom;
    }
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final isAtBottom =
        _scrollController.offset >= maxScroll - _bottomThreshold;

    if (_isAtBottom != isAtBottom) {
      setState(() {
        _isAtBottom = isAtBottom;
      });
    }
  }

  Future<void> _loadOlderMessages() async {
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

    await _chatController.insertAllMessages(
      messages,
      index: 0,
      animated: false,
    );
    _lastMessageId = messages.first.id;
    _isLoading = false;
  }

  Future<void> _scrollToMessage(MessageID messageId) async {
    var messageExists =
        _chatController.messages.any((m) => m.id == messageId);

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
      messageExists =
          _chatController.messages.any((m) => m.id == messageId);
    }

    scaffoldMessenger.hideCurrentSnackBar();
    await _chatController.scrollToMessage(messageId, offset: 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

    final effectiveIsAtBottom =
        _isKeyboardVisible ? _lockedIsAtBottom : _isAtBottom;

    final composerBottomPadding =
        (!effectiveIsAtBottom && keyboardHeight > 0) ? keyboardHeight : 0.0;

    return Scaffold(
      resizeToAvoidBottomInset: effectiveIsAtBottom,
      appBar: AppBar(
        title: const Text('Keyboard Resize Demo'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              label: Text(
                _isAtBottom ? 'Bottom' : 'Scrolled',
                style: const TextStyle(fontSize: 12),
              ),
              backgroundColor: _isAtBottom ? Colors.green : Colors.orange,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              label: Text(
                effectiveIsAtBottom ? 'Resize' : 'Overlay',
                style: const TextStyle(fontSize: 12),
              ),
              backgroundColor:
                  effectiveIsAtBottom ? Colors.blue : Colors.purple,
            ),
          ),
        ],
      ),
      body: Chat(
        builders: Builders(
          chatAnimatedListBuilder: (context, itemBuilder) {
            return Stack(
              children: [
                ChatAnimatedList(
                  shouldAdjustScrollOnKeyboard: false,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.manual,
                  itemBuilder: itemBuilder,
                  scrollController: _scrollController,
                  bottomPadding: 80,
                  onEndReached: _loadOlderMessages,
                  topSlivers: [
                    SliverToBoxAdapter(
                      child: Container(
                        height: 200,
                        color: theme.colorScheme.primaryContainer,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.photo_library,
                                size: 48,
                                color:
                                    theme.colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Top Sliver (200px)',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(
                                      color: theme
                                          .colorScheme
                                          .onPrimaryContainer,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: composerBottomPadding,
                  child: _CustomComposer(
                    focusNode: _focusNode,
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
                          icon: Icons.keyboard_arrow_down,
                          title: 'To bottom',
                          onPressed: () =>
                              _chatController.scrollToBottom(),
                        ),
                        ComposerActionButton(
                          icon: Icons.keyboard_arrow_up,
                          title: 'To top',
                          onPressed: () =>
                              _chatController.scrollToTop(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
          composerBuilder: (context) {
            return const SizedBox.shrink();
          },
          textMessageBuilder: (
            context,
            message,
            index, {
            required bool isSentByMe,
            MessageGroupStatus? groupStatus,
          }) =>
              FlyerChatTextMessage(message: message, index: index),
        ),
        chatController: _chatController,
        currentUserId: _currentUser.id,
        onMessageSend: (text) {
          if (text == null || text.trim().isEmpty) return;
          _chatController.insertMessage(
            Message.text(
              id: UniqueKey().toString(),
              authorId: _currentUser.id,
              createdAt: DateTime.now().toUtc(),
              text: text,
            ),
          );
        },
        resolveUser: (id) => Future.value(switch (id) {
          'me' => _currentUser,
          _ => null,
        }),
        theme: ChatTheme.fromThemeData(theme),
      ),
    );
  }
}

/// Custom composer that reports its height via ComposerHeightNotifier.
class _CustomComposer extends StatefulWidget {
  final FocusNode focusNode;
  final Widget topWidget;

  const _CustomComposer({
    required this.focusNode,
    required this.topWidget,
  });

  @override
  State<_CustomComposer> createState() => _CustomComposerState();
}

class _CustomComposerState extends State<_CustomComposer> {
  final _key = GlobalKey();
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant _CustomComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    final chatTheme = context.select(
      (ChatTheme t) => (
        surfaceContainerLow: t.colors.surfaceContainerLow,
        surfaceContainerHigh: t.colors.surfaceContainerHigh,
        onSurface: t.colors.onSurface,
        bodyMedium: t.typography.bodyMedium,
      ),
    );

    return ClipRect(
      child: Container(
        key: _key,
        color: chatTheme.surfaceContainerLow,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomSafeArea),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.topWidget,
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: widget.focusNode,
                        decoration: InputDecoration(
                          hintText: 'Type a message',
                          hintStyle: chatTheme.bodyMedium.copyWith(
                            color: chatTheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                          border: const OutlineInputBorder(
                            borderRadius:
                                BorderRadius.all(Radius.circular(24)),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: chatTheme.surfaceContainerHigh
                              .withValues(alpha: 0.8),
                        ),
                        style: chatTheme.bodyMedium.copyWith(
                          color: chatTheme.onSurface,
                        ),
                        onSubmitted: _handleSend,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send),
                      color: chatTheme.onSurface.withValues(alpha: 0.5),
                      onPressed: () => _handleSend(_textController.text),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSend(String text) {
    if (text.trim().isEmpty) return;
    context.read<OnMessageSendCallback?>()?.call(text.trim());
    _textController.clear();
  }

  void _measure() {
    if (!mounted) return;

    final renderBox =
        _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final height = renderBox.size.height;
      final bottomSafeArea = MediaQuery.of(context).padding.bottom;

      context
          .read<ComposerHeightNotifier>()
          .setHeight(height - bottomSafeArea);
    }
  }
}
