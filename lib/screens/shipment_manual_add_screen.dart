import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_colors.dart';
import '../core/route_catalog.dart';
import '../services/supabase_service.dart';

class ShipmentManualAddScreen extends StatefulWidget {
  const ShipmentManualAddScreen({
    super.key,
    required this.route,
    required this.year,
    required this.voyage,
  });

  final String route;
  final int year;
  final String voyage;

  @override
  State<ShipmentManualAddScreen> createState() => _ShipmentManualAddScreenState();
}

class _ShipmentManualAddScreenState extends State<ShipmentManualAddScreen> {
  final _box = TextEditingController();
  final _invoice = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _receivedAt;
  bool _busy = false;
  bool _checking = false;
  bool _boxDuplicate = false;
  bool _invoiceDuplicate = false;

  String get _prefix => RouteCatalog.boxPrefixFor(widget.route);
  String get _fullBox {
    final raw = _box.text.trim();
    if (raw.isEmpty) return '';
    return _prefix.isEmpty || raw.startsWith(_prefix) ? raw : '$_prefix$raw';
  }

  @override
  void dispose() {
    _box.dispose(); _invoice.dispose(); _name.dispose(); _phone.dispose(); _notes.dispose();
    super.dispose();
  }

  Future<void> _checkDuplicates() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final result = await SupabaseService.client.rpc(
        'manager_check_shipment_duplicates',
        params: {
          'p_route': widget.route,
          'p_year': widget.year,
          'p_voyage': widget.voyage.replaceAll('항차', '').trim(),
          'p_box_number': _fullBox,
          'p_invoice_number': _invoice.text.trim(),
        },
      );
      if (!mounted) return;
      final data = Map<String, dynamic>.from(result as Map);
      setState(() {
        _boxDuplicate = data['box_duplicate'] == true;
        _invoiceDuplicate = data['invoice_duplicate'] == true;
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _receivedAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _receivedAt = picked);
  }

  Future<void> _save() async {
    await _checkDuplicates();
    if (_box.text.trim().isEmpty) {
      _message('박스번호를 입력해 주세요.');
      return;
    }
    if (_boxDuplicate) {
      _message('같은 운송 경로/년도/항차에 이미 존재하는 박스번호입니다.');
      return;
    }
    setState(() => _busy = true);
    try {
      await SupabaseService.client.rpc(
        'manager_add_manual_shipment',
        params: {
          'p_route': widget.route,
          'p_year': widget.year,
          'p_voyage': widget.voyage.replaceAll('항차', '').trim(),
          'p_box_number': _fullBox,
          'p_invoice_number': _invoice.text.trim(),
          'p_consignee_name': _name.text.trim(),
          'p_consignee_phone': _phone.text.trim(),
          'p_received_at': _receivedAt?.toIso8601String(),
          'p_notes': _notes.text.trim(),
        },
      );
      if (!mounted) return;
      _message('화물 데이터를 추가했습니다.');
      Navigator.pop(context, true);
    } catch (error) {
      _message('화물 추가 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  InputDecoration _decoration(String label, IconData icon, {String? errorText}) =>
      InputDecoration(
        labelText: label, prefixIcon: Icon(icon), errorText: errorText,
        filled: true, fillColor: AppColors.inputFill,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('화물 추가 입력'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        backgroundColor: AppColors.background,
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('${widget.route} · ${widget.year}년 · ${widget.voyage}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
            const SizedBox(height: 14),
            TextField(
              controller: _box,
              keyboardType: _prefix.isEmpty ? TextInputType.text : TextInputType.number,
              inputFormatters: _prefix.isEmpty ? null : <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
              ],
              onChanged: (_) => _checkDuplicates(),
              decoration: _decoration('박스번호', Icons.inventory_2_outlined,
                      errorText: _boxDuplicate ? '중복 박스번호입니다.' : null)
                  .copyWith(
                prefixText: _prefix.isEmpty ? null : _prefix,
                prefixStyle: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _invoice,
              onChanged: (_) => _checkDuplicates(),
              decoration: _decoration('송장번호', Icons.receipt_long_outlined,
                  errorText: _invoiceDuplicate ? '중복 송장번호가 있습니다.' : null),
            ),
            const SizedBox(height: 10),
            TextField(controller: _name, decoration: _decoration('이름/라오스 수령인', Icons.person_outline)),
            const SizedBox(height: 10),
            TextField(controller: _phone, keyboardType: TextInputType.phone,
                decoration: _decoration('연락처', Icons.phone_outlined)),
            const SizedBox(height: 10),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: _decoration('입고 날짜', Icons.calendar_today),
                child: Text(_receivedAt == null
                    ? '선택'
                    : '${_receivedAt!.year}-${_receivedAt!.month.toString().padLeft(2, '0')}-${_receivedAt!.day.toString().padLeft(2, '0')}'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(controller: _notes, maxLines: 3,
                decoration: _decoration('기타 추가 내용', Icons.edit_note_outlined)),
            const SizedBox(height: 6),
            const Text('기타 추가 내용은 Excel 다운로드 시 기본 폼의 구획 뒤 "비고" 컬럼에 반영됩니다.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            if (_checking) ...[const SizedBox(height: 8), const LinearProgressIndicator()],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_busy ? '저장 중...' : '화물 데이터 저장'),
            ),
          ],
        ),
      );
}
