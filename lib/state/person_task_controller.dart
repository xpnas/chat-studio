import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../data/models.dart';
import '../data/person_models.dart';
import '../data/person_api.dart';
import 'person_controller.dart';

class PersonTaskController extends ChangeNotifier {
  PersonTaskController(this.person, this.id);
  final PersonController person;
  final String id;
  PersonTask? task;
  PersonExecution? execution;
  List<PersonExecution> executions = [];
  Map<String, dynamic> acceptance = {};
  List<Map<String, dynamic>> pending = [];
  String selectedExecution = '';
  String? error;
  bool loading = false, _disposed = false;
  int _generation = 0;
  bool get current =>
      task != null &&
      (selectedExecution.isEmpty || selectedExecution == task!.executionId);
  bool get canFollowUp =>
      current &&
      task?.canFollowUp == true &&
      !loading &&
      !person.operation.pending &&
      !person.operation.uncertain;
  Future<void> refresh({String? executionId}) async {
    if (_disposed || !person.valid) return;
    final generation = ++_generation;
    selectedExecution = executionId ?? selectedExecution;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await person.api.personTaskChat(
        id,
        executionId: selectedExecution.isEmpty ? null : selectedExecution,
      );
      final runs = await person.api.personExecutions(id);
      if (_disposed || !person.valid || generation != _generation) return;
      task = PersonTask.fromJson(asMap(data['task']));
      executions = runs;
      final selected = selectedExecution.isEmpty
          ? task!.executionId
          : selectedExecution;
      execution = runs.where((run) => run.id == selected).firstOrNull;
      if (execution == null && asMap(data['execution'])['id'] == selected) {
        final events = await person.api.personExecutionEvents(selected);
        if (_disposed || !person.valid || generation != _generation) return;
        final terminal = events
            .where(
              (event) =>
                  event['type'] == 'run.completed' ||
                  event['event'] == 'run.completed',
            )
            .lastOrNull;
        Map<String, dynamic> details = {};
        if (terminal != null) {
          final raw = terminal['data'] ?? terminal['data_json'];
          try {
            details = asMap(raw is String ? jsonDecode(raw) : raw);
          } catch (_) {
            /* Authorized metadata remains readable. */
          }
        }
        execution = PersonExecution.fromJson({
          ...asMap(data['execution']),
          'output': details['output'] ?? '',
        });
        executions = [...runs, execution!];
      }
      acceptance = asMap(data['acceptance']);
      pending = asList(data['pending']).map(asMap).toList();
    } catch (e) {
      if (!_disposed && person.valid && generation == _generation) {
        error = '$e';
        task = null;
        execution = null;
        pending = [];
      }
    } finally {
      if (!_disposed && person.valid && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> followUp(String text) async {
    final currentTask = task;
    if (!canFollowUp || currentTask == null || text.trim().isEmpty) return;
    await person.operation.perform('task-chat:$id', {
      'input': [
        {'type': 'text', 'text': text.trim()},
      ],
      'expected_revision': currentTask.revision,
      'expected_execution_id': currentTask.executionId.isEmpty
          ? null
          : currentTask.executionId,
      if (execution != null) 'execution_id': execution!.id,
    }, (input) => person.api.continuePersonTask(id, input));
    await refresh();
    await person.refreshSnapshot();
  }

  Future<void> stop() async {
    final currentTask = task;
    if (!current ||
        currentTask == null ||
        !currentTask.running ||
        currentTask.executionId.isEmpty ||
        person.operation.pending ||
        person.operation.uncertain) {
      return;
    }
    await person.operation.perform('task-stop:$id', {
      'task_id': id,
      'execution_id': currentTask.executionId,
      'expected_execution_id': currentTask.executionId,
      'expected_revision': currentTask.revision,
    }, (input) => person.api.stopPersonTask(input));
    await refresh();
    await person.refreshSnapshot();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
