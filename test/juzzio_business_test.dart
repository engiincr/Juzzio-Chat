// JUZZIO v0.9.0 Business — istemci durum modeli (yetki ve geçişler sunucuda; SQL testli)
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/services/juzzio_business_service.dart';

void main() {
  test('sunucu yanıtı yoksa Personal', () {
    final s = JuzzioBusinessState.fromMap(null);
    expect(s.status, 'personal');
    expect(s.isActive, isFalse);
    expect(s.isBusinessView, isFalse);
    expect(s.nextStep, 'profile');
  });

  test('kurulum kaldığı yerden devam eder; ilerleme gerçek adım sayısı', () {
    final s = JuzzioBusinessState.fromMap({
      'status': 'business_preparing',
      'steps': ['profile', 'workspace'],
      'missing_consents': [],
    });
    expect(s.isPreparing, isTrue);
    expect(s.nextStep, 'security');
    expect(s.setupProgress, closeTo(2 / 5, 1e-9));
  });

  test('Business görünümü yalnız aktif hesapta', () {
    expect(JuzzioBusinessState.fromMap({'status': 'business_paused', 'active_view': 'business'}).isBusinessView, isFalse);
    expect(JuzzioBusinessState.fromMap({'status': 'business_active', 'active_view': 'business'}).isBusinessView, isTrue);
    expect(JuzzioBusinessState.fromMap({'status': 'business_active', 'active_view': 'personal'}).isBusinessView, isFalse);
  });

  test('eksik onaylar ve ekip davetleri ayrıştırılır', () {
    final s = JuzzioBusinessState.fromMap({
      'status': 'business_terms_pending',
      'missing_consents': ['business_kvkk_notice'],
      'memberships': [
        {'business_id': 'b1', 'role': 'support_agent', 'status': 'invited', 'name': 'Ali Kuaför'},
      ],
    });
    expect(s.inApplication, isTrue);
    expect(s.missingConsents, ['business_kvkk_notice']);
    expect(s.memberships.single['status'], 'invited');
  });

  test('hukuki belge taslak etiketi tanınır; önceden onaylı değil', () {
    final d = JuzzioLegalDoc.fromMap({
      'doc_key': 'business_terms_of_use',
      'version': 1,
      'title': 'Koşullar',
      'body': 'x',
      'consent_type': 'contract',
      'required': true,
      'review_status': 'DRAFT - LEGAL REVIEW REQUIRED',
    });
    expect(d.isDraft, isTrue);
    expect(d.accepted, isFalse);
    expect(d.required, isTrue);
  });

  test('istek kimliği sunucu biçimine uygun', () {
    expect(JuzzioBusinessService.newRequestId(), matches(RegExp(r'^biz_[0-9a-f]{24}$')));
  });
}
