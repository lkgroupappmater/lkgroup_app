import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_colors.dart';
import '../core/route_catalog.dart';
import '../services/shipment_service.dart';
import '../services/supabase_service.dart';

class ShipmentManualAddScreen extends StatefulWidget {
  const ShipmentManualAddScreen({
    super.key,
    this.initialRoute,
    this.initialYear,
    this.initialVoyage,
    this.initialInvoice = '',
    this.initialName = '',
    this.initialPhone = '',
  });

  final String? initialRoute;
  final int? initialYear;
  final String? initialVoyage;
  final String initialInvoice;
  final String initialName;
  final String initialPhone;

  @override
  State<ShipmentManualAddScreen> createState() => _ShipmentManualAddScreenState();
}

class _ShipmentManualAddScreenState extends State<ShipmentManualAddScreen> {
  final _box = TextEditingController();
  final _invoice = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _weight = TextEditingController();
  final _length = TextEditingController();
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _notes = TextEditingController();

  String? _route;
  int? _year;
  String? _voyage;
  DateTime? _receivedAt;

  bool _busy = false;
  bool _checking = false;
  bool _loadingNextBox = false;
  bool _boxDuplicate = false;
  bool _invoiceDuplicate = false;

  static final List<int> _years =
      List<int>.generate(10, (i) => DateTime.now().year - 2 + i);
  static final List<String> _voyages =
      List<String>.generate(30, (i) => '${(i + 1).toString().padLeft(2, '0')}항차');

  bool get _routeReady => _route != null && _year != null && _voyage != null;
  String get _prefix => _route == null ? '' : RouteCatalog.boxPrefixFor(_route!);

  String get _fullBox {
    final raw = _box.text.trim();
    if (raw.isEmpty) return '';
    return _prefix.isEmpty || raw.startsWith(_prefix) ? raw : '$_prefix$raw';
  }

  @override
  void initState() {
    super.initState();
    _route = widget.initialRoute;
    _year = widget.initialYear;
    _voyage = widget.initialVoyage;
    _invoice.text = widget.initialInvoice;
    _name.text = widget.initialName;
    _phone.text = widget.initialPhone;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_routeReady) _loadNextBoxNumber();
    });
  }

  @override
  void dispose() {
    _box.dispose();
    _invoice.dispose();
    _name.dispose();
    _phone.dispose();
    _quantity.dispose();
    _weight.dispose();
    _length.dispose();
    _width.dispose();
    _height.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadNextBoxNumber() async {
    if (!_routeReady) {
      if (mounted) {
        setState(() {
          _box.clear();
          _boxDuplicate = false;
        });
      }
      return;
    }
    if (_prefix.isEmpty) return;

    setState(() => _loadingNextBox = true);
    try {
      final nextBox = await ShipmentService.instance.getNextBoxNumber(
        route: _route!,
        year: _year!,
        voyage: _voyage!,
        prefix: _prefix,
      );
      if (!mounted) return;
      setState(() {
        _box.text = nextBox.startsWith(_prefix)
            ? nextBox.substring(_prefix.length)
            : nextBox;
        _boxDuplicate = false;
      });
      await _checkDuplicates();
    } catch (error) {
      _message('다음 박스번호 확인 실패: $error');
    } finally {
      if (mounted) setState(() => _loadingNextBox = false);
    }
  }

  Future<void> _checkDuplicates() async {
    if (!_routeReady || _checking) return;
    setState(() => _checking = true);
    try {
      final result = await SupabaseService.client.rpc(
        'manager_check_shipment_duplicates',
        params: {
          'p_route': _route,
          'p_year': _year,
          'p_voyage': _voyage!.replaceAll('항차', '').trim(),
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

  int? _int(TextEditingController controller) =>
      int.tryParse(controller.text.replaceAll(',', '').trim());

  double? _double(TextEditingController controller) {
    final text = controller.text.replaceAll(',', '').trim();
    return text.isEmpty ? null : double.tryParse(text);
  }

  Future<void> _save() async {
    if (!_routeReady) {
      _message('운송 경로, 년도, 항차를 모두 선택해 주세요.');
      return;
    }
    await _checkDuplicates();
    if (_box.text.trim().isEmpty) {
      _message('박스번호를 입력해 주세요.');
      return;
    }
    if (_boxDuplicate) {
      _message('같은 운송 경로/년도/항차에 이미 존재하는 박스번호입니다.');
      return;
    }

    final quantity = _int(_quantity);
    if (quantity == null || quantity <= 0) {
      _message('박스 개수(수량)는 1 이상의 숫자로 입력해 주세요.');
      return;
    }

    final weight = _double(_weight);
    final length = _double(_length);
    final width = _double(_width);
    final height = _double(_height);

    if ((_weight.text.trim().isNotEmpty && weight == null) ||
        (_length.text.trim().isNotEmpty && length == null) ||
        (_width.text.trim().isNotEmpty && width == null) ||
        (_height.text.trim().isNotEmpty && height == null)) {
      _message('중량과 크기(L/W/H)는 숫자로 입력해 주세요.');
      return;
    }

    setState(() => _busy = true);
    try {
      await SupabaseService.client.rpc(
        'manager_add_manual_shipment',
        params: {
          'p_route': _route,
          'p_year': _year,
          'p_voyage': _voyage!.replaceAll('항차', '').trim(),
          'p_box_number': _fullBox,
          'p_invoice_number': _invoice.text.trim(),
          'p_consignee_name': _name.text.trim(),
          'p_consignee_phone': _phone.text.trim(),
          'p_received_at': _receivedAt?.toIso8601String(),
          'p_notes': _notes.text.trim(),
          'p_quantity': quantity,
          'p_weight_kg': weight,
          'p_length_cm': length,
          'p_width_cm': width,
          'p_height_cm': height,
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
        labelText: label,
        prefixIcon: Icon(icon),
        errorText: errorText,
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
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
            DropdownButtonFormField<String>(
              initialValue: _route,
              decoration: _decoration('운송 경로', Icons.route),
              items: routeLabels
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: _busy
                  ? null
                  : (value) async {
                      setState(() {
                        _route = value;
                        _box.clear();
                      });
                      await _loadNextBoxNumber();
                    },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _year,
                    decoration: _decoration('년도', Icons.calendar_today),
                    items: _years
                        .map((v) => DropdownMenuItem(value: v, child: Text('$v년')))
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) async {
                            setState(() {
                              _year = value;
                              _box.clear();
                            });
                            await _loadNextBoxNumber();
                          },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _voyage,
                    decoration:
                        _decoration('항차', Icons.confirmation_number_outlined),
                    items: _voyages
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) async {
                            setState(() {
                              _voyage = value;
                              _box.clear();
                            });
                            await _loadNextBoxNumber();
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _box,
              enabled: _routeReady && !_loadingNextBox,
              keyboardType:
                  _prefix.isEmpty ? TextInputType.text : TextInputType.number,
              inputFormatters: _prefix.isEmpty
                  ? null
                  : <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                    ],
              onChanged: (_) => _checkDuplicates(),
              decoration: _decoration(
                '박스번호',
                Icons.inventory_2_outlined,
                errorText: _boxDuplicate
                    ? '중복 박스번호입니다. 저장할 수 없습니다.'
                    : null,
              ).copyWith(
                prefixText: _prefix.isEmpty ? null : _prefix,
                prefixStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                helperText: _loadingNextBox ? '다음 박스번호 확인 중...' : null,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _invoice,
              onChanged: (_) => _checkDuplicates(),
              decoration: _decoration(
                '송장번호',
                Icons.receipt_long_outlined,
                errorText: _invoiceDuplicate ? '중복 송장번호가 있습니다.' : null,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              decoration: _decoration('이름/라오스 수령인', Icons.person_outline),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: _decoration('연락처', Icons.phone_outlined),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _decoration('박스 개수/수량', Icons.numbers_outlined),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _decoration('중량', Icons.scale_outlined).copyWith(
                suffixText: 'kg',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _length,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _decoration('L', Icons.straighten).copyWith(
                      suffixText: 'cm',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _width,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _decoration('W', Icons.straighten).copyWith(
                      suffixText: 'cm',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _height,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _decoration('H', Icons.height).copyWith(
                      suffixText: 'cm',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: _decoration('입고 날짜', Icons.calendar_today),
                child: Text(
                  _receivedAt == null
                      ? '선택'
                      : '${_receivedAt!.year}-${_receivedAt!.month.toString().padLeft(2, '0')}-${_receivedAt!.day.toString().padLeft(2, '0')}',
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: _decoration('기타 추가 내용', Icons.edit_note_outlined),
            ),
            if (_checking) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed:
                  _busy || !_routeReady || _boxDuplicate ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_busy ? '저장 중...' : '화물 데이터 저장'),
            ),
          ],
        ),
      );
}
