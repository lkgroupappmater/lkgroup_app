import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../config/supabase_config.dart';
import '../services/company_verification_service.dart';
import '../services/supabase_service.dart';
import 'auto_refresh_state.dart';

String companyText(AppLanguage language, String key) {
  const labels = {
    'title': ['회사명 확인·승인', 'Company verification', 'ຢືນຢັນບໍລິສັດ'],
    'pending': ['확인 대기', 'Pending review', 'ລໍຖ້າກວດສອບ'],
    'approved': ['승인 완료', 'Approved', 'ອະນຸມັດແລ້ວ'],
    'rejected': ['승인 거절', 'Rejected', 'ປະຕິເສດ'],
    'revoked': ['승인 해제', 'Revoked', 'ຍົກເລີກການອະນຸມັດ'],
    'approve': ['일치 확인·승인', 'Confirm and approve', 'ຢືນຢັນ ແລະ ອະນຸມັດ'],
    'reject': ['거절', 'Reject', 'ປະຕິເສດ'],
    'revoke': ['승인 해제', 'Revoke approval', 'ຍົກເລີກການອະນຸມັດ'],
    'cancel': ['취소', 'Cancel', 'ຍົກເລີກ'],
    'empty': ['해당 요청이 없습니다.', 'No requests.', 'ບໍ່ມີຄຳຮ້ອງ'],
    'matches': ['회사명 일치 화물', 'Matching company cargo', 'ສິນຄ້າຊື່ບໍລິສັດກົງກັນ'],
    'confirm': ['이 회원과 회사의 관계를 확인했습니까? 승인하면 해당 회사 화물·운임·명세서를 전체 조회할 수 있습니다.', 'Have you verified this member’s company? Approval enables full company cargo, freight and statement access.', 'ທ່ານໄດ້ກວດສອບສະມາຊິກກັບບໍລິສັດແລ້ວບໍ? ການອະນຸມັດໃຫ້ເບິ່ງສິນຄ້າ, ຄ່າຂົນສົ່ງ ແລະ ໃບແຈ້ງໜີ້ທັງໝົດ.'],
    'waiting': ['총괄 관리자 승인 후 회사 화물의 검색·운임·명세서 조회가 가능합니다.', 'Company cargo, freight and statements become available after administrator approval.', 'ເບິ່ງສິນຄ້າ, ຄ່າຂົນສົ່ງ ແລະ ໃບແຈ້ງໜີ້ໄດ້ຫຼັງຜູ້ບໍລິຫານອະນຸມັດ.'],
    'saved': ['처리했습니다.', 'Saved.', 'ບັນທຶກແລ້ວ'],
    'failed': ['조회·처리에 실패했습니다. 새로고침해 주세요.', 'Could not load or save. Please refresh.', 'ບໍ່ສາມາດໂຫຼດ ຫຼື ບັນທຶກໄດ້. ກະລຸນາໂຫຼດໃໝ່.'],
  };
  return labels[key]?[language == AppLanguage.korean ? 0 : language == AppLanguage.english ? 1 : 2] ?? key;
}

class CompanyVerificationButton extends StatefulWidget {
  const CompanyVerificationButton({super.key, this.language = AppLanguage.korean});
  final AppLanguage language;
  @override
  State<CompanyVerificationButton> createState() => _CompanyVerificationButtonState();
}
class _CompanyVerificationButtonState extends State<CompanyVerificationButton> with AutoRefreshState {
  int? _count;
  @override
  Set<String> get autoRefreshTopics => {'*'};
  @override
  Future<void> refreshAutomatically() => _load();
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    if (!SupabaseConfig.isConfigured) return;
    final owner = SupabaseService.client.auth.currentUser?.id;
    if (owner == null) return;
    try {
      final rows = await CompanyVerificationService.list();
      if (mounted && owner == SupabaseService.client.auth.currentUser?.id) setState(() => _count = rows.length);
    } catch (_) { if (mounted) setState(() => _count = null); }
  }
  @override
  Widget build(BuildContext context) => _count == null ? const SizedBox.shrink() : Align(
    alignment: Alignment.centerLeft,
    child: OutlinedButton.icon(icon: const Icon(Icons.fact_check_outlined),
      label: Text('${companyText(widget.language, 'title')} · ${companyText(widget.language, 'pending')} $_count'),
      onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CompanyVerificationScreen(language: widget.language)));
        if (mounted) await _load();
      }),
  );
}

class CompanyVerificationStatus extends StatefulWidget {
  const CompanyVerificationStatus({super.key, required this.language});
  final AppLanguage language;
  @override
  State<CompanyVerificationStatus> createState() => _CompanyVerificationStatusState();
}
class _CompanyVerificationStatusState extends State<CompanyVerificationStatus> with AutoRefreshState {
  String _status = 'none';
  @override
  Set<String> get autoRefreshTopics => {'*'};
  @override
  Future<void> refreshAutomatically() => _load();
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    if (!SupabaseConfig.isConfigured) return;
    final owner = SupabaseService.client.auth.currentUser?.id;
    if (owner == null) return;
    try {
      final row = await CompanyVerificationService.mine();
      if (mounted && owner == SupabaseService.client.auth.currentUser?.id) setState(() => _status = '${row['status']}');
    } catch (_) { if (mounted) setState(() => _status = 'failed'); }
  }
  @override
  Widget build(BuildContext context) => _status == 'none' ? const SizedBox.shrink() : ListTile(
    dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.business_outlined),
    title: Text('${companyText(widget.language, 'title')}: ${companyText(widget.language, _status)}'),
    subtitle: _status == 'approved' ? null : Text(companyText(widget.language, 'waiting')),
  );
}

class CompanyVerificationScreen extends StatefulWidget {
  const CompanyVerificationScreen({super.key, required this.language});
  final AppLanguage language;
  @override
  State<CompanyVerificationScreen> createState() => _CompanyVerificationScreenState();
}
class _CompanyVerificationScreenState extends State<CompanyVerificationScreen> with AutoRefreshState {
  String _status = 'pending';
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true, _saving = false;
  String? _error;
  String tr(String key) => companyText(widget.language, key);
  @override
  Set<String> get autoRefreshTopics => {'*'};
  @override
  bool get autoRefreshAllowed => !_loading && !_saving;
  @override
  Future<void> refreshAutomatically() => _load(background: true);
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load({bool background = false}) async {
    if (!SupabaseConfig.isConfigured) { setState(() => _loading = false); return; }
    final owner = SupabaseService.client.auth.currentUser?.id, status = _status;
    if (!background) setState(() => _loading = true);
    try {
      final rows = await CompanyVerificationService.list(status);
      if (mounted && owner == SupabaseService.client.auth.currentUser?.id && status == _status) setState(() { _rows = rows; _error = null; });
    } catch (_) { if (mounted) setState(() => _error = tr('failed')); }
    finally { if (mounted) setState(() => _loading = false); }
  }
  Future<void> _review(Map<String, dynamic> row, String action) async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(tr(action)), content: Text('${row['member_name']} · ${row['member_phone']}\n${row['company']}\n\n${action == 'approve' ? tr('confirm') : tr(action)}'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr(action)))],
    ));
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await CompanyVerificationService.review((row['id'] as num).toInt(), action);
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('saved')))); await _load(); }
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('failed')))); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('title')), actions: [IconButton(onPressed: _saving ? null : () => _load(), icon: const Icon(Icons.refresh))]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: DropdownButtonFormField<String>(
        initialValue: _status, items: ['pending','approved','rejected','revoked'].map((s) => DropdownMenuItem(value: s, child: Text(tr(s)))).toList(),
        onChanged: _saving ? null : (s) { if (s != null) { setState(() => _status = s); _load(); } },
      )),
      Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          if (_error != null) Text(_error!),
          if (_rows.isEmpty && _error == null) ListTile(title: Text(tr('empty'))),
          ..._rows.map((row) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${row['member_name']} · ${row['member_phone']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${row['email'] ?? ''}\n${row['company']}'),
            Text('${tr('matches')}: ${row['match_count']}'),
            ...((row['matches'] as List?) ?? []).map((m) => ListTile(dense: true, contentPadding: EdgeInsets.zero,
              title: Text('${m['consignee_name']} · ${m['consignee_phone']}'),
              subtitle: Text('${(m['customer_codes'] as List? ?? []).map((id) => 'LK ${id.toString().padLeft(4, '0')}').join(' / ')} · ${m['cargo_count']}'))),
            Wrap(spacing: 8, children: [
              if (row['status'] != 'approved') FilledButton(onPressed: _saving ? null : () => _review(row, 'approve'), child: Text(tr('approve'))),
              if (row['status'] == 'pending') OutlinedButton(onPressed: _saving ? null : () => _review(row, 'reject'), child: Text(tr('reject'))),
              if (row['status'] == 'approved') OutlinedButton(onPressed: _saving ? null : () => _review(row, 'revoke'), child: Text(tr('revoke'))),
            ]),
          ])))),
        ]))),
    ]),
  );
}
