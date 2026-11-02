// =============================================================================
// JUZZIO v0.9.0 — Faz 2: Ana kabuk geri tuşu durum makinesi (Android)
//
// Eski davranış: ana kabukta PopScope yoktu → sohbetin içindeyken bile sistem geri
// hareketi uygulamayı doğrudan kapatıyordu. Yeni davranış, sırasıyla:
//   1. Sohbet içinde emoji paneli açıksa → paneli kapat.
//   2. Sohbet içindeyse → sohbet listesine dön.
//   3. Sohbetler sekmesinde filtre seçiliyse → "Tümü" filtresine dön.
//   4. Ana Sayfa dışındaki bir sekmedeyse → Ana Sayfa'ya dön (son talimat §3.1: kök = Ana Sayfa).
//   5. Kök durumda ilk basış → engellemeyen ipucu ("çıkmak için tekrar basın").
//   6. [exitWindow] içinde ikinci basış → uygulamadan çık (SystemNavigator.pop).
// Saf Dart; saat enjekte edilir → birim testlenir (test/juzzio_back_navigation_test.dart).
// =============================================================================

/// Geri tuşuna basıldığında kabuğun yapması gereken tek işlem.
enum JuzzioBackAction { closeEmojiPanel, leaveConversation, goToHomeTab, resetChatFilter, showExitHint, exitApp }

/// Kabuğun o anki durumundan geri tuşu kararını hesaplayan durum makinesi.
class JuzzioBackNavigator {
  JuzzioBackNavigator({DateTime Function()? clock, this.exitWindow = const Duration(seconds: 2)})
      : _clock = clock ?? DateTime.now;

  /// Sohbetler sekmesinin indeksi (kabuktaki `_selectedBottomTab` değeri).
  static const int chatsTab = 0;

  /// Ana Sayfa sekmesinin indeksi (kök).
  static const int homeTab = 5;

  /// Sohbet listesindeki varsayılan ("Tümü") filtre indeksi.
  static const int defaultFilter = 0;

  final DateTime Function() _clock;
  final Duration exitWindow;
  DateTime? _firstPressAt;

  /// İpucu gösterildi ve ikinci basış bekleniyor mu?
  bool get awaitingSecondPress {
    final t = _firstPressAt;
    return t != null && _clock().difference(t) <= exitWindow;
  }

  /// Kullanıcı başka bir şey yaptığında (sekme değişimi, sohbete giriş) çıkış sayacı sıfırlanır.
  void reset() => _firstPressAt = null;

  JuzzioBackAction decide({
    required bool insideConversation,
    required bool emojiPanelOpen,
    required int selectedTab,
    required int chatFilter,
  }) {
    if (insideConversation) {
      reset();
      return emojiPanelOpen ? JuzzioBackAction.closeEmojiPanel : JuzzioBackAction.leaveConversation;
    }
    if (selectedTab == chatsTab && chatFilter != defaultFilter) {
      reset();
      return JuzzioBackAction.resetChatFilter;
    }
    if (selectedTab != homeTab) {
      reset();
      return JuzzioBackAction.goToHomeTab;
    }
    final now = _clock();
    final first = _firstPressAt;
    if (first != null && now.difference(first) <= exitWindow) {
      _firstPressAt = null;
      return JuzzioBackAction.exitApp;
    }
    _firstPressAt = now;
    return JuzzioBackAction.showExitHint;
  }
}
