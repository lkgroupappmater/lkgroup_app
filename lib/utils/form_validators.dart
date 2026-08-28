class FormValidators {
  FormValidators._();

  static String? requiredText(String? value, String label) {
    if ((value ?? '').trim().isEmpty) return '$label을(를) 입력해 주세요.';
    return null;
  }

  static String? email(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return '이메일을 입력해 주세요.';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
    return ok ? null : '예: member@example.com 형식으로 입력해 주세요.';
  }

  static String? password(String? value) {
    final text = value ?? '';
    if (text.length < 8) return '암호는 8자 이상 입력해 주세요.';
    if (!RegExp(r'[a-z]').hasMatch(text)) return '영문 소문자를 1자 이상 포함해 주세요.';
    if (!RegExp(r'[A-Z]').hasMatch(text)) return '영문 대문자를 1자 이상 포함해 주세요.';
    if (!RegExp(r'[0-9]').hasMatch(text)) return '숫자를 1자 이상 포함해 주세요.';
    return null;
  }

  static String? phone(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return '전화번호를 입력해 주세요.';
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 8 || digits.length > 15) {
      return '예: 020-5889-2547 형식으로 입력해 주세요.';
    }
    return null;
  }

  static String normalizePhone(String value) {
    final text = value.trim();
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 11 && digits.startsWith('020')) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    }
    return text;
  }

  static String normalizeDate(String value) {
    final text = value.trim();
    if (RegExp(r'^\d{8}$').hasMatch(text)) {
      return '${text.substring(0, 4)}-${text.substring(4, 6)}-${text.substring(6, 8)}';
    }
    return text;
  }

  static String? date(String? value, {bool required = false}) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return required ? '날짜를 입력해 주세요.' : null;
    final text = normalizeDate(raw);
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
    if (match == null) return '예: 2026-09-03 형식으로 입력해 주세요.';
    final y = int.tryParse(match.group(1)!);
    final m = int.tryParse(match.group(2)!);
    final d = int.tryParse(match.group(3)!);
    if (y == null || m == null || d == null) return '올바른 날짜를 입력해 주세요.';
    try {
      final dt = DateTime(y, m, d);
      if (dt.year != y || dt.month != m || dt.day != d) {
        return '존재하는 날짜를 입력해 주세요.';
      }
    } catch (_) {
      return '올바른 날짜를 입력해 주세요.';
    }
    return null;
  }
}
