import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../services/quote_service.dart';

class QuoteRequestManagementScreen extends StatefulWidget {
  const QuoteRequestManagementScreen({super.key});

  @override
  State<QuoteRequestManagementScreen> createState() =>
      _QuoteRequestManagementScreenState();
}

class _QuoteRequestManagementScreenState
    extends State<QuoteRequestManagementScreen> {
  List<Map<String, dynamic>> _quotes = const [];
  bool _loading = true;
  int? _replyingQuoteId;
  int? _editingMessageId;
  final _replyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await QuoteService.instance.listAdminSpecialQuotes();
      if (!mounted) return;
      setState(() => _quotes = rows);
    } catch (error) {
      _message('견적 요청 조회 실패: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendReply(Map<String, dynamic> quote) async {
    final text = _replyController.text.trim();
    if (text.isEmpty) {
      _message('답변 내용을 입력해 주세요.');
      return;
    }
    try {
      if (_editingMessageId != null) {
        await QuoteService.instance.updateAdminReply(
          messageId: _editingMessageId!,
          message: text,
        );
      } else {
        await QuoteService.instance.addSpecialQuoteMessage(
          quoteId: _int(quote['id']),
          message: text,
        );
      }
      if (!mounted) return;
      setState(() {
        _replyingQuoteId = null;
        _editingMessageId = null;
        _replyController.clear();
      });
      _message('회신을 보냈습니다.');
      await _load();
    } catch (error) {
      _message('회신 처리 실패: $error');
    }
  }

  void _startReply(Map<String, dynamic> quote) {
    setState(() {
      _replyingQuoteId = _int(quote['id']);
      _editingMessageId = null;
      _replyController.clear();
    });
  }

  void _startEditReply(Map<String, dynamic> message) {
    setState(() {
      _replyingQuoteId = _int(message['quote_id']);
      _editingMessageId = _int(message['id']);
      _replyController.text = '${message['message'] ?? ''}';
    });
  }

  Future<void> _deleteReply(Map<String, dynamic> message) async {
    final ok = await _confirm('해당 답신을 삭제하시겠습니까?');
    if (!ok) return;
    try {
      await QuoteService.instance.deleteAdminReply(_int(message['id']));
      await _load();
    } catch (error) {
      _message('답신 삭제 실패: $error');
    }
  }

  Future<void> _requestDelete(Map<String, dynamic> quote) async {
    final ok = await _confirm('견적 요청을 삭제 대기로 전환하시겠습니까?');
    if (!ok) return;
    try {
      await QuoteService.instance.requestDelete(_int(quote['id']));
      await _load();
    } catch (error) {
      _message('삭제 처리 실패: $error');
    }
  }

  Future<void> _cancelDelete(Map<String, dynamic> quote) async {
    try {
      await QuoteService.instance.cancelDelete(_int(quote['id']));
      await _load();
    } catch (error) {
      _message('삭제 취소 실패: $error');
    }
  }

  Future<void> _deleteNow(Map<String, dynamic> quote) async {
    final ok = await _confirm('지금 목록에서 삭제하시겠습니까?');
    if (!ok) return;
    try {
      await QuoteService.instance.deleteNow(_int(quote['id']));
      await _load();
    } catch (error) {
      _message('바로 삭제 실패: $error');
    }
  }

  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('확인'),
            ),
          ],
        ),
      ) ??
      false;

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('견적 요청 관리'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        backgroundColor: AppColors.background,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_quotes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 50),
                        child: Center(child: Text('견적 요청이 없습니다.')),
                      )
                    else
                      ..._quotes.map(_quoteCard),
                  ],
                ),
              ),
      );

  Widget _quoteCard(Map<String, dynamic> quote) {
    final quoteId = _int(quote['id']);
    final messages = _messages(quote);
    final deletePending = quote['deletion_requested_at'] != null;
    final isReplying = _replyingQuoteId == quoteId;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${quote['subject'] ?? ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.navyPrimary,
                    ),
                  ),
                ),
                if (deletePending)
                  const Text(
                    '삭제 대기',
                    style: TextStyle(fontSize: 11, color: AppColors.error),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text('${quote['route'] ?? ''}', style: const TextStyle(fontSize: 12)),
            Text(
              '요청자: ${quote['customer_name'] ?? ''} · ${quote['contact_phone'] ?? ''}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            if ('${quote['other_contact'] ?? ''}'.trim().isNotEmpty)
              Text(
                '기타 연락처: ${quote['other_contact']}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            const SizedBox(height: 10),
            const Text('요청 내용', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            Text('${quote['content'] ?? ''}'),
            if (messages.isNotEmpty) ...[
              const Divider(height: 24),
              ...messages.map(_messageCard),
            ],
            if (isReplying) ...[
              const Divider(height: 24),
              TextField(
                controller: _replyController,
                minLines: 3,
                maxLines: 7,
                decoration: InputDecoration(
                  labelText: _editingMessageId == null ? '답변' : '답신 수정',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => setState(() {
                        _replyingQuoteId = null;
                        _editingMessageId = null;
                        _replyController.clear();
                      }),
                      child: const Text('취소'),
                    ),
                    ElevatedButton(
                      onPressed: () => _sendReply(quote),
                      child: Text(_editingMessageId == null ? '회신 하기' : '수정 저장'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (deletePending) ...[
                    OutlinedButton(
                      onPressed: () => _cancelDelete(quote),
                      child: const Text('삭제 취소'),
                    ),
                    ElevatedButton(
                      onPressed: () => _deleteNow(quote),
                      child: const Text('바로 삭제'),
                    ),
                  ] else ...[
                    OutlinedButton(
                      onPressed: isReplying ? null : () => _startReply(quote),
                      child: const Text('답변하기'),
                    ),
                    TextButton(
                      onPressed: () => _requestDelete(quote),
                      child: const Text('삭제'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageCard(Map<String, dynamic> message) {
    final admin = '${message['sender_role']}' == 'admin';
    final canEditAdmin = admin && message['viewed_at'] == null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: admin ? AppColors.inputFill : AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  admin ? '관리자 답신' : '요청자 추가 회신',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              if (canEditAdmin) ...[
                TextButton(
                  onPressed: () => _startEditReply(message),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: const Text('수정', style: TextStyle(fontSize: 11)),
                ),
                TextButton(
                  onPressed: () => _deleteReply(message),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: const Text('삭제', style: TextStyle(fontSize: 11)),
                ),
              ],
            ],
          ),
          Text('${message['message'] ?? ''}', style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _messages(Map<String, dynamic> quote) {
    final raw = quote['messages'];
    if (raw is! List) return const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static int _int(dynamic value) => int.tryParse('$value') ?? 0;
}
