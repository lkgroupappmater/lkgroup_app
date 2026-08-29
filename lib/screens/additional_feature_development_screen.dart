import 'package:flutter/material.dart';

import '../services/route_development_service.dart';

class AdditionalFeatureDevelopmentScreen extends StatefulWidget {
  const AdditionalFeatureDevelopmentScreen({super.key});

  @override
  State<AdditionalFeatureDevelopmentScreen> createState() =>
      _AdditionalFeatureDevelopmentScreenState();
}

class _AdditionalFeatureDevelopmentScreenState
    extends State<AdditionalFeatureDevelopmentScreen> {
  List<Map<String, dynamic>> _routes = const [];
  String? _selectedRouteKey;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await RouteDevelopmentService.instance.listRoutes();
      if (!mounted) return;
      setState(() {
        _routes = rows;
        if (_selectedRouteKey != null &&
            !_activeRoutes.any(
              (row) => '${row['route_key']}' == _selectedRouteKey,
            )) {
          _selectedRouteKey = null;
        }
      });
    } catch (error) {
      if (mounted) _message('운송 경로 목록 조회 실패: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _activeRoutes => _routes
      .where((row) => '${row['status']}' == 'active')
      .toList(growable: false);

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _openEditor({required bool create}) async {
    Map<String, dynamic>? route;
    if (!create) {
      final key = _selectedRouteKey;
      if (key == null) return;
      route = _activeRoutes.firstWhere(
        (row) => '${row['route_key']}' == key,
      );
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RouteDefinitionEditorScreen(
          route: route,
          allRoutes: _routes,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('추가 기능 개발')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '운송 경로 BASE / 공통 운임 관리',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedRouteKey,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '운송 경로 선택',
                    border: OutlineInputBorder(),
                  ),
                  items: _activeRoutes
                      .map(
                        (row) => DropdownMenuItem<String>(
                          value: '${row['route_key']}',
                          child: Text('${row['display_name']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _selectedRouteKey = value);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _selectedRouteKey == null
                            ? null
                            : () => _openEditor(create: false),
                        icon: const Icon(Icons.edit),
                        label: const Text('편집'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openEditor(create: true),
                        icon: const Icon(Icons.add),
                        label: const Text('신규 운송 경로 추가'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '여기서 저장한 운임은 DB freight_rate_tiers가 원본이 되며 '
                      '가견적·명세서·화물 운임 계산이 같은 기준을 사용합니다.',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class RouteDefinitionEditorScreen extends StatefulWidget {
  const RouteDefinitionEditorScreen({
    super.key,
    this.route,
    required this.allRoutes,
  });

  final Map<String, dynamic>? route;
  final List<Map<String, dynamic>> allRoutes;

  @override
  State<RouteDefinitionEditorScreen> createState() =>
      _RouteDefinitionEditorScreenState();
}

class _RouteDefinitionEditorScreenState
    extends State<RouteDefinitionEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _companyController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _boxPrefixController;
  late final TextEditingController _receiptPrefixController;
  late final TextEditingController _factorController;
  late final TextEditingController _minimumController;

  List<Map<String, dynamic>> _tiers = [];
  String? _baseRouteKey;
  bool _savedDraft = false;
  bool _busy = false;

  bool get _isCreate => widget.route == null;

  List<Map<String, dynamic>> get _activeRoutes => widget.allRoutes
      .where((row) => '${row['status']}' == 'active')
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    final route = widget.route ?? const <String, dynamic>{};

    _titleController =
        TextEditingController(text: '${route['display_name'] ?? ''}');
    _companyController =
        TextEditingController(text: '${route['company_name'] ?? ''}');
    _phoneController =
        TextEditingController(text: '${route['phone'] ?? ''}');
    _addressController =
        TextEditingController(text: '${route['address'] ?? ''}');
    _boxPrefixController =
        TextEditingController(text: '${route['box_prefix'] ?? ''}');
    _receiptPrefixController =
        TextEditingController(text: '${route['receipt_prefix'] ?? ''}');
    _factorController = TextEditingController(
      text: '${route['volumetric_factor'] ?? 0.00022}',
    );
    _minimumController = TextEditingController(
      text: '${route['minimum_charge'] ?? 0}',
    );

    if (!_isCreate) {
      _baseRouteKey = '${route['route_key']}';
      _loadRates();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _companyController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _boxPrefixController.dispose();
    _receiptPrefixController.dispose();
    _factorController.dispose();
    _minimumController.dispose();
    super.dispose();
  }

  Future<void> _loadRates() async {
    final key = _baseRouteKey;
    if (key == null || key.isEmpty) return;
    try {
      final rows = await RouteDevelopmentService.instance.rates(key);
      if (!mounted) return;
      setState(() {
        _tiers = rows.map(Map<String, dynamic>.from).toList();
      });
    } catch (error) {
      if (mounted) _message('단가 조회 실패: $error');
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  List<Map<String, double>> _tierData() {
    return _tiers
        .map(
          (row) => <String, double>{
            'min_weight_kg':
                double.tryParse('${row['min_weight_kg'] ?? ''}') ?? 0,
            'rate_per_kg':
                double.tryParse('${row['rate_per_kg'] ?? ''}') ?? 0,
          },
        )
        .toList(growable: false);
  }

  void _addTier() {
    setState(() {
      _tiers.add({
        'min_weight_kg': 0.0,
        'rate_per_kg': 0.0,
      });
    });
  }

  Future<void> _selectBaseRoute(String? value) async {
    if (value == null) return;

    final route = _activeRoutes.firstWhere(
      (row) => '${row['route_key']}' == value,
    );

    setState(() {
      _baseRouteKey = value;
      _companyController.text = '${route['company_name'] ?? ''}';
      _phoneController.text = '${route['phone'] ?? ''}';
      _addressController.text = '${route['address'] ?? ''}';
      _boxPrefixController.text = '${route['box_prefix'] ?? ''}';
      _receiptPrefixController.text = '${route['receipt_prefix'] ?? ''}';
      _factorController.text = '${route['volumetric_factor'] ?? 0.00022}';
      _minimumController.text = '${route['minimum_charge'] ?? 0}';
    });

    await _loadRates();
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isCreate ? '신규 운송 경로' : '운송 경로 편집'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (_isCreate) ...[
            DropdownButtonFormField<String>(
              initialValue: _baseRouteKey,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '기반 BASE 운송 경로',
                border: OutlineInputBorder(),
              ),
              items: _activeRoutes
                  .map(
                    (row) => DropdownMenuItem<String>(
                      value: '${row['route_key']}',
                      child: Text('${row['display_name']}'),
                    ),
                  )
                  .toList(),
              onChanged: _busy ? null : _selectBaseRoute,
            ),
            const SizedBox(height: 10),
          ],
          _field(_titleController, '운송 경로 타이틀'),
          const SizedBox(height: 8),
          _field(_companyController, '회사명'),
          const SizedBox(height: 8),
          _field(_phoneController, '전화번호'),
          const SizedBox(height: 8),
          _field(_addressController, '주소'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _field(_boxPrefixController, '박스 Prefix'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _field(_receiptPrefixController, '영수번호 Prefix'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _field(
                  _factorController,
                  '부피중량 계수',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _field(
                  _minimumController,
                  '최소 운임 USD',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '단가 구조',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _addTier,
                icon: const Icon(Icons.add),
                label: const Text('구간 추가'),
              ),
            ],
          ),
          ...List.generate(_tiers.length, (index) {
            final row = _tiers[index];
            return Card(
              key: ValueKey(
                'tier-$index-${row['min_weight_kg']}-${row['rate_per_kg']}',
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: '${row['min_weight_kg'] ?? 0}',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: '이상 kg',
                        ),
                        onChanged: (value) {
                          row['min_weight_kg'] =
                              double.tryParse(value) ?? 0;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: '${row['rate_per_kg'] ?? 0}',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'USD/kg',
                        ),
                        onChanged: (value) {
                          row['rate_per_kg'] =
                              double.tryParse(value) ?? 0;
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: '구간 삭제',
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() => _tiers.removeAt(index));
                            },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _busy ? null : () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: _savedDraft
                      ? FilledButton.styleFrom(
                          backgroundColor: Colors.green,
                        )
                      : null,
                  onPressed: _busy ? null : _save,
                  child: Text(
                    _savedDraft
                        ? '신규 경로 적용'
                        : _isCreate
                            ? '내용 저장 (아직 적용 안됨)'
                            : '내용 저장',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty ||
        _tiers.isEmpty ||
        (_isCreate && _baseRouteKey == null)) {
      _message('운송 경로, 기반 BASE, 단가를 확인해 주세요.');
      return;
    }

    if (_savedDraft) {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('신규 운송 경로 적용'),
              content: const Text(
                '작성하신 데이터를 기반으로 신규 운송 경로가 추가 됩니다.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('확인'),
                ),
              ],
            ),
          ) ??
          false;

      if (!confirmed) return;

      setState(() => _busy = true);
      try {
        await RouteDevelopmentService.instance.applyDraft(_baseRouteKey!);
        if (mounted) Navigator.pop(context);
      } catch (error) {
        if (mounted) _message('신규 운송 경로 적용 실패: $error');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    setState(() => _busy = true);
    try {
      final volumetricFactor =
          double.tryParse(_factorController.text.trim()) ?? 0.00022;
      final minimumCharge =
          double.tryParse(_minimumController.text.trim()) ?? 0;

      if (_isCreate) {
        final draftKey =
            await RouteDevelopmentService.instance.createDraft(
          label: _titleController.text.trim(),
          baseRouteKey: _baseRouteKey!,
          company: _companyController.text.trim(),
          phone: _phoneController.text.trim(),
          address: _addressController.text.trim(),
          boxPrefix: _boxPrefixController.text.trim(),
          receiptPrefix: _receiptPrefixController.text.trim(),
          volumetricFactor: volumetricFactor,
          minimumCharge: minimumCharge,
          tiers: _tierData(),
        );
        if (!mounted) return;
        setState(() {
          _baseRouteKey = draftKey;
          _savedDraft = true;
        });
        _message('내용을 저장했습니다. 아직 실제 신규 경로에는 적용되지 않았습니다.');
      } else {
        await RouteDevelopmentService.instance.saveExisting(
          key: '${widget.route!['route_key']}',
          label: _titleController.text.trim(),
          company: _companyController.text.trim(),
          phone: _phoneController.text.trim(),
          address: _addressController.text.trim(),
          boxPrefix: _boxPrefixController.text.trim(),
          receiptPrefix: _receiptPrefixController.text.trim(),
          volumetricFactor: volumetricFactor,
          minimumCharge: minimumCharge,
          tiers: _tierData(),
        );
        if (mounted) Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) _message('내용 저장 실패: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
