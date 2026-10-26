import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// 验证 Markdown + LaTeX 渲染链路（不涉及网络）。
///
/// 重点确认：粗体、列表、代码、表格、公式都能被解析器识别，
/// 且不会因格式异常导致渲染崩溃。
void main() {
  testWidgets('粗体与斜体可渲染', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GptMarkdown('这是**粗体**与*斜体*，还有`代码`。'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GptMarkdown), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('标题与列表可渲染', (tester) async {
    const md = '''
# 标题一
## 标题二

- 项目一
- 项目二

1. 第一步
2. 第二步
''';
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: GptMarkdown(md))),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('行内公式可渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GptMarkdown(
            r'分式是 $\frac{x+1}{x-2}$，乘方是 $x^{2}$。',
            useDollarSignsForLatex: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('块级公式与方程组可渲染', (tester) async {
    const md = r'''
$$\frac{a}{b}$$

$$\begin{cases} x + y = 5 \\ 2x - y = 1 \end{cases}$$
''';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GptMarkdown(md, useDollarSignsForLatex: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('表格与引用可渲染', (tester) async {
    const md = '''
| 题型 | 数量 |
| --- | --- |
| 单选 | 3 |
| 填空 | 2 |

> 这是一段引用
''';
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: GptMarkdown(md))),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('代码块可渲染', (tester) async {
    const md = '''
```dart
void main() {
  print("hello");
}
```
''';
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: GptMarkdown(md))),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('粗体内嵌公式不崩溃', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GptMarkdown(
            r'**重点：$\frac{1}{2}$ 是答案**',
            useDollarSignsForLatex: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('格式异常时不崩溃', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GptMarkdown(
            r'未闭合的公式 $\frac{1}{2 和 **未闭合的粗体',
            useDollarSignsForLatex: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 不要求渲染正确，但不能抛异常
    expect(tester.takeException(), isNull);
  });
}
