# flutter_chat_ui 正向列表完整功能实现指南

基于 `ChatAnimatedList`（正向列表）实现以下功能：
1. 加载更多旧消息（分页）
2. 动态软键盘行为（底部顶起 / 非底部覆盖）
3. 滑动到底部 / 滑动到顶部
4. 初始滚动位置控制（默认居底/居顶）

## 整体架构

```
Scaffold (resizeToAvoidBottomInset: 动态)
└── Chat
    └── Stack (通过 chatAnimatedListBuilder 返回)
        ├── ChatAnimatedList (正向列表 + 自定义 ScrollController)
        │   ├── topSlivers (可选顶部区域)
        │   ├── 消息列表
        │   └── bottomPadding (预留输入框空间)
        └── Positioned (自定义 Composer，动态 bottom)
            ├── ActionBar (可选操作按钮)
            └── TextField + SendButton
```

核心思路：
- 不使用默认 Composer，通过 Stack 自己控制输入框位置
- 自定义 `ScrollController` + `ScrollPosition` 实现丝滑键盘顶起
- 通过 `ComposerHeightNotifier` 让列表自动预留输入框空间
- 初始滚动位置通过 `postFrameCallback` + `scrollToBottom()` 控制

---

## 一、BottomKeepingScrollController（正向列表丝滑键盘顶起）

### 为什么需要

正向列表的 viewport 缩小时（键盘弹出），Flutter 默认保持顶部内容不动，底部被截断。
反向列表则天然保持底部内容不动。

自定义 `ScrollPosition` 重写 `applyViewportDimension`，在 layout 阶段同步调用 `correctBy(delta)` 调整 offset，让正向列表也能逐帧跟随 viewport 变化，和反向列表一样丝滑。

### 代码

```dart
/// 自定义 ScrollPosition：viewport 缩小时同步调整 offset，保持底部内容可见
class BottomKeepingScrollPosition extends ScrollPositionWithSingleContext {
  double? _previousViewportDimension;
  bool keepBottomOnResize = true;

  BottomKeepingScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
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

/// 自定义 ScrollController：创建 BottomKeepingScrollPosition
class BottomKeepingScrollController extends ScrollController {
  bool _keepBottomOnResize = true;

  set keepBottomOnResize(bool value) {
    _keepBottomOnResize = value;
    for (final position in positions) {
      if (position is BottomKeepingScrollPosition) {
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
    return BottomKeepingScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
    )..keepBottomOnResize = _keepBottomOnResize;
  }
}
```

### 原理

```
反向列表（天然丝滑）：
  viewport 缩小 → 底部内容自动保持可见（growthDirection 向上）

正向列表（默认行为）：
  viewport 缩小 → 顶部内容保持不动，底部被截断

正向列表 + BottomKeepingScrollPosition：
  viewport 缩小 delta → correctBy(delta) → offset 增加 delta → 底部内容保持可见
  每一帧都同步调整，和反向列表一样丝滑
```

---

## 二、State 类声明

```dart
class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final _chatController = InMemoryChatController(messages: [...]);
  final _scrollController = BottomKeepingScrollController();
  final _focusNode = FocusNode();

  static const double _bottomThreshold = 10.0;

  // --- 键盘状态 ---
  bool _isAtBottom = true;
  bool _lockedIsAtBottom = true;   // 键盘弹出时锁定
  bool _isKeyboardVisible = false;

  // --- 分页状态 ---
  MessageID? _lastMessageId;
  bool _hasMore = true;
  bool _isLoading = false;
```

---

## 三、生命周期

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  _scrollController.addListener(_onScrollChanged);

  // 默认居底：第一帧渲染后跳到底部
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _chatController.scrollToBottom();
  });
  // 默认居顶：去掉上面的 postFrameCallback 即可
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
```

### 初始滚动位置

| 需求 | 做法 |
|------|------|
| 默认居底 | `initState` 中 `postFrameCallback` + `_chatController.scrollToBottom()` |
| 默认居顶 | 不做任何处理（默认行为） |

**注意**：配合 `initialScrollToEndMode: InitialScrollToEndMode.none` 使用，关掉库自带的初始滚动逻辑，完全由自己控制。

---

## 四、键盘监听

```dart
@override
void didChangeMetrics() {
  final bottomInset = WidgetsBinding
      .instance.platformDispatcher.views.first.viewInsets.bottom;
  final keyboardVisible = bottomInset > 0;

  if (keyboardVisible && !_isKeyboardVisible) {
    // 键盘弹出 → 锁定当前状态，设置 ScrollController
    _isKeyboardVisible = true;
    _lockedIsAtBottom = _isAtBottom;
    _scrollController.keepBottomOnResize = _isAtBottom;
  } else if (!keyboardVisible && _isKeyboardVisible) {
    // 键盘收起
    _isKeyboardVisible = false;
    _scrollController.keepBottomOnResize = _isAtBottom;
  }
}
```

**关键**：
- 键盘弹出时锁定 `_lockedIsAtBottom`，整个键盘显示期间不变
- `keepBottomOnResize = _isAtBottom`：在底部时启用丝滑顶起，不在底部时禁用
- **不在 `didChangeMetrics` 中调用 `setState`**，避免键盘动画过程中触发重建

---

## 五、滚动位置监听（正向列表）

```dart
void _onScrollChanged() {
  if (!_scrollController.hasClients) return;

  final maxScroll = _scrollController.position.maxScrollExtent;
  final isAtBottom = _scrollController.offset >= maxScroll - _bottomThreshold;

  if (_isAtBottom != isAtBottom) {
    setState(() {
      _isAtBottom = isAtBottom;
    });
  }
}
```

**正向 vs 反向列表底部判断**：

| 列表类型 | 在底部的条件 |
|----------|-------------|
| 正向列表 | `offset >= maxScrollExtent - threshold` |
| 反向列表 | `offset <= threshold` |

---

## 六、加载更多旧消息

```dart
Future<void> _loadOlderMessages() async {
  if (!_hasMore || _isLoading) return;

  _isLoading = true;

  // 从你的数据源获取旧消息
  final messages = await YourApi.getOlderMessages(
    limit: 20,
    lastMessageId: _lastMessageId,
  );

  if (messages.isEmpty) {
    _hasMore = false;
    _isLoading = false;
    return;
  }

  // 插入到列表头部，不带动画
  await _chatController.insertAllMessages(
    messages,
    index: 0,
    animated: false,
  );
  _lastMessageId = messages.first.id;
  _isLoading = false;
}
```

**关键参数**：
- `index: 0`：插入到列表头部（旧消息在前）
- `animated: false`：分页消息不需要动画，且分页锚定逻辑依赖即时插入

**触发方式**：通过 `ChatAnimatedList` 的 `onEndReached` 参数，滚动到顶部时自动触发。

---

## 七、滑动到指定消息（自动加载缺失页）

```dart
Future<void> _scrollToMessage(MessageID messageId) async {
  var exists = _chatController.messages.any((m) => m.id == messageId);

  if (exists) {
    await _chatController.scrollToMessage(messageId, offset: 0);
    return;
  }

  // 消息未加载，持续加载直到找到
  while (!exists && _hasMore) {
    await _loadOlderMessages();
    exists = _chatController.messages.any((m) => m.id == messageId);
  }

  await _chatController.scrollToMessage(messageId, offset: 0);
}
```

---

## 八、滑动到底部 / 顶部

```dart
// 滑动到底部
_chatController.scrollToBottom();

// 滑动到顶部
_chatController.scrollToTop();
```

这两个方法由 `ChatController` 提供，内部通过 `ScrollToMessageMixin` 实现。

---

## 九、build 方法

```dart
@override
Widget build(BuildContext context) {
  final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

  // 键盘可见时用锁定值
  final effectiveIsAtBottom =
      _isKeyboardVisible ? _lockedIsAtBottom : _isAtBottom;

  // 非底部 + 键盘可见 → 手动顶起输入框
  final composerBottomPadding =
      (!effectiveIsAtBottom && keyboardHeight > 0) ? keyboardHeight : 0.0;

  return Scaffold(
    resizeToAvoidBottomInset: effectiveIsAtBottom,
    body: Chat(
      builders: Builders(
        chatAnimatedListBuilder: (context, itemBuilder) {
          return Stack(
            children: [
              ChatAnimatedList(
                shouldAdjustScrollOnKeyboard: false,
                initialScrollToEndMode: InitialScrollToEndMode.none,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                itemBuilder: itemBuilder,
                scrollController: _scrollController,
                bottomPadding: 80,  // 预留输入框高度
                onEndReached: _loadOlderMessages,
                topSlivers: [
                  // 可选：顶部 sliver
                  SliverToBoxAdapter(child: YourTopWidget()),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: composerBottomPadding,
                child: YourCustomComposer(focusNode: _focusNode),
              ),
            ],
          );
        },
        composerBuilder: (context) => const SizedBox.shrink(),
      ),
      chatController: _chatController,
      currentUserId: 'user-id',
      onMessageSend: _handleSend,
      resolveUser: (id) async => User(id: id),
    ),
  );
}
```

**关键参数说明**：

| 参数 | 值 | 说明 |
|------|------|------|
| `resizeToAvoidBottomInset` | `effectiveIsAtBottom` | 底部时 true（Scaffold 顶起），非底部时 false |
| `shouldAdjustScrollOnKeyboard` | `false` | 关掉库自带的延迟调整，由自定义 ScrollPosition 接管 |
| `initialScrollToEndMode` | `none` | 关掉库自带的初始滚动，由 `postFrameCallback` + `scrollToBottom()` 接管 |
| `keyboardDismissBehavior` | `manual` | 滑动列表时不自动收起键盘 |
| `bottomPadding` | `80` | 列表底部预留空间，避免被输入框遮挡 |
| `onEndReached` | `_loadOlderMessages` | 滚动到顶部时触发加载旧消息 |
| `topSlivers` | `[SliverToBoxAdapter(...)]` | 可选的顶部区域（如用户资料卡片等） |
| `composerBuilder` | `SizedBox.shrink()` | 隐藏默认 Composer，使用自定义的 |

---

## 十、自定义 Composer（通知列表预留空间）

自定义 Composer 必须通过 `ComposerHeightNotifier` 报告高度，列表才能自动预留底部空间。

```dart
class CustomComposer extends StatefulWidget {
  final FocusNode focusNode;
  const CustomComposer({super.key, required this.focusNode});

  @override
  State<CustomComposer> createState() => _CustomComposerState();
}

class _CustomComposerState extends State<CustomComposer> {
  final _key = GlobalKey();
  final _textController = TextEditingController();

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
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: Container(
        key: _key,
        color: Colors.white,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomSafeArea),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 可选：action bar 等
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: widget.focusNode,
                        decoration: const InputDecoration(
                          hintText: 'Type a message',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(24)),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                        ),
                        onSubmitted: _handleSend,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send),
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
    // 通过 Provider 调用 Chat 的 onMessageSend
    context.read<OnMessageSendCallback?>()?.call(text.trim());
    _textController.clear();
  }

  /// 关键：测量高度并通知列表
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
```

### 为什么需要 `_measure()`

Chat 内部是 Stack 布局，Composer 通过 `Positioned` 浮在列表上方。列表通过 `SliverSpacing` 消费 `ComposerHeightNotifier.height` 来预留底部空间。

如果不报告高度，列表底部的消息会被 Composer 遮挡。

```
Chat Stack 布局：
├── ChatAnimatedList
│   └── SliverSpacing (bottom: ComposerHeightNotifier.height)  ← 自动预留
└── Positioned (Composer)
    └── _measure() → ComposerHeightNotifier.setHeight()  ← 报告高度
```

---

## 状态流转总结

```
┌─────────────────────────────────────────────────────────────┐
│  键盘隐藏                                                    │
│  • effectiveIsAtBottom = _isAtBottom（实时）                 │
│  • resizeToAvoidBottomInset = _isAtBottom                   │
│  • composerBottomPadding = 0                                │
│  • keepBottomOnResize = _isAtBottom                         │
├─────────────────────────────────────────────────────────────┤
│  键盘弹出瞬间                                                │
│  • 锁定 _lockedIsAtBottom = _isAtBottom                     │
│  • 锁定 keepBottomOnResize = _isAtBottom                    │
├─────────────────────────────────────────────────────────────┤
│  键盘显示中 + 列表原本在底部                                  │
│  • resizeToAvoidBottomInset = true                          │
│  • keepBottomOnResize = true → ScrollPosition 同步调整       │
│  • composerBottomPadding = 0                                │
│  → Scaffold 缩小 body + ScrollPosition 逐帧跟随 = 丝滑顶起  │
├─────────────────────────────────────────────────────────────┤
│  键盘显示中 + 列表原本不在底部                                │
│  • resizeToAvoidBottomInset = false                         │
│  • keepBottomOnResize = false → ScrollPosition 不调整        │
│  • composerBottomPadding = keyboardHeight                   │
│  → 列表不动，输入框通过 Positioned.bottom 顶起               │
├─────────────────────────────────────────────────────────────┤
│  键盘收起                                                    │
│  • _isKeyboardVisible = false                               │
│  • 恢复使用 _isAtBottom                                     │
└─────────────────────────────────────────────────────────────┘
```

---

## 注意事项

1. **必须使用 `BottomKeepingScrollController`**：普通 ScrollController 无法实现丝滑键盘顶起
2. **必须传入 `focusNode`**：保持输入框焦点稳定，避免键盘收起
3. **必须实现 `_measure()`**：自定义 Composer 必须通过 `ComposerHeightNotifier` 报告高度
4. **`shouldAdjustScrollOnKeyboard: false`**：关掉库自带的延迟调整，由自定义 ScrollPosition 接管
5. **`initialScrollToEndMode: InitialScrollToEndMode.none`**：关掉库自带的初始滚动，由 `postFrameCallback` + `scrollToBottom()` 接管
6. **`composerBuilder: SizedBox.shrink()`**：隐藏默认 Composer
7. **`onEndReached`**：传入加载旧消息的回调，滚动到顶部时自动触发

## 完整示例

参考：`examples/flyer_chat/lib/keyboard_resize_demo.dart`
