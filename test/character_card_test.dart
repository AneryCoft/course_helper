import 'package:flutter_test/flutter_test.dart';

import 'package:course_helper/models/character_card.dart';
import 'package:course_helper/setting/built_in_cards.dart';

void main() {
  group('CharacterCard 序列化', () {
    test('编解码保持字段一致', () {
      const card = CharacterCard(
        id: 'c1',
        name: '测试角色',
        description: '简介',
        persona: '设定内容',
        greetings: ['开场白一', '开场白二'],
      );

      final restored = CharacterCard.decode(card.encode());
      expect(restored, isNotNull);
      expect(restored!.id, 'c1');
      expect(restored.name, '测试角色');
      expect(restored.description, '简介');
      expect(restored.persona, '设定内容');
      expect(restored.greetings, ['开场白一', '开场白二']);
    });

    test('空开场白在解码时被过滤', () {
      const raw = '{"id":"c2","name":"X","persona":"P",'
          '"greetings":["有效","", "  "]}';
      final card = CharacterCard.decode(raw);
      expect(card!.greetings, ['有效']);
    });

    test('非法内容返回 null', () {
      expect(CharacterCard.decode(null), isNull);
      expect(CharacterCard.decode(''), isNull);
      expect(CharacterCard.decode('not json'), isNull);
      expect(CharacterCard.decode('{"id":"","name":"x"}'), isNull);
    });
  });

  group('CharacterCard 校验', () {
    test('名称必填', () {
      const card = CharacterCard(id: 'x', name: '', persona: 'P', greetings: ['g']);
      expect(card.validate(), '请填写角色名称');
    });

    test('设定必填', () {
      const card = CharacterCard(id: 'x', name: 'N', persona: '', greetings: ['g']);
      expect(card.validate(), '请填写角色设定');
    });

    test('至少一条开场白', () {
      const card = CharacterCard(id: 'x', name: 'N', persona: 'P', greetings: []);
      expect(card.validate(), '至少需要一条开场白');
    });

    test('合法卡返回 null', () {
      const card = CharacterCard(id: 'x', name: 'N', persona: 'P', greetings: ['g']);
      expect(card.validate(), isNull);
    });
  });

  group('内置角色卡', () {
    test('默认卡开场白不少于 5 条', () {
      expect(BuiltInCards.defaultCard.greetings.length, greaterThanOrEqualTo(5));
    });

    test('所有内置卡开场白均不少于 5 条', () {
      for (final card in BuiltInCards.all) {
        expect(
          card.greetings.length,
          greaterThanOrEqualTo(5),
          reason: '角色卡「${card.name}」开场白不足 5 条',
        );
      }
    });

    test('所有内置卡均通过校验', () {
      for (final card in BuiltInCards.all) {
        expect(card.validate(), isNull, reason: card.name);
      }
    });

    test('内置卡 ID 唯一且标记为内置', () {
      final ids = BuiltInCards.all.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final card in BuiltInCards.all) {
        expect(card.builtIn, isTrue);
      }
    });

    test('开场白互不重复', () {
      for (final card in BuiltInCards.all) {
        expect(card.greetings.toSet().length, card.greetings.length,
            reason: card.name);
      }
    });

    test('默认卡设定包含答题关键准则', () {
      final persona = BuiltInCards.defaultCard.persona;
      expect(persona.contains('JSON'), isTrue);
      expect(persona.contains('审题'), isTrue);
      expect(persona.contains('解析'), isTrue);
    });

    test('按 ID 查找', () {
      expect(BuiltInCards.findById(BuiltInCards.defaultCardId), isNotNull);
      expect(BuiltInCards.findById('不存在'), isNull);
    });
  });

  group('随机开场白', () {
    test('单条时总是返回同一条', () {
      const card = CharacterCard(id: 'x', name: 'N', persona: 'P', greetings: ['only']);
      expect(card.randomGreeting(), 'only');
      expect(card.randomGreeting(99), 'only');
    });

    test('多条时按 seed 取模，结果稳定', () {
      const card = CharacterCard(
        id: 'x',
        name: 'N',
        persona: 'P',
        greetings: ['a', 'b', 'c'],
      );
      expect(card.randomGreeting(0), 'a');
      expect(card.randomGreeting(4), 'b');
      expect(card.randomGreeting(5), 'c');
    });

    test('空列表返回空串', () {
      const card = CharacterCard(id: 'x', name: 'N', persona: 'P', greetings: []);
      expect(card.randomGreeting(), '');
    });
  });
}
