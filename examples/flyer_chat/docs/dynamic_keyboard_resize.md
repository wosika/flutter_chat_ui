# 动态软键盘行为 (Dynamic Keyboard Resize)

## 功能说明

实现聊天列表的智能键盘行为：
- **列表在底部时**：软键盘弹出会顶起整个聊天界面（包括列表和输入框）
- **列表不在底部时**：软键盘只顶起输入框，覆盖聊天列表

## 效果演示

| 场景 | 行为 |
|------|------|
| 列表在底部 + 键盘弹出 | 整体上移，用户可以看到最新消息 |
| 列表不在底部 + 键盘弹出 | 只有输入框上移，列表被键盘覆盖，保持阅读位置 |

## 核心原理

对于 `ChatAnimatedListReversed`（reversed=true 的列表）：
- `scrollController.offset <= 0` 表示列表在底部
- 通过动态设置 `Scaffold.resizeToAvoidBottomInset` 控制键盘行为
- 使用 `Composer.bottom` 参数在 overlay 模式下手动顶起输入框

## 完整示例代码

```dart
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';

class DynamicKeyboardChat extends StatefulWidget {
  const DynamicKeyboardChat({super.key});

  @override
  State<DynamicKeyboardChat> createState() => _DynamicKeyboardChatState();
}

class _DynamicKeyboardChatState extends State<DynamicKeyboardChat>
    with WidgetsBindingObserver {
  final _chatController = InMemoryChatController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  static const double _bottomThreshold = 10.0;

  bool _isAtBottom = true;
  bool _lockedIsAtBottom = true;
  bool _isKeyboardVisible = false;

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
        .instance.platformDispatcher.views.first.viewInsets.bottom;
    final keyboardVisible = bottomInset > 0;

    if (keyboardVisible && !_isKeyboardVisible) {
      _isKeyboardVisible = true;
      _lockedIsAtBottom = _isAtBottom;
    } else if (!keyboardVisible && _isKeyboardVisible) {
      _isKeyboardVisible = false;
    }
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;

    final isAtBottom = _scrollController.offset <= _bottomThreshold;

    if (_isAtBottom != isAtBottom) {
      setState(() {
        _isAtBottom = isAtBottom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

    final effectiveIsAtBottom =
        _isKeyboardVisible ? _lockedIsAtBottom : _isAtBottom;

    final composerBottomPadding =
        (!effectiveIsAtBottom && keyboardHeight > 0) ? keyboardHeight : 0.0;

    return Scaffold(
      resizeToAvoidBottomInset: effectiveIsAtBottom,
      appBar: AppBar(title: const Text('Chat')),
      body: Chat(
        builders: Builders(
          chatAnimatedListBuilder: (context, itemBuilder) {
            return ChatAnimatedListReversed(
              itemBuilder: itemBuilder,
              scrollController: _scrollController,
            );
          },
          composerBuilder: (context) {
            return Composer(
              focusNode: _focusNode,
              bottom: composerBottomPadding,
            );
          },
        ),
        chatController: _chatController,
        currentUserId: 'user-id',
        resolveUser: (id) async => User(id: id),
      ),
    );
  }
}
```

## 实现步骤详解

### 步骤 1: 添加 WidgetsBindingObserver

```dart
class _YourChatPageState extends State<YourChatPage>
    with WidgetsBindingObserver {
```

用于监听系统指标变化（键盘弹出/收起）。

### 步骤 2: 声明必要的变量

```dart
final _scrollController = ScrollController();
final _focusNode = FocusNode();

static const double _bottomThreshold = 10.0;

bool _isAtBottom = true;           // 当前是否在底部
bool _lockedIsAtBottom = true;     // 键盘弹出时锁定的状态
bool _isKeyboardVisible = false;   // 键盘是否可见
```

### 步骤 3: 生命周期管理

```dart
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
  super.dispose();
}
```

### 步骤 4: 监听键盘状态

```dart
@override
void didChangeMetrics() {
  final bottomInset = WidgetsBinding
      .instance.platformDispatcher.views.first.viewInsets.bottom;
  final keyboardVisible = bottomInset > 0;

  if (keyboardVisible && !_isKeyboardVisible) {
    // 键盘弹出 - 锁定当前滚动状态
    _isKeyboardVisible = true;
    _lockedIsAtBottom = _isAtBottom;
  } else if (!keyboardVisible && _isKeyboardVisible) {
    // 键盘收起
    _isKeyboardVisible = false;
  }
}
```

**重要**：在键盘弹出时锁定状态，避免键盘动画过程中状态变化导致的抖动。

### 步骤 5: 监听滚动位置

```dart
void _onScrollChanged() {
  if (!_scrollController.hasClients) return;

  // reversed 列表，offset <= threshold 表示在底部
  final isAtBottom = _scrollController.offset <= _bottomThreshold;

  if (_isAtBottom != isAtBottom) {
    setState(() {
      _isAtBottom = isAtBottom;
    });
  }
}
```

### 步骤 6: 构建 UI

```dart
@override
Widget build(BuildContext context) {
  final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

  // 键盘可见时使用锁定值，否则使用实时值
  final effectiveIsAtBottom =
      _isKeyboardVisible ? _lockedIsAtBottom : _isAtBottom;

  // 非底部模式下，手动计算输入框底部位置
  final composerBottomPadding =
      (!effectiveIsAtBottom && keyboardHeight > 0) ? keyboardHeight : 0.0;

  return Scaffold(
    resizeToAvoidBottomInset: effectiveIsAtBottom,
    body: Chat(
      builders: Builders(
        chatAnimatedListBuilder: (context, itemBuilder) {
          return ChatAnimatedListReversed(
            itemBuilder: itemBuilder,
            scrollController: _scrollController,
          );
        },
        composerBuilder: (context) {
          return Composer(
            focusNode: _focusNode,
            bottom: composerBottomPadding,
          );
        },
      ),
      // ... 其他参数
    ),
  );
}
```

## 关键参数说明

| 组件 | 参数 | 说明 |
|------|------|------|
| `Scaffold` | `resizeToAvoidBottomInset` | 动态设置：底部时 `true`，非底部时 `false` |
| `ChatAnimatedListReversed` | `scrollController` | 传入自定义 controller 以监听滚动位置 |
| `Composer` | `focusNode` | 保持焦点稳定，避免状态变化导致键盘收起 |
| `Composer` | `bottom` | 非底部模式下设为键盘高度，手动顶起输入框 |

## 状态锁定机制

```
┌─────────────────────────────────────────────────────────┐
│  键盘隐藏时                                              │
│  └─> 使用 _isAtBottom（实时滚动状态）                    │
├─────────────────────────────────────────────────────────┤
│  键盘弹出瞬间                                            │
│  └─> 锁定 _lockedIsAtBottom = _isAtBottom               │
├─────────────────────────────────────────────────────────┤
│  键盘显示中                                              │
│  └─> 使用 _lockedIsAtBottom（锁定状态，不随滚动变化）    │
├─────────────────────────────────────────────────────────┤
│  键盘收起后                                              │
│  └─> 恢复使用 _isAtBottom                               │
└─────────────────────────────────────────────────────────┘
```

这个机制确保：
1. 键盘弹出过程中不会因为状态变化导致布局抖动
2. 输入框不会因为 widget 重建而失去焦点
3. 用户滚动列表时，键盘行为保持一致

## 注意事项

1. **必须使用 `ChatAnimatedListReversed`**：此方案基于 reversed 列表的滚动特性
2. **必须传入 `focusNode`**：避免 Composer 重建导致焦点丢失
3. **使用 `bottom` 而非外层 Padding**：保持 widget 结构稳定
4. **不要在 `didChangeMetrics` 中调用 `setState`**：避免键盘动画过程中触发重建

## 参考文件

- 完整示例：`examples/flyer_chat/lib/keyboard_resize_demo.dart`
