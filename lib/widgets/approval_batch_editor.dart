import 'package:flutter/material.dart';

import '../core/approval_batch.dart';

class ApprovalBatchEditor extends StatefulWidget {
  const ApprovalBatchEditor({
    super.key,
    required this.items,
    required this.savedDrafts,
  });
  final List<ApprovalItem> items;
  final Map<String, Map<String, dynamic>> savedDrafts;
  @override
  State<ApprovalBatchEditor> createState() => _ApprovalBatchEditorState();
}

class _ApprovalBatchEditorState extends State<ApprovalBatchEditor> {
  late final drafts = [
    for (final item in widget.items)
      ApprovalDraft(item, saved: widget.savedDrafts[item.key]),
  ];
  String? error;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('선택 ${drafts.length}건 수정'),
    content: SizedBox(
      width: 680,
      height: MediaQuery.sizeOf(context).height * .6,
      child: Column(
        children: [
          const Text('각 화물의 값을 확인·수정한 뒤 아래 버튼으로 한 번에 처리합니다.'),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: drafts.length,
              itemBuilder: (context, index) {
                final draft = drafts[index];
                return ExpansionTile(
                  key: PageStorageKey(draft.item.key),
                  initiallyExpanded: index == 0,
                  title: Text(draft.item.label),
                  children: [
                    for (final field in draft.item.fields)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: TextFormField(
                          key: ValueKey('${draft.item.key}:$field'),
                          initialValue: draft.values[field],
                          onChanged: (value) => draft.values[field] = value,
                          keyboardType: approvalNumericFields.contains(field)
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                )
                              : TextInputType.text,
                          decoration: InputDecoration(
                            labelText: approvalFieldLabels[field],
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    if (draft.item.kind == ApprovalKind.incomplete)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: draft.lock,
                        onChanged: (value) =>
                            setState(() => draft.lock = value == true),
                        title: const Text('수정 후 데이터 잠금'),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: () {
          try {
            final values = {
              for (final draft in drafts) draft.item.key: draft.payload(),
            };
            Navigator.pop(context, values);
          } catch (e) {
            setState(() => error = '$e');
          }
        },
        child: Text(
          widget.items.first.kind == ApprovalKind.incomplete
              ? '선택 수정 저장'
              : '수정 후 일괄 승인',
        ),
      ),
    ],
  );
}
