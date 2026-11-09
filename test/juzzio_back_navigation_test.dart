// JUZZIO v0.9.0 — Faz 2 geri tuşu durum makinesi
import 'package:flutter_test/flutter_test.dart';
import 'package:juzzio/core/juzzio_back_navigation.dart';

void main() {
  late DateTime now;
  late JuzzioBackNavigator nav;

  setUp(() {
    now = DateTime(2026, 11, 1, 12);
    nav = JuzzioBackNavigator(clock: () => now);
  });

  JuzzioBackAction press({bool inside = false, bool emoji = false, int tab = JuzzioBackNavigator.homeTab, int filter = 0}) =>
      nav.decide(insideConversation: inside, emojiPanelOpen: emoji, selectedTab: tab, chatFilter: filter);

  test('sohbet içinde önce emoji paneli, sonra sohbetten çıkış — uygulama KAPANMAZ', () {
    expect(press(inside: true, emoji: true), JuzzioBackAction.closeEmojiPanel);
    expect(press(inside: true), JuzzioBackAction.leaveConversation);
    expect(press(inside: true), JuzzioBackAction.leaveConversation);
  });

  test('kök sekme Sohbetler', () {
    expect(JuzzioBackNavigator.homeTab, JuzzioBackNavigator.chatsTab);
  });

  test('sohbet filtresi önce Tümü\'ne, diğer sekmeler Sohbetler\'e döner', () {
    expect(press(tab: 0, filter: 2), JuzzioBackAction.resetChatFilter);
    expect(press(tab: 0), JuzzioBackAction.showExitHint);
    nav.reset();
    expect(press(tab: 1), JuzzioBackAction.goToHomeTab);
    expect(press(tab: 4), JuzzioBackAction.goToHomeTab);
    expect(press(tab: 6), JuzzioBackAction.goToHomeTab);
    expect(press(tab: 3, filter: 2), JuzzioBackAction.goToHomeTab);
  });

  test('kökte ilk basış ipucu, 2 sn içinde ikinci basış çıkış', () {
    expect(press(), JuzzioBackAction.showExitHint);
    expect(nav.awaitingSecondPress, isTrue);
    now = now.add(const Duration(milliseconds: 1999));
    expect(press(), JuzzioBackAction.exitApp);
    expect(nav.awaitingSecondPress, isFalse);
  });

  test('2 sn geçtikten sonra ikinci basış yeniden ipucu gösterir', () {
    expect(press(), JuzzioBackAction.showExitHint);
    now = now.add(const Duration(milliseconds: 2001));
    expect(nav.awaitingSecondPress, isFalse);
    expect(press(), JuzzioBackAction.showExitHint);
    now = now.add(const Duration(milliseconds: 500));
    expect(press(), JuzzioBackAction.exitApp);
  });

  test('araya başka gezinme girerse sayaç sıfırlanır (yanlışlıkla çıkış yok)', () {
    expect(press(), JuzzioBackAction.showExitHint);
    expect(press(tab: 3), JuzzioBackAction.goToHomeTab);
    expect(press(), JuzzioBackAction.showExitHint);
    nav.reset();
    expect(press(), JuzzioBackAction.showExitHint);
  });
}
