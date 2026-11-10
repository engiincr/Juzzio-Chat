// JUZZIO v1.2.6 — Juzzio Community resmî kanal kuralları + grup/kanal logosu
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/juzzio_community.dart';
import 'package:juzzio/core/release_notes.dart';
import 'package:juzzio/services/juzzio_features_service.dart' show juzzioRoomAvatarSlug;

String _src(String p) => File(p).readAsStringSync();

void main() {
  test('logo dosya adı parçası sunucunun kabul ettiği karakterlerle sınırlı', () {
    expect(juzzioRoomAvatarSlug('21deef26-3f02-4849-867f-ae8125afce04'), '21deef26');
    expect(juzzioRoomAvatarSlug('a/b?c'), 'abc');
    expect(juzzioRoomAvatarSlug(''), 'room');
    expect(RegExp(r'^[A-Za-z0-9]+$').hasMatch(juzzioRoomAvatarSlug('x y z ../..')), isTrue);
  });

  test('oda logosu algılama', () {
    expect(juzzioHasRoomLogo(null), isFalse);
    expect(juzzioHasRoomLogo(''), isFalse);
    expect(juzzioHasRoomLogo('   '), isFalse);
    expect(juzzioHasRoomLogo('https://x.supabase.co/storage/v1/object/public/avatars/u/room_a_1.jpg'), isTrue);
    expect(juzzioHasRoomLogo(kJuzzioLogoAvatar), isTrue);
    expect(juzzioHasRoomLogo('javascript:alert(1)'), isFalse);
  });

  test('Juzzio Community: logo uygulama logosu, tek yetkili @tugkancr', () {
    expect(kJuzzioLogoAvatar, 'asset:assets/logo/juzzio_logo.png');
    expect(File('assets/logo/juzzio_logo.png').existsSync(), isTrue);
    expect(kJuzzioCommunityAdminUsername, 'tugkancr');
    final svc = _src('lib/services/supabase_service.dart');
    expect(svc.contains('avatarUrl: community ? kJuzzioLogoAvatar'), isTrue);
  });

  test('sunucu kuralları: üyeler birbirini görmez, mesaj/tepki/arama yok, logo denetimli', () {
    final sql = _src('supabase/juzzio_database.sql');
    final i = sql.indexOf('10.35 v1.2.6');
    expect(i, greaterThan(0));
    final sec = sql.substring(i);
    for (final needle in [
      'CREATE POLICY room_participants_select_member',
      'FUNCTION public.get_group_members',
      'FUNCTION public.sync_room_member_cache',
      'trg_juzzio_guard_community_roles',
      "RAISE EXCEPTION 'community_roles_fixed'",
      "RAISE EXCEPTION 'community_membership_automatic'",
      "RAISE EXCEPTION 'community_read_only'",
      'trg_juzzio_guard_community_call',
      'FUNCTION public.set_room_avatar',
      'trg_juzzio_guard_room_avatar',
      'juzzio_room_avatar_moderated',
      "RAISE EXCEPTION 'community_logo_fixed'",
    ]) {
      expect(sec.contains(needle), isTrue, reason: needle);
    }
  });

  test('istemci: topluluk sayfası üye listesini gizler, logo düzenleme yalnız yetkili', () {
    final sheet = _src('lib/widgets/group_management_sheet.dart');
    expect(sheet.contains('bool get _showMemberList => !widget.isCommunity || _iAmStaff;'), isTrue);
    expect(sheet.contains('bool get _canEditLogo => _iAmStaff && !widget.isCommunity;'), isTrue);
    expect(sheet.contains('setRoomAvatar('), isTrue);
    final chat = _src('lib/screens/chat_screen.dart');
    expect(chat.contains('juzzioHasRoomLogo(_activeConversationData?.avatarUrl)'), isTrue);
    expect(chat.contains('onTap: _inCommunity ? null : () => _showReactionsWho(p, msg)'), isTrue);
    expect(chat.contains('if (juzzioIsCommunityTitle(group.title)) return;'), isTrue);
  });

  test('v1.2.6 sürüm notu mevcut', () {
    final n = kJuzzioBundledReleaseNotes.firstWhere((r) => r.versionName == '1.2.6');
    expect(n.versionName, '1.2.6');
    expect(n.versionCode, 126);
    expect(n.sections.keys, containsAll(['tr', 'en']));
  });
}
