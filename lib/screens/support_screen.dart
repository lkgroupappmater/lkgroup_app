import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_language.dart';
import '../services/support_service.dart';
import '../services/quote_service.dart';
import '../services/supabase_service.dart';
import '../widgets/auto_refresh_state.dart';
import '../widgets/content_media.dart';

String supportText(AppLanguage l, String ko, String en, String lo) =>
    sharedText(l, ko, en, lo);
String supportTitle(AppLanguage l) => supportText(
    l, '견적 요청 및 상담 관리', 'Quotes & consultations', 'ຈັດການຄຳຂໍລາຄາ ແລະ ປຶກສາ');
String staffTitle(AppLanguage l) =>
    supportText(l, '담당자 1:1 상담', 'Talk to our team', 'ປຶກສາພະນັກງານ 1:1');

Future<void> startStaffConsultation(BuildContext context, AppLanguage language,
    {int? quoteId, String route = '', String content = ''}) async {
  await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StaffConsultationScreen(
          language: language,
          quoteId: quoteId,
          route: route,
          content: content)));
}

class SupportInboxScreen extends StatefulWidget {
  const SupportInboxScreen(
      {super.key, this.manager = false, this.language = AppLanguage.korean});
  final bool manager;
  final AppLanguage language;
  @override
  State<SupportInboxScreen> createState() => _SupportInboxState();
}

class _SupportInboxState extends State<SupportInboxScreen>
    with AutoRefreshState<SupportInboxScreen> {
  final _search = TextEditingController();
  String _kind = '';
  int _offset = 0;
  bool _busy = false, _searched = false, _more = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  int _generation = 0;
  String s(String k, String e, String l) =>
      supportText(widget.language, k, e, l);
  @override
  Set<String> get autoRefreshTopics =>
      const {'notifications', 'quote_requests'};
  @override
  bool get autoRefreshAllowed => !_busy;
  @override
  Future<void> refreshAutomatically() async {
    if (_searched) await _load();
  }

  @override
  void initState() {
    super.initState();
    if (!widget.manager) _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final owner = SupabaseService.client.auth.currentUser?.id,
        token = ++_generation;
    setState(() {
      _busy = true;
      _searched = true;
      _error = null;
    });
    try {
      final data = await SupportService.list(
          manager: widget.manager,
          search: _search.text.trim(),
          kind: _kind,
          offset: _offset);
      if (!mounted ||
          token != _generation ||
          owner != SupabaseService.client.auth.currentUser?.id) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(data['rows'] as List);
        _more = data['has_more'] == true;
      });
    } catch (e) {
      if (mounted && token == _generation) setState(() => _error = '$e');
    } finally {
      if (mounted && token == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _open(Map<String, dynamic> row) async {
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => SupportDetailScreen(
                id: (row['id'] as num).toInt(),
                manager: widget.manager,
                language: widget.language)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(supportTitle(widget.language))),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              TextField(
                  controller: _search,
                  onSubmitted: (_) {
                    _offset = 0;
                    _load();
                  },
                  decoration: InputDecoration(
                      labelText: s(
                          '이름·연락처·번호·운송 경로',
                          'Name, contact, ID or route',
                          'ຊື່, ຕິດຕໍ່, ເລກ ຫຼື ເສັ້ນທາງ'),
                      suffixIcon: IconButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  _offset = 0;
                                  _load();
                                },
                          icon: const Icon(Icons.search)))),
              Row(children: [
                Expanded(
                    child: DropdownButton<String>(
                        value: _kind,
                        isExpanded: true,
                        items: [
                          ['', s('전체', 'All', 'ທັງໝົດ')],
                          ['quote', s('견적 요청', 'Quote requests', 'ຂໍລາຄາ')],
                          [
                            'consultation',
                            s('1:1 상담', '1:1 consultation', 'ປຶກສາ 1:1')
                          ]
                        ]
                            .map((v) => DropdownMenuItem(
                                value: v[0], child: Text(v[1])))
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _kind = v ?? ''))),
                const SizedBox(width: 12),
                FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            _offset = 0;
                            _load();
                          },
                    child: Text(AppStrings.get(widget.language, 'search')))
              ])
            ])),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        Expanded(
            child: !_searched
                ? Center(
                    child: Text(s('검색하면 요청 목록이 표시됩니다.',
                        'Search to view requests.', 'ຄົ້ນຫາເພື່ອເບິ່ງຄຳຂໍ.')))
                : ListView.builder(
                    itemCount: _rows.length,
                    itemBuilder: (context, i) {
                      final r = _rows[i];
                      return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          child: ListTile(
                              onTap: () => _open(r),
                              title: Text(
                                  '${r['unread'] == true ? '● ' : ''}${r['subject'] ?? r['customer_name'] ?? ''}'),
                              subtitle: Text(
                                  '#${r['id']} · ${r['customer_name'] ?? ''}\n${r['contact_phone'] ?? ''} · ${r['route'] ?? ''}\n${r['content'] ?? ''}',
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis),
                              trailing: TextButton(
                                  onPressed: () => _open(r),
                                  child: Text(s('회신', 'Reply', 'ຕອບກັບ')))));
                    })),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton(
              onPressed: _offset > 0 && !_busy
                  ? () {
                      _offset -= 50;
                      _load();
                    }
                  : null,
              child: Text(s('이전', 'Previous', 'ກ່ອນໜ້າ'))),
          Text('${_offset ~/ 50 + 1}'),
          TextButton(
              onPressed: _more && !_busy
                  ? () {
                      _offset += 50;
                      _load();
                    }
                  : null,
              child: Text(s('다음', 'Next', 'ຕໍ່ໄປ')))
        ])
      ]));
}

class SupportDetailScreen extends StatefulWidget {
  const SupportDetailScreen(
      {super.key,
      required this.id,
      this.manager = false,
      this.language = AppLanguage.korean,
      this.onEditRequest});
  final int id;
  final bool manager;
  final AppLanguage language;
  final Future<void> Function(Map<String, dynamic>)? onEditRequest;
  @override
  State<SupportDetailScreen> createState() => _SupportDetailState();
}

class _SupportDetailState extends State<SupportDetailScreen> {
  Map<String, dynamic>? _row;
  String? _error;
  bool _busy = false;
  String s(String k, String e, String l) =>
      supportText(widget.language, k, e, l);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final owner = SupabaseService.client.auth.currentUser?.id;
    setState(() => _error = null);
    try {
      final r = await SupportService.open(widget.id);
      if (mounted && owner == SupabaseService.client.auth.currentUser?.id)
        setState(() => _row = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _reply([Map<String, dynamic>? message]) async {
    await Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => SupportReplyScreen(
                row: _row!, language: widget.language, message: message)));
    if (mounted) _load();
  }

  Future<void> _action(Future<void> Function() action,
      {bool remove = false}) async {
    if (_busy) return;
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(s(
                    '선택한 요청을 처리할까요?', 'Apply this action?', 'ດຳເນີນການນີ້ບໍ?')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text(AppStrings.get(widget.language, 'close'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(AppStrings.get(widget.language, 'confirm')))
                ]));
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      if (remove) {
        Navigator.pop(context);
        return;
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _status() async {
    final r = _row!,
        amount = TextEditingController(text: '${_row!['quoted_amount'] ?? ''}'),
        note = TextEditingController(text: '${_row!['admin_note'] ?? ''}');
    var status = '${r['status']}';
    final statuses = {
      status,
      'pending',
      'reviewing',
      'approved',
      'rejected',
      'completed'
    }.toList();
    final save = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
            builder: (c, set) => AlertDialog(
                    title: Text(s('상태 / 견적 금액', 'Status / quoted amount',
                        'ສະຖານະ / ຈຳນວນ')),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      DropdownButton<String>(
                          value: status,
                          items: statuses
                              .map((v) =>
                                  DropdownMenuItem(value: v, child: Text(v)))
                              .toList(),
                          onChanged: (v) => set(() => status = v!)),
                      TextField(
                          controller: amount,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              labelText: s('견적 금액', 'Quoted amount', 'ຈຳນວນ'))),
                      TextField(
                          controller: note,
                          maxLines: 3,
                          decoration: InputDecoration(
                              labelText:
                                  s('관리자 메모', 'Admin note', 'ບັນທຶກຜູ້ຈັດການ')))
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child:
                              Text(AppStrings.get(widget.language, 'close'))),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: Text(AppStrings.get(widget.language, 'save')))
                    ])));
    if (save == true) {
      try {
        await QuoteService.instance.updateStatus(widget.id, status,
            note: note.text, amount: num.tryParse(amount.text));
        await _load();
      } catch (e) {
        if (mounted) setState(() => _error = '$e');
      }
    }
    amount.dispose();
    note.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _row,
        messages = List<Map<String, dynamic>>.from(r?['messages'] ?? []),
        pending = r?['deletion_requested_at'] != null,
        replied = messages.any((m) => m['sender_role'] == 'admin');
    return Scaffold(
        appBar: AppBar(title: Text(supportTitle(widget.language)), actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ]),
        body: r == null
            ? Center(
                child: _error != null
                    ? Text(_error!)
                    : const CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                Text(
                    '#${r['id']} · ${r['subject'] ?? r['customer_name'] ?? ''}',
                    style: Theme.of(context).textTheme.titleLarge),
                Text('${r['route'] ?? ''} · ${r['status'] ?? ''}'),
                Text(
                    '${r['customer_name'] ?? ''} · ${r['contact_phone'] ?? ''} · ${r['contact_email'] ?? ''}'),
                const SizedBox(height: 12),
                SelectableText('${(r['content']?.toString().isNotEmpty ?? false) ? r['content'] : r['note'] ?? ''}'),
                if ('${r['other_contact'] ?? ''}'.isNotEmpty)
                  Text('${r['other_contact']}'),
                for (final m in messages)
                  Card(
                      color: m['sender_role'] == 'admin'
                          ? const Color(0xfff0f6fc)
                          : null,
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${m['sender_role'] == 'admin' ? s('관리자 회신', 'Team reply', 'ພະນັກງານຕອບ') : s('회신', 'Reply', 'ຕອບກັບ')} · ${m['created_at'] ?? ''}',
                                    style:
                                        Theme.of(context).textTheme.labelSmall),
                                SelectableText('${m['message'] ?? ''}'),
                                if ('${m['reply_contact'] ?? ''}'.isNotEmpty)
                                  SelectableText('${m['reply_contact']}'),
                                for (final f in List<Map<String, dynamic>>.from(
                                    m['attachments'] ?? []))
                                  TextButton.icon(
                                      icon: const Icon(Icons.attach_file),
                                      label: Text('${f['name']}'),
                                      onPressed: () async {
                                        try {
                                          final url =
                                              await SupportService.fileUrl(
                                                  '${f['path']}');
                                          await launchUrl(Uri.parse(url),
                                              mode: LaunchMode
                                                  .externalApplication);
                                        } catch (e) {
                                          if (mounted)
                                            setState(() => _error = '$e');
                                        }
                                      }),
                                if (widget.manager &&
                                    m['sender_role'] == 'admin' &&
                                    m['viewed_at'] == null &&
                                    !pending)
                                  Wrap(children: [
                                    TextButton(
                                        onPressed: () => _reply(m),
                                        child: Text(AppStrings.get(
                                            widget.language, 'edit'))),
                                    TextButton(
                                        onPressed: () => _action(() =>
                                            QuoteService.instance
                                                .deleteAdminReply(
                                                    (m['id'] as num).toInt())),
                                        child: Text(AppStrings.get(
                                            widget.language, 'delete')))
                                  ])
                              ]))),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                Wrap(spacing: 8, children: [
                  if (!pending) ...[
                    FilledButton(
                        onPressed: _busy ? null : () => _reply(),
                        child: Text(s('회신', 'Reply', 'ຕອບກັບ'))),
                    if (!widget.manager)
                      OutlinedButton(
                          onPressed: () => startStaffConsultation(
                              context, widget.language,
                              quoteId: widget.id,
                              route: '${r['route'] ?? ''}',
                              content: '${r['subject'] ?? ''}'),
                          child: Text(staffTitle(widget.language)))
                  ],
                  if (r['quote_type'] == 'special') ...[
                    if (pending) ...[
                      TextButton(
                          onPressed: () => _action(() =>
                              QuoteService.instance.cancelDelete(widget.id)),
                          child: Text(
                              s('삭제 취소', 'Cancel deletion', 'ຍົກເລີກລຶບ'))),
                      TextButton(
                          onPressed: () => _action(
                              () => QuoteService.instance.deleteNow(widget.id),
                              remove: true),
                          child:
                              Text(s('바로 삭제', 'Remove now', 'ເອົາອອກດຽວນີ້')))
                    ] else ...[
                      if (!widget.manager &&
                          r['admin_viewed_at'] == null &&
                          widget.onEditRequest != null)
                        TextButton(
                            onPressed: () async {
                              await widget.onEditRequest!(r);
                              if (mounted) _load();
                            },
                            child:
                                Text(AppStrings.get(widget.language, 'edit'))),
                      if (widget.manager ||
                          r['admin_viewed_at'] == null ||
                          replied)
                        TextButton(
                            onPressed: () => _action(
                                () => QuoteService.instance
                                    .requestDelete(widget.id),
                                remove: !widget.manager &&
                                    r['admin_viewed_at'] == null),
                            child:
                                Text(AppStrings.get(widget.language, 'delete')))
                    ]
                  ] else if (widget.manager)
                    TextButton(
                        onPressed: _status,
                        child: Text(
                            s('상태 / 금액', 'Status / amount', 'ສະຖານະ / ຈຳນວນ')))
                ])
              ]));
  }
}

class SupportReplyScreen extends StatefulWidget {
  const SupportReplyScreen(
      {super.key, required this.row, required this.language, this.message});
  final Map<String, dynamic> row;
  final AppLanguage language;
  final Map<String, dynamic>? message;
  @override
  State<SupportReplyScreen> createState() => _SupportReplyState();
}

class _SupportReplyState extends State<SupportReplyScreen> {
  late final TextEditingController _message;
  final _contact = TextEditingController();
  final _clientId = SupportService.newId();
  List<SupportFile> _files = [];
  bool _busy = false;
  String? _error;
  String s(String k, String e, String l) =>
      supportText(widget.language, k, e, l);
  @override
  void initState() {
    super.initState();
    _message =
        TextEditingController(text: '${widget.message?['message'] ?? ''}');
  }

  @override
  void dispose() {
    _message.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || _message.text.trim().isEmpty) return;
    final owner = SupabaseService.client.auth.currentUser?.id;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.message != null) {
        await QuoteService.instance.updateAdminReply(
            messageId: (widget.message!['id'] as num).toInt(),
            message: _message.text.trim());
      } else {
        final files = <Map<String, dynamic>>[];
        for (final f in _files) {
          files.add(await SupportService.upload(
              (widget.row['id'] as num).toInt(), f));
        }
        if (owner != SupabaseService.client.auth.currentUser?.id) return;
        await SupportService.send((widget.row['id'] as num).toInt(),
            _message.text.trim(), _contact.text.trim(), files, _clientId);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(s('회신', 'Reply', 'ຕອບກັບ'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
            controller: _message,
            maxLines: 7,
            maxLength: 10000,
            enabled: !_busy,
            decoration:
                InputDecoration(labelText: s('내용', 'Message', 'ເນື້ອຫາ'))),
        if (widget.message == null) ...[
          TextField(
              controller: _contact,
              maxLength: 500,
              enabled: !_busy,
              decoration: InputDecoration(
                  labelText: s(
                      '회신 연락처 (전화·이메일·기타)',
                      'Reply contact (phone, email or other)',
                      'ຂໍ້ມູນຕິດຕໍ່'))),
          OutlinedButton.icon(
              icon: const Icon(Icons.attach_file),
              label: Text(s('사진·파일 첨부 (5개 / 각 10MB)',
                  'Attach files (5 / 10MB each)', 'ແນບໄຟລ໌ (5 / 10MB)')),
              onPressed: _busy
                  ? null
                  : () async {
                      try {
                        final f = await SupportService.pick();
                        if (mounted && f.isNotEmpty) setState(() => _files = f);
                      } catch (e) {
                        if (mounted) setState(() => _error = '$e');
                      }
                    }),
          for (final f in _files)
            ListTile(
                title: Text(f.name),
                trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed:
                        _busy ? null : () => setState(() => _files.remove(f))))
        ],
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        FilledButton(
            onPressed: _busy ? null : _send,
            child: Text(_busy
                ? AppStrings.get(widget.language, 'loading')
                : s('회신 보내기', 'Send reply', 'ສົ່ງຄຳຕອບ')))
      ]));
}

class StaffConsultationScreen extends StatefulWidget {
  const StaffConsultationScreen(
      {super.key,
      required this.language,
      this.quoteId,
      this.route = '',
      this.content = ''});
  final AppLanguage language;
  final int? quoteId;
  final String route, content;
  @override
  State<StaffConsultationScreen> createState() => _StaffConsultationState();
}

class _StaffConsultationState extends State<StaffConsultationScreen> {
  late final TextEditingController _content;
  final _clientId = SupportService.newId();
  bool _busy = false;
  int? _id;
  String? _error;
  String s(String k, String e, String l) =>
      supportText(widget.language, k, e, l);
  @override
  void initState() {
    super.initState();
    _content = TextEditingController(text: widget.content);
  }

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _chat() async {
    await launchUrl(Uri.parse('https://open.kakao.com/o/sYly2bxf'),
        mode: LaunchMode.externalApplication);
  }

  Future<void> _send() async {
    if (_busy || _content.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final id = await SupportService.start(_content.text.trim(), _clientId,
          quoteId: widget.quoteId, route: widget.route);
      if (!mounted) return;
      setState(() => _id = id);
      await _chat();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(staffTitle(widget.language))),
      body: Padding(
          padding: const EdgeInsets.all(16),
          child: SupabaseService.client.auth.currentUser == null
              ? Text(s(
                  '로그인 후 상담 요청을 보내 주세요.',
                  'Sign in to request consultation.',
                  'ເຂົ້າລະບົບເພື່ອຂໍປຶກສາ.'))
              : ListView(children: [
                  if (_id == null) ...[
                    TextField(
                        controller: _content,
                        maxLines: 6,
                        maxLength: 10000,
                        enabled: !_busy,
                        decoration: InputDecoration(
                            labelText: s('상담 내용', 'Consultation details',
                                'ເນື້ອຫາປຶກສາ'))),
                    FilledButton(
                        onPressed: _busy ? null : _send,
                        child: Text(s(
                            '상담 요청 후 오픈채팅 연결',
                            'Request consultation & open chat',
                            'ຂໍປຶກສາ ແລະ ເປີດແຊັດ')))
                  ] else ...[
                    Text(s('상담 요청을 접수했습니다.', 'Your request was sent.',
                        'ຮັບຄຳຂໍແລ້ວ.')),
                    FilledButton(
                        onPressed: _chat,
                        child: Text(s('카카오톡 오픈채팅 열기', 'Open Kakao OpenChat',
                            'ເປີດ Kakao OpenChat'))),
                    TextButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) => SupportDetailScreen(
                                    id: _id!, language: widget.language))),
                        child: Text(s('요청 내용 보기', 'View request', 'ເບິ່ງຄຳຂໍ')))
                  ],
                  if (_error != null) Text(_error!)
                ])));
}
