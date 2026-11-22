import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatstudio/state/app_controller.dart';
import 'support.dart';

void main() {
  test(
    'pinned preview plugin preserves full identity, model and restored history',
    () async {
      final first = AppController(storage: MemoryStorage());
      final second = AppController(storage: MemoryStorage());
      String? id;
      Future<void> until(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 50));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail(
              'Plugin condition timed out: ${first.engine}/${first.agentMode}, send=${first.canSend}, catalog=${first.nativeModelsError}/${first.nativeModelStatus}, working=${first.working}, body=${first.timeline.messages.map((m) => m.content).join("|")}; second send=${second.canSend}, working=${second.working}, body=${second.timeline.messages.map((m) => m.content).join("|")}; ${first.error}, ${second.error}',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      try {
        for (final client in [first, second]) {
          await client.initialize();
          expect(
            await client.login(
              Platform.environment['CHATSTUDIO_TEST_SERVER']!,
              'admin',
              Platform.environment['CHATSTUDIO_TEST_PASSWORD']!,
              true,
            ),
            true,
          );
          client.api!.enablePluginAgents = true;
          await client.refreshAgents();
        }
        const agent = 'plugin:mobile-fixture/echo';
        expect(first.availableAgents.any((a) => a.id == agent), true);
        await until(() => first.canSend);
        await first.chooseEngine(agent);
        await first.chooseAgentMode('global');
        await first.refreshNativeModels();
        await until(
          () => !first.nativeModelsLoading && first.nativeCatalog != null,
        );
        final model = first.selectableModels.singleWhere(
          (m) => m.id == 'fixture-alias',
        );
        await first.chooseModel(model);
        expect(first.send('first plugin turn'), true);
        id = first.sessionId;
        await until(() => !first.working);
        expect(
          first.timeline.messages
              .where((m) => m.delivery == 'failed')
              .map((m) => m.failure),
          isEmpty,
        );
        await until(
          () =>
              !first.working &&
              first.timeline.messages.any(
                (m) => m.content.contains('PLUGIN_FIXTURE_OK history=0'),
              ),
        );
        final metadata = await first.api!.sessionMetadata(id!);
        expect(metadata.agent, agent);
        expect(metadata.agentMode, 'global');
        expect(metadata.model, 'fixture-alias');
        await second.openConversation(metadata);
        await until(
          () => !second.syncing && !second.loadingMessages && second.canSend,
        );
        expect(second.engine, agent);
        expect(second.selectedModel?.id, 'fixture-alias');
        expect(second.send('second plugin turn'), true);
        await until(
          () =>
              !second.working &&
              second.timeline.messages.any(
                (m) => m.content.contains('PLUGIN_FIXTURE_OK history=2'),
              ),
        );
        final messages = await second.api!.messages(id);
        expect(messages.messages.where((m) => m.role == 'user').length, 2);
        expect(messages.messages.where((m) => m.role == 'assistant').length, 2);
      } finally {
        if (id != null) await first.api?.delete(id);
        first.dispose();
        second.dispose();
      }
    },
    skip:
        Platform.environment['CHATSTUDIO_TEST_SERVER'] == null ||
        Platform.environment['CHATSTUDIO_TEST_BASELINE'] != 'preview-agents',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
