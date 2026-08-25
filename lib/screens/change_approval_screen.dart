import 'package:flutter/material.dart';
import '../core/app_colors.dart';

class ChangeApprovalScreen extends StatefulWidget {
  const ChangeApprovalScreen({super.key});
  @override
  State<ChangeApprovalScreen> createState() => _ChangeApprovalScreenState();
}

class _ChangeApprovalScreenState extends State<ChangeApprovalScreen> {
  final List<Map<String, String>> _requests = [
    {
      'route': '한국-라오스 해상',
      'voyage': '01항차',
      'date': '2026-06-24',
      'cargo': 'LK-2026-001',
      'requester': '홍길동',
      'old': '연락처: 020-1111-2222',
      'new': '연락처: 020-9999-8888'
    },
    {
      'route': '한국-라오스 항공',
      'voyage': '02항차',
      'date': '2026-06-25',
      'cargo': 'LK-2026-002',
      'requester': '김민수',
      'old': '수령인: 김민수',
      'new': '수령인: 김민수(수정)'
    },
  ];
  final Set<int> _checked = {};
  final Set<int> _editing = {};
  void _result(String message, {int? index}) {
    if (index != null) setState(() => _requests.removeAt(index));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _bulk(String message) {
    final targets = _checked.toList()..sort((a, b) => b.compareTo(a));
    setState(() {
      for (final i in targets) {
        if (i < _requests.length) _requests.removeAt(i);
      }
      _checked.clear();
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$message 처리되었습니다.')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: const Text('화물 정보 변경 승인 요청 관리'),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white),
      backgroundColor: AppColors.background,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        CheckboxListTile(
            value: _checked.length == _requests.length && _requests.isNotEmpty,
            onChanged: (v) => setState(() {
                  if (v == true) {
                    _checked.addAll(List.generate(_requests.length, (i) => i));
                  } else {
                    _checked.clear();
                  }
                }),
            title: const Text('전체 선택',
                style: TextStyle(fontWeight: FontWeight.bold))),
        ...List.generate(_requests.length, (index) {
          final r = _requests[index];
          final editing = _editing.contains(index);
          return Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Checkbox(
                              value: _checked.contains(index),
                              onChanged: (v) => setState(() => v == true
                                  ? _checked.add(index)
                                  : _checked.remove(index))),
                          Expanded(
                              child: Text(
                                  '${r['cargo']}  ·  ${r['route']}  ·  ${r['voyage']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary)))
                        ]),
                        Text(
                            '날짜: ${r['date']}\n요청인: ${r['requester']}\n기존 내용: ${r['old']}\n요청 내용: ${r['new']}'),
                        if (editing)
                          Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(spacing: 8, children: [
                                OutlinedButton(
                                    onPressed: () =>
                                        setState(() => _editing.remove(index)),
                                    child: const Text('취소')),
                                FilledButton(
                                    onPressed: () =>
                                        setState(() => _editing.remove(index)),
                                    child: const Text('수정 완료'))
                              ]))
                        else
                          Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                    onPressed: () =>
                                        setState(() => _editing.add(index)),
                                    child: const Text('수정')),
                                TextButton(
                                    onPressed: () =>
                                        _result('거절되었습니다', index: index),
                                    child: const Text('거절')),
                                FilledButton(
                                    onPressed: () =>
                                        _result('승인되었습니다', index: index),
                                    child: const Text('승인'))
                              ])
                      ])));
        }),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: _checked.isEmpty ? null : () => _bulk('전체 거절'),
                  child: const Text('체크된 요청 전체 거절'))),
          const SizedBox(width: 8),
          Expanded(
              child: FilledButton(
                  onPressed:
                      _checked.isEmpty ? null : () => _bulk('체크된 요청 전체 승인'),
                  child: const Text('체크된 요청 전체 승인')))
        ]),
      ]));
}
