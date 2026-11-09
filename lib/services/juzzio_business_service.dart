// =============================================================================
// JUZZIO v0.9.0 — Business istemci servisi (tek kimlik, tek uygulama)
//  Tüm durum geçişleri ve yetkiler SUNUCUDA (SQL 10.20–10.21: RPC + RLS). Bu sınıf yalnızca
//  çağırır ve sonucu gösterilebilir modele çevirir; hiçbir yetki kararı istemcide verilmez.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sunucudaki kurulum adımları (sıra önemli; sunucu da zorlar).
const List<String> kJuzzioBusinessSetupSteps = ['profile', 'workspace', 'security', 'modules', 'final'];

class JuzzioBusinessState {
  const JuzzioBusinessState({
    this.status = 'personal',
    this.activeView = 'personal',
    this.profileType,
    this.displayName = '',
    this.reason = '',
    this.steps = const [],
    this.missingConsents = const [],
    this.memberships = const [],
  });

  final String status;
  final String activeView;
  final String? profileType;
  final String displayName;
  final String reason;
  final List<String> steps;
  final List<String> missingConsents;
  final List<Map<String, dynamic>> memberships;

  bool get isActive => status == 'business_active';
  bool get isBusinessView => isActive && activeView == 'business';
  bool get inApplication => status == 'business_application_started' || status == 'business_terms_pending';
  bool get isPreparing => status == 'business_preparing';

  /// Kaldığı yerden devam: sıradaki yapılmamış adım (yoksa null).
  String? get nextStep {
    for (final s in kJuzzioBusinessSetupSteps) {
      if (!steps.contains(s)) return s;
    }
    return null;
  }

  double get setupProgress => steps.where(kJuzzioBusinessSetupSteps.contains).length / kJuzzioBusinessSetupSteps.length;

  factory JuzzioBusinessState.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const JuzzioBusinessState();
    List<String> strs(Object? v) => v is List ? [for (final e in v) e.toString()] : const [];
    return JuzzioBusinessState(
      status: (m['status'] ?? 'personal').toString(),
      activeView: (m['active_view'] ?? 'personal').toString(),
      profileType: m['profile_type']?.toString(),
      displayName: (m['display_name'] ?? '').toString(),
      reason: (m['reason'] ?? '').toString(),
      steps: strs(m['steps']),
      missingConsents: strs(m['missing_consents']),
      memberships: m['memberships'] is List
          ? [for (final e in (m['memberships'] as List).whereType<Map>()) Map<String, dynamic>.from(e)]
          : const [],
    );
  }
}

class JuzzioLegalDoc {
  const JuzzioLegalDoc({
    required this.key,
    required this.version,
    required this.title,
    required this.body,
    required this.consentType,
    required this.required,
    required this.reviewStatus,
    required this.accepted,
  });
  final String key;
  final int version;
  final String title;
  final String body;
  final String consentType; // contract | information | explicit_consent | marketing
  final bool required;
  final String reviewStatus;
  final bool accepted;

  bool get isDraft => reviewStatus.startsWith('DRAFT');

  factory JuzzioLegalDoc.fromMap(Map<String, dynamic> m) => JuzzioLegalDoc(
        key: m['doc_key'].toString(),
        version: (m['version'] as num?)?.toInt() ?? 1,
        title: (m['title'] ?? '').toString(),
        body: (m['body'] ?? '').toString(),
        consentType: (m['consent_type'] ?? 'information').toString(),
        required: m['required'] == true,
        reviewStatus: (m['review_status'] ?? '').toString(),
        accepted: m['accepted'] == true,
      );
}

class JuzzioBusinessService extends ChangeNotifier {
  JuzzioBusinessService._();
  static final JuzzioBusinessService instance = JuzzioBusinessService._();

  SupabaseClient get _c => Supabase.instance.client;
  JuzzioBusinessState _state = const JuzzioBusinessState();
  JuzzioBusinessState get state => _state;

  /// İşletme kimliği = sahibin kullanıcı kimliği (tek kimlik).
  String? get myBusinessId => _c.auth.currentUser?.id;

  static String newRequestId() {
    final r = math.Random.secure();
    return 'biz_${List.generate(12, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  JuzzioBusinessState _apply(Object? res) {
    _state = JuzzioBusinessState.fromMap(res is Map ? Map<String, dynamic>.from(res) : null);
    notifyListeners();
    return _state;
  }

  Future<JuzzioBusinessState> refresh() async => _apply(await _c.rpc('business_get_state'));

  Future<JuzzioBusinessState> startApplication({required String profileType, required String displayName}) async =>
      _apply(await _c.rpc('business_start_application', params: {
        'p_profile_type': profileType,
        'p_display_name': displayName.trim(),
        'p_request_id': newRequestId(),
      }));

  Future<List<JuzzioLegalDoc>> legalDocuments(String locale) async {
    final res = await _c.rpc('get_business_legal_documents', params: {'p_locale': locale});
    return [for (final e in (res as List? ?? const []).whereType<Map>()) JuzzioLegalDoc.fromMap(Map<String, dynamic>.from(e))];
  }

  Future<void> recordConsent(String docKey, bool accept, {String locale = 'tr', String clientInfo = ''}) async {
    await _c.rpc('record_consent', params: {
      'p_doc_key': docKey,
      'p_accept': accept,
      'p_locale': locale,
      'p_client_info': clientInfo,
    });
  }

  Future<JuzzioBusinessState> submitConsents() async => _apply(await _c.rpc('business_submit_consents'));

  Future<JuzzioBusinessState> runStep(String step) async =>
      _apply(await _c.rpc('business_run_setup_step', params: {'p_step': step}));

  Future<void> setView(String view) async {
    await _c.rpc('business_set_view', params: {'p_view': view});
    await refresh();
  }

  Future<JuzzioBusinessState> ownerAction(String action, {String reason = ''}) async =>
      _apply(await _c.rpc('business_owner_action', params: {'p_action': action, 'p_reason': reason}));

  Future<Map<String, dynamic>> myAccount() async {
    final id = myBusinessId;
    if (id == null) return const {};
    final row = await _c.from('business_accounts').select().eq('id', id).maybeSingle();
    return row == null ? const {} : Map<String, dynamic>.from(row);
  }

  Future<void> updateProfile(Map<String, dynamic> patch) async {
    await _c.rpc('business_update_profile', params: {'p_patch': patch});
  }

  Future<Map<String, dynamic>> overview({int days = 30}) async {
    final res = await _c.rpc('business_overview', params: {'p_business': myBusinessId, 'p_days': days});
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  // ---------------------------------------------------------------------------
  // CRM / gelen kutusu / randevu / görev / ekip (RLS ile korunan tablolar)
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> _list(String table, {String order = 'created_at', bool asc = false, int limit = 500}) async {
    final id = myBusinessId;
    if (id == null) return const [];
    final rows = await _c.from(table).select().eq('business_id', id).order(order, ascending: asc).limit(limit);
    return [for (final r in (rows as List).whereType<Map>()) Map<String, dynamic>.from(r)];
  }

  Future<List<Map<String, dynamic>>> customers() => _list('business_customers', order: 'updated_at');
  Future<List<Map<String, dynamic>>> conversations() => _list('business_conversations', order: 'last_activity_at');
  Future<List<Map<String, dynamic>>> appointments() => _list('business_appointments', order: 'starts_at', asc: true);
  Future<List<Map<String, dynamic>>> services() => _list('business_services', order: 'name', asc: true);
  Future<List<Map<String, dynamic>>> tasks() => _list('business_tasks');
  Future<List<Map<String, dynamic>>> members() => _list('business_members', order: 'created_at', asc: true);
  Future<List<Map<String, dynamic>>> autoReplies() => _list('business_auto_replies', order: 'kind', asc: true);

  Future<List<Map<String, dynamic>>> customerChildren(String table, String customerId) async {
    final rows = await _c.from(table).select().eq('customer_id', customerId).order('created_at', ascending: false);
    return [for (final r in (rows as List).whereType<Map>()) Map<String, dynamic>.from(r)];
  }

  Future<void> insert(String table, Map<String, dynamic> values) async {
    await _c.from(table).insert({'business_id': myBusinessId, ...values});
  }

  Future<void> update(String table, String id, Map<String, dynamic> values) async {
    await _c.from(table).update(values).eq('id', id);
  }

  Future<void> delete(String table, String id) async {
    await _c.from(table).delete().eq('id', id);
  }

  Future<void> upsertAutoReply(String kind, {required bool enabled, required String body}) async {
    await _c.from('business_auto_replies').upsert(
      {'business_id': myBusinessId, 'kind': kind, 'enabled': enabled, 'body': body.trim(), 'updated_at': DateTime.now().toUtc().toIso8601String()},
      onConflict: 'business_id,kind',
    );
  }

  Future<void> assignConversation(String conversationId, String? assigneeId, {String reason = ''}) async {
    await _c.rpc('business_assign_conversation', params: {
      'p_conversation': conversationId,
      'p_assignee': assigneeId,
      'p_reason': reason,
    });
  }

  Future<void> inviteMember(String username, String role) async {
    await _c.rpc('business_invite_member', params: {'p_business': myBusinessId, 'p_username': username.trim(), 'p_role': role});
  }

  Future<void> setMember(String userId, {String role = 'support_agent', bool remove = false}) async {
    await _c.rpc('business_set_member', params: {'p_business': myBusinessId, 'p_user': userId, 'p_role': role, 'p_remove': remove});
  }

  Future<void> respondInvite(String businessId, bool accept) async {
    await _c.rpc('business_respond_invite', params: {'p_business': businessId, 'p_accept': accept});
    await refresh();
  }

  /// Ekip üyelerinin görünen adları (atama listeleri için).
  Future<Map<String, String>> memberNames() async {
    final ms = await members();
    final ids = [for (final m in ms) if (m['status'] == 'active') m['user_id'].toString()];
    if (ids.isEmpty) return const {};
    final rows = await _c.from('profiles').select('id, display_name, username').inFilter('id', ids);
    return {
      for (final r in (rows as List).whereType<Map>())
        r['id'].toString(): ((r['display_name'] ?? '').toString().isNotEmpty ? r['display_name'] : r['username']).toString(),
    };
  }
}
