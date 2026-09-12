import 'package:flutter/material.dart';

import '../core/app_language.dart';
import '../services/code_update_service.dart';

class CodeUpdateText {
  const CodeUpdateText(this.language);
  final AppLanguage language;
  String pick(String ko, String en, String lo) => switch (language) {
    AppLanguage.korean => ko,
    AppLanguage.lao => lo,
    _ => en,
  };
  String get title => pick('앱 업데이트', 'App updates', 'ອັບເດດແອັບ');
  String get close => pick('확인', 'OK', 'ຕົກລົງ');
  String get check => pick('업데이트 확인', 'Check for updates', 'ກວດຫາອັບເດດ');
  String get restart => pick(
    '작업을 저장한 뒤 앱을 완전히 종료하고 다시 실행해 주세요.',
    'Save your work, fully close the app, then open it again.',
    'ບັນທຶກວຽກ, ປິດແອັບໃຫ້ໝົດ ແລ້ວເປີດໃໝ່.',
  );
  String get unsupported => pick(
    '이 설치본은 자동 코드 업데이트를 지원하지 않습니다. GitHub Actions의 release가 성공한 뒤 생성된 Shorebird APK를 설치해 주세요. 소스를 pull하거나 일반 flutter build로 만든 앱에는 자동 업데이트 엔진이 포함되지 않습니다.',
    'This installation cannot receive automatic code updates. Install the Shorebird APK from a successful GitHub Actions release. Pulling source or building with flutter build does not include the updater engine.',
    'ແອັບທີ່ຕິດຕັ້ງນີ້ບໍ່ຮອງຮັບອັບເດດອັດຕະໂນມັດ. ກະລຸນາຕິດຕັ້ງເວີຊັນທີ່ຮອງຮັບ.',
  );
  String status(CodeUpdateService s) => switch (s.status) {
    CodeUpdateStatus.checking => pick(
      '업데이트 확인 중입니다.',
      'Checking for updates.',
      'ກຳລັງກວດຫາອັບເດດ.',
    ),
    CodeUpdateStatus.unsupported => unsupported,
    CodeUpdateStatus.development =>
      s.runtime == CodeUpdateRuntime.web
          ? pick(
              '웹 실행에서는 앱 코드 자동 업데이트를 확인할 수 없습니다.',
              'App code updates are unavailable in a web run.',
              'ກວດອັບເດດໂຄດແອັບໃນເວັບບໍ່ໄດ້.',
            )
          : pick(
              '개발용 실행입니다. IDE 실행 버튼이나 flutter run으로 실행한 앱에서는 자동 업데이트가 동작하지 않습니다. 확인하려면 Actions에서 만든 Shorebird APK를 설치하고 휴대폰의 앱 아이콘으로 실행해 주세요.',
              'Development run: automatic updates do not run with the IDE Run button or flutter run. Install the Shorebird APK built by Actions, then open it from the phone app icon to check updates.',
              'ເປັນການທົດລອງພັດທະນາ. ກະລຸນາຕິດຕັ້ງ Shorebird APK ຈາກ Actions ແລ້ວເປີດຈາກໄອຄອນແອັບໃນໂທລະສັບເພື່ອກວດອັບເດດ.',
            ),
    CodeUpdateStatus.current => pick(
      '현재 설치 버전의 최신 패치입니다.',
      'This release has the latest patch.',
      'ເວີຊັນນີ້ມີແພັດຫຼ້າສຸດແລ້ວ.',
    ),
    CodeUpdateStatus.available => pick(
      '새 업데이트를 발견했습니다.',
      'A new update is available.',
      'ມີອັບເດດໃໝ່.',
    ),
    CodeUpdateStatus.downloading => pick(
      '업데이트 다운로드 중입니다.',
      'Downloading an update.',
      'ກຳລັງດາວໂຫຼດອັບເດດ.',
    ),
    CodeUpdateStatus.ready =>
      '${pick('업데이트 다운로드가 완료되었습니다.', 'The update is downloaded.', 'ດາວໂຫຼດອັບເດດແລ້ວ.')}\n$restart',
    CodeUpdateStatus.error => pick(
      '업데이트를 확인하거나 내려받지 못했습니다. 인터넷 연결을 확인하고 다시 시도해 주세요.',
      'Could not check or download updates. Check your connection and try again.',
      'ກວດຫາ ຫຼື ດາວໂຫຼດອັບເດດບໍ່ສຳເລັດ. ກວດອິນເຕີເນັດ ແລ້ວລອງໃໝ່.',
    ),
  };
  String installed(CodeUpdateService s) =>
      '${pick('현재 앱', 'Installed app', 'ແອັບປັດຈຸບັນ')} ${s.version} · '
      '${s.currentPatch == null ? pick('기본 설치본', 'Base release', 'ເວີຊັນພື້ນຖານ') : 'Patch ${s.currentPatch}'}';
  String notice(CodeUpdateService s) => switch (s.notice) {
    CodeUpdateNotice.unsupported => unsupported,
    CodeUpdateNotice.applied =>
      '${pick('업데이트 적용을 확인했습니다.', 'Update applied.', 'ອັບເດດສຳເລັດແລ້ວ.')}\n${installed(s)}',
    _ =>
      '${pick('새 업데이트가 준비되었습니다.', 'An update is ready.', 'ອັບເດດໃໝ່ພ້ອມແລ້ວ.')} '
          '${s.nextPatch == null ? '' : '(Patch ${s.nextPatch})'}\n$restart',
  };
}

class CodeUpdatePanel extends StatelessWidget {
  const CodeUpdatePanel({
    super.key,
    required this.language,
    required this.service,
  });
  final AppLanguage language;
  final CodeUpdateService service;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (_, __) {
      final t = CodeUpdateText(language);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(t.installed(service)),
          Text(
            '${t.pick('실행 모드', 'Run mode', 'ໂໝດ')}: ${service.runtime.name}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(t.status(service)),
          if (service.version == '1.0.5+6') ...[
            const SizedBox(height: 12),
            Text(
              t.pick(
                '현재 버전에 포함된 개선',
                'Included in this version',
                'ສິ່ງປັບປຸງໃນເວີຊັນນີ້',
              ),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              t.pick(
                '• 작은 시작 로고 제거, 큰 LK GROUP 로고 한 번 표시\n• 자동 업데이트 상태·알림·팝업 안내\n• 배송 정보 색상과 중복 화폐 기호 정리',
                '• One large LK GROUP logo at startup\n• Automatic update status, notices and prompts\n• Delivery colors and cleaner currency amounts',
                '• ສະແດງໂລໂກ້ LK GROUP ຂະໜາດໃຫຍ່ພຽງຄັ້ງດຽວ\n• ສະຖານະ ແລະ ແຈ້ງເຕືອນອັບເດດ\n• ສີຂໍ້ມູນຈັດສົ່ງ ແລະ ຈຳນວນເງິນ',
              ),
            ),
          ],
          if (service.status == CodeUpdateStatus.ready &&
              service.nextPatch != null)
            Text(
              '${t.pick('대기 중인 업데이트', 'Pending update', 'ອັບເດດທີ່ລໍຖ້າ')}: Patch ${service.nextPatch}',
            ),
          if (service.lastChecked != null)
            Text(
              '${t.pick('최근 확인', 'Last checked', 'ກວດຫຼ້າສຸດ')}: ${service.lastChecked!.toLocal().toString().split('.').first}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          TextButton.icon(
            onPressed: service.busy ? null : () => service.check(force: true),
            icon: const Icon(Icons.refresh),
            label: Text(t.check),
          ),
        ],
      );
    },
  );
}

class CodeUpdateBanner extends StatelessWidget {
  const CodeUpdateBanner({
    super.key,
    required this.language,
    required this.service,
    required this.onDetails,
  });
  final AppLanguage language;
  final CodeUpdateService service;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (_, __) {
      if (service.status != CodeUpdateStatus.ready &&
          service.status != CodeUpdateStatus.downloading &&
          !service.hasUnread) {
        return const SizedBox.shrink();
      }
      final t = CodeUpdateText(language);
      return MaterialBanner(
        leading: const Icon(Icons.system_update_alt),
        content: Text(
          service.status == CodeUpdateStatus.downloading
              ? t.status(service)
              : t.notice(service),
        ),
        actions: [
          TextButton(
            onPressed: onDetails,
            child: Text(t.pick('자세히', 'Details', 'ລາຍລະອຽດ')),
          ),
        ],
      );
    },
  );
}

Future<void> showCodeUpdateNotice(
  BuildContext context,
  CodeUpdateService service,
  AppLanguage language,
) async {
  if (!service.needsPopup) return;
  final id = service.noticeId;
  final t = CodeUpdateText(language);
  final message = t.notice(service);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(t.title),
      content: SingleChildScrollView(child: Text(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(t.close),
        ),
      ],
    ),
  );
  await service.acknowledge(id);
}
