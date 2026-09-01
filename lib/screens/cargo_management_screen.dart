import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_colors.dart';
import '../core/route_catalog.dart';
import '../core/money_format.dart';
import '../models/app_user.dart';
import '../services/shipment_service.dart';
import '../services/freight_service.dart';
import '../services/shipment_filter_options_service.dart';
import '../services/receipt_extra_cost_service.dart';
import '../services/receipt_discount_service.dart';
import 'shipment_manual_add_screen.dart';
import 'notice_management_screen.dart';
import 'schedule_management_screen.dart';
import 'excel_upload_screen.dart';
import 'exchange_rate_screen.dart';
import 'member_management_screen.dart';
import 'change_approval_screen.dart';
import 'quote_request_management_screen.dart';
import 'statement_preview_dialog.dart';
import 'batch_statement_pdf_dialog.dart';

class CargoManagementScreen extends StatefulWidget {
  const CargoManagementScreen({
    super.key,
    required this.user,
    this.onBack,
    this.initialSelectedIds = const <String>[],
  });

  final AppUser user;
  final VoidCallback? onBack;
  final List<String> initialSelectedIds;

  @override
  State<CargoManagementScreen> createState() => _CargoManagementScreenState();
}

class _CargoManagementScreenState extends State<CargoManagementScreen> {
  final _boxNumberController = TextEditingController();
  final _invoiceController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  final _editBoxNumberController = TextEditingController();
  final _editNameController = TextEditingController();
  final _editPhoneController = TextEditingController();
  final _editNoteController = TextEditingController();
  final _weightController = TextEditingController();
  final _lengthController = TextEditingController();
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();

  String _route = '전체';
  String _year = '전체';
  String _voyage = '전체';
  List<Map<String, dynamic>> _results = const [];
  List<Map<String, dynamic>> _pendingDeletions = const [];
  List<ShipmentBatchOption> _filterBatches = const [];
  final Set<String> _selectedIds = <String>{};
  bool _searched = false;
  bool _busy = false;

  bool _showBoxSearch = true;
  bool _showInvoiceSearch = true;
  bool _showNameSearch = true;
  bool _showPhoneSearch = true;

  bool get _isAdmin => widget.user.role == UserRole.admin;
  bool get _isStaff => widget.user.role == UserRole.staff;
  bool get _isPartner => widget.user.role == UserRole.partner;
  bool get _isManager => _isAdmin || _isStaff || _isPartner;
  bool get _canSaveDirectly => _isManager;
  List<String> get _availableYears {
    final years =
        ShipmentFilterOptionsService.instance.yearsFor(_filterBatches, _route);
    return <String>['전체', ...years.map((e) => '$e년')];
  }

  List<String> get _availableVoyages {
    final year =
        int.tryParse(_year.replaceAll(RegExp(r'[^0-9]'), ''));
    if (year == null) return const <String>['전체'];
    final voyages = ShipmentFilterOptionsService.instance
        .voyagesFor(_filterBatches, _route, year);
    return <String>[
      '전체',
      ...voyages.map(
        (e) => e.endsWith('항차') ? e : '${e}항차',
      ),
    ];
  }

  Future<void> _loadFilterBatches() async {
    try {
      final rows = await ShipmentFilterOptionsService.instance.listBatches();
      if (!mounted) return;
      setState(() {
        _filterBatches = rows;
        if (!_availableYears.contains(_year)) _year = '전체';
        if (!_availableVoyages.contains(_voyage)) _voyage = '전체';
      });
    } catch (_) {
      // 공통 조회 옵션 실패가 기존 화물 관리 기능을 막지 않도록 합니다.
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFilterBatches();
    if (widget.initialSelectedIds.isNotEmpty) _loadSelected();
    if (_isManager) _loadPendingDeletions();
  }

  @override
  void dispose() {
    _boxNumberController.dispose();
    _invoiceController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _editBoxNumberController.dispose();
    _editNameController.dispose();
    _editPhoneController.dispose();
    _editNoteController.dispose();
    _weightController.dispose();
    _lengthController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  Future<void> _loadSelected() async {
    final rows = await ShipmentService.instance.getRowsByIds(widget.initialSelectedIds);
    if (!mounted) return;
    setState(() {
      _results = rows;
      _searched = true;
    });
    _syncEditControllers();
  }

  String _boxNumberForRequest() {
    final raw = _boxNumberController.text.trim();
    if (raw.isEmpty) return '';
    final prefix = RouteCatalog.boxPrefixFor(_route);
    if (prefix.isEmpty) return raw;
    return '$prefix$raw';
  }

  Future<void> _search() async {
    setState(() => _busy = true);
    try {
      final rows = await ShipmentService.instance.searchRows(
        route: _route,
        boxNumber: _showBoxSearch ? _boxNumberForRequest() : '',
        invoice: _showInvoiceSearch ? _invoiceController.text.trim() : '',
        recipient: _showNameSearch ? _nameController.text.trim() : '',
        phone: _showPhoneSearch ? _phoneController.text.trim() : '',
        year: _year,
        voyage: _voyage,
        currentUser: widget.user,
      );
      if (!mounted) return;
      setState(() {
        _results = rows;
        _searched = true;
        _selectedIds.clear();
      });
      _syncEditControllers();

      if (_isManager && rows.isEmpty) {
        final add = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            content: const Text(
              '검색 하신 화물 데이타가 없습니다. 화물을 추가 하시겠습니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('화물 추가 입력'),
              ),
            ],
          ),
        );
        if (add == true && mounted) {
          await _openManualAdd(
            route: _route,
            year: _year,
            voyage: _voyage,
            boxNumber: _boxNumberController.text.trim(),
            invoice: _invoiceController.text.trim(),
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
          );
        }
      }
    } catch (error) {
      _message('화물 검색 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openManualAdd({
    String? route,
    String? year,
    String? voyage,
    String boxNumber = '',
    String invoice = '',
    String name = '',
    String phone = '',
  }) async {
    final parsedYear = year == null || year == '전체'
        ? null
        : int.tryParse(year.replaceAll(RegExp(r'[^0-9]'), ''));
    final selectedVoyage =
        voyage == null || voyage == '전체' ? null : voyage;

    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ShipmentManualAddScreen(
          initialRoute: route,
          initialYear: parsedYear,
          initialVoyage: selectedVoyage,
          initialBoxNumber: boxNumber,
          initialInvoice: invoice,
          initialName: name,
          initialPhone: phone,
        ),
      ),
    );
    if (added == true && mounted) {
      await _search();
    }
  }

  void _toggle(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
    _syncEditControllers();
  }

  void _syncEditControllers() {
    if (_selectedIds.length != 1) {
      _editBoxNumberController.clear();
      _editNameController.clear();
      _editPhoneController.clear();
      _editNoteController.clear();
      _weightController.clear();
      _lengthController.clear();
      _widthController.clear();
      _heightController.clear();
      return;
    }
    final id = _selectedIds.first;
    Map<String, dynamic>? row;
    for (final item in _results) {
      if ('${item['id']}' == id) {
        row = item;
        break;
      }
    }
    if (row == null) return;
    final rowRoute = '${row['route'] ?? ''}';
    final prefix = RouteCatalog.boxPrefixFor(rowRoute);
    final currentBox = '${row['box_number'] ?? ''}';
    _editBoxNumberController.text = prefix.isNotEmpty && currentBox.startsWith(prefix)
        ? currentBox.substring(prefix.length)
        : currentBox;
    _editNameController.text = '${row['consignee_name'] ?? ''}';
    _editPhoneController.text = '${row['consignee_phone'] ?? ''}';
    _editNoteController.text = '${row['notes'] ?? ''}';
    _weightController.text = '${row['weight_kg'] ?? ''}';
    _lengthController.text = '${row['length_cm'] ?? ''}';
    _widthController.text = '${row['width_cm'] ?? ''}';
    _heightController.text = '${row['height_cm'] ?? ''}';
  }

  Map<String, dynamic> _memberChanges() {
    final changes = <String, dynamic>{};
    if (_editNameController.text.trim().isNotEmpty) {
      changes['consignee_name'] = _editNameController.text.trim();
    }
    if (_editPhoneController.text.trim().isNotEmpty) {
      changes['consignee_phone'] = _editPhoneController.text.trim();
    }
    if (_editNoteController.text.trim().isNotEmpty) {
      changes['notes'] = _editNoteController.text.trim();
    }
    return changes;
  }

  Map<String, dynamic> _managerChanges() {
    final changes = _memberChanges();
    final weight = num.tryParse(_weightController.text.trim());
    final length = num.tryParse(_lengthController.text.trim());
    final width = num.tryParse(_widthController.text.trim());
    final height = num.tryParse(_heightController.text.trim());
    if (_weightController.text.trim().isNotEmpty && weight != null) {
      changes['weight_kg'] = weight;
    }
    if (_lengthController.text.trim().isNotEmpty && length != null) {
      changes['length_cm'] = length;
    }
    if (_widthController.text.trim().isNotEmpty && width != null) {
      changes['width_cm'] = width;
    }
    if (_heightController.text.trim().isNotEmpty && height != null) {
      changes['height_cm'] = height;
    }
    return changes;
  }

  Future<void> _showStatement() async {
    if (_isPartner) {
      _message('협력/파트너 계정은 명세서를 조회할 수 없습니다.');
      return;
    }
    if (_selectedIds.isEmpty) {
      _message('명세서를 확인할 화물을 선택해 주세요.');
      return;
    }

    final selected = _results
        .where((row) => _selectedIds.contains('${row['id']}'))
        .toList(growable: false);
    if (selected.isEmpty) return;

    final receipt = '${selected.first['receipt_number'] ?? ''}'.trim();
    if (receipt.isEmpty) {
      _message('선택한 화물에 영수번호가 없습니다.');
      return;
    }
    if (selected.any((row) =>
        '${row['receipt_number'] ?? ''}'.trim() != receipt)) {
      _message('명세서는 같은 영수번호(고객)의 화물끼리 선택해 주세요.');
      return;
    }

    final route = '${selected.first['route'] ?? ''}';
    final year = (selected.first['shipment_year'] as num?)?.toInt();
    final voyage = '${selected.first['voyage'] ?? ''}';
    if (route.isEmpty || year == null || voyage.isEmpty) {
      _message('명세서의 운송경로/년도/항차 정보를 확인할 수 없습니다.');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (_) => StatementPreviewDialog(
        routeLabel: route,
        year: year,
        voyage: voyage,
        receiptNumber: receipt,
      ),
    );
  }

  Future<void> _showBatchStatementPdf({
    List<Map<String, dynamic>>? scopeRows,
  }) async {
    if (_isPartner) {
      _message('협력/파트너 계정은 명세서를 출력할 수 없습니다.');
      return;
    }
    if (_selectedIds.isEmpty) {
      _message('PDF로 저장할 명세서의 화물을 먼저 체크해 주세요.');
      return;
    }
    final source = scopeRows ?? _results;
    final selected = source
        .where((row) => _selectedIds.contains('${row['id']}'))
        .toList(growable: false);
    if (selected.isEmpty) {
      _message('이 항차에서 체크된 화물이 없습니다.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => BatchStatementPdfDialog(selectedRows: selected),
    );
  }
  Future<void> _save() async {
    if (_selectedIds.isEmpty) return;
    final changes = _canSaveDirectly ? _managerChanges() : _memberChanges();
    if (changes.isEmpty) {
      _message('수정할 내용을 입력해 주세요.');
      return;
    }

    setState(() => _busy = true);
    try {
      if (_canSaveDirectly) {
        if (_isAdmin && _selectedIds.length == 1 && _editBoxNumberController.text.trim().isNotEmpty) {
          final selectedId = _selectedIds.first;
          final row = _results.firstWhere((item) => '${item['id']}' == selectedId);
          final rowRoute = '${row['route'] ?? ''}';
          final prefix = RouteCatalog.boxPrefixFor(rowRoute);
          final raw = _editBoxNumberController.text.trim();
          final fullBox = prefix.isEmpty || raw.startsWith(prefix) ? raw : '$prefix$raw';
          if (fullBox != '${row['box_number'] ?? ''}') {
            await ShipmentService.instance.adminUpdateBoxNumber(
              shipmentId: selectedId,
              boxNumber: fullBox,
            );
          }
        }
        for (final id in _selectedIds) {
          await ShipmentService.instance.updateRow(id, changes);
        }
        _message('선택한 화물 정보를 저장했습니다.');
        await _reloadCurrentRows();
      } else {
        await ShipmentService.instance.requestChanges(
          shipmentIds: _selectedIds.toList(),
          changes: changes,
        );
        _message('관리자에게 화물 정보 수정 요청을 보냈습니다.');
      }
    } catch (error) {
      _message('화물 정보 처리 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadPendingDeletions() async {
    if (!_isManager) return;
    try {
      final rows =
          await ShipmentService.instance.getPendingShipmentDeletions();
      if (!mounted) return;
      setState(() => _pendingDeletions = rows);
    } catch (error) {
      _message('화물 삭제 대기 목록 불러오기 실패: $error');
    }
  }

  Future<void> _requestDeletion(Map<String, dynamic> item) async {
    final id = '${item['id']}';
    final box = '${item['box_number'] ?? ''}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('화물 삭제'),
        content: Text(
          '$box 화물을 삭제 대기로 이동하시겠습니까?\n\n'
          '삭제 대기 중에는 아래 "화물 삭제 대기"에서 취소하거나 바로 삭제할 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('삭제 대기'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ShipmentService.instance.requestShipmentDeletion(id);
      _selectedIds.remove(id);
      setState(() {
        _results = _results
            .where((row) => '${row['id']}' != id)
            .toList(growable: false);
      });
      await _loadPendingDeletions();
      _message('$box 화물을 삭제 대기로 이동했습니다.');
    } catch (error) {
      _message('화물 삭제 대기 처리 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelDeletion(Map<String, dynamic> item) async {
    final id = '${item['id']}';
    setState(() => _busy = true);
    try {
      await ShipmentService.instance.cancelShipmentDeletion(id);
      await _loadPendingDeletions();
      _message('화물 삭제를 취소했습니다.');
      if (_searched) await _search();
    } catch (error) {
      _message('삭제 취소 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteNow(Map<String, dynamic> item) async {
    final id = '${item['id']}';
    final box = '${item['box_number'] ?? ''}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('화물 바로 삭제'),
        content: Text(
          '$box 화물을 바로 삭제하시겠습니까?\n\n'
          '바로 삭제 후에는 앱에서 복구할 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('바로 삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ShipmentService.instance.deleteShipmentNow(id);
      await _loadPendingDeletions();
      _message('$box 화물을 바로 삭제했습니다.');
    } catch (error) {
      _message('화물 바로 삭제 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _pendingDeletionCard(Map<String, dynamic> item) {
    final quantity = int.tryParse('${item['quantity'] ?? ''}') ?? 1;
    final receipt = '${item['receipt_number'] ?? ''}'.trim();
    final zone = '${item['unloading_zone'] ?? ''}'.trim();
    final phone = '${item['consignee_phone'] ?? ''}'.trim();
    final receivedDate = _dateOnly(item['received_at']);
    final length = _naturalNumber(item['length_cm']);
    final height = _naturalNumber(item['height_cm']);
    final width = _naturalNumber(item['width_cm']);
    final size = '$length × $height × $width cm';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${item['consignee_name'] ?? '-'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.navyPrimary,
                  ),
                ),
                Text(
                  phone.isEmpty ? '-' : phone,
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  '영수번호/구획: ${receipt.isEmpty ? '-' : receipt} / ${zone.isEmpty ? '-' : zone}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  '${item['route'] ?? ''} · ${item['shipment_year'] ?? ''}년 · ${_voyageLabel(item['voyage'])}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _infoRow('화물번호', '${item['box_number'] ?? ''}'),
            _infoRow('송장번호', '${item['invoice_number'] ?? ''}'),
            _infoRow('화물개수', '$quantity개'),
            _infoRow(
              '무게 / 크기',
              '${_weightOneDecimal(item['weight_kg'])} kg / $size',
            ),
            _infoRow('입고날짜', receivedDate),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _cancelDeletion(item),
                    child: const Text('삭제 취소'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _deleteNow(item),
                    child: const Text('바로 삭제'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  Future<void> _reloadCurrentRows() async {
    if (_selectedIds.isEmpty) return;
    final rows = await ShipmentService.instance.getRowsByIds(_selectedIds.toList());
    if (!mounted) return;
    final replacements = {for (final row in rows) '${row['id']}': row};
    setState(() {
      _results = _results
          .map((row) => replacements['${row['id']}'] ?? row)
          .toList(growable: false);
    });
    _syncEditControllers();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );

  Widget _managementSection() {
    final items = <Map<String, Object>>[
      {
        'label': '선적 일정 관리',
        'icon': Icons.calendar_month,
        'page': ScheduleManagementScreen(user: widget.user),
      },
      {
        'label': '공지사항 관리',
        'icon': Icons.campaign_outlined,
        'page': NoticeManagementScreen(user: widget.user),
      },
      {
        'label': '화물 종합 관리',
        'icon': Icons.inventory_2_outlined,
        'page': CargoManagementScreen(user: widget.user),
      },
    ];

    if (_isAdmin || _isStaff) {
      items.add({
        'label': '엑셀 화물 업로드',
        'icon': Icons.upload_file_outlined,
        'page': const ExcelUploadScreen(),
      });
    }

    if (_isAdmin) {
      items.addAll([
        {
          'label': '회원 종합 관리',
          'icon': Icons.people_alt_outlined,
          'page': const MemberManagementScreen(),
        },
        {
          'label': '변경 승인 관리',
          'icon': Icons.fact_check_outlined,
          'page': const ChangeApprovalScreen(),
        },
        {
          'label': '견적 요청 관리',
          'icon': Icons.request_quote_outlined,
          'page': const QuoteRequestManagementScreen(),
        },
        {
          'label': '기준 환율 입력',
          'icon': Icons.currency_exchange,
          'page': const ExchangeRateScreen(),
        },
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '통합 관리',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.65,
          children: items.map((item) {
            return OutlinedButton.icon(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => item['page']! as Widget),
              ),
              icon: Icon(item['icon']! as IconData, size: 18),
              label: Text(item['label']! as String, textAlign: TextAlign.center),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _filterToggles() => Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _filterChip('박스번호', _showBoxSearch,
              (v) => setState(() => _showBoxSearch = v)),
          _filterChip('송장번호', _showInvoiceSearch,
              (v) => setState(() => _showInvoiceSearch = v)),
          _filterChip('이름', _showNameSearch,
              (v) => setState(() => _showNameSearch = v)),
          _filterChip('연락처', _showPhoneSearch,
              (v) => setState(() => _showPhoneSearch = v)),
        ],
      );

  Widget _filterChip(String label, bool selected, ValueChanged<bool> onSelected) =>
      FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: onSelected,
        visualDensity: VisualDensity.compact,
      );

  Future<void> _showSelectedStatementChoice() async {
    if (_isPartner) {
      _message('협력/파트너 계정은 명세서를 조회할 수 없습니다.');
      return;
    }
    if (_selectedIds.isEmpty) {
      _message('확인 할 고객을 선택 하시오');
      return;
    }

    final selected = _results
        .where((row) => _selectedIds.contains('${row['id']}'))
        .toList(growable: false);
    if (selected.isEmpty) {
      _message('확인 할 고객을 선택 하시오');
      return;
    }

    String receiptKey(Map<String, dynamic> row) =>
        '${row['route'] ?? ''}|${row['shipment_year'] ?? ''}|'
        '${row['voyage'] ?? ''}|${row['receipt_number'] ?? ''}';

    final receiptGroups = selected.map(receiptKey).toSet();
    final singleReceipt = receiptGroups.length == 1;

    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('명세서 발급'),
        content: Text(
          singleReceipt
              ? '선택한 고객/영수번호의 명세서 발급 형식을 선택해 주세요.'
              : '복수 고객/영수번호 명세서는 PDF로만 발급됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          if (singleReceipt)
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'image'),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('이미지'),
            ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'pdf'),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('PDF'),
          ),
        ],
      ),
    );

    if (!mounted || choice == null) return;
    if (choice == 'image') {
      await _showStatement();
    } else if (choice == 'pdf') {
      await _showBatchStatementPdf();
    }
  }

  Widget _cargoFixedBottomBar() {
    final enabled = _results.isNotEmpty;
    return Material(
      elevation: 14,
      borderRadius: BorderRadius.circular(22),
      color: Colors.transparent,
      shadowColor: Colors.black38,
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: AppColors.navyPrimary,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: enabled ? _toggleAllSearchResults : null,
                    borderRadius: BorderRadius.circular(15),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _allSearchResultsSelected
                              ? Icons.check_circle
                              : Icons.check_circle_outline,
                          size: 21,
                          color: enabled
                              ? AppColors.tealAccent
                              : Colors.white38,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '전체',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: enabled ? Colors.white : Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 34,
                  color: Colors.white.withValues(alpha: .16),
                ),
                Expanded(
                  flex: 2,
                  child: InkWell(
                    onTap: _isPartner ? null : _showSelectedStatementChoice,
                    borderRadius: BorderRadius.circular(15),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 22,
                          color: _isPartner
                              ? Colors.white38
                              : AppColors.tealAccent,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selectedIds.isEmpty
                              ? '명세서'
                              : '명세서 · ${_selectedIds.length}개 선택',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color:
                                _isPartner ? Colors.white38 : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            if (widget.onBack != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('계정으로 돌아가기'),
                ),
              ),
            Card(
              color: AppColors.primary,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundImage: widget.user.avatarUrl != null &&
                          widget.user.avatarUrl!.trim().isNotEmpty
                      ? NetworkImage(widget.user.avatarUrl!)
                      : null,
                  child: widget.user.avatarUrl == null ||
                          widget.user.avatarUrl!.trim().isEmpty
                      ? const Icon(Icons.person)
                      : null,
                ),
                title: Text(
                  widget.user.name.isEmpty ? '회원' : widget.user.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  widget.user.roleLabel,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '화물 관리',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                if (_isManager) ...[
                  const SizedBox(width: 10),
                  Expanded(child: _filterToggles()),
                ],
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _route,
              decoration: _decoration('운송 경로', Icons.route),
              items: routeLabels
                  .map((route) => DropdownMenuItem(value: route, child: Text(route)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _route = value;
                    _year = '전체';
                    _voyage = '전체';
                    _boxNumberController.clear();
                  });
                }
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _year,
                    decoration: _decoration('년도', Icons.calendar_today),
                    items: _availableYears
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _year = v;
                          _voyage = '전체';
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _voyage,
                    decoration: _decoration('항차', Icons.confirmation_number_outlined),
                    items: _availableVoyages
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _voyage = v);
                    },
                  ),
                ),
              ],
            ),
            if (_isManager && _showBoxSearch) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _boxNumberController,
                keyboardType: RouteCatalog.boxPrefixFor(_route).isEmpty
                    ? TextInputType.text
                    : TextInputType.number,
                inputFormatters: RouteCatalog.boxPrefixFor(_route).isEmpty
                    ? null
                    : <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                      ],
                decoration: _decoration(
                  RouteCatalog.boxExampleFor(_route).isEmpty
                      ? '박스번호'
                      : '박스번호 (예: ${RouteCatalog.boxExampleFor(_route)})',
                  Icons.inventory_2_outlined,
                ).copyWith(
                  prefixText: RouteCatalog.boxPrefixFor(_route).isEmpty
                      ? null
                      : RouteCatalog.boxPrefixFor(_route),
                  prefixStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
            if (!_isManager || _showInvoiceSearch) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _invoiceController,
                decoration: _decoration('송장번호', Icons.receipt_long_outlined),
              ),
            ],
            if (!_isManager || _showNameSearch) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                decoration: _decoration('이름/라오스 수령인', Icons.person_outline),
              ),
            ],
            if (!_isManager || _showPhoneSearch) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: _decoration('연락처', Icons.phone_outlined),
              ),
            ],
            const SizedBox(height: 10),
            if (_isManager)
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _search,
                        icon: const Icon(Icons.search),
                        label: Text(_busy ? '검색 중...' : '화물 검색'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _openManualAdd(),
                        icon: const Icon(Icons.add_box_outlined),
                        label: const Text('화물 추가 입력'),
                      ),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _search,
                  icon: const Icon(Icons.search),
                  label: Text(_busy ? '검색 중...' : '화물 검색'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            if (_searched) ...[
              const SizedBox(height: 16),
              Text(
                '화물 정보 (${_results.length}건)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              ..._managementGroupWidgets(),
            ],
            if (false && _selectedIds.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                '선택한 화물 정보 수정',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              if (_isAdmin && _selectedIds.length == 1) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _editBoxNumberController,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                  ],
                  decoration: _decoration('박스번호', Icons.inventory_2_outlined).copyWith(
                    prefixText: _selectedBoxPrefix(),
                    prefixStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _editNameController,
                decoration: _decoration('이름/라오스 수령인', Icons.person_outline),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _editPhoneController,
                keyboardType: TextInputType.phone,
                decoration: _decoration('연락처', Icons.phone_outlined),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _editNoteController,
                maxLines: 3,
                decoration: _decoration('기타 내용', Icons.edit_note_outlined),
              ),
              if (_isManager) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _numberField(_weightController, '무게(kg)')),
                    const SizedBox(width: 8),
                    Expanded(child: _numberField(_lengthController, '가로(cm)')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _numberField(_widthController, '세로(cm)')),
                    const SizedBox(width: 8),
                    Expanded(child: _numberField(_heightController, '높이(cm)')),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save),
                label: Text(_canSaveDirectly ? '화물 정보 저장' : '화물 정보 수정 요청'),
              ),              const SizedBox(height: 8),
              if (!_isPartner)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _showBatchStatementPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('체크 명세서 PDF'),
                ),
            ],
            if (_isManager) ...[
              const SizedBox(height: 24),
              const Text(
                '화물 삭제 대기',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 6),
              if (_pendingDeletions.isEmpty)
                const Text(
                  '삭제 대기 중인 화물이 없습니다.',
                  style: TextStyle(color: AppColors.textSecondary),
                )
              else
                ..._pendingDeletions.map(_pendingDeletionCard),
            ],
          ],
          ),
            if (_searched)
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: _cargoFixedBottomBar(),
              ),
          ],
        ),
      );

  String _selectedBoxPrefix() {
    if (_selectedIds.length != 1) return '';
    final id = _selectedIds.first;
    final row = _results.cast<Map<String, dynamic>?>().firstWhere(
          (item) => item != null && '${item['id']}' == id,
          orElse: () => null,
        );
    if (row == null) return '';
    return RouteCatalog.boxPrefixFor('${row['route'] ?? ''}');
  }

  Future<void> _showAddShipmentRowDialog() async {
    if (_route == '전체' || _year == '전체' || _voyage == '전체') {
      _message('박스를 추가하려면 운송 경로, 년도, 항차를 각각 선택해 주세요.');
      return;
    }
    final year = int.tryParse(_year.replaceAll(RegExp(r'[^0-9]'), ''));
    if (year == null) {
      _message('년도를 확인해 주세요.');
      return;
    }
    final prefix = RouteCatalog.boxPrefixFor(_route);
    if (prefix.isEmpty) {
      _message('선택한 운송 경로의 박스번호 형식을 확인할 수 없습니다.');
      return;
    }

    setState(() => _busy = true);
    String nextBox;
    try {
      nextBox = await ShipmentService.instance.getNextBoxNumber(
        route: _route,
        year: year,
        voyage: _voyage,
        prefix: prefix,
      );
    } catch (error) {
      if (mounted) _message('다음 박스번호 확인 실패: $error');
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;

    final invoice = TextEditingController();
    final name = TextEditingController();
    final phone = TextEditingController();
    final notes = TextEditingController();
    final weight = TextEditingController();
    final length = TextEditingController();
    final width = TextEditingController();
    final height = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('박스 추가 (행 추가)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                readOnly: true,
                controller: TextEditingController(text: nextBox),
                decoration: const InputDecoration(labelText: '박스번호'),
              ),
              TextField(controller: invoice, decoration: const InputDecoration(labelText: '송장번호')),
              TextField(controller: name, decoration: const InputDecoration(labelText: '이름/라오스 수령인')),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: '연락처')),
              TextField(controller: notes, decoration: const InputDecoration(labelText: '기타 내용')),
              Row(children: [
                Expanded(child: TextField(controller: weight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '무게(kg)'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: length, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '가로(cm)'))),
              ]),
              Row(children: [
                Expanded(child: TextField(controller: width, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '세로(cm)'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: height, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '높이(cm)'))),
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('추가'),
          ),
        ],
      ),
    );

    if (saved == true) {
      setState(() => _busy = true);
      try {
        await ShipmentService.instance.adminAddShipmentRow(
          route: _route,
          year: year,
          voyage: _voyage,
          boxNumber: nextBox,
          invoiceNumber: invoice.text,
          consigneeName: name.text,
          consigneePhone: phone.text,
          notes: notes.text,
          weightKg: num.tryParse(weight.text.trim()),
          lengthCm: num.tryParse(length.text.trim()),
          widthCm: num.tryParse(width.text.trim()),
          heightCm: num.tryParse(height.text.trim()),
        );
        _message('$nextBox 박스 행을 추가했습니다.');
        await _search();
      } catch (error) {
        _message('박스 행 추가 실패: $error');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    invoice.dispose();
    name.dispose();
    phone.dispose();
    notes.dispose();
    weight.dispose();
    length.dispose();
    width.dispose();
    height.dispose();
  }

  Widget _numberField(TextEditingController controller, String label) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        decoration: _decoration(label, Icons.straighten_outlined),
      );

  String _managementGroupKey(Map<String, dynamic> r) =>
      '${r['route'] ?? ''}|${r['shipment_year'] ?? ''}|${r['voyage'] ?? ''}';

  bool get _allSearchResultsSelected {
    if (_results.isEmpty) return false;
    return _selectedIds.containsAll(_results.map((r) => '${r['id']}'));
  }

  void _toggleAllSearchResults() {
    final ids = _results.map((r) => '${r['id']}').toSet();
    setState(() {
      if (ids.isNotEmpty && _selectedIds.containsAll(ids)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  Future<void> _showAllSearchResultStatements() async {
    if (_results.isEmpty || _isPartner) return;
    final groups = _managementGroups();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('검색 결과 명세서 (${_results.length}건)'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: groups.map((entry) {
              final rows = entry.value;
              final first = rows.first;
              final receiptCount = rows
                  .map((r) => '${r['receipt_number'] ?? ''}'.trim())
                  .where((v) => v.isNotEmpty)
                  .toSet()
                  .length;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await _showGroupStatement(rows);
                  },
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text(
                    '${first['route']} · ${first['shipment_year']}년도 · '
                    '${_voyageLabel(first['voyage'])} ($receiptCount건)',
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }
  List<MapEntry<String, List<Map<String, dynamic>>>> _managementGroups() {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final row in _results) {
      map.putIfAbsent(_managementGroupKey(row), () => <Map<String, dynamic>>[]).add(row);
    }
    return map.entries.toList();
  }

  void _toggleManagementGroup(List<Map<String, dynamic>> rows) {
    final ids = rows.map((r) => '${r['id']}').toSet();
    setState(() {
      if (ids.isNotEmpty && _selectedIds.containsAll(ids)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  List<Map<String, dynamic>> _checkedRowsInGroup(List<Map<String, dynamic>> rows) =>
      rows.where((r) => _selectedIds.contains('${r['id']}')).toList();

  Future<void> _editCheckedGroup(List<Map<String, dynamic>> rows) async {
    final selected = _checkedRowsInGroup(rows);
    if (selected.isEmpty) {
      _message('편집할 화물을 먼저 체크해 주세요.');
      return;
    }
    final one = selected.length == 1 ? selected.first : null;
    final name = TextEditingController(text: one == null ? '' : '${one['consignee_name'] ?? ''}');
    final phone = TextEditingController(text: one == null ? '' : '${one['consignee_phone'] ?? ''}');
    final notes = TextEditingController(text: one == null ? '' : '${one['notes'] ?? ''}');
    final weight = TextEditingController(text: one == null ? '' : '${one['weight_kg'] ?? ''}');
    final length = TextEditingController(text: one == null ? '' : '${one['length_cm'] ?? ''}');
    final width = TextEditingController(text: one == null ? '' : '${one['width_cm'] ?? ''}');
    final height = TextEditingController(text: one == null ? '' : '${one['height_cm'] ?? ''}');

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('화물 편집 (${selected.length}건)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected.length > 1)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    '여러 화물 편집 시 입력한 항목만 선택 화물 전체에 적용됩니다.',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
              TextField(controller: name, decoration: const InputDecoration(labelText: '이름/수령인')),
              TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: '연락처')),
              TextField(controller: notes, decoration: const InputDecoration(labelText: '기타 내용')),
              if (_isManager) ...[
                TextField(controller: weight, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '무게(kg)')),
                TextField(controller: length, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '가로(cm)')),
                TextField(controller: width, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '세로(cm)')),
                TextField(controller: height, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '높이(cm)')),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('화물 정보 저장')),
        ],
      ),
    );

    if (save == true) {
      final changes = <String, dynamic>{};
      if (name.text.trim().isNotEmpty) changes['consignee_name'] = name.text.trim();
      if (phone.text.trim().isNotEmpty) changes['consignee_phone'] = phone.text.trim();
      if (notes.text.trim().isNotEmpty) changes['notes'] = notes.text.trim();
      num? n(String v) => num.tryParse(v.trim());
      if (_isManager && n(weight.text) != null) changes['weight_kg'] = n(weight.text);
      if (_isManager && n(length.text) != null) changes['length_cm'] = n(length.text);
      if (_isManager && n(width.text) != null) changes['width_cm'] = n(width.text);
      if (_isManager && n(height.text) != null) changes['height_cm'] = n(height.text);

      if (changes.isEmpty) {
        _message('수정할 내용을 입력해 주세요.');
      } else {
        setState(() => _busy = true);
        try {
          for (final row in selected) {
            await ShipmentService.instance.updateRow('${row['id']}', changes);
          }
          _message('선택한 화물 정보를 저장했습니다.');
          await _search();
        } catch (error) {
          _message('화물 편집 실패: $error');
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      }
    }

    // Dialog reverse transition이 끝나기 전에 controller를 dispose하면
    // Flutter framework의 _dependents.isEmpty assertion이 발생할 수 있습니다.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    name.dispose(); phone.dispose(); notes.dispose();
    weight.dispose(); length.dispose(); width.dispose(); height.dispose();
  }

  Future<void> _deleteCheckedGroup(List<Map<String, dynamic>> rows) async {
    final selected = _checkedRowsInGroup(rows);
    if (selected.isEmpty) {
      _message('삭제할 화물을 먼저 체크해 주세요.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('선택 화물 삭제 대기'),
        content: Text('${selected.length}건을 삭제 대기로 이동하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('삭제 대기')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      for (final row in selected) {
        await ShipmentService.instance.requestShipmentDeletion('${row['id']}');
        _selectedIds.remove('${row['id']}');
      }
      await _loadPendingDeletions();
      await _search();
      _message('${selected.length}건을 삭제 대기로 이동했습니다.');
    } catch (error) {
      _message('그룹 삭제 처리 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleManualUncertain(Map<String, dynamic> item) async {
    if (!_isAdmin || _busy) return;
    final id='${item['id']}';
    final current=item['manual_uncertain']==true;
    setState(()=>_busy=true);
    try {
      await ShipmentService.instance.setManualUncertain(id,!current);
      if(!mounted)return;
      setState(()=>item['manual_uncertain']=!current);
      _message(!current
          ? '불확실 화물로 표시했습니다. 변경 승인 관리에서 확인할 수 있습니다.'
          : '불확실 표시를 해제했습니다.');
    } catch(error) {
      _message('불확실 표시 처리 실패: $error');
    } finally {
      if(mounted)setState(()=>_busy=false);
    }
  }

  Future<void> _toggleShipmentLock(Map<String, dynamic> item) async {
    if (!_isAdmin || _busy) return;
    final id = '${item['id']}';
    final current = item['data_locked'] == true;
    setState(() => _busy = true);
    try {
      await ShipmentService.instance.updateRow(
        id,
        {'data_locked': !current},
      );
      if (!mounted) return;
      setState(() => item['data_locked'] = !current);
      _message(!current ? '화물 데이터를 잠금했습니다.' : '화물 데이터 잠금을 해제했습니다.');
    } catch (error) {
      _message('화물 잠금 처리 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editReceiptGroupCustomer(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty || !(_isAdmin || _isStaff)) return;

    final first = rows.first;
    final name = TextEditingController(
      text: '${first['consignee_name'] ?? ''}',
    );
    final phone = TextEditingController(
      text: '${first['consignee_phone'] ?? ''}',
    );
    final notes = TextEditingController(
      text: '${first['notes'] ?? ''}',
    );

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '${first['receipt_number'] ?? ''} 고객 정보 편집',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: '이름 / 회사명',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: '연락처',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '기타 내용',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '이 영수번호에 묶인 ${rows.length}개 화물에 동일하게 적용됩니다.',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('일괄 저장'),
          ),
        ],
      ),
    );

    if (save == true) {
      final changes = <String, dynamic>{
        'consignee_name': name.text.trim(),
        'consignee_phone': phone.text.trim(),
        'notes': notes.text.trim(),
      };

      setState(() => _busy = true);
      try {
        for (final row in rows) {
          await ShipmentService.instance.updateRow(
            '${row['id']}',
            changes,
          );
        }
        if (mounted) {
          _message('${rows.length}개 화물의 고객 정보를 수정했습니다.');
          await _search();
        }
      } catch (error) {
        _message('고객 단위 편집 실패: $error');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));
    name.dispose();
    phone.dispose();
    notes.dispose();
  }

  Future<void> _editCargoMeasurements(
    Map<String, dynamic> item,
  ) async {
    final weight = TextEditingController(
      text: '${item['weight_kg'] ?? ''}',
    );
    final length = TextEditingController(
      text: '${item['length_cm'] ?? ''}',
    );
    final width = TextEditingController(
      text: '${item['width_cm'] ?? ''}',
    );
    final height = TextEditingController(
      text: '${item['height_cm'] ?? ''}',
    );

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${item['box_number'] ?? ''} 중량 / 크기 편집'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: weight,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '중량 (kg)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: length,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '가로 (cm)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: width,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '세로 (cm)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: height,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '높이 (cm)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (save == true) {
      num? n(String value) =>
          value.trim().isEmpty ? null : num.tryParse(value.trim());

      final changes = <String, dynamic>{
        'weight_kg': n(weight.text),
        'length_cm': n(length.text),
        'width_cm': n(width.text),
        'height_cm': n(height.text),
      };

      setState(() => _busy = true);
      try {
        await ShipmentService.instance.updateRow(
          '${item['id']}',
          changes,
        );
        if (mounted) {
          _message('중량 / 크기 정보를 저장했습니다.');
          await _search();
        }
      } catch (error) {
        _message('중량 / 크기 편집 실패: $error');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));
    weight.dispose();
    length.dispose();
    width.dispose();
    height.dispose();
  }

  Future<void> _showGroupStatement(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty || _isPartner) return;
    try {
      final freight = await FreightService.instance.calculate(rows);
      if (!mounted) return;
      final receipts = rows
          .map((r) => '${r['receipt_number'] ?? ''}'.trim())
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList();

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            '${rows.first['route']} · ${rows.first['shipment_year']}년 · ${_voyageLabel(rows.first['voyage'])}',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('그룹 전체 운임', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('박스 ${rows.length}건'),
                Text('USD  \$${freight.totalUsd.toStringAsFixed(2)}'),
                Text('KIP  ${freight.totalKip.toStringAsFixed(0)}'),
                Text('THB  ${freight.totalThb.toStringAsFixed(1)}'),
                Text('KRW  ${freight.totalKrw.toStringAsFixed(0)}'),
                const Divider(),
                if (receipts.isEmpty)
                  const Text('명세서를 열 수 있는 영수번호가 없습니다.')
                else ...[
                  const Text('영수번호별 명세서', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  ...receipts.map((receipt) => OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(dialogContext);
                      await showDialog<void>(
                        context: context,
                        builder: (_) => StatementPreviewDialog(
                          routeLabel: '${rows.first['route']}',
                          year: (rows.first['shipment_year'] as num).toInt(),
                          voyage: '${rows.first['voyage']}',
                          receiptNumber: receipt,
                        ),
                      );
                    },
                    child: Text('$receipt 명세서 보기'),
                  )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('닫기')),
          ],
        ),
      );
    } catch (error) {
      _message('그룹 명세서/운임 로딩 실패: $error');
    }
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _receiptGroups(
    List<Map<String, dynamic>> rows,
  ) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final receipt = '${row['receipt_number'] ?? ''}'.trim();
      map.putIfAbsent(receipt, () => <Map<String, dynamic>>[]).add(row);
    }
    final entries = map.entries.toList();
    int tailNumber(String value) {
      final m = RegExp(r'(\d+)\s*$').firstMatch(value);
      return m == null ? 999999 : int.tryParse(m.group(1)!) ?? 999999;
    }
    entries.sort((a, b) {
      final an = tailNumber(a.key);
      final bn = tailNumber(b.key);
      if (an != bn) return an.compareTo(bn);
      return a.key.compareTo(b.key);
    });
    return entries;
  }

  void _toggleReceiptGroup(List<Map<String, dynamic>> rows) {
    final ids = rows.map((r) => '${r['id']}').toSet();
    setState(() {
      if (ids.isNotEmpty && _selectedIds.containsAll(ids)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  Future<void> _showReceiptDiscountDialog(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty || !(_isAdmin || _isStaff)) return;
    final first = rows.first;
    final routeKey =
        RouteCatalog.formRouteKeyFor('${first['route'] ?? ''}'.trim());
    final year = (first['shipment_year'] as num?)?.toInt();
    final voyage = '${first['voyage'] ?? ''}'.trim();
    final receipt = '${first['receipt_number'] ?? ''}'.trim();
    if (routeKey.isEmpty || year == null || voyage.isEmpty || receipt.isEmpty) {
      _message('할인을 연결할 영수번호 정보를 확인할 수 없습니다.');
      return;
    }

    var current = await ReceiptDiscountService.instance.get(
      routeKey: routeKey,
      year: year,
      voyage: voyage,
      receiptNumber: receipt,
    );
    if (!mounted) return;

    final discountName =
        TextEditingController(text: current?.discountName ?? '특별할인');
    final percent = TextEditingController(
      text: current == null
          ? ''
          : (current.discountPercent * 100)
              .toStringAsFixed(2)
              .replaceFirst(RegExp(r'\.00$'), ''),
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('$receipt · 할인 적용'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (current != null)
                  Text(
                    '현재: ${current!.discountName} '
                    '${(current!.discountPercent * 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '')}%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: discountName,
                  decoration: const InputDecoration(
                    labelText: '할인명 / 단체명',
                    hintText: '예: 라선협, 기업 할인, 특별할인',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: percent,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '할인율',
                    suffixText: '%',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (current != null)
              TextButton.icon(
                onPressed: () async {
                  await ReceiptDiscountService.instance.delete(
                    routeKey: routeKey,
                    year: year,
                    voyage: voyage,
                    receiptNumber: receipt,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  _message('$receipt 할인 적용을 삭제했습니다.');
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('삭제'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('닫기'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final value = double.tryParse(percent.text.trim());
                if (value == null || value < 0 || value > 100) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('할인율은 0~100 사이로 입력해 주세요.')),
                  );
                  return;
                }
                await ReceiptDiscountService.instance.save(
                  routeKey: routeKey,
                  year: year,
                  voyage: voyage,
                  receiptNumber: receipt,
                  discountName: discountName.text.trim().isEmpty
                      ? '특별할인'
                      : discountName.text.trim(),
                  discountPercent: value / 100,
                );
                current = await ReceiptDiscountService.instance.get(
                  routeKey: routeKey,
                  year: year,
                  voyage: voyage,
                  receiptNumber: receipt,
                );
                if (dialogContext.mounted) setDialogState(() {});
                _message('$receipt 할인 적용 완료');
              },
              icon: const Icon(Icons.percent),
              label: Text(current == null ? '적용' : '수정 저장'),
            ),
          ],
        ),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 350));
    discountName.dispose();
    percent.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _showReceiptExtraCostDialog(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty || !(_isAdmin || _isStaff)) return;
    final first = rows.first;
    final route = '${first['route'] ?? ''}'.trim();
    final year = (first['shipment_year'] as num?)?.toInt();
    final voyage = '${first['voyage'] ?? ''}'.trim();
    final receipt = '${first['receipt_number'] ?? ''}'.trim();
    if (route.isEmpty || year == null || voyage.isEmpty || receipt.isEmpty) {
      _message('기타 비용을 연결할 영수번호 정보를 확인할 수 없습니다.');
      return;
    }

    final name = TextEditingController();
    final amount = TextEditingController();
    int? editingId;
    var discountApplies = false;
    var items = await ReceiptExtraCostService.instance.list(
      route: route,
      year: year,
      voyage: voyage,
      receiptNumber: receipt,
    );
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> reload() async {
            final next = await ReceiptExtraCostService.instance.list(
              route: route,
              year: year,
              voyage: voyage,
              receiptNumber: receipt,
            );
            if (dialogContext.mounted) setDialogState(() => items = next);
          }

          return AlertDialog(
            title: Text('$receipt · 기타 비용 (+\$)'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (items.isNotEmpty) ...[
                      ...items.map(
                        (e) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(e.name),
                          subtitle: Text(
                            '\$${e.amountUsd.toStringAsFixed(2)}'
                            '${e.discountApplies ? ' · 할인 적용' : ''}',
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: '수정',
                                onPressed: () {
                                  setDialogState(() => editingId = e.id);
                                  name.text = e.name;
                                  amount.text = e.amountUsd.toStringAsFixed(2);
                                  setDialogState(
                                    () => discountApplies = e.discountApplies,
                                  );
                                },
                                icon: const Icon(Icons.edit_outlined, size: 19),
                              ),
                              IconButton(
                                tooltip: '삭제',
                                onPressed: e.id == null
                                    ? null
                                    : () async {
                                        await ReceiptExtraCostService.instance
                                            .delete(e.id!);
                                        await reload();
                                      },
                                icon: const Icon(Icons.delete_outline, size: 19),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(),
                    ],
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: '비용 이름',
                        hintText: '예: 통관비용, 보관료',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: amount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '금액 (USD)',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: discountApplies,
                      title: const Text('할인 적용'),
                      subtitle: const Text(
                        '체크 시 해당 고객의 할인율을 이 기타 비용에도 적용합니다. '
                        '기본은 미체크입니다.',
                      ),
                      onChanged: (v) => setDialogState(
                        () => discountApplies = v == true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('닫기'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final value = double.tryParse(amount.text.trim());
                  if (name.text.trim().isEmpty || value == null || value < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('비용 이름과 금액을 확인해 주세요.')),
                    );
                    return;
                  }
                  await ReceiptExtraCostService.instance.save(
                    id: editingId,
                    route: route,
                    year: year,
                    voyage: voyage,
                    receiptNumber: receipt,
                    name: name.text,
                    amountUsd: value,
                    discountApplies: discountApplies,
                  );
                  name.clear();
                  amount.clear();
                  setDialogState(() {
                    editingId = null;
                    discountApplies = false;
                  });
                  await reload();
                },
                icon: const Icon(Icons.add_card_outlined, size: 18),
                label: Text(editingId == null ? '추가' : '수정 저장'),
              ),
            ],
          );
        },
      ),
    );
    // showDialog의 reverse transition이 완전히 끝난 뒤 controller를 정리합니다.
    // 즉시 dispose하면 Flutter InheritedElement의 _dependents assertion이 발생할 수 있습니다.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    name.dispose();
    amount.dispose();
  }

  List<Widget> _managementGroupWidgets() {
    return _managementGroups().map((entry) {
      final rows = entry.value;
      final first = rows.first;
      final ids = rows.map((r) => '${r['id']}').toSet();
      final all = ids.isNotEmpty && _selectedIds.containsAll(ids);
      return Card(
        margin: const EdgeInsets.only(bottom: 14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              color: AppColors.inputFill,
              child: Row(
                children: [
                  Checkbox(
                    value: all,
                    onChanged: (_) => _toggleManagementGroup(rows),
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      '${first['route']} · ${first['shipment_year']}년도 · ${_voyageLabel(first['voyage'])}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.navyPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (_isManager)
                    IconButton(
                      tooltip: '선택 화물 편집',
                      onPressed: _busy ? null : () => _editCheckedGroup(rows),
                      icon: const Icon(Icons.edit_outlined, size: 19),
                    ),
                  if (_isManager)
                    IconButton(
                      tooltip: '선택 화물 삭제',
                      onPressed: _busy ? null : () => _deleteCheckedGroup(rows),
                      icon: const Icon(Icons.delete_outline, size: 19),
                    ),
                ],
              ),
            ),
            ..._receiptGroups(rows).map((e) => _receiptGroupCard(e.value)),
          ],
        ),
      );
    }).toList();
  }

  Widget _receiptGroupCard(List<Map<String, dynamic>> rows) {
    final first = rows.first;
    final ids = rows.map((r) => '${r['id']}').toSet();
    final all = ids.isNotEmpty && _selectedIds.containsAll(ids);
    final receipt = '${first['receipt_number'] ?? ''}'.trim();
    final zone = '${first['unloading_zone'] ?? ''}'.trim();
    final specialNote = '${first['special_note_auto'] ?? ''}'.trim();
    final deliveryLabel = const <String>[
      '지방배송(선결제)',
      '지방배송',
      '시내배송(선결제)',
      '시내배송',
    ].firstWhere(
      (label) => specialNote.contains(label),
      orElse: () => '',
    );
    final deliveryColor = switch (deliveryLabel) {
      '지방배송(선결제)' => const Color(0xFF5B9BD5),
      '지방배송' => const Color(0xFFFFC000),
      '시내배송(선결제)' => const Color(0xFFFFFF00),
      '시내배송' => const Color(0xFF92D050),
      _ => Colors.transparent,
    };
    final name = '${first['consignee_name'] ?? ''}'.trim();
    final company = _companyOf(first);
    final phone = '${first['consignee_phone'] ?? ''}'.trim();
    final totalQty = rows.fold<int>(
      0,
      (sum, r) => sum + (int.tryParse('${r['quantity'] ?? ''}') ?? 1),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD7DEE7)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: all,
                  onChanged: (_) => _toggleReceiptGroup(rows),
                  visualDensity: VisualDensity.compact,
                ),
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '$name / ${company.isEmpty ? '-' : company}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.navyPrimary,
                        ),
                      ),
                      Text(
                        phone.isEmpty ? '-' : phone,
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: '영수번호/구획: ',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            TextSpan(
                              text: receipt.isEmpty ? '-' : receipt,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.navyPrimary,
                              ),
                            ),
                            const TextSpan(
                              text: ' / ',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            TextSpan(
                              text: zone.isEmpty ? '-' : zone,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.navyPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (deliveryLabel.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: deliveryColor,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: .12),
                            ),
                          ),
                          child: Text(
                            deliveryLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: '총 개수: ',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            TextSpan(
                              text: '$totalQty개',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppColors.navyPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if ((_isAdmin || _isStaff) && receipt.isNotEmpty)
                  IconButton(
                    tooltip: '고객 단위 편집',
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy
                        ? null
                        : () => _editReceiptGroupCustomer(rows),
                    icon: const Icon(Icons.edit_note_outlined, size: 20),
                  ),
                if ((_isAdmin || _isStaff) && receipt.isNotEmpty)
                  FutureBuilder<ReceiptDiscountOverride?>(
                    future: ReceiptDiscountService.instance.get(
                      routeKey: RouteCatalog.formRouteKeyFor(
                        '${first['route'] ?? ''}',
                      ),
                      year: (first['shipment_year'] as num?)?.toInt() ?? 0,
                      voyage: '${first['voyage'] ?? ''}'.trim(),
                      receiptNumber: receipt,
                    ),
                    builder: (context, snapshot) {
                      final rule = snapshot.data;
                      final pct = rule == null
                          ? ''
                          : '${(rule.discountPercent * 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '')}%';
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (pct.isNotEmpty)
                            Text(
                              pct,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppColors.navyPrimary,
                              ),
                            ),
                          IconButton(
                            tooltip: rule == null ? '할인 적용' : '할인 편집 / 삭제',
                            visualDensity: VisualDensity.compact,
                            onPressed: _busy
                                ? null
                                : () => _showReceiptDiscountDialog(rows),
                            icon: const Icon(Icons.percent, size: 21),
                          ),
                        ],
                      );
                    },
                  ),
                if ((_isAdmin || _isStaff) && receipt.isNotEmpty)
                  FutureBuilder<List<ExtraCostItem>>(
                    future: ReceiptExtraCostService.instance.list(
                      route: '${first['route'] ?? ''}'.trim(),
                      year: (first['shipment_year'] as num?)?.toInt() ?? 0,
                      voyage: '${first['voyage'] ?? ''}'.trim(),
                      receiptNumber: receipt,
                    ),
                    builder: (context, snapshot) {
                      final count = snapshot.data?.length ?? 0;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (count > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 2),
                              child: Text(
                                '+$count',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.navyPrimary,
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: '기타 비용 (+\$)',
                            visualDensity: VisualDensity.compact,
                            onPressed: _busy
                                ? null
                                : () async {
                                    await _showReceiptExtraCostDialog(rows);
                                    if (mounted) setState(() {});
                                  },
                            icon: const Icon(
                              Icons.add_card_outlined,
                              size: 21,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          ...rows.map(_receiptShipmentCard),
        ],
      ),
    );
  }

  Widget _receiptShipmentCard(Map<String, dynamic> item) {
    final id = '${item['id']}';
    final quantity = int.tryParse('${item['quantity'] ?? ''}') ?? 1;
    final receivedDate = _dateOnly(item['received_at']);
    final length = _naturalNumber(item['length_cm']);
    final height = _naturalNumber(item['height_cm']);
    final width = _naturalNumber(item['width_cm']);
    final size = '$length × $height × $width cm';

    return InkWell(
      onTap: () => _toggle(id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _selectedIds.contains(id),
              onChanged: (_) => _toggle(id),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('화물번호', '${item['box_number'] ?? ''}'),
                  _infoRow('송장번호', '${item['invoice_number'] ?? ''}'),
                  _infoRow('화물개수', '$quantity개'),
                  _infoRow(
                    '무게 / 크기',
                    '${_weightOneDecimal(item['weight_kg'])} kg / $size',
                  ),
                  _infoRow('입고날짜', receivedDate),
                ],
              ),
            ),
            if (_isManager)
              Padding(
                padding: const EdgeInsets.only(left: 2, top: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '편집',
                      visualDensity: VisualDensity.compact,
                      onPressed: _busy
                          ? null
                          : () => _editCargoMeasurements(item),
                      icon: const Icon(Icons.edit_outlined, size: 19),
                    ),
                    if (_isAdmin) const SizedBox(height: 8),
                    if (_isAdmin)
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: item['data_locked'] == true
                              ? Colors.transparent
                              : const Color(0xFF9CA3AF),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          tooltip:
                              item['data_locked'] == true ? '잠금 해제' : '잠금',
                          visualDensity: VisualDensity.compact,
                          onPressed: _busy
                              ? null
                              : () => _toggleShipmentLock(item),
                          icon: Icon(
                            item['data_locked'] == true
                                ? Icons.lock
                                : Icons.lock_open_outlined,
                            size: 19,
                            color: item['data_locked'] == true
                                ? Colors.red
                                : Colors.white,
                          ),
                        ),
                      ),
                    if (_isAdmin) const SizedBox(height: 8),
                    if (_isAdmin)
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: item['manual_uncertain'] == true
                              ? Colors.yellow
                              : Colors.white,
                          border: Border.all(color: Colors.black54),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          tooltip: item['manual_uncertain'] == true
                              ? '불확실 표시 해제'
                              : '불확실 화물 표시',
                          visualDensity: VisualDensity.compact,
                          onPressed: _busy
                              ? null
                              : () => _toggleManualUncertain(item),
                          icon: const Icon(
                            Icons.question_mark,
                            size: 20,
                            color: Colors.black,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
  Widget _shipmentCard(Map<String, dynamic> item) {
    final id = '${item['id']}';
    final quantity = int.tryParse('${item['quantity'] ?? ''}') ?? 1;
    final receivedDate = _dateOnly(item['received_at']);
    final length = _naturalNumber(item['length_cm']);
    final height = _naturalNumber(item['height_cm']);
    final width = _naturalNumber(item['width_cm']);
    final size = '$length × $height × $width cm';
    final name = '${item['consignee_name'] ?? ''}'.trim();
    final company = _companyOf(item);
    final nameCompany = '$name / ${company.isEmpty ? '-' : company}';
    final receipt = '${item['receipt_number'] ?? ''}'.trim();
    final zone = '${item['unloading_zone'] ?? ''}'.trim();

    return Card(
      child: InkWell(
        onTap: () => _toggle(id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _selectedIds.contains(id),
                onChanged: (_) => _toggle(id),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '박스번호: ${item['box_number'] ?? ''} / 박스개수: ${quantity}개 / 입고 날짜: $receivedDate',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.navyPrimary,
                            ),
                          ),
                        ),
                        if (_isManager)
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () async {
                                    setState(() {
                                      _selectedIds
                                        ..clear()
                                        ..add(id);
                                    });
                                    await _editCheckedGroup([item]);
                                  },
                            icon: const Icon(Icons.edit_outlined, size: 17),
                            label: const Text('편집'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _infoRow('운송 경로', '${item['route'] ?? ''}'),
                    _infoRow(
                      '년도 / 항차',
                      '${item['shipment_year'] ?? ''} / ${_voyageLabel(item['voyage'])}',
                    ),
                    _infoRow('송장번호', '${item['invoice_number'] ?? ''}'),
                    _infoRow('수령인 / 회사명', nameCompany),
                    _infoRow('연락처', '${item['consignee_phone'] ?? ''}'),
                    _infoRow(
                      '무게 / 크기',
                      '${_weightOneDecimal(item['weight_kg'])} kg / $size',
                    ),
                    if (_isAdmin || _isStaff)
                      _infoRow(
                        '영수번호 / 구획',
                        '$receipt / ${zone.isEmpty ? '-' : zone}',
                      )
                    else
                      _infoRow('영수번호', receipt),
                    if (_isManager) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _busy ? null : () => _requestDeletion(item),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('삭제'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _weightOneDecimal(dynamic value) {
    final text = '${value ?? ''}'.trim();
    final number = double.tryParse(text);
    return number == null ? (text.isEmpty ? '-' : text) : number.toStringAsFixed(1);
  }

  String _naturalNumber(dynamic value) {
    final text = '${value ?? ''}'.trim();
    final number = double.tryParse(text);
    return number == null ? (text.isEmpty ? '-' : text) : number.round().toString();
  }
  String _dateOnly(dynamic value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return '-';
    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return text.length >= 10 ? text.substring(0, 10) : text;
    }
    final local = parsed.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  String _companyOf(Map<String, dynamic> row) {
    for (final key in const ['consignee_company', 'company_name', 'company']) {
      final value = '${row[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }
  String _voyageLabel(dynamic value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return '';
    return text.endsWith('항차') ? text : '$text항차';
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}















