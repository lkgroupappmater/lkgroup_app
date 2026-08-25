import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/route_options.dart';
import '../models/app_user.dart';
import 'admin_account_management_screen.dart';
import 'change_approval_screen.dart';
import 'notice_management_screen.dart';
import 'schedule_management_screen.dart';

class CargoManagementScreen extends StatefulWidget {
  const CargoManagementScreen({super.key, required this.user, this.onBack});
  final AppUser user;
  final VoidCallback? onBack;

  @override
  State<CargoManagementScreen> createState() => _CargoManagementScreenState();
}

class _CargoManagementScreenState extends State<CargoManagementScreen> {
  final _invoice = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  String _route = RouteOptions.defaultLabel;
  String _year = '2026년';
  String _voyage = '01항차';
  bool _searched = false;
  final Set<int> _selected = <int>{};

  final List<Map<String, String>> _results = [
    {
      'box': 'BX-001',
      'invoice': 'LK-2026-001',
      'name': '홍길동',
      'phone': '020-1111-2222',
      'received': '2026-06-24',
    },
    {
      'box': 'BX-002',
      'invoice': 'LK-2026-002',
      'name': '김민수',
      'phone': '020-3333-4444',
      'received': '2026-06-25',
    },
  ];

  bool get _isManager =>
      widget.user.role == UserRole.staff || widget.user.role == UserRole.admin;
  bool get _canSaveDirectly =>
      widget.user.role == UserRole.partner || widget.user.role == UserRole.admin;
  bool get _isGrandAdmin => widget.user.role == UserRole.admin;

  @override
  void dispose() {
    _invoice.dispose();
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      );

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _search() {
    setState(() {
      _searched = true;
      _selected.clear();
    });
    _message('일치하는 화물 정보를 조회했습니다.');
  }

  void _save() {
    if (!_searched || _selected.isEmpty) {
      _message('저장할 화물을 하나 이상 선택해 주세요.');
      return;
    }
    _message(_canSaveDirectly ? '화물 정보가 저장되었습니다.' : '화물 정보 수정 요청이 등록되었습니다.');
  }

  Future<void> _openScheduleOrNotice() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: const Text('선적 일정 관리'),
              onTap: () => Navigator.pop(c, 'schedule'),
            ),
            ListTile(
              leading: const Icon(Icons.campaign),
              title: const Text('공지사항 관리'),
              onTap: () => Navigator.pop(c, 'notice'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => choice == 'schedule'
            ? const ScheduleManagementScreen()
            : const NoticeManagementScreen(),
      ),
    );
  }

  Widget _resultCard(int index) {
    final item = _results[index];
    final checked = _selected.contains(index);
    return Card(
      child: CheckboxListTile(
        value: checked,
        onChanged: (value) => setState(() {
          if (value == true) {
            _selected.add(index);
          } else {
            _selected.remove(index);
          }
        }),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text('${item['box']} · ${item['invoice']}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '이름: ${item['name']}\n연락처: ${item['phone']}\n입고 날짜: ${item['received']}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: AppColors.primary,
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(
              widget.user.name.isEmpty ? '회원' : widget.user.name,
              style: const TextStyle(
                color: AppColors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(widget.user.roleLabel,
                style: const TextStyle(color: Colors.white70)),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _isManager ? '통합 관리' : '회원님의 화물 정보를 입력해 주세요.',
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isManager
              ? '통합 관리 권한 계정입니다. 화물 수정 및 승인 시 주의하시기 바랍니다.'
              : '본인 화물을 검색하고 필요한 정보를 수정할 수 있습니다.',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          value: _route,
          decoration: _dec('운송 경로', Icons.route),
          items: RouteOptions.labels
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (value) => setState(() => _route = value ?? _route),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _year,
                decoration: _dec('년도', Icons.calendar_today),
                items: const ['2026년', '2027년', '2028년']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (value) => setState(() => _year = value ?? _year),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _voyage,
                decoration: _dec('항차', Icons.confirmation_number_outlined),
                items: const ['01항차', '02항차', '03항차', '04항차', '05항차']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (value) =>
                    setState(() => _voyage = value ?? _voyage),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _invoice,
          decoration: _dec('송장번호/화물번호', Icons.receipt_long_outlined),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _name,
          decoration: _dec('라오스 수령인', Icons.person_outline),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: _dec('라오스 전화번호', Icons.phone_outlined),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _search,
                icon: const Icon(Icons.search),
                label: const Text('화물 검색'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _searched
                    ? () => _message('중량·크기 기준 운임 확인 결과를 표시할 예정입니다.')
                    : null,
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('운임'),
              ),
            ),
          ],
        ),
        if (_searched) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text('화물 정보',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              ),
              Text('${_selected.length}건 선택'),
            ],
          ),
          const SizedBox(height: 4),
          ...List.generate(_results.length, _resultCard),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: _dec('화물 정보 또는 수정 내용', Icons.edit_note_outlined),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _selected.isEmpty ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_canSaveDirectly ? '화물 정보 저장' : '화물 정보 수정 요청'),
            ),
          ),
        ],
        if (_isManager) ...[
          const SizedBox(height: 22),
          Card(
            child: ListTile(
              leading: const Icon(Icons.calendar_month),
              title: const Text('일정·공지 관리'),
              subtitle: const Text('선적 일정 또는 공지사항을 선택해 관리합니다.'),
              onTap: _openScheduleOrNotice,
            ),
          ),
          if (_isGrandAdmin)
            Card(
              child: ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('화물 정보 변경 승인 요청'),
                subtitle: const Text('승인 요청 건을 확인하고 처리합니다.'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ChangeApprovalScreen()),
                ),
              ),
            ),
          if (_isGrandAdmin)
            Card(
              child: ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('회원 관리'),
                subtitle: const Text('회원 검색·등록·정보 및 권한을 관리합니다.'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdminAccountManagementScreen()),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

