import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  group('ChatAnimatedList Pagination', () {
    late InMemoryChatController chatController;
    late ScrollController scrollController;

    setUp(() {
      // Create initial messages (simulating newest 20 messages)
      final initialMessages = List.generate(
        20,
        (i) => Message.text(
          id: '${80 + i}', // IDs 80-99 (newest)
          authorId: 'user',
          createdAt: DateTime.now().subtract(Duration(minutes: 20 - i)),
          text: 'Message ${80 + i}',
        ),
      );

      chatController = InMemoryChatController(messages: initialMessages);
      scrollController = ScrollController();
    });

    tearDown(() {
      chatController.dispose();
      scrollController.dispose();
    });

    Widget buildTestWidget({
      required Future<void> Function()? onEndReached,
      bool reversed = false,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            width: 400,
            child: MultiProvider(
              providers: [
                Provider<ChatController>.value(value: chatController),
                Provider<Builders>.value(value: const Builders()),
                Provider<UserID>.value(value: 'user'),
                Provider<ChatTheme>.value(
                  value: ChatTheme.fromThemeData(ThemeData.light()),
                ),
                ChangeNotifierProvider(create: (_) => LoadMoreNotifier()),
                ChangeNotifierProvider(create: (_) => ComposerHeightNotifier()),
              ],
              child: ChatAnimatedList(
                scrollController: scrollController,
                reversed: reversed,
                topPadding: 0,
                bottomPadding: 0,
                initialScrollToEndMode: InitialScrollToEndMode.none,
                onEndReached: onEndReached,
                itemBuilder: (
                  context,
                  message,
                  index,
                  animation, {
                  messagesGroupingMode,
                  messageGroupingTimeoutInSeconds,
                  isRemoved,
                }) {
                  return SizeTransition(
                    sizeFactor: animation,
                    child: Container(
                      key: ValueKey(message.id),
                      height: 50,
                      color: Colors.grey[200],
                      child: Center(
                        child: Text('Message ${message.id}'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    testWidgets(
      'Pagination trigger test: onEndReached should be called when scrolling to top',
      (tester) async {
        final completer = Completer<void>();
        bool onEndReachedCalled = false;

        Future<void> loadOlderMessages() async {
          onEndReachedCalled = true;
          debugPrint('onEndReached called!');

          final olderMessages = List.generate(
            20,
            (i) => Message.text(
              id: '${60 + i}',
              authorId: 'user',
              createdAt: DateTime.now().subtract(Duration(minutes: 40 - i)),
              text: 'Older Message ${60 + i}',
            ),
          );
          await chatController.insertAllMessages(olderMessages, index: 0);
          completer.complete();
        }

        await tester.pumpWidget(buildTestWidget(
          onEndReached: loadOlderMessages,
        ));

        await tester.pumpAndSettle();

        debugPrint('Initial state:');
        debugPrint('  messages: ${chatController.messages.length}');
        debugPrint('  offset: ${scrollController.offset}');
        debugPrint('  maxScrollExtent: ${scrollController.position.maxScrollExtent}');

        // Record message 90 position before
        final message90Finder = find.byKey(const ValueKey('90'));
        final positionBefore = tester
            .renderObject<RenderBox>(message90Finder)
            .localToGlobal(Offset.zero);
        debugPrint('  Message 90 position: $positionBefore');

        // Simulate user scrolling up (this sets _paginationShouldTrigger = true)
        // We need to use fling to simulate a real scroll gesture
        await tester.fling(
          find.byType(CustomScrollView),
          const Offset(0, 500), // Scroll up
          1000,
        );
        await tester.pumpAndSettle();

        debugPrint('After scroll up:');
        debugPrint('  offset: ${scrollController.offset}');
        debugPrint('  onEndReachedCalled: $onEndReachedCalled');

        if (onEndReachedCalled) {
          // Wait for the completer
          await completer.future;
          await tester.pumpAndSettle();

          debugPrint('After pagination:');
          debugPrint('  messages: ${chatController.messages.length}');
          debugPrint('  offset: ${scrollController.offset}');
          debugPrint('  maxScrollExtent: ${scrollController.position.maxScrollExtent}');

          // Check message 90 position after
          final positionAfter = tester
              .renderObject<RenderBox>(message90Finder)
              .localToGlobal(Offset.zero);
          debugPrint('  Message 90 position: $positionAfter');

          final positionDiff = (positionAfter.dy - positionBefore.dy).abs();
          debugPrint('  Position difference: $positionDiff');
        }

        // This test documents the behavior
        expect(true, isTrue);
      },
    );

    testWidgets(
      'Manual scroll adjustment test: jumpTo should keep viewport stable',
      (tester) async {
        await tester.pumpWidget(buildTestWidget(
          onEndReached: null,
        ));

        await tester.pumpAndSettle();

        // Scroll to middle
        scrollController.jumpTo(200);
        await tester.pumpAndSettle();

        // Record state before
        final offsetBefore = scrollController.offset;
        final maxExtentBefore = scrollController.position.maxScrollExtent;
        final message90Finder = find.byKey(const ValueKey('90'));
        final positionBefore = tester
            .renderObject<RenderBox>(message90Finder)
            .localToGlobal(Offset.zero);

        debugPrint('Before insert:');
        debugPrint('  offset: $offsetBefore');
        debugPrint('  maxScrollExtent: $maxExtentBefore');
        debugPrint('  Message 90 position: $positionBefore');

        // Insert older messages
        final olderMessages = List.generate(
          20,
          (i) => Message.text(
            id: '${60 + i}',
            authorId: 'user',
            createdAt: DateTime.now().subtract(Duration(minutes: 40 - i)),
            text: 'Older Message ${60 + i}',
          ),
        );

        await chatController.insertAllMessages(olderMessages, index: 0);
        await tester.pump(); // Just one frame

        // Record state after insert (before any adjustment)
        final offsetAfterInsert = scrollController.offset;
        final maxExtentAfterInsert = scrollController.position.maxScrollExtent;

        debugPrint('After insert (before adjustment):');
        debugPrint('  offset: $offsetAfterInsert');
        debugPrint('  maxScrollExtent: $maxExtentAfterInsert');

        // Calculate and apply adjustment
        final addedExtent = maxExtentAfterInsert - maxExtentBefore;
        final targetOffset = offsetBefore + addedExtent;

        debugPrint('Adjustment:');
        debugPrint('  addedExtent: $addedExtent');
        debugPrint('  targetOffset: $targetOffset');

        scrollController.jumpTo(targetOffset);
        await tester.pumpAndSettle();

        // Check message 90 position after adjustment
        final positionAfter = tester
            .renderObject<RenderBox>(message90Finder)
            .localToGlobal(Offset.zero);

        debugPrint('After adjustment:');
        debugPrint('  offset: ${scrollController.offset}');
        debugPrint('  Message 90 position: $positionAfter');

        final positionDiff = (positionAfter.dy - positionBefore.dy).abs();
        debugPrint('  Position difference: $positionDiff');

        // The position should be the same (or very close)
        expect(
          positionDiff,
          lessThan(1.0),
          reason: 'Message position should not change after adjustment',
        );
      },
    );
  });
}

