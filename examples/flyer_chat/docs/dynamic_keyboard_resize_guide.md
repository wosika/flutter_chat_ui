# Flutter 聊天列表动态键盘行为实现指南

## 功能说明

实现聊天列表的智能键盘行为：
- **列表在底部时**：软键盘弹出会顶起整个聊天界面（包括列表和输入框）
- **列表不在底部时**：软键盘只顶起输入框，覆盖聊天列表（保持用户阅读位置）

## 核心原理

1. 对于 reversed 列表，`scrollController.offset <= 0` 表示列表在底部
2. 通过动态设置 `Scaffold.resizeToAvoidBottomInset` 控制键盘是否顶起内容
3. 在 overlay 模式下，手动给输入框添加底部偏移以避开键盘
4. 使用状态锁定机制，避免键盘动画过程中的抖动

## 通用实现模板

### 1. State 类声明

```dart
class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  // 滚动控制器 - 用于监听列表滚动位置
  final _scrollController = ScrollController();

  // 输入框焦点 - 保持焦点稳定，避免键盘收起
  final _focusNode = FocusNode();

  // 判断"在底部"的阈值（像素）
  static const double _bottomThreshold = 10.0;

  // 当前是否在底部（实时状态）
  bool _isAtBottom = true;

  // 键盘弹出时锁定的状态
  bool _lockedIsAtBottom = true;

  // 键盘是否可见
  bool _isKeyboardVisible = false;
```

### 2. 生命周期管理

```dart
@override
void initState() {
  super.initState();
  // 注册系统指标监听（用于检测键盘）
  WidgetsBinding.instance.addObserver(this);
  // 注册滚动监听
  _scrollController.addListener(_onScrollChanged);
}

@override
void dispose() {
  // 移除监听
  WidgetsBinding.instance.removeObserver(this);
  _scrollController.removeListener(_onScrollChanged);
  // 释放资源
  _scrollController.dispose();
  _focusNode.dispose();
  super.dispose();
}
```

### 3. 键盘状态监听

```dart
@override
void didChangeMetrics() {
  // 获取键盘高度
  final bottomInset = WidgetsBinding
      .instance.platformDispatcher.views.first.viewInsets.bottom;
  final keyboardVisible = bottomInset > 0;

  if (keyboardVisible && !_isKeyboardVisible) {
    // 键盘弹出瞬间 - 锁定当前滚动状态
    _isKeyboardVisible = true;
    _lockedIsAtBottom = _isAtBottom;
  } else if (!keyboardVisible && _isKeyboardVisible) {
    // 键盘收起
    _isKeyboardVisible = false;
  }
  // 注意：这里不调用 setState，避免键盘动画过程中触发重建
}
```

### 4. 滚动位置监听

```dart
void _onScrollChanged() {
  if (!_scrollController.hasClients) return;

  // 对于 reversed 列表，offset <= threshold 表示在底部
  final isAtBottom = _scrollController.offset <= _bottomThreshold;

  if (_isAtBottom != isAtBottom) {
    setState(() {
      _isAtBottom = isAtBottom;
    });
  }
}
```

### 5. 构建 UI

```dart
@override
Widget build(BuildContext context) {
  // 获取键盘高度
  final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

  // 键盘可见时使用锁定值，否则使用实时值
  final effectiveIsAtBottom =
      _isKeyboardVisible ? _lockedIsAtBottom : _isAtBottom;

  // 计算输入框底部偏移
  // 非底部模式 + 键盘可见时，需要手动顶起输入框
  final inputBottomOffset =
      (!effectiveIsAtBottom && keyboardHeight > 0) ? keyboardHeight : 0.0;

  return Scaffold(
    // 关键：动态设置是否让键盘顶起内容
    resizeToAvoidBottomInset: effectiveIsAtBottom,
    body: Column(
      children: [
        // 聊天列表
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            reverse: true,  // 重要：必须是 reversed 列表
            // ...
          ),
        ),
        // 输入框 - 使用 Transform 或 Padding 调整位置
        Transform.translate(
          offset: Offset(0, -inputBottomOffset),
          child: YourInputWidget(
            focusNode: _focusNode,
          ),
        ),
      ],
    ),
  );
}
```

## flutter_chat_ui 专用实现

如果使用 `flutter_chat_ui` 包，实现更简洁：

```dart
@override
Widget build(BuildContext context) {
  final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

  final effectiveIsAtBottom =
      _isKeyboardVisible ? _lockedIsAtBottom : _isAtBottom;

  final composerBottomPadding =
      (!effectiveIsAtBottom && keyboardHeight > 0) ? keyboardHeight : 0.0;

  return Scaffold(
    resizeToAvoidBottomInset: effectiveIsAtBottom,
    body: Chat(
      builders: Builders(
        chatAnimatedListBuilder: (context, itemBuilder) {
          return ChatAnimatedListReversed(
            itemBuilder: itemBuilder,
            scrollController: _scrollController,  // 传入 scrollController
          );
        },
        composerBuilder: (context) {
          return Composer(
            focusNode: _focusNode,    // 传入 focusNode
            bottom: composerBottomPadding,  // 使用 bottom 参数调整位置
          );
        },
      ),
      chatController: _chatController,
      currentUserId: 'user-id',
      resolveUser: (id) async => User(id: id),
    ),
  );
}
```

## 状态流转图

```
┌────────────────────────────────────────────────────────────┐
│                        键盘隐藏                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ • 使用 _isAtBottom（实时滚动状态）                    │  │
│  │ • resizeToAvoidBottomInset = _isAtBottom             │  │
│  │ • inputBottomOffset = 0                              │  │
│  └──────────────────────────────────────────────────────┘  │
│                           │                                 │
│                           ▼ 用户点击输入框                   │
│                                                             │
│                      键盘弹出瞬间                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ • 锁定状态：_lockedIsAtBottom = _isAtBottom          │  │
│  │ • _isKeyboardVisible = true                          │  │
│  └──────────────────────────────────────────────────────┘  │
│                           │                                 │
│                           ▼                                 │
│                                                             │
│                       键盘显示中                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ • 使用 _lockedIsAtBottom（锁定状态）                  │  │
│  │ • 滚动列表不会改变 resizeToAvoidBottomInset          │  │
│  │ • 如果 _lockedIsAtBottom = false:                    │  │
│  │   - resizeToAvoidBottomInset = false                 │  │
│  │   - inputBottomOffset = keyboardHeight               │  │
│  └──────────────────────────────────────────────────────┘  │
│                           │                                 │
│                           ▼ 用户收起键盘                     │
│                                                             │
│                        键盘收起                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ • _isKeyboardVisible = false                         │  │
│  │ • 恢复使用 _isAtBottom                               │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

## 关键点总结

| 要点 | 说明 |
|------|------|
| **reversed 列表** | 必须使用 `reverse: true` 的列表，offset <= 0 才表示底部 |
| **状态锁定** | 键盘弹出时锁定状态，避免动画过程中抖动 |
| **focusNode** | 必须传入并复用，避免输入框重建导致焦点丢失 |
| **不在 didChangeMetrics 中 setState** | 避免键盘动画过程中触发重建 |
| **使用 bottom/Transform 而非外层 Padding** | 保持 widget 结构稳定 |

## 常见问题

### Q: 为什么键盘弹出后会立即收起？

A: 通常是因为：
1. 在 `didChangeMetrics` 中调用了 `setState`，导致重建
2. 输入框的 widget 结构变化（如条件渲染不同的 widget），导致焦点丢失
3. 没有传入 `focusNode`

### Q: 为什么列表顶部出现空白？

A: 如果使用 `Transform.translate` 移动列表，只是视觉偏移，布局空间不变。应该只移动输入框，不移动列表。

### Q: 如何判断非 reversed 列表是否在底部？

A: 对于普通列表（非 reversed）：
```dart
final isAtBottom = _scrollController.position.pixels >=
    _scrollController.position.maxScrollExtent - _bottomThreshold;
```

## 完整示例文件

参考：`examples/flyer_chat/lib/keyboard_resize_demo.dart`
