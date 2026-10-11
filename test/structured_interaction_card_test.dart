import 'dart:convert';

import 'package:chatstudio/data/structured_interaction.dart';
import 'package:chatstudio/ui/widgets/structured_interaction_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'renders mixed question controls and submits structured answers',
    (tester) async {
      final questionSet = StructuredQuestionSet.parse([
        {
          'qid': 'q0',
          'question': '单选',
          'choices': ['A (Recommended)', 'B'],
          'choices_offered': ['A', 'B'],
          'multi_select': false,
        },
        {
          'qid': 'q1',
          'question': '多选',
          'choices': ['X', 'Y'],
          'choices_offered': ['X', 'Y'],
          'multi_select': true,
        },
        {
          'qid': 'q2',
          'question': '开放输入',
          'choices': null,
          'choices_offered': null,
          'multi_select': false,
        },
      ])!;
      String? response;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StructuredInteractionCard(
              questionSet: questionSet,
              enabled: true,
              submitting: false,
              onSubmit: (value) => response = value,
            ),
          ),
        ),
      );

      expect(find.text('请逐项回答'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      final chips = find.byType(FilterChip);
      await tester.tap(chips.at(0));
      await tester.tap(chips.at(2));
      await tester.tap(chips.at(3));
      await tester.enterText(find.byType(TextField), '继续');
      await tester.tap(find.text('提交回答'));
      await tester.pump();

      expect(response, isNotNull);
      final payload = jsonDecode(response!) as Map<String, dynamic>;
      expect(payload['responses'], hasLength(3));
      expect((payload['responses'] as List)[0]['answer'], 'A (Recommended)');
      expect((payload['responses'] as List)[1]['answers'], ['X', 'Y']);
      expect((payload['responses'] as List)[2]['answer'], '继续');
    },
  );
}
