// =============================================================================
// JUZZIO v0.4.0 — Kategorili ve aramalı emoji paneli (ek paket gerektirmez)
// Seçilen emoji, imlecin bulunduğu yere eklenir; mesaj otomatik gönderilmez.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/app_theme_and_locale.dart';
import '../core/theme/juzzio_colors.dart';
import '../core/theme/juzzio_glass.dart';

class _EmojiCategory {
  final IconData icon;
  final String tr;
  final String en;
  final String de;
  final List<String> emojis;
  const _EmojiCategory(this.icon, this.tr, this.en, this.de, this.emojis);
}

const List<_EmojiCategory> _kCategories = [
  _EmojiCategory(Icons.emoji_emotions_outlined, 'İfadeler', 'Smileys', 'Smileys', [
    '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃', '😉', '😊', '😇', '🥰', '😍', '🤩',
    '😘', '😗', '☺️', '😚', '😙', '🥲', '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔',
    '🤐', '🤨', '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '😮‍💨', '🤥', '😌', '😔', '😪', '🤤', '😴',
    '😷', '🤒', '🤕', '🤢', '🤮', '🤧', '🥵', '🥶', '🥴', '😵', '🤯', '🤠', '🥳', '🥸', '😎', '🤓',
    '🧐', '😕', '😟', '🙁', '☹️', '😮', '😯', '😲', '😳', '🥺', '😦', '😧', '😨', '😰', '😥', '😢',
    '😭', '😱', '😖', '😣', '😞', '😓', '😩', '😫', '🥱', '😤', '😡', '😠', '🤬', '😈', '👿', '💀',
    '💩', '🤡', '👻', '👽', '🤖', '😺', '😸', '😹', '😻', '😼', '😽', '🙀', '😿', '😾',
  ]),
  _EmojiCategory(Icons.waving_hand_outlined, 'İnsanlar', 'People', 'Menschen', [
    '👋', '🤚', '🖐️', '✋', '🖖', '👌', '🤌', '🤏', '✌️', '🤞', '🤟', '🤘', '🤙', '👈', '👉', '👆',
    '👇', '☝️', '👍', '👎', '✊', '👊', '🤛', '🤜', '👏', '🙌', '👐', '🤲', '🤝', '🙏', '✍️', '💅',
    '💪', '🦾', '🧠', '👀', '👁️', '👅', '👄', '💋', '👶', '🧒', '👦', '👧', '🧑', '👨', '👩', '🧔',
    '👴', '👵', '🙋', '🙆', '🙅', '🤷', '🤦', '💁', '🙇', '👮', '👷', '💂', '🕵️', '👩‍⚕️', '👨‍🍳', '👩‍🎓',
    '👨‍💻', '👩‍🎤', '🧑‍🚀', '🦸', '🦹', '🧙', '🧚', '🧛', '🧜', '🧞', '💃', '🕺', '👯', '🧘', '🏃', '🚶',
    '👫', '👭', '👬', '💏', '💑', '👪',
  ]),
  _EmojiCategory(Icons.favorite_border_rounded, 'Kalpler', 'Hearts', 'Herzen', [
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔', '❤️‍🔥', '❤️‍🩹', '❣️', '💕', '💞', '💓',
    '💗', '💖', '💘', '💝', '💟', '♥️', '😍', '🥰', '😘', '💌', '💐', '🌹', '💍', '💎',
  ]),
  _EmojiCategory(Icons.pets_outlined, 'Hayvanlar', 'Animals', 'Tiere', [
    '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵', '🙈',
    '🙉', '🙊', '🐔', '🐧', '🐦', '🐤', '🐣', '🐥', '🦆', '🦅', '🦉', '🦇', '🐺', '🐗', '🐴', '🦄',
    '🐝', '🐛', '🦋', '🐌', '🐞', '🐢', '🐍', '🦎', '🐙', '🦑', '🦀', '🐠', '🐟', '🐬', '🐳', '🦈',
    '🐊', '🐅', '🐆', '🦓', '🐘', '🦒', '🐪', '🐄', '🐎', '🐑', '🐕', '🐈', '🌵', '🎄', '🌲', '🌳',
    '🌴', '🌱', '🌿', '☘️', '🍀', '🍁', '🍂', '🍃', '🌸', '🌼', '🌻', '🌞', '🌝', '🌙', '⭐', '🌟',
    '✨', '⚡', '🔥', '🌈', '☀️', '⛅', '☁️', '🌧️', '⛈️', '❄️', '☃️', '💧', '🌊',
  ]),
  _EmojiCategory(Icons.fastfood_outlined, 'Yiyecek', 'Food', 'Essen', [
    '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐', '🍒', '🍑', '🥭', '🍍', '🥥', '🥝',
    '🍅', '🥑', '🍆', '🥔', '🥕', '🌽', '🌶️', '🥒', '🥬', '🥦', '🧄', '🧅', '🍄', '🥜', '🍞', '🥐',
    '🥖', '🥨', '🥯', '🧀', '🥚', '🍳', '🥞', '🧇', '🥓', '🥩', '🍗', '🍖', '🌭', '🍔', '🍟', '🍕',
    '🥪', '🌮', '🌯', '🥙', '🧆', '🥗', '🍝', '🍜', '🍲', '🍛', '🍣', '🍱', '🥟', '🍤', '🍙', '🍚',
    '🍦', '🍧', '🍨', '🍩', '🍪', '🎂', '🍰', '🧁', '🥧', '🍫', '🍬', '🍭', '🍯', '☕', '🍵', '🧃',
    '🥤', '🧋', '🍺', '🍻', '🥂', '🍷', '🥃', '🍸', '🍹', '🧉',
  ]),
  _EmojiCategory(Icons.sports_soccer_outlined, 'Etkinlik', 'Activities', 'Aktivitäten', [
    '⚽', '🏀', '🏈', '⚾', '🥎', '🎾', '🏐', '🏉', '🎱', '🏓', '🏸', '🥊', '🥋', '⛳', '🎣', '🏊',
    '🏄', '🚴', '🏋️', '🤸', '⛹️', '🤾', '🏆', '🥇', '🥈', '🥉', '🏅', '🎖️', '🎗️', '🎫', '🎟️', '🎪',
    '🎭', '🎨', '🎬', '🎤', '🎧', '🎼', '🎹', '🥁', '🎷', '🎺', '🎸', '🎻', '🎲', '♟️', '🎯', '🎳',
    '🎮', '🎰', '🧩', '🎉', '🎊', '🎈', '🎁', '🎀', '🪅',
  ]),
  _EmojiCategory(Icons.flight_outlined, 'Seyahat', 'Travel', 'Reisen', [
    '🚗', '🚕', '🚙', '🚌', '🚎', '🏎️', '🚓', '🚑', '🚒', '🚐', '🛻', '🚚', '🚜', '🛵', '🏍️', '🚲',
    '🛴', '🚨', '🚔', '🚘', '🚖', '🚡', '🚠', '🚟', '🚃', '🚋', '🚝', '🚄', '🚅', '🚈', '🚂', '🚆',
    '✈️', '🛫', '🛬', '🚀', '🛸', '🚁', '⛵', '🚤', '🛳️', '⛴️', '🚢', '⚓', '🗺️', '🗽', '🗼', '🏰',
    '🏯', '🏟️', '🎡', '🎢', '🏖️', '🏝️', '🏜️', '🌋', '⛰️', '🏔️', '🏕️', '🏠', '🏡', '🏢', '🕌', '⛪',
    '🕍', '🌃', '🌆', '🌇', '🌉', '🌅', '🌄',
  ]),
  _EmojiCategory(Icons.lightbulb_outline_rounded, 'Nesneler', 'Objects', 'Objekte', [
    '⌚', '📱', '💻', '⌨️', '🖥️', '🖨️', '🖱️', '💽', '💾', '💿', '📷', '📸', '📹', '🎥', '📞', '☎️',
    '📺', '📻', '🎙️', '⏰', '⌛', '⏳', '📡', '🔋', '🔌', '💡', '🔦', '🕯️', '💸', '💵', '💰', '💳',
    '🧾', '✉️', '📧', '📦', '📫', '📝', '📁', '📅', '📌', '📎', '✂️', '🔒', '🔓', '🔑', '🔨', '🛠️',
    '⚙️', '🧲', '💊', '💉', '🩺', '🧸', '🛍️', '🎒', '👓', '🕶️', '👔', '👕', '👖', '👗', '👙', '👠',
    '👟', '👑', '🎩', '🧢', '💄', '💼', '☂️',
  ]),
  _EmojiCategory(Icons.emoji_symbols_rounded, 'Semboller', 'Symbols', 'Symbole', [
    '✅', '☑️', '✔️', '❌', '❎', '➕', '➖', '➗', '✖️', '♾️', '‼️', '⁉️', '❓', '❔', '❕', '❗',
    '💯', '🔴', '🟠', '🟡', '🟢', '🔵', '🟣', '⚫', '⚪', '🟤', '🔺', '🔻', '🔸', '🔹', '🔶', '🔷',
    '💠', '🔘', '🆗', '🆕', '🆒', '🆓', '🆙', '🆘', '⛔', '🚫', '📵', '🔞', '♻️', '⚠️', '🚸', '🔱',
    '⚜️', '🔰', '✳️', '❇️', '🌀', '💤', '💢', '💬', '💭', '🗯️', '♈', '♉', '♊', '♋', '♌', '♍',
    '♎', '♏', '♐', '♑', '♒', '♓', '🎵', '🎶', '☮️', '☯️', '✡️', '☪️', '🕉️', '✝️', '☦️', '🛐',
  ]),
  _EmojiCategory(Icons.flag_outlined, 'Bayraklar', 'Flags', 'Flaggen', [
    '🇹🇷', '🇦🇿', '🇩🇪', '🇬🇧', '🇺🇸', '🇫🇷', '🇮🇹', '🇪🇸', '🇳🇱', '🇧🇪', '🇦🇹', '🇨🇭', '🇸🇪', '🇳🇴', '🇩🇰', '🇫🇮',
    '🇵🇱', '🇷🇺', '🇺🇦', '🇬🇷', '🇧🇬', '🇷🇴', '🇭🇺', '🇨🇿', '🇵🇹', '🇮🇪', '🇸🇦', '🇦🇪', '🇶🇦', '🇪🇬', '🇲🇦', '🇮🇷',
    '🇮🇶', '🇸🇾', '🇯🇴', '🇮🇱', '🇵🇸', '🇰🇿', '🇺🇿', '🇹🇲', '🇰🇬', '🇯🇵', '🇰🇷', '🇨🇳', '🇮🇳', '🇵🇰', '🇧🇩', '🇮🇩',
    '🇲🇾', '🇹🇭', '🇻🇳', '🇵🇭', '🇦🇺', '🇳🇿', '🇨🇦', '🇲🇽', '🇧🇷', '🇦🇷', '🇨🇴', '🇨🇱', '🇿🇦', '🇳🇬', '🏳️', '🏴',
    '🏁', '🚩', '🏳️‍🌈', '🇪🇺', '🇺🇳',
  ]),
];

/// Arama için anahtar kelimeler (Türkçe / İngilizce / Almanca).
const Map<String, String> _kKeywords = {
  '😀': 'gülen mutlu smile happy grin lächeln', '😂': 'gülmek kahkaha ağlayarak laugh lol tears lachen',
  '🤣': 'gülmek yerlere rofl lachen', '😊': 'mutlu utangaç smile blush glücklich', '😍': 'aşık kalp göz love heart eyes verliebt',
  '🥰': 'sevgi aşk love liebe', '😘': 'öpücük kiss kuss', '😎': 'havalı güneş gözlüğü cool sunglasses',
  '🤔': 'düşünmek think denken', '😢': 'üzgün ağlamak sad cry traurig weinen', '😭': 'ağlamak hıçkırık cry sob weinen',
  '😡': 'kızgın sinirli angry wütend', '😱': 'korku çığlık scream fear angst', '😴': 'uyku uyumak sleep schlafen',
  '🥳': 'parti kutlama party feier', '🤗': 'sarılmak hug umarmung', '🙄': 'göz devirmek eye roll',
  '😇': 'melek angel engel', '🤩': 'yıldız harika star wow', '😋': 'lezzetli yum lecker', '🥺': 'rica lütfen please bitte',
  '👍': 'tamam beğen like ok daumen', '👎': 'beğenme dislike', '👏': 'alkış clap applaus', '🙏': 'lütfen teşekkür dua pray thanks danke',
  '💪': 'güç kas strong stark', '👋': 'merhaba selam hi hello hallo winken', '👌': 'tamam ok perfekt', '✌️': 'barış zafer peace victory',
  '🤝': 'anlaşma tokalaşma deal handshake', '❤️': 'kalp aşk heart love herz liebe', '💔': 'kırık kalp broken heart',
  '🔥': 'ateş harika fire hot feuer', '✨': 'parıltı sparkle glitzer', '🎉': 'kutlama parti tebrik party congrats',
  '🎂': 'doğum günü pasta birthday cake geburtstag', '🎁': 'hediye gift geschenk', '🌹': 'gül çiçek rose flower blume',
  '☕': 'kahve çay coffee kaffee', '🍕': 'pizza', '🍔': 'hamburger burger', '⚽': 'futbol top football soccer fussball',
  '🐶': 'köpek dog hund', '🐱': 'kedi cat katze', '🐣': 'civciv yumurta chick egg küken', '🐥': 'civciv chick küken',
  '🌞': 'güneş sun sonne', '🌙': 'ay gece moon nacht', '⭐': 'yıldız star stern', '🌈': 'gökkuşağı rainbow regenbogen',
  '💯': 'yüz tam perfect hundred', '✅': 'tamam onay check ok', '❌': 'hayır iptal no cancel nein', '❓': 'soru question frage',
  '💤': 'uyku sleep', '💬': 'mesaj konuşma message chat', '🇹🇷': 'türkiye turkey türkei bayrak flag',
  '🇩🇪': 'almanya germany deutschland', '🇬🇧': 'ingiltere england uk', '🇺🇸': 'amerika usa', '🇦🇿': 'azerbaycan azerbaijan',
  '🚗': 'araba car auto', '✈️': 'uçak plane flugzeug', '🏠': 'ev home haus', '📱': 'telefon phone handy', '💻': 'bilgisayar laptop',
  '🎵': 'müzik nota music musik', '🎶': 'müzik music', '😈': 'şeytan devil', '💀': 'kurukafa skull', '🤡': 'palyaço clown',
};

class JuzzioEmojiPicker extends StatefulWidget {
  final TextEditingController controller;
  final double height;
  final bool isDark;

  const JuzzioEmojiPicker({super.key, required this.controller, this.height = 300, required this.isDark});

  /// Bu oturumda son kullanılanlar (uygulama açıkken korunur)
  static final List<String> recents = <String>[];

  @override
  State<JuzzioEmojiPicker> createState() => _JuzzioEmojiPickerState();
}

class _JuzzioEmojiPickerState extends State<JuzzioEmojiPicker> {
  int _category = JuzzioEmojiPicker.recents.isEmpty ? 1 : 0;
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _insert(String emoji) {
    final ctrl = widget.controller;
    final text = ctrl.text;
    final sel = ctrl.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final next = text.replaceRange(start, end, emoji);
    ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    JuzzioEmojiPicker.recents.remove(emoji);
    JuzzioEmojiPicker.recents.insert(0, emoji);
    if (JuzzioEmojiPicker.recents.length > 32) JuzzioEmojiPicker.recents.removeLast();
  }

  void _backspace() {
    final ctrl = widget.controller;
    final text = ctrl.text;
    if (text.isEmpty) return;
    final sel = ctrl.selection;
    final cursor = sel.isValid ? sel.start : text.length;
    if (cursor <= 0) return;
    final trimmed = _dropLastGrapheme(text.substring(0, cursor));
    ctrl.value = TextEditingValue(
      text: trimmed + text.substring(cursor),
      selection: TextSelection.collapsed(offset: trimmed.length),
    );
  }

  /// Son "görünen karakteri" siler (emoji birleşimleri, ten rengi, bayraklar dahil).
  static String _dropLastGrapheme(String input) {
    final runes = input.runes.toList();
    if (runes.isEmpty) return input;
    bool isJoiner(int r) =>
        r == 0x200D || r == 0xFE0F || r == 0xFE0E || r == 0x20E3 || (r >= 0x1F3FB && r <= 0x1F3FF) ||
        (r >= 0xE0020 && r <= 0xE007F);
    bool isRegional(int r) => r >= 0x1F1E6 && r <= 0x1F1FF;
    // Sondaki birleştirici/değiştiricileri ve bir temel karakteri at
    while (runes.isNotEmpty && isJoiner(runes.last)) {
      runes.removeLast();
    }
    if (runes.isEmpty) return '';
    final last = runes.removeLast();
    if (isRegional(last) && runes.isNotEmpty && isRegional(runes.last)) {
      runes.removeLast();
    }
    // ZWJ ile bağlı önceki parçalar (ör. 👨‍👩‍👧)
    while (runes.isNotEmpty && runes.last == 0x200D) {
      runes.removeLast();
      while (runes.isNotEmpty && isJoiner(runes.last)) {
        runes.removeLast();
      }
      if (runes.isNotEmpty) runes.removeLast();
    }
    return String.fromCharCodes(runes);
  }

  List<String> _visible() {
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      final all = <String>{for (final c in _kCategories) ...c.emojis};
      return all.where((e) => (_kKeywords[e] ?? '').contains(q)).toList();
    }
    if (_category == 0) return List<String>.from(JuzzioEmojiPicker.recents);
    return _kCategories[_category - 1].emojis;
  }

  @override
  Widget build(BuildContext context) {
    final app = JuzzioAppController.instance;
    final bg = widget.isDark ? JuzzioColors.surface141519 : JuzzioColors.surfaceF6F7FA;
    final fg = widget.isDark ? Colors.white : JuzzioColors.ink;
    final emojis = _visible();
    return Container(
      height: widget.height,
      color: bg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 4),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(color: fg, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: app.trEn('Emoji ara', 'Search emoji', 'Emoji suchen'),
                        prefixIcon: const Icon(Icons.search_rounded, size: 19),
                        contentPadding: EdgeInsets.zero,
                        filled: true,
                        fillColor: widget.isDark ? JuzzioColors.surface1E2029 : Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: app.trEn('Sil', 'Delete', 'Löschen'),
                  icon: Icon(Icons.backspace_outlined, color: fg, size: 21),
                  onPressed: _backspace,
                ),
              ],
            ),
          ),
          Expanded(
            child: emojis.isEmpty
                ? Center(
                    child: Text(
                      _category == 0 && _search.text.isEmpty
                          ? app.trEn('Son kullanılan emoji yok', 'No recent emoji', 'Keine zuletzt verwendeten Emojis')
                          : app.trEn('Sonuç bulunamadı', 'No results', 'Keine Ergebnisse'),
                      style: const TextStyle(color: JuzzioColors.slate500),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 44),
                    itemCount: emojis.length,
                    itemBuilder: (_, i) => InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _insert(emojis[i])),
                      child: Center(child: Text(emojis[i], style: juzzioEmojiStyle(27))),
                    ),
                  ),
          ),
          Container(
            height: 44,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: widget.isDark ? Colors.white10 : JuzzioColors.slate200)),
            ),
            child: Row(
              children: [
                for (var i = 0; i <= _kCategories.length; i++)
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() {
                        _category = i;
                        _search.clear();
                      }),
                      child: Tooltip(
                        message: i == 0
                            ? app.trEn('Son kullanılanlar', 'Recent', 'Zuletzt')
                            : app.trEn(_kCategories[i - 1].tr, _kCategories[i - 1].en, _kCategories[i - 1].de),
                        child: Icon(
                          i == 0 ? Icons.access_time_rounded : _kCategories[i - 1].icon,
                          size: 21,
                          color: _category == i && _search.text.isEmpty ? JuzzioColors.blue500 : JuzzioColors.slate500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
