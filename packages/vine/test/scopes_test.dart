import 'package:test/test.dart';
import 'package:vine/vine.dart';

void main() {
  group('overrides', () {
    test('Garden(overrides:) replaces a single vine\'s body', () {
      final greeting = Vine.single((tap) => 'hello');
      final garden =
          Garden(overrides: [greeting.override((tap) => 'overridden')]).grow();
      expect(garden.tap(greeting), 'overridden');
    });

    test('an override can itself depend on other vines', () {
      final name = Vine.value('world');
      final greeting = Vine.single((tap) => 'hello');
      final garden = Garden(
        overrides: [greeting.override((tap) => 'hi, ${tap(name)}')],
      ).grow();
      expect(garden.tap(greeting), 'hi, world');
    });

    test('growScope(overrides:) shadows only within that scope', () {
      final greeting = Vine.single((tap) => 'hello');
      final root = Garden().grow();
      final child =
          root.growScope(overrides: [greeting.override((tap) => 'child')]);
      expect(root.tap(greeting), 'hello');
      expect(child.tap(greeting), 'child');
    });

    test('nearest scope wins when a grandchild also overrides', () {
      final greeting = Vine.single((tap) => 'root');
      final root = Garden().grow();
      final child =
          root.growScope(overrides: [greeting.override((tap) => 'child')]);
      final grandchild = child
          .growScope(overrides: [greeting.override((tap) => 'grandchild')]);
      expect(grandchild.tap(greeting), 'grandchild');
    });

    test('a child scope with no override of its own inherits the parent\'s',
        () {
      final greeting = Vine.single((tap) => 'root');
      final root = Garden().grow();
      final child = root
          .growScope(overrides: [Vine.single((tap) => 0).override((tap) => 1)]);
      final grandchild = child.growScope();
      expect(grandchild.tap(greeting), 'root');
    });
  });

  group('scoped singleton isolation', () {
    test('an unoverridden vine tapped first in a child gets its own instance',
        () {
      var creations = 0;
      final vine = Vine.single((tap) {
        creations++;
        return Object();
      });
      final root = Garden().grow();
      final child = root.growScope();
      final fromChild = child.tap(vine);
      final fromRoot = root.tap(vine);
      expect(identical(fromChild, fromRoot), isFalse);
      expect(creations, 2);
    });

    test('two sibling scopes each get their own instance', () {
      final vine = Vine.single((tap) => Object());
      final root = Garden().grow();
      final childA = root.growScope();
      final childB = root.growScope();
      expect(identical(childA.tap(vine), childB.tap(vine)), isFalse);
    });

    test('a cell written in one scope does not affect a sibling scope', () {
      final cell = Vine.cell(0);
      final root = Garden().grow();
      final childA = root.growScope();
      final childB = root.growScope();
      childA.set(cell, 1);
      expect(childA.tap(cell), 1);
      expect(childB.tap(cell), 0);
      expect(root.tap(cell), 0);
    });
  });

  group('scope disposal', () {
    test('a child scope disposes before its parent', () async {
      final order = <String>[];
      final parentVine =
          Vine.single((tap) => 'p', dispose: (_) => order.add('parent'));
      final childVine =
          Vine.single((tap) => 'c', dispose: (_) => order.add('child'));
      final root = Garden().grow();
      root.tap(parentVine);
      final child = root.growScope();
      child.tap(childVine);
      await root.dispose();
      expect(order, ['child', 'parent']);
    });

    test('using a disposed garden throws GardenDisposedError', () async {
      final vine = Vine.single((tap) => 1);
      final garden = Garden().grow();
      await garden.dispose();
      expect(() => garden.tap(vine), throwsA(isA<GardenDisposedError>()));
    });
  });

  group('Vine.each', () {
    test('memoizes per key: same key returns the same instance', () {
      var creations = 0;
      final family = Vine.each<String, Object>((tap, key) {
        creations++;
        return Object();
      });
      final garden = Garden().grow();
      final a1 = garden.tap(family('a'));
      final a2 = garden.tap(family('a'));
      final b1 = garden.tap(family('b'));
      expect(identical(a1, a2), isTrue);
      expect(identical(a1, b1), isFalse);
      expect(creations, 2);
    });

    test('a family instance is reactive like any computed', () {
      final cell = Vine.cell(1);
      final family = Vine.each<int, int>((tap, key) => tap(cell) * key);
      final garden = Garden().grow();
      expect(garden.tap(family(3)), 3);
      garden.set(cell, 10);
      expect(garden.tap(family(3)), 30);
    });

    test('recursive family (tree keyed by id) resolves', () {
      final nodes = {
        1: (parent: null as int?, value: 'root'),
        2: (parent: 1, value: 'child'),
        3: (parent: 2, value: 'grandchild'),
      };
      late final EachVine<int, String> path;
      path = Vine.each<int, String>((tap, id) {
        final node = nodes[id]!;
        if (node.parent == null) return node.value;
        return '${tap(path(node.parent!))}/${node.value}';
      });
      final garden = Garden().grow();
      expect(garden.tap(path(3)), 'root/child/grandchild');
    });

    test('each family can be overridden at the family level', () {
      final family = Vine.each<int, String>((tap, key) => 'real-$key');
      final garden = Garden(
        overrides: [family.overrideCreate((tap, key) => 'fake-$key')],
      ).grow();
      expect(garden.tap(family(1)), 'fake-1');
    });
  });

  group('Vine.eachAsync overrides', () {
    test('can be overridden at the family level', () async {
      final family =
          Vine.eachAsync<int, String>((tap, key) async => 'real-$key');
      final garden = Garden(
        overrides: [family.overrideCreate((tap, key) async => 'fake-$key')],
      ).grow();
      expect(await garden.tapAsync(family(1)), 'fake-1');
    });
  });
}
