import 'package:flutter_test/flutter_test.dart';

import 'package:anima/services/nanogpt_service.dart';

void main() {
  group('NanoGptModelInfo uncensored heuristics', () {
    test('isUncensoredFriendly matches category', () {
      const model = NanoGptModelInfo(
        id: 'vendor/foo',
        ownedBy: 'vendor',
        name: 'Foo',
        category: 'Uncensored',
      );
      expect(model.isUncensoredFriendly, isTrue);
    });

    test('isUncensoredFriendly matches abliterated in id', () {
      const model = NanoGptModelInfo(
        id: 'huihui-ai/Llama-3.3-70B-Instruct-abliterated',
        ownedBy: 'huihui',
        name: 'Llama 3.3 70B',
        category: 'More',
      );
      expect(model.isUncensoredFriendly, isTrue);
    });

    test('isUncensoredFriendly matches derestricted in name', () {
      const model = NanoGptModelInfo(
        id: 'custom/qwen-blossom',
        ownedBy: 'custom',
        name: 'Qwen Blossom V6.4 Derestricted',
      );
      expect(model.isUncensoredFriendly, isTrue);
    });

    test('inferParameterSizeLabel finds 70B in name', () {
      final label = NanoGptModelInfo.inferParameterSizeLabel(
        id: 'huihui-ai/Llama-3.3-70B-Instruct-abliterated',
        name: 'Llama 3.3 70B Instruct abliterated',
      );
      expect(label, '70B');
    });

    test('statChipLine includes runtime stats', () {
      const model = NanoGptModelInfo(
        id: 'vendor/foo-70b',
        ownedBy: 'vendor',
        name: 'Foo 70B',
        contextLength: 65536,
        maxOutputTokens: 8192,
        parameterSizeLabel: '70B',
        subscriptionIncluded: true,
      );
      final line = model.statChipLine(
        runtime: const NanoGptModelRuntimeStats(
          tps: 57.9,
          ttftMs: 320,
          uptimePercent: 50,
        ),
      );
      expect(line, contains('66K ctx'));
      expect(line, contains('8.2K out'));
      expect(line, contains('70B'));
      expect(line, contains('57.9 TPS'));
      expect(line, contains('50% up'));
      expect(line, contains('Included'));
    });
  });

  group('NanoGptTextModelCatalogFilter', () {
    final models = [
      const NanoGptModelInfo(
        id: 'a/uncensored-official',
        ownedBy: 'a',
        name: 'Official',
        category: 'Uncensored',
      ),
      const NanoGptModelInfo(
        id: 'b/foo-abliterated',
        ownedBy: 'b',
        name: 'Foo',
        category: 'More',
      ),
      const NanoGptModelInfo(
        id: 'openai/gpt',
        ownedBy: 'openai',
        name: 'GPT',
        category: 'More',
      ),
      const NanoGptModelInfo(
        id: 'c/hero',
        ownedBy: 'c',
        name: 'Hero',
        category: 'Roleplay',
      ),
    ];

    test('uncensored friendly filter catches category and names', () {
      final filtered = NanoGptTextModelCatalogFilter.apply(
        models,
        NanoGptTextModelCatalogFilter.uncensoredFriendlyId,
      );
      expect(filtered.map((m) => m.id).toList(), [
        'a/uncensored-official',
        'b/foo-abliterated',
      ]);
    });

    test('exact category filter matches Roleplay only', () {
      final filtered = NanoGptTextModelCatalogFilter.apply(models, 'Roleplay');
      expect(filtered.length, 1);
      expect(filtered.first.id, 'c/hero');
    });

    test('categoryFilterIds includes broad bucket and sorted categories', () {
      final ids = NanoGptTextModelCatalogFilter.categoryFilterIds(models);
      expect(ids.first, NanoGptTextModelCatalogFilter.allId);
      expect(ids[1], NanoGptTextModelCatalogFilter.uncensoredFriendlyId);
      expect(ids.contains('Roleplay'), isTrue);
      expect(ids.contains('Uncensored'), isTrue);
    });
  });
}
