import 'package:flutter/material.dart';
import '../core/app_language.dart';
import '../core/waybill_intake_text.dart';
import '../services/domestic_tracking_service.dart';
import '../services/waybill_intake_service.dart';

class CustomerIdentityCard extends StatefulWidget {
  const CustomerIdentityCard({super.key, required this.userId, required this.language, this.loadIdentity});
  final String userId;
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
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(t('uniqueCustomerId')),
    subtitle: Text(_busy ? t('identityLoading') : _failed ? t('identityError') : _identity?['customer_code'] == null ? t('identityUnmatched') : '${_identity!['customer_code']}${_identity!['status'] == 'review_required' ? ' · ${t('identityReview')}' : ''}', key: const ValueKey('my-customer-id')),
    trailing: IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh), tooltip: t('refresh')),
  );
}
