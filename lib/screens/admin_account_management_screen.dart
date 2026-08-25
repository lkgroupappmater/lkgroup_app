import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';

class AdminAccountManagementScreen extends StatefulWidget {
  const AdminAccountManagementScreen({super.key});

  @override
  State<AdminAccountManagementScreen> createState() =>
      _AdminAccountManagementScreenState();
}

class _AdminAccountManagementScreenState
    extends State<AdminAccountManagementScreen> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _company = TextEditingController();
  final _phone = TextEditingController();
  UserRole _role = UserRole.member;
  final List<AppUser> _users = [
    const AppUser(
        id: 'member-001',
        email: 'member@example.com',
        name: '홍길동',
        phone: '020-1111-2222',
        company: 'LK 고객사',
        role: UserRole.member),
    const AppUser(
        id: 'partner-001',
        email: 'partner@example.com',
        name: 'Sokxay',
        phone: '020-3333-4444',
        company: 'Sokxay Group',
        role: UserRole.partner),
  ];
  bool _loading = false;

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    _email.dispose();
    _company.dispose();
    _phone.dispose();
    super.dispose();
  }

  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.inputFill,
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(10),
        ),
      );

  List<AppUser> get _filtered {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _users;
    return _users.where((user) {
      return user.id.toLowerCase().contains(query) ||
          user.name.toLowerCase().contains(query) ||
          user.phone.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query);
    }).toList();
  }

  void _resetForm() {
    _name.clear();
    _email.clear();
    _company.clear();
    _phone.clear();
    setState(() => _role = UserRole.member);
  }

  void _editUser(AppUser user) {
    _name.text = user.name;
    _email.text = user.email;
    _company.text = user.company;
    _phone.text = user.phone;
    setState(() => _role = user.role == UserRole.admin ? UserRole.staff : user.role);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _editorDialog(
        dialogContext,
        title: '회원 정보 편집',
        onSave: () {
          final index = _users.indexWhere((item) => item.id == user.id);
          if (index >= 0) {
            setState(() {
              _users[index] = user.copyWith(
                name: _name.text.trim(),
                email: _email.text.trim(),
                company: _company.text.trim(),
                phone: _phone.text.trim(),
                role: _role,
              );
            });
          }
          Navigator.pop(dialogContext);
          _resetForm();
          _message('회원 정보가 수정되었습니다.');
        },
      ),
    );
  }

  AlertDialog _editorDialog(BuildContext dialogContext,
      {required String title, required VoidCallback onSave}) {
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _name, decoration: _input('고객 이름')),
            const SizedBox(height: 8),
            TextField(controller: _email, decoration: _input('계정/이메일')),
            const SizedBox(height: 8),
            TextField(controller: _phone, decoration: _input('전화번호')),
            const SizedBox(height: 8),
            TextField(controller: _company, decoration: _input('회사명')),
            const SizedBox(height: 8),
            DropdownButtonFormField<UserRole>(
              value: _role,
              decoration: _input('권한'),
              items: const [
                DropdownMenuItem(value: UserRole.member, child: Text('일반 회원')),
                DropdownMenuItem(value: UserRole.partner, child: Text('협력/파트너사')),
                DropdownMenuItem(value: UserRole.staff, child: Text('관리자(직원)')),
              ],
              onChanged: (value) => setState(() => _role = value ?? _role),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소')),
        FilledButton(onPressed: onSave, child: const Text('저장')),
      ],
    );
  }

  void _addUser() {
    _resetForm();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _editorDialog(
        dialogContext,
        title: '회원 등록',
        onSave: () {
          if (_name.text.trim().isEmpty || _email.text.trim().isEmpty) {
            _message('고객 이름과 계정을 입력해 주세요.');
            return;
          }
          setState(() {
            _users.add(AppUser(
              id: 'user-${DateTime.now().millisecondsSinceEpoch}',
              name: _name.text.trim(),
              email: _email.text.trim(),
              company: _company.text.trim(),
              phone: _phone.text.trim(),
              role: _role,
            ));
          });
          Navigator.pop(dialogContext);
          _resetForm();
          _message('회원이 등록되었습니다.');
        },
      ),
    );
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _requestStaffAccount() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty) {
      _message('이름과 계정을 입력해 주세요.');
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.instance.requestStaffOrPartnerAccount(
        AccountProvisionRequest(
          name: _name.text.trim(),
          email: _email.text.trim(),
          role: _role == UserRole.staff ? UserRole.staff : UserRole.partner,
          company: _company.text.trim(),
          phone: _phone.text.trim(),
        ),
      );
      if (mounted) _message('계정 발급 요청이 등록되었습니다.');
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('회원 관리')),
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('총괄 관리자 전용',
              style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: _input('회원 계정, 고객 이름, 전화번호 검색').copyWith(
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _addUser,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('회원 등록'),
          ),
          const SizedBox(height: 12),
          if (users.isEmpty)
            const Card(child: ListTile(title: Text('검색 결과가 없습니다.')))
          else
            ...users.map((user) => Card(
                  child: ListTile(
                    leading: CircleAvatar(child: Text(user.name.isEmpty ? '?' : user.name[0])),
                    title: Text(user.name.isEmpty ? user.email : user.name),
                    subtitle: Text('${user.email}\n${user.phone} · ${user.roleLabel}'),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: '회원 편집',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editUser(user),
                    ),
                  ),
                )),
          const SizedBox(height: 22),
          const Divider(),
          const Text('관리자·파트너 계정 발급 요청',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _name, decoration: _input('이름')),
          const SizedBox(height: 8),
          TextField(controller: _email, decoration: _input('계정/이메일')),
          const SizedBox(height: 8),
          TextField(controller: _company, decoration: _input('회사명')),
          const SizedBox(height: 8),
          TextField(controller: _phone, decoration: _input('연락처')),
          const SizedBox(height: 8),
          DropdownButtonFormField<UserRole>(
            value: _role == UserRole.member ? UserRole.staff : _role,
            decoration: _input('계정 유형'),
            items: const [
              DropdownMenuItem(value: UserRole.staff, child: Text('관리자(직원)')),
              DropdownMenuItem(value: UserRole.partner, child: Text('협력/파트너사')),
            ],
            onChanged: (value) => setState(() => _role = value ?? UserRole.staff),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loading ? null : _requestStaffAccount,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('가입/발급 요청 등록'),
          ),
        ],
      ),
    );
  }
}

