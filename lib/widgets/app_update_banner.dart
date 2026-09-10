import 'package:flutter/material.dart';

import '../core/app_language.dart';
import '../services/app_update_service.dart';

class AppUpdateBanner extends StatelessWidget {
  const AppUpdateBanner({super.key, required this.language});
  final AppLanguage language;

  String _text(String ko, String en, String lo) => switch (language) {
        AppLanguage.korean => ko,
        AppLanguage.lao => lo,
        _ => en,
      };

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppUpdateStatus>(
        valueListenable: AppUpdateService.instance,
        builder: (context, status, _) {
          if (status == AppUpdateStatus.unavailable) return const SizedBox.shrink();
          final ready = status == AppUpdateStatus.ready;
          final downloading = status == AppUpdateStatus.downloading;
          return MaterialBanner(
            leading: Icon(ready ? Icons.restart_alt : Icons.system_update),
            content: Text(downloading
                ? _text('업데이트 다운로드 중입니다.', 'Downloading an update.', 'ກຳລັງດາວໂຫຼດອັບເດດ.')
                : ready
                    ? _text('업데이트가 준비되었습니다. 작업 저장 후 다시 시작하세요.',
                        'Update ready. Save your work before restarting.',
                        'ອັບເດດພ້ອມແລ້ວ. ບັນທຶກວຽກກ່ອນເລີ່ມໃໝ່.')
                    : _text('새 앱 버전을 사용할 수 있습니다.', 'A new app version is available.',
                        'ມີແອັບເວີຊັນໃໝ່.')),
            actions: [
              if (downloading)
                const Padding(padding: EdgeInsets.all(12), child: SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              else
                TextButton(
                  onPressed: () async {
                    if (ready) {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          content: Text(_text('저장하지 않은 작업이 있으면 먼저 저장하세요. 앱을 다시 시작할까요?',
                              'Save any unfinished work first. Restart the app now?',
                              'ກະລຸນາບັນທຶກວຽກກ່ອນ. ເລີ່ມແອັບໃໝ່ດຽວນີ້ບໍ?')),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                                child: Text(_text('나중에', 'Later', 'ພາຍຫຼັງ'))),
                            TextButton(onPressed: () => Navigator.pop(dialogContext, true),
                                child: Text(_text('다시 시작', 'Restart', 'ເລີ່ມໃໝ່'))),
                          ],
                        ),
                      );
                      if (confirmed != true || !context.mounted) return;
                    }
                    final ok = ready ? await AppUpdateService.instance.install()
                        : await AppUpdateService.instance.download();
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
                        _text('업데이트를 완료하지 못했습니다. 잠시 후 다시 시도하세요.',
                          'Could not complete the update. Please try again later.',
                          'ອັບເດດບໍ່ສຳເລັດ. ກະລຸນາລອງໃໝ່ພາຍຫຼັງ.'))));
                    }
                  },
                  child: Text(ready ? _text('다시 시작', 'Restart', 'ເລີ່ມໃໝ່')
                      : _text('업데이트', 'Update', 'ອັບເດດ')),
                ),
            ],
          );
        },
      );
}
