import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../core/app_colors.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../utils/form_validators.dart';

class MemberManagementScreen extends StatefulWidget {
  const MemberManagementScreen({super.key});

  @override
  State<MemberManagementScreen> createState() =>
      _MemberManagementScreenState();
}

class _MemberManagementScreenState extends State<MemberManagementScreen> {
  final _search = TextEditingController();
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
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      if (!SupabaseConfig.isConfigured) {
        _members = [];
      } else {
        final rows = await Supabase.instance.client
            .from('profiles')
            .select('id,email,name,phone,company,role,requested_role,approval_status,avatar_url,created_at,deletion_status,deletion_type,deleted_at,purge_after')
            .order('created_at', ascending: false);
        _members = List<Map<String, dynamic>>.from(rows);
      }
    } catch (e) {
      _message('회원 목록 조회 실패: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _pendingRequests => _members.where((m) {
        final myId = Supabase.instance.client.auth.currentUser?.id;
        if ('${m['id']}' == myId) return false;
        if ('${m['deletion_status'] ?? 'active'}' != 'active') return false;
        final status = '${m['approval_status'] ?? ''}';
        final requested = '${m['requested_role'] ?? 'member'}';
        final currentRole = '${m['role'] ?? 'member'}';
        return status != 'rejected' &&
            requested != currentRole &&
            (requested == 'admin' || requested == 'partner');
      }).toList();

  List<Map<String, dynamic>> get _fixedManagementMembers {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    final rows = _members.where((m) {
      if ('${m['id']}' == myId) return false;
      if ('${m['deletion_status'] ?? 'active'}' != 'active') return false;
      // 관리자(총괄/직원)와 협력·파트너사는 승인 상태와 관계없이
      // 활성 계정이면 항상 고정 영역에 표시합니다.
      return ['admin', 'staff', 'partner'].contains('${m['role']}');
    }).toList();
    rows.sort((a, b) {
      const order = {'admin': 0, 'staff': 1, 'partner': 2};
      return (order['${a['role']}'] ?? 9)
          .compareTo(order['${b['role']}'] ?? 9);
    });
    return rows;
  }

  List<Map<String, dynamic>> get _filteredMembers {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    final myId = Supabase.instance.client.auth.currentUser?.id;
    return _members.where((m) {
      if ('${m['id']}' == myId) return false;
      if ('${m['deletion_status'] ?? 'active'}' != 'active') return false;
      if ('${m['approval_status'] ?? 'approved'}' == 'rejected') return false;
      // 관리자/파트너는 위 고정 목록에 항상 표시하므로 검색 영역에서는 일반회원만 표시합니다.
      if ('${m['role'] ?? 'member'}' != 'member') return false;
      return '${m['name']} ${m['email']} ${m['phone']} ${m['company']} ${m['role']}'
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  List<Map<String, dynamic>> get _deletedMembers {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    final rows = _members.where((m) {
      if ('${m['id']}' == myId) return false;
      return '${m['deletion_status'] ?? 'active'}' == 'pending';
    }).toList();
    rows.sort((a, b) {
      final ad = DateTime.tryParse('${a['deleted_at'] ?? ''}');
      final bd = DateTime.tryParse('${b['deleted_at'] ?? ''}');
      return (bd ?? DateTime(1970)).compareTo(ad ?? DateTime(1970));
    });
    return rows;
  }

  Future<void> _approve(Map<String, dynamic> member) async {
    final requested = '${member['requested_role'] ?? 'member'}';
    if (requested != 'admin' && requested != 'partner') {
      _message('승인 가능한 요청 권한이 아닙니다.', error: true);
      return;
    }

    var approvedRole = requested;
    if (requested == 'admin') {
      final selected = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('관리자 종류 선택'),
          content: Text(
            '${member['name'] ?? member['email']}님의 관리자 권한을 선택해 주세요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'staff'),
              child: const Text('관리자(직원)'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'admin'),
              child: const Text('관리자(총괄)'),
            ),
          ],
        ),
      );
      if (selected == null) return;
      approvedRole = selected;
    }

    try {
      await Supabase.instance.client.from('profiles').update({
        'role': approvedRole,
        'requested_role': approvedRole,
        'approval_status': 'approved',
      }).eq('id', member['id']);
      _message('${_roleLabel(approvedRole)} 권한으로 승인했습니다.');
      await _loadMembers();
    } catch (e) {
      _message('승인 실패: $e', error: true);
    }
  }

  Future<void> _reject(Map<String, dynamic> member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('가입 권한 요청 거절'),
        content: Text(
          '${member['name'] ?? member['email']}님의 '
          '${_roleLabel(member['requested_role'])} 요청을 거절할까요?\n'
          '거절해도 계정은 일반회원으로 계속 사용할 수 있습니다.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('거절')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.from('profiles').update({
        'role': 'member',
        'requested_role': 'member',
        'approval_status': 'approved',
      }).eq('id', member['id']);
      _message('권한 요청을 거절했습니다. 계정은 일반회원으로 유지됩니다.');
      await _loadMembers();
    } catch (e) {
      _message('거절 처리 실패: $e', error: true);
    }
  }

  Future<void> _registerMember() async {
    final data = await showDialog<_AdminMemberData>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AdminMemberRegistrationDialog(),
    );
    if (data == null) return;

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'admin-create-user',
        body: {
          'email': data.email,
          'password': data.password,
          'name': data.name,
          'phone': data.phone,
          'company': data.company,
          'role': data.role.name,
        },
      );
      if (response.status < 200 || response.status >= 300) {
        throw Exception(response.data);
      }
      _message('${data.name} 회원을 ${data.role.label} 권한으로 등록했습니다.');
      await _loadMembers();
    } catch (e) {
      _message('회원 등록 실패: $e', error: true);
    }
  }

  Future<void> _saveMember(Map<String, dynamic> data, {required String id}) async {
    try {
      await Supabase.instance.client.from('profiles').update(data).eq('id', id);
      await _loadMembers();
      _message('회원 정보가 저장되었습니다.');
    } catch (e) {
      _message('저장 실패: $e', error: true);
    }
  }

  Future<void> _openEditor(Map<String, dynamic> member) async {
    final name = TextEditingController(text: '${member['name'] ?? ''}');
    final phone = TextEditingController(text: '${member['phone'] ?? ''}');
    final company = TextEditingController(text: '${member['company'] ?? ''}');
    UserRole role = UserRole.values.firstWhere(
      (r) => r.name == '${member['role']}',
      orElse: () => UserRole.member,
    );

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('회원 정보 편집'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: '이름')),
                TextFormField(
                  initialValue: '${member['email'] ?? ''}',
                  readOnly: true,
                  decoration: const InputDecoration(labelText: '이메일 (수정 불가)'),
                ),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(
                    labelText: '전화번호',
                    hintText: '예: 020-5889-2547',
                  ),
                ),
                TextField(
                  controller: company,
                  decoration: const InputDecoration(labelText: '회사명'),
                ),
                DropdownButtonFormField<UserRole>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: '권한'),
                  items: const [
                    DropdownMenuItem(value: UserRole.member, child: Text('일반 회원')),
                    DropdownMenuItem(value: UserRole.partner, child: Text('협력/파트너사')),
                    DropdownMenuItem(value: UserRole.staff, child: Text('관리자(직원)')),
                    DropdownMenuItem(value: UserRole.admin, child: Text('관리자(총괄)')),
                  ],
                  onChanged: (v) => setDialogState(() => role = v ?? role),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'name': name.text.trim(),
                'phone': FormValidators.normalizePhone(phone.text),
                'company': company.text.trim(),
                'role': role.name,
                'requested_role': role.name,
                'approval_status': 'approved',
              }),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 250));
    name.dispose();
    phone.dispose();
    company.dispose();

    if (result == null) return;
    await _saveMember(result, id: '${member['id']}');
  }

  Future<void> _deleteMember(Map<String, dynamic> member) async {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if ('${member['id']}' == myId) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('회원 삭제'),
        content: Text(
          '${member['name'] ?? member['email']} 회원을 삭제할까요?\n\n'
          '삭제 즉시 로그인할 수 없으며, 관련 계정 데이터는 약 30일간 보관된 후 DB에서 완전히 삭제됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제 확인'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AuthService.instance.adminDeleteMember('${member['id']}');
      _message('회원이 삭제 대기 처리되었습니다.');
      await _loadMembers();
    } catch (e) {
      _message('회원 삭제 실패: $e', error: true);
    }
  }

  Future<void> _cancelDeletion(Map<String, dynamic> member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('탈퇴 취소'),
        content: Text(
          '${member['name'] ?? member['email']} 회원의 탈퇴를 취소하고 정상 회원으로 복구할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('탈퇴 취소'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AuthService.instance.adminCancelMemberDeletion('${member['id']}');
      _message('탈퇴를 취소하고 정상 회원으로 복구했습니다.');
      await _loadMembers();
    } catch (e) {
      _message('탈퇴 취소 실패: $e', error: true);
    }
  }

  Future<void> _confirmDeletion(Map<String, dynamic> member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('탈퇴 확정'),
        content: Text(
          '${member['name'] ?? member['email']} 회원을 DB에서 완전히 삭제할까요?\n\n'
          '이 작업은 되돌릴 수 없습니다. 탈퇴 확정 후 동일 이메일은 3일 제한 없이 즉시 신규 가입할 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('탈퇴 확정'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AuthService.instance.adminConfirmMemberDeletion('${member['id']}');
      _message('탈퇴를 확정하고 회원 계정 데이터를 완전히 삭제했습니다.');
      await _loadMembers();
    } catch (e) {
      _message('탈퇴 확정 실패: $e', error: true);
    }
  }

  Widget _deletedMemberCard(Map<String, dynamic> member) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${member['name'] ?? ''} · ${_roleLabel(member['role'])}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('${member['email'] ?? ''}'),
              Text('${member['phone'] ?? ''} ${member['company'] ?? ''}'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _cancelDeletion(member),
                      child: const Text('탈퇴 취소'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _confirmDeletion(member),
                      child: const Text('탈퇴 확정'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.error : AppColors.primary,
      ),
    );
  }

  Widget _memberCard(Map<String, dynamic> member) => Card(
        child: ListTile(
          title: Text('${member['name'] ?? ''} · ${_roleLabel(member['role'])}'),
          subtitle: Text(
            '${member['email'] ?? ''}\n${member['phone'] ?? ''} ${member['company'] ?? ''}',
          ),
          isThreeLine: true,
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 36,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => _openEditor(member),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
              ),
              SizedBox(
                width: 36,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  tooltip: '회원 삭제',
                  onPressed: () => _deleteMember(member),
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pending = _pendingRequests;
    final fixed = _fixedManagementMembers;
    final list = _filteredMembers;
    final deleted = _deletedMembers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('회원 종합 관리'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _registerMember,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('회원 등록'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadMembers,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  const Text(
                    '가입 권한 승인 요청',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                  const SizedBox(height: 8),
                  if (pending.isEmpty)
                    const Card(child: ListTile(title: Text('대기 중인 요청이 없습니다.'))),
                  ...pending.map((member) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${member['name'] ?? ''} · ${_roleLabel(member['requested_role'])}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('${member['email'] ?? ''}'),
                          Text('${member['phone'] ?? ''} ${member['company'] ?? ''}'),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(child: OutlinedButton(
                              onPressed: () => _reject(member),
                              child: const Text('거절'),
                            )),
                            const SizedBox(width: 8),
                            Expanded(child: FilledButton(
                              onPressed: () => _approve(member),
                              child: const Text('승인'),
                            )),
                          ]),
                        ],
                      ),
                    ),
                  )),
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    '관리자 / 협력·파트너사',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                  const SizedBox(height: 8),
                  if (fixed.isEmpty)
                    const Card(child: ListTile(title: Text('등록된 관리자/파트너가 없습니다.'))),
                  ...fixed.map(_memberCard),
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    '일반 회원 검색',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: '이름·이메일·전화번호 검색',
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_search.text.trim().isNotEmpty && list.isEmpty)
                    const Card(child: ListTile(title: Text('검색된 회원이 없습니다.'))),
                  ...list.map(_memberCard),
                  const SizedBox(height: 18),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    '탈퇴 회원',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                  const SizedBox(height: 8),
                  if (deleted.isEmpty)
                    const Card(child: ListTile(title: Text('탈퇴 처리 중인 회원이 없습니다.'))),
                  ...deleted.map(_deletedMemberCard),
                ],
              ),
            ),
    );
  }

  String _roleLabel(dynamic value) => switch (value?.toString()) {
        'admin' => '관리자(총괄)',
        'staff' => '관리자(직원)',
        'partner' => '협력/파트너사',
        _ => '일반 회원',
      };
}

class _AdminMemberRegistrationDialog extends StatefulWidget {
  const _AdminMemberRegistrationDialog();

  @override
  State<_AdminMemberRegistrationDialog> createState() =>
      _AdminMemberRegistrationDialogState();
}

class _AdminMemberRegistrationDialogState
    extends State<_AdminMemberRegistrationDialog> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _phone = TextEditingController();
  final _company = TextEditingController();
  UserRole _role = UserRole.member;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _phone.dispose();
    _company.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('회원 등록'),
        content: Form(
          key: _key,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: '이름', hintText: '예: 홍길동'),
                  validator: (v) => FormValidators.requiredText(v, '이름'),
                ),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: '이메일', hintText: '예: member@example.com'),
                  validator: FormValidators.email,
                ),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '암호',
                    hintText: '예: Lkgroup2026',
                    helperText: '대문자·소문자·숫자 포함 8자 이상',
                  ),
                  validator: FormValidators.password,
                ),
                TextFormField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '암호 확인'),
                  validator: (v) => v == _password.text ? null : '암호가 서로 일치하지 않습니다.',
                ),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(labelText: '전화번호', hintText: '예: 020-5889-2547'),
                  validator: FormValidators.phone,
                ),
                TextFormField(
                  controller: _company,
                  decoration: const InputDecoration(labelText: '회사명(선택)', hintText: '예: LK Trading'),
                ),
                DropdownButtonFormField<UserRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: '권한'),
                  items: const [
                    DropdownMenuItem(value: UserRole.member, child: Text('일반 회원')),
                    DropdownMenuItem(value: UserRole.partner, child: Text('협력/파트너사')),
                    DropdownMenuItem(value: UserRole.staff, child: Text('관리자(직원)')),
                    DropdownMenuItem(value: UserRole.admin, child: Text('관리자(총괄)')),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? _role),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(
            onPressed: () {
              if (!_key.currentState!.validate()) return;
              Navigator.pop(
                context,
                _AdminMemberData(
                  name: _name.text.trim(),
                  email: _email.text.trim(),
                  password: _password.text,
                  phone: FormValidators.normalizePhone(_phone.text),
                  company: _company.text.trim(),
                  role: _role,
                ),
              );
            },
            child: const Text('등록'),
          ),
        ],
      );
}

class _AdminMemberData {
  const _AdminMemberData({
    required this.name,
    required this.email,
    required this.password,
    required this.phone,
    required this.company,
    required this.role,
  });
  final String name, email, password, phone, company;
  final UserRole role;
}
