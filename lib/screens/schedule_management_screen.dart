import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/route_options.dart';

// ---------------------------------------------------------------------------
// Route labels defined locally so the file compiles even if RouteOptions
// does not expose a static label list.
// ---------------------------------------------------------------------------
class _Routes {
  static const List<String> labels = [
    '전체',
    '한국-라오스 해상',
    '한국-라오스 항공',
    '라오스-한국 항공 특송',
    '라오스-태국 육로',
    '라오스-베트남 육로',
    '라오스-중국 육로',
    '라오스-캄보디아 육로',
  ];
  static const String defaultLabel = '한국-라오스 해상';
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------
class _Schedule {
  String route;
  String year;
  String voyage;
  String from;
  String to;
  String deadline;
  String arrival;

  _Schedule({
    required this.route,
    required this.year,
    required this.voyage,
    required this.from,
    required this.to,
    required this.deadline,
    required this.arrival,
  });
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------
class ScheduleManagementScreen extends StatefulWidget {
  const ScheduleManagementScreen({super.key});

  @override
  State<ScheduleManagementScreen> createState() =>
      _ScheduleManagementScreenState();
}

class _ScheduleManagementScreenState extends State<ScheduleManagementScreen> {
  // ── sample data ──────────────────────────────────────────────────────────
  final List<_Schedule> _schedules = [
    _Schedule(
      route: '한국-라오스 해상',
      year: '2026년',
      voyage: '01항차',
      from: '부산항',
      to: '비엔티안',
      deadline: '2026-07-05',
      arrival: '2026-08-01',
    ),
    _Schedule(
      route: '한국-라오스 항공',
      year: '2026년',
      voyage: '02항차',
      from: '인천공항',
      to: '와타이공항',
      deadline: '2026-07-10',
      arrival: '2026-07-12',
    ),
    _Schedule(
      route: '라오스-태국 육로',
      year: '2026년',
      voyage: '01항차',
      from: '비엔티안',
      to: '방콕',
      deadline: '2026-07-15',
      arrival: '2026-07-18',
    ),
  ];

  static const List<String> _years = ['2026년', '2027년', '2028년'];
  static const List<String> _voyages = [
    '01항차',
    '02항차',
    '03항차',
    '04항차',
    '05항차',
  ];

  // ── helpers ───────────────────────────────────────────────────────────────

  /// Opens add/edit dialog. Pass [index] to edit, omit (null) to add.
  Future<void> _openDialog({int? index}) async {
    final isEdit = index != null;
    final original = isEdit ? _schedules[index] : null;

    // Controllers
    final fromCtrl =
    TextEditingController(text: isEdit ? original!.from : '');
    final toCtrl = TextEditingController(text: isEdit ? original!.to : '');
    final deadlineCtrl =
    TextEditingController(text: isEdit ? original!.deadline : '');
    final arrivalCtrl =
    TextEditingController(text: isEdit ? original!.arrival : '');

    String selectedRoute =
    isEdit ? original!.route : _Routes.defaultLabel;
    String selectedYear = isEdit ? original!.year : _years.first;
    String selectedVoyage = isEdit ? original!.voyage : _voyages.first;
    String? fromError;
    String? toError;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              void validate() {
                setDialogState(() {
                  fromError =
                  fromCtrl.text.trim().isEmpty ? '출발지를 입력하세요.' : null;
                  toError =
                  toCtrl.text.trim().isEmpty ? '도착지를 입력하세요.' : null;
                });
              }

              void save() {
                validate();
                if (fromError != null || toError != null) return;

                final updated = _Schedule(
                  route: selectedRoute,
                  year: selectedYear,
                  voyage: selectedVoyage,
                  from: fromCtrl.text.trim(),
                  to: toCtrl.text.trim(),
                  deadline: deadlineCtrl.text.trim(),
                  arrival: arrivalCtrl.text.trim(),
                );

                setState(() {
                  if (isEdit) {
                    _schedules[index] = updated;
                  } else {
                    _schedules.add(updated);
                  }
                });
                Navigator.of(ctx).pop();
              }

              return AlertDialog(
                title: Text(isEdit ? '일정 수정' : '선적 일정 추가'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Route dropdown ──────────────────────────────────
                      _DialogLabel('운송 경로'),
                      DropdownButtonFormField<String>(
                        value: selectedRoute,
                        decoration: _inputDecoration(),
                        items: _Routes.labels
                            .map((l) => DropdownMenuItem(
                          value: l,
                          child: Text(l),
                        ))
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => selectedRoute = v!),
                      ),
                      const SizedBox(height: 12),
                      // ── Year dropdown ───────────────────────────────────
                      _DialogLabel('년도'),
                      DropdownButtonFormField<String>(
                        value: selectedYear,
                        decoration: _inputDecoration(),
                        items: _years
                            .map((y) => DropdownMenuItem(
                          value: y,
                          child: Text(y),
                        ))
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => selectedYear = v!),
                      ),
                      const SizedBox(height: 12),
                      // ── Voyage dropdown ─────────────────────────────────
                      _DialogLabel('항차'),
                      DropdownButtonFormField<String>(
                        value: selectedVoyage,
                        decoration: _inputDecoration(),
                        items: _voyages
                            .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text(v),
                        ))
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => selectedVoyage = v!),
                      ),
                      const SizedBox(height: 12),
                      // ── From ─────────────────────────────────────────────
                      _DialogLabel('출발지'),
                      TextField(
                        controller: fromCtrl,
                        decoration: _inputDecoration(
                          hint: '예) 부산항',
                          errorText: fromError,
                        ),
                        onChanged: (_) {
                          if (fromError != null) {
                            setDialogState(() => fromError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // ── To ───────────────────────────────────────────────
                      _DialogLabel('도착지'),
                      TextField(
                        controller: toCtrl,
                        decoration: _inputDecoration(
                          hint: '예) 비엔티안',
                          errorText: toError,
                        ),
                        onChanged: (_) {
                          if (toError != null) {
                            setDialogState(() => toError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // ── Deadline ─────────────────────────────────────────
                      _DialogLabel('접수 마감일'),
                      TextField(
                        controller: deadlineCtrl,
                        decoration: _inputDecoration(hint: '예) 2026-07-05'),
                      ),
                      const SizedBox(height: 12),
                      // ── Arrival ──────────────────────────────────────────
                      _DialogLabel('도착 예정일'),
                      TextField(
                        controller: arrivalCtrl,
                        decoration: _inputDecoration(hint: '예) 2026-08-01'),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('취소'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                    ),
                    onPressed: save,
                    child: const Text('저장'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      fromCtrl.dispose();
      toCtrl.dispose();
      deadlineCtrl.dispose();
      arrivalCtrl.dispose();
    }
  }

  Future<void> _confirmDelete(int index) async {
    final schedule = _schedules[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('일정 삭제'),
        content: Text(
          '${schedule.route} / ${schedule.year} / ${schedule.voyage}\n'
              '${schedule.from} → ${schedule.to}\n\n'
              '정말 삭제하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _schedules.removeAt(index));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('일정이 삭제되었습니다.')),
      );
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('선적 일정 목록 관리'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        iconTheme: const IconThemeData(color: AppColors.white),
      ),
      body: Column(
        children: [
          Expanded(
            child: _schedules.isEmpty
                ? Center(
              child: Text(
                '등록된 일정이 없습니다.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
                : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _schedules.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _ScheduleCard(
                schedule: _schedules[i],
                onEdit: () => _openDialog(index: i),
                onDelete: () => _confirmDelete(i),
              ),
            ),
          ),
          // ── Add button ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text(
                  '선적 일정 추가',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _openDialog(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Schedule card widget
// ---------------------------------------------------------------------------
class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.schedule,
    required this.onEdit,
    required this.onDelete,
  });

  final _Schedule schedule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Info column ─────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Route · voyage
                  Row(
                    children: [
                      _Badge(label: schedule.route, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        '${schedule.year}  ${schedule.voyage}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // From → To
                  Text(
                    '${schedule.from}  →  ${schedule.to}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  // Deadline
                  Text(
                    '접수 마감: ${schedule.deadline}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  // Arrival
                  Text(
                    '도착 예정: ${schedule.arrival}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // ── Action icons ─────────────────────────────────────────────────
            Column(
              children: [
                IconButton(
                  icon: Icon(Icons.edit, color: AppColors.primary, size: 20),
                  tooltip: '수정',
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: Icon(Icons.delete, color: AppColors.error, size: 20),
                  tooltip: '삭제',
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _DialogLabel extends StatelessWidget {
  const _DialogLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

InputDecoration _inputDecoration({String? hint, String? errorText}) {
  return InputDecoration(
    hintText: hint,
    errorText: errorText,
    isDense: true,
    contentPadding:
    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  );
}
