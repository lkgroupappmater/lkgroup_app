import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../core/app_colors.dart';
import '../models/app_user.dart';

/// 관리자용 회원 관리 화면입니다.
/// profiles 테이블: id, email, name, phone, company, role, created_at
/// 실제 Auth 사용자 생성/삭제는 service_role을 앱에 넣지 않고 Edge Function에서 처리하세요.
class MemberManagementScreen extends StatefulWidget {
  const MemberManagementScreen({super.key});

  @override
  State<MemberManagementScreen> createState() => _MemberManagementScreenState();
}

class _MemberManagementScreenState extends State<MemberManagementScreen> {
  final _search = TextEditingController();
  final List<Map<String, dynamic>> _mockMembers = [
    {'id': 'demo-1', 'name': '관리자', 'email': 'admin@cargoflow.dev', 'phone': '010-0000-0001', 'company': 'LK Group', 'role': 'admin'},
    {'id': 'demo-3', 'name': '관리자(직원)', 'email': 'staff@cargoflow.dev', 'phone': '010-0000-0003', 'company': 'LK Group', 'role': 'staff'},
    {'id': 'demo-4', 'name': '협력/파트너사', 'email': 'partner@cargoflow.dev', 'phone': '010-0000-0004', 'company': 'Partner Co.', 'role': 'partner'},
  ];
  List<Map<String, dynamic>> _members = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() => _loading = true);
    try {
      if (!SupabaseConfig.isConfigured) {
        _members = List<Map<String, dynamic>>.from(_mockMembers);
      } else {
        final rows = await Supabase.instance.client
            .from('profiles')
            .select('id,email,name,phone,company,role,created_at')
            .order('created_at', ascending: false);
        _members = List<Map<String, dynamic>>.from(rows);
      }
    } catch (e) {
      _members = List<Map<String, dynamic>>.from(_mockMembers);
      _message('회원 목록을 불러오지 못해 테스트 목록을 표시합니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredMembers {
    final query = _search.text.trim().toLowerCase();
    final managed = _members.where((m) => m['role'] == 'staff' || m['role'] == 'partner').toList();
    if (query.isEmpty) return managed;
    return managed.where((m) => '${m['name']} ${m['email']} ${m['phone']} ${m['company']}'.toLowerCase().contains(query)).toList();
  }

  Future<void> _saveMember(Map<String, dynamic> data, {String? id}) async {
    try {
      if (SupabaseConfig.isConfigured) {
        final client = Supabase.instance.client;
        if (id == null) {
          await client.from('profiles').insert(data);
        } else {
          await client.from('profiles').update(data).eq('id', id);
        }
      } else {
        final index = _members.indexWhere((m) => m['id']?.toString() == id);
        if (index >= 0) {
          _members[index] = {..._members[index], ...data};
        } else {
          _members.add({'id': 'demo-${DateTime.now().millisecondsSinceEpoch}', ...data});
        }
      }
      await _loadMembers();
      _message('회원 정보가 저장되었습니다.');
    } catch (e) {
      _message('저장 실패: $e', error: true);
    }
  }

  Future<void> _deleteMember(Map<String, dynamic> member) async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('회원 삭제'),
      content: Text('${member['name'] ?? member['email']} 회원을 삭제할까요?\nAuth 계정 삭제는 서버 함수에서 별도로 처리해야 합니다.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제'))],
    ));
    if (ok != true) return;
    try {
      if (SupabaseConfig.isConfigured) {
        await Supabase.instance.client.from('profiles').delete().eq('id', member['id']);
      } else {
        _members.removeWhere((m) => m['id'] == member['id']);
      }
      setState(() {});
      _message('회원 프로필이 삭제되었습니다.');
    } catch (e) {
      _message('삭제 실패: $e', error: true);
    }
  }

  Future<void> _openEditor([Map<String, dynamic>? member]) async {
    final name = TextEditingController(text: member?['name']?.toString());
    final email = TextEditingController(text: member?['email']?.toString());
    final phone = TextEditingController(text: member?['phone']?.toString());
    final company = TextEditingController(text: member?['company']?.toString());
    UserRole role = UserRole.values.firstWhere((r) => r.name == member?['role'], orElse: () => UserRole.member);
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: Text(member == null ? '회원 등록' : '회원 정보 편집'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _field(name, '이름'), _field(email, '이메일'), _field(phone, '전화번호'), _field(company, '회사명'),
        DropdownButtonFormField<UserRole>(value: role, decoration: const InputDecoration(labelText: '권한'), items: const [
          DropdownMenuItem(value: UserRole.member, child: Text('일반 회원')),
          DropdownMenuItem(value: UserRole.partner, child: Text('협력/파트너사')),
          DropdownMenuItem(value: UserRole.staff, child: Text('관리자(직원)')),
          DropdownMenuItem(value: UserRole.admin, child: Text('관리자(총괄)')),
        ], onChanged: (v) => setDialogState(() => role = v ?? role)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')), ElevatedButton(onPressed: () => Navigator.pop(context, {'name': name.text.trim(), 'email': email.text.trim(), 'phone': phone.text.trim(), 'company': company.text.trim(), 'role': role.name}), child: const Text('저장'))],
    )));
    name.dispose(); email.dispose(); phone.dispose(); company.dispose();
    if (result == null || result['name'] == '' || result['email'] == '') { if (result != null) _message('이름과 이메일은 필수입니다.', error: true); return; }
    await _saveMember(result, id: member?['id']?.toString());
  }

  Widget _field(TextEditingController c, String label) => Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: c, decoration: InputDecoration(labelText: label)));
  void _message(String text, {bool error = false}) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? AppColors.error : AppColors.primary)); }

  @override
  Widget build(BuildContext context) {
    final list = _filteredMembers;
    return Scaffold(
      appBar: AppBar(title: const Text('회원 관리')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '이름·이메일·전화번호 검색'))),
            const SizedBox(width: 8),

          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadMembers,
                  child: list.isEmpty
                      ? ListView(children: const [SizedBox(height: 100), Center(child: Text('회원이 없습니다.'))])
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final member = list[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                              child: ListTile(
                                title: Text('${member['name'] ?? ''}  ·  ${_roleLabel(member['role'])}'),
                                subtitle: Text('${member['email'] ?? ''}\\n${member['phone'] ?? ''} ${member['company'] ?? ''}'),
                                isThreeLine: true,
                                trailing: Wrap(children: [
                                  IconButton(onPressed: () => _openEditor(member), icon: const Icon(Icons.edit_outlined)),
                                  IconButton(onPressed: () => _deleteMember(member), icon: const Icon(Icons.delete_outline, color: AppColors.error)),
                                ]),
                              ),
                            );
                          },
                        ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => _openEditor(), icon: const Icon(Icons.person_add), label: const Text('회원 등록'))),
        ),
      ]),
    );
  }

  String _roleLabel(dynamic value) => switch (value?.toString()) { 'admin' => '관리자(총괄)', 'staff' => '관리자(직원)', 'partner' => '협력/파트너사', _ => '일반 회원' };
}



