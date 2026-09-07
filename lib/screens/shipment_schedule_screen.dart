import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_language.dart';
import '../services/content_service.dart';
import '../widgets/content_media.dart';

class ShipmentScheduleScreen extends StatefulWidget {
  const ShipmentScheduleScreen({
    super.key,
    this.language = AppLanguage.korean,
  });

  final AppLanguage language;

  @override
  State<ShipmentScheduleScreen> createState() =>
      _ShipmentScheduleScreenState();
}

class _ShipmentScheduleScreenState extends State<ShipmentScheduleScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  String _t(String key) => AppStrings.get(widget.language, key);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    return ContentService.fetchSchedules(language: widget.language);
  }

  String _v(Map<String, dynamic> row, String key) =>
      (row[key] ?? '').toString();

  String _date(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = _v(row, key).trim();
      if (value.isNotEmpty) return value.split('T').first;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_t('schedule')),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
        ),
        backgroundColor: AppColors.background,
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  '${_t('schedule_load_failed')}\n${snapshot.error}',
                ),
              );
            }
            final rows = snapshot.data ?? <Map<String, dynamic>>[];
            if (rows.isEmpty) return Center(child: Text(_t('no_schedule')));
            return RefreshIndicator(
              onRefresh: () async {
                setState(() => _future = _load());
                await _future;
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: rows
                    .map(
                      (row) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ExpansionTile(
                          title: Text(
                            _v(row, 'route'),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          subtitle: Text(
                            '${_v(row, 'origin')} → ${_v(row, 'destination')}',
                          ),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          children: [
                            ContentMediaGallery(items: contentAttachments(row['attachments']), language: widget.language),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${_t('booking_close')}: '
                                '${_date(row, const ['booking_close_date', 'closing_date', 'departure_date'])}\n'
                                '${_t('arrival_expected')}: '
                                '${_date(row, const ['estimated_arrival_date', 'arrival_date'])}'
                                '${_v(row, 'detail').trim().isEmpty ? '' : '\n\n${_v(row, 'detail')}'}',
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            );
          },
        ),
      );
}
