import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 IndexedStack 能保持子页面 State，避免切换标签后状态丢失。
///
/// 这是对话记录被清空问题的回归测试：曾用 AnimatedSwitcher + KeyedSubtree
/// 包裹 IndexedStack，导致每次切换都重建子树、销毁 State。
void main() {
  testWidgets('IndexedStack 切换后保持子页面状态', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: _Harness()),
    );

    // 初始在第一个页面
    expect(find.text('页面一'), findsOneWidget);

    // 在页面一里累加计数
    await tester.tap(find.text('累加'));
    await tester.pump();
    await tester.tap(find.text('累加'));
    await tester.pump();
    expect(find.text('计数：2'), findsOneWidget);

    // 切到第二个页面
    await tester.tap(find.text('切换到二'));
    await tester.pumpAndSettle();
    expect(find.text('页面二'), findsOneWidget);

    // 切回第一个页面，计数应保留
    await tester.tap(find.text('切换到一'));
    await tester.pumpAndSettle();
    expect(find.text('计数：2'), findsOneWidget);
  });
}

class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _index = 0),
                child: const Text('切换到一'),
              ),
              TextButton(
                onPressed: () => setState(() => _index = 1),
                child: const Text('切换到二'),
              ),
            ],
          ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [
                _CounterPage(),
                Center(child: Text('页面二')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CounterPage extends StatefulWidget {
  const _CounterPage();

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('页面一'),
        Text('计数：$_count'),
        TextButton(
          onPressed: () => setState(() => _count++),
          child: const Text('累加'),
        ),
      ],
    );
  }
}
