import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/waybill_intake_text.dart';
import '../services/domestic_tracking_service.dart';
import '../services/waybill_intake_service.dart';

class CustomerIdentityCard extends StatefulWidget {
  const CustomerIdentityCard({super.key, required this.userId, required this.language, this.loadIdentity, this.compact = false, this.foregroundColor});
  final String userId;
  final bool compact;
  final Color? foregroundColor;
  final AppLanguage language;
  final Future<Map<String, dynamic>> Function()? loadIdentity;
  @override
  State<CustomerIdentityCard> createState() => _CustomerIdentityCardState();
}
class _CustomerIdentityCardState extends State<CustomerIdentityCard> {
  Map<String, dynamic>? _identity;
  bool _busy = true, _failed = false;
  int _request = 0;
  String t(String k) => intakeText(widget.language, k);
  @override
  void initState() { super.initState(); _load(); }
  @override
  void didUpdateWidget(covariant CustomerIdentityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) { _identity = null; _load(); }
  }
  Future<void> _load() async {
    final request = ++_request, owner = widget.userId;
    setState(() { _busy = true; _failed = false; _identity = null; });
    try {
      if (widget.loadIdentity == null && DomesticTrackingService.currentUserId != owner) return;
      final value = await (widget.loadIdentity?.call() ?? WaybillIntakeService.call('my_customer_id'));
      if (mounted && request == _request && owner == widget.userId && (widget.loadIdentity != null || DomesticTrackingService.currentUserId == owner)) setState(() => _identity = value);
    } catch (_) { if (mounted && request == _request) setState(() => _failed = true); }
    finally { if (mounted && request == _request) setState(() => _busy = false); }
  }
  String get _value => _busy ? t('identityLoading') : _failed ? t('identityError') : _identity?['customer_code'] == null ? t('identityUnmatched') : '${_identity!['customer_code']}${_identity!['status'] == 'review_required' ? ' · ${t('identityReview')}' : ''}';
  @override
  Widget build(BuildContext context) {
    if (widget.compact) return TextButton(
      onPressed: _busy ? null : _load,
      style: TextButton.styleFrom(foregroundColor: widget.foregroundColor, disabledForegroundColor: widget.foregroundColor, padding: const EdgeInsets.symmetric(horizontal: 4), minimumSize: const Size(0, 24), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      child: Text('${t('uniqueCustomerId')}: $_value', key: const ValueKey('my-customer-id'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
    );
    return ListTile(title: Text(t('uniqueCustomerId')), subtitle: Text(_value, key: const ValueKey('my-customer-id')), trailing: IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh), tooltip: t('refresh')));
  }
}
