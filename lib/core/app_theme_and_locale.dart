// =============================================================================
// JUZZIO v0.1.0 - Instagram.jpg Beyaz Tema & "Cool!" Buton Tasarım Motoru,
// RBold-İtalic.otf & R-RegularBold.otf Özel Font Altyapısı,
// Cihaz Dilini Otomatik Baz Alan 139+ (142) Dil Çeviri Motoru ve
// Telegram/WhatsApp Seviyesi Modern Görsel Kırpma & Filtre Stüdyosu
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'config.dart';
import 'pq/juzzio_pq.dart';
import 'theme/juzzio_aurora.dart';
import 'theme/juzzio_glass.dart';
import 'theme/juzzio_custom_theme.dart';
import 'theme/juzzio_colors.dart';
import '../l10n/juzzio_inline_catalog.dart';
import '../l10n/juzzio_strings_v030.dart';

class JuzzioLanguageOption {
  final String code;
  final String nativeName;
  final String turkishName;
  final String flag;

  const JuzzioLanguageOption({
    required this.code,
    required this.nativeName,
    required this.turkishName,
    required this.flag,
  });
}

/// 142 Farklı Dünya Dili (139+ Dil Altyapısı)
const List<JuzzioLanguageOption> kJuzzioSupportedLanguages = [
  JuzzioLanguageOption(code: 'tr', nativeName: 'Türkçe', turkishName: 'Türkçe', flag: '🇹🇷'),
  JuzzioLanguageOption(code: 'en', nativeName: 'English', turkishName: 'İngilizce', flag: '🇬🇧'),
  JuzzioLanguageOption(code: 'de', nativeName: 'Deutsch', turkishName: 'Almanca', flag: '🇩🇪'),
  JuzzioLanguageOption(code: 'es', nativeName: 'Español', turkishName: 'İspanyolca', flag: '🇪🇸'),
  JuzzioLanguageOption(code: 'fr', nativeName: 'Français', turkishName: 'Fransızca', flag: '🇫🇷'),
  JuzzioLanguageOption(code: 'ar', nativeName: 'العربية', turkishName: 'Arapça', flag: '🇸🇦'),
  JuzzioLanguageOption(code: 'ru', nativeName: 'Русский', turkishName: 'Rusça', flag: '🇷🇺'),
  JuzzioLanguageOption(code: 'it', nativeName: 'Italiano', turkishName: 'İtalyanca', flag: '🇮🇹'),
  JuzzioLanguageOption(code: 'pt', nativeName: 'Português', turkishName: 'Portekizce', flag: '🇵🇹'),
  JuzzioLanguageOption(code: 'ja', nativeName: '日本語', turkishName: 'Japonca', flag: '🇯🇵'),
  JuzzioLanguageOption(code: 'ko', nativeName: '한국어', turkishName: 'Korece', flag: '🇰🇷'),
  JuzzioLanguageOption(code: 'nl', nativeName: 'Nederlands', turkishName: 'Felemenkçe', flag: '🇳🇱'),
  JuzzioLanguageOption(code: 'zh', nativeName: '中文 (简体)', turkishName: 'Çince (Basitleştirilmiş)', flag: '🇨🇳'),
  JuzzioLanguageOption(code: 'zh-tw', nativeName: '繁體中文', turkishName: 'Çince (Geleneksel)', flag: '🇹🇼'),
  JuzzioLanguageOption(code: 'hi', nativeName: 'हिन्दी', turkishName: 'Hintçe', flag: '🇮🇳'),
  JuzzioLanguageOption(code: 'az', nativeName: 'Azərbaycan dili', turkishName: 'Azerbaycan Türkçesi', flag: '🇦🇿'),
  JuzzioLanguageOption(code: 'kk', nativeName: 'Қазақ тілі', turkishName: 'Kazakça', flag: '🇰🇿'),
  JuzzioLanguageOption(code: 'uz', nativeName: 'Oʻzbekcha', turkishName: 'Özbekçe', flag: '🇺🇿'),
  JuzzioLanguageOption(code: 'tk', nativeName: 'Türkmençe', turkishName: 'Türkmence', flag: '🇹🇲'),
  JuzzioLanguageOption(code: 'ky', nativeName: 'Кыргызча', turkishName: 'Kırgızca', flag: '🇰🇬'),
  JuzzioLanguageOption(code: 'tt', nativeName: 'Татарча', turkishName: 'Tatarca', flag: '🌐'),
  JuzzioLanguageOption(code: 'ug', nativeName: 'ئۇيغۇرچە', turkishName: 'Uygurca', flag: '🌐'),
  JuzzioLanguageOption(code: 'uk', nativeName: 'Українська', turkishName: 'Ukraynaca', flag: '🇺🇦'),
  JuzzioLanguageOption(code: 'pl', nativeName: 'Polski', turkishName: 'Lehçe', flag: '🇵🇱'),
  JuzzioLanguageOption(code: 'ro', nativeName: 'Română', turkishName: 'Rumence', flag: '🇷🇴'),
  JuzzioLanguageOption(code: 'el', nativeName: 'Ελληνικά', turkishName: 'Yunanca', flag: '🇬🇷'),
  JuzzioLanguageOption(code: 'bg', nativeName: 'Български', turkishName: 'Bulgarca', flag: '🇧🇬'),
  JuzzioLanguageOption(code: 'cs', nativeName: 'Čeština', turkishName: 'Çekçe', flag: '🇨🇿'),
  JuzzioLanguageOption(code: 'hu', nativeName: 'Magyar', turkishName: 'Macarca', flag: '🇭🇺'),
  JuzzioLanguageOption(code: 'sv', nativeName: 'Svenska', turkishName: 'İsveççe', flag: '🇸🇪'),
  JuzzioLanguageOption(code: 'no', nativeName: 'Norsk', turkishName: 'Norveççe', flag: '🇳🇴'),
  JuzzioLanguageOption(code: 'da', nativeName: 'Dansk', turkishName: 'Danca', flag: '🇩🇰'),
  JuzzioLanguageOption(code: 'fi', nativeName: 'Suomi', turkishName: 'Fince', flag: '🇫🇮'),
  JuzzioLanguageOption(code: 'is', nativeName: 'Íslenska', turkishName: 'İzlandaca', flag: '🇮🇸'),
  JuzzioLanguageOption(code: 'sr', nativeName: 'Српски', turkishName: 'Sırpça', flag: '🇷🇸'),
  JuzzioLanguageOption(code: 'hr', nativeName: 'Hrvatski', turkishName: 'Hırvatça', flag: '🇭🇷'),
  JuzzioLanguageOption(code: 'bs', nativeName: 'Bosanski', turkishName: 'Boşnakça', flag: '🇧🇦'),
  JuzzioLanguageOption(code: 'sq', nativeName: 'Shqip', turkishName: 'Arnavutça', flag: '🇦🇱'),
  JuzzioLanguageOption(code: 'mk', nativeName: 'Македонски', turkishName: 'Makedonca', flag: '🇲🇰'),
  JuzzioLanguageOption(code: 'sl', nativeName: 'Slovenščina', turkishName: 'Slovence', flag: '🇸🇮'),
  JuzzioLanguageOption(code: 'sk', nativeName: 'Slovenčina', turkishName: 'Slovakça', flag: '🇸🇰'),
  JuzzioLanguageOption(code: 'et', nativeName: 'Eesti', turkishName: 'Estonca', flag: '🇪🇪'),
  JuzzioLanguageOption(code: 'lv', nativeName: 'Latviešu', turkishName: 'Letonca', flag: '🇱🇻'),
  JuzzioLanguageOption(code: 'lt', nativeName: 'Lietuvių', turkishName: 'Litvanca', flag: '🇱🇹'),
  JuzzioLanguageOption(code: 'ka', nativeName: 'ქართული', turkishName: 'Gürcüce', flag: '🇬🇪'),
  JuzzioLanguageOption(code: 'hy', nativeName: 'Հայերեն', turkishName: 'Ermenice', flag: '🇦🇲'),
  JuzzioLanguageOption(code: 'he', nativeName: 'עברית', turkishName: 'İbranice', flag: '🇮🇱'),
  JuzzioLanguageOption(code: 'fa', nativeName: 'فارسی', turkishName: 'Farsça', flag: '🇮🇷'),
  JuzzioLanguageOption(code: 'ur', nativeName: 'اردو', turkishName: 'Urduca', flag: '🇵🇰'),
  JuzzioLanguageOption(code: 'bn', nativeName: 'বাংলা', turkishName: 'Bengalce', flag: '🇧🇩'),
  JuzzioLanguageOption(code: 'pa', nativeName: 'ਪੰਜਾਬੀ', turkishName: 'Pencapça', flag: '🇮🇳'),
  JuzzioLanguageOption(code: 'gu', nativeName: 'ગુજરાતી', turkishName: 'Güceratça', flag: '🇮🇳'),
  JuzzioLanguageOption(code: 'mr', nativeName: 'मराठी', turkishName: 'Marathi', flag: '🇮🇳'),
  JuzzioLanguageOption(code: 'ta', nativeName: 'தமிழ்', turkishName: 'Tamilce', flag: '🇮🇳'),
  JuzzioLanguageOption(code: 'te', nativeName: 'తెలుగు', turkishName: 'Teluguca', flag: '🇮🇳'),
  JuzzioLanguageOption(code: 'kn', nativeName: 'ಕನ್ನಡ', turkishName: 'Kannadaca', flag: '🇮🇳'),
  JuzzioLanguageOption(code: 'ml', nativeName: 'മലയാളം', turkishName: 'Malayalamca', flag: '🇮🇳'),
  JuzzioLanguageOption(code: 'si', nativeName: 'සිංහල', turkishName: 'Seylanca', flag: '🇱🇰'),
  JuzzioLanguageOption(code: 'ne', nativeName: 'नेपाली', turkishName: 'Nepalce', flag: '🇳🇵'),
  JuzzioLanguageOption(code: 'id', nativeName: 'Bahasa Indonesia', turkishName: 'Endonezce', flag: '🇮🇩'),
  JuzzioLanguageOption(code: 'ms', nativeName: 'Bahasa Melayu', turkishName: 'Malayca', flag: '🇲🇾'),
  JuzzioLanguageOption(code: 'vi', nativeName: 'Tiếng Việt', turkishName: 'Vietnamca', flag: '🇻🇳'),
  JuzzioLanguageOption(code: 'th', nativeName: 'ไทย', turkishName: 'Tayca', flag: '🇹🇭'),
  JuzzioLanguageOption(code: 'tl', nativeName: 'Filipino', turkishName: 'Filipince (Tagalog)', flag: '🇵🇭'),
  JuzzioLanguageOption(code: 'my', nativeName: 'မြန်မာစာ', turkishName: 'Birmanca', flag: '🇲🇲'),
  JuzzioLanguageOption(code: 'km', nativeName: 'ភាសាខ្មែរ', turkishName: 'Khmerce', flag: '🇰🇭'),
  JuzzioLanguageOption(code: 'lo', nativeName: 'ລາວ', turkishName: 'Laoca', flag: '🇱🇦'),
  JuzzioLanguageOption(code: 'mn', nativeName: 'Монгол', turkishName: 'Moğolca', flag: '🇲🇳'),
  JuzzioLanguageOption(code: 'sw', nativeName: 'Kiswahili', turkishName: 'Svahili', flag: '🇰🇪'),
  JuzzioLanguageOption(code: 'am', nativeName: 'አማርኛ', turkishName: 'Amharca', flag: '🇪🇹'),
  JuzzioLanguageOption(code: 'ha', nativeName: 'Hausa', turkishName: 'Hausaca', flag: '🇳🇬'),
  JuzzioLanguageOption(code: 'yo', nativeName: 'Yorùbá', turkishName: 'Yorubaca', flag: '🇳🇬'),
  JuzzioLanguageOption(code: 'ig', nativeName: 'Igbo', turkishName: 'İgboca', flag: '🇳🇬'),
  JuzzioLanguageOption(code: 'zu', nativeName: 'isiZulu', turkishName: 'Zuluca', flag: '🇿🇦'),
  JuzzioLanguageOption(code: 'xh', nativeName: 'isiXhosa', turkishName: 'Zosaca', flag: '🇿🇦'),
  JuzzioLanguageOption(code: 'af', nativeName: 'Afrikaans', turkishName: 'Afrikaanca', flag: '🇿🇦'),
  JuzzioLanguageOption(code: 'so', nativeName: 'Soomaali', turkishName: 'Somalice', flag: '🇸🇴'),
  JuzzioLanguageOption(code: 'rw', nativeName: 'Kinyarwanda', turkishName: 'Kinyarwanda', flag: '🇷🇼'),
  JuzzioLanguageOption(code: 'mg', nativeName: 'Malagasy', turkishName: 'Malgaşça', flag: '🇲🇬'),
  JuzzioLanguageOption(code: 'SN', nativeName: 'ChiShona', turkishName: 'Şonaca', flag: '🇿🇼'),
  JuzzioLanguageOption(code: 'ny', nativeName: 'Chichewa', turkishName: 'Çiçevaca', flag: '🇲🇼'),
  JuzzioLanguageOption(code: 'st', nativeName: 'Sesotho', turkishName: 'Sothoca', flag: '🇱🇸'),
  JuzzioLanguageOption(code: 'tn', nativeName: 'Setswana', turkishName: 'Tsvanaca', flag: '🇧🇼'),
  JuzzioLanguageOption(code: 'ts', nativeName: 'Xitsonga', turkishName: 'Tsongaca', flag: '🇿🇦'),
  JuzzioLanguageOption(code: 'ss', nativeName: 'SiSwati', turkishName: 'Swatice', flag: '🇸🇿'),
  JuzzioLanguageOption(code: 've', nativeName: 'Tshivenḓa', turkishName: 'Vendaca', flag: '🇿🇦'),
  JuzzioLanguageOption(code: 'nr', nativeName: 'isiNdebele', turkishName: 'Ndebelece', flag: '🇿🇦'),
  JuzzioLanguageOption(code: 'wo', nativeName: 'Wolof', turkishName: 'Volofça', flag: '🇸🇳'),
  JuzzioLanguageOption(code: 'bm', nativeName: 'Bamanankan', turkishName: 'Bambaraca', flag: '🇲🇱'),
  JuzzioLanguageOption(code: 'ff', nativeName: 'Fulfulde', turkishName: 'Fulani', flag: '🇸🇳'),
  JuzzioLanguageOption(code: 'ln', nativeName: 'Lingála', turkishName: 'Lingala', flag: '🇨🇩'),
  JuzzioLanguageOption(code: 'kg', nativeName: 'Kikongo', turkishName: 'Kongoca', flag: '🇨🇬'),
  JuzzioLanguageOption(code: 'RN', nativeName: 'Ikirundi', turkishName: 'Kirundi', flag: '🇧🇮'),
  JuzzioLanguageOption(code: 'om', nativeName: 'Afaan Oromoo', turkishName: 'Oromca', flag: '🇪🇹'),
  JuzzioLanguageOption(code: 'ti', nativeName: 'ትግርኛ', turkishName: 'Tigrinya', flag: '🇪🇷'),
  JuzzioLanguageOption(code: 'ku', nativeName: 'Kurdî (Kurmancî)', turkishName: 'Kürtçe (Kurmanci)', flag: '🌐'),
  JuzzioLanguageOption(code: 'ckb', nativeName: 'کوردیی ناوەندی', turkishName: 'Kürtçe (Sorani)', flag: '🌐'),
  JuzzioLanguageOption(code: 'ps', nativeName: 'پښتو', turkishName: 'Peştuca', flag: '🇦🇫'),
  JuzzioLanguageOption(code: 'sd', nativeName: 'سنڌي', turkishName: 'Sindhî', flag: '🇵🇰'),
  JuzzioLanguageOption(code: 'tg', nativeName: 'Тоҷикӣ', turkishName: 'Tacikçe', flag: '🇹🇯'),
  JuzzioLanguageOption(code: 'be', nativeName: 'Беларуская', turkishName: 'Belarusça', flag: '🇧🇾'),
  JuzzioLanguageOption(code: 'ca', nativeName: 'Català', turkishName: 'Katalanca', flag: '🇪🇸'),
  JuzzioLanguageOption(code: 'eu', nativeName: 'Euskara', turkishName: 'Baskça', flag: '🇪🇸'),
  JuzzioLanguageOption(code: 'gl', nativeName: 'Galego', turkishName: 'Galiçyaca', flag: '🇪🇸'),
  JuzzioLanguageOption(code: 'cy', nativeName: 'Cymraeg', turkishName: 'Galce', flag: '🏴󠁧󠁢󠁷󠁬󠁳󠁿'),
  JuzzioLanguageOption(code: 'ga', nativeName: 'Gaeilge', turkishName: 'İrlandaca', flag: '🇮🇪'),
  JuzzioLanguageOption(code: 'gd', nativeName: 'Gàidhlig', turkishName: 'İskoç گالcesi', flag: '🏴󠁧󠁢󠁳󠁣󠁴󠁿'),
  JuzzioLanguageOption(code: 'mt', nativeName: 'Malti', turkishName: 'Maltaca', flag: '🇲🇹'),
  JuzzioLanguageOption(code: 'lb', nativeName: 'Lëtzebuergesch', turkishName: 'Lüksemburgca', flag: '🇱🇺'),
  JuzzioLanguageOption(code: 'fy', nativeName: 'Frysk', turkishName: 'Frizce', flag: '🇳🇱'),
  JuzzioLanguageOption(code: 'yi', nativeName: 'ייִדיש', turkishName: 'Yidiş', flag: '🌐'),
  JuzzioLanguageOption(code: 'eo', nativeName: 'Esperanto', turkishName: 'Esperanto', flag: '🌍'),
  JuzzioLanguageOption(code: 'la', nativeName: 'Latina', turkishName: 'Latince', flag: '🇻🇦'),
  JuzzioLanguageOption(code: 'co', nativeName: 'Corsu', turkishName: 'Korsikaca', flag: '🇫🇷'),
  JuzzioLanguageOption(code: 'br', nativeName: 'Brezhoneg', turkishName: 'Bretonca', flag: '🇫🇷'),
  JuzzioLanguageOption(code: 'oc', nativeName: 'Occitan', turkishName: 'Oksitanca', flag: '🇫🇷'),
  JuzzioLanguageOption(code: 'sc', nativeName: 'Sardu', turkishName: 'Sardunyaca', flag: '🇮🇹'),
  JuzzioLanguageOption(code: 'rm', nativeName: 'Rumantsch', turkishName: 'Romanşça', flag: '🇨🇭'),
  JuzzioLanguageOption(code: 'fo', nativeName: 'Føroyskt', turkishName: 'Faroece', flag: '🇫🇴'),
  JuzzioLanguageOption(code: 'kl', nativeName: 'Kalaallisut', turkishName: 'Grönlandca', flag: '🇬🇱'),
  JuzzioLanguageOption(code: 'se', nativeName: 'Davvisámegiella', turkishName: 'Kuzey Samice', flag: '🇳🇴'),
  JuzzioLanguageOption(code: 'jv', nativeName: 'Basa Jawa', turkishName: 'Cavaca', flag: '🇮🇩'),
  JuzzioLanguageOption(code: 'su', nativeName: 'Basa Sunda', turkishName: 'Sundaca', flag: '🇮🇩'),
  JuzzioLanguageOption(code: 'ceb', nativeName: 'Cebuano', turkishName: 'Sebuanca', flag: '🇵🇭'),
  JuzzioLanguageOption(code: 'ilo', nativeName: 'Ilokano', turkishName: 'İlokano', flag: '🇵🇭'),
  JuzzioLanguageOption(code: 'mi', nativeName: 'Te Reo Māori', turkishName: 'Maorice', flag: '🇳🇿'),
  JuzzioLanguageOption(code: 'sm', nativeName: 'Gagana Sāmoa', turkishName: 'Samoaca', flag: '🇼🇸'),
  JuzzioLanguageOption(code: 'to', nativeName: 'Lea Fakatonga', turkishName: 'Tongaca', flag: '🇹🇴'),
  JuzzioLanguageOption(code: 'fj', nativeName: 'Vosa Vakaviti', turkishName: 'Fijice', flag: '🇫🇯'),
  JuzzioLanguageOption(code: 'haw', nativeName: 'ʻŌlelo Hawaiʻi', turkishName: 'Hawaiice', flag: '🇺🇸'),
  JuzzioLanguageOption(code: 'ht', nativeName: 'Kreyòl Ayisyen', turkishName: 'Haiti Kreolü', flag: '🇭🇹'),
  JuzzioLanguageOption(code: 'qu', nativeName: 'Runa Simi', turkishName: 'Keçuvaca', flag: '🇵🇪'),
  JuzzioLanguageOption(code: 'ay', nativeName: 'Aymar Aru', turkishName: 'Aymaraca', flag: '🇧🇴'),
  JuzzioLanguageOption(code: 'gn', nativeName: 'Avañeʼẽ', turkishName: 'Guaranice', flag: '🇵🇾'),
  JuzzioLanguageOption(code: 'as', nativeName: 'অসমীয়া', turkishName: 'Assamca', flag: '🇮🇳'),
  JuzzioLanguageOption(code: 'or', nativeName: 'ଓଡ଼ିଆ', turkishName: 'Odia', flag: '🇮🇳'),
  JuzzioLanguageOption(code: 'mai', nativeName: 'मैथिली', turkishName: 'Maithili', flag: '🇮🇳'),
  JuzzioLanguageOption(code: 'sa', nativeName: 'संस्कृतम्', turkishName: 'Sanskritçe', flag: '🇮🇳'),
  JuzzioLanguageOption(code: 'bo', nativeName: 'བོད་ཡིག', turkishName: 'Tibetçe', flag: '🌐'),
  JuzzioLanguageOption(code: 'dz', nativeName: 'རྫོང་ཁ', turkishName: 'Dzongkha', flag: '🇧🇹'),
  JuzzioLanguageOption(code: 'dv', nativeName: 'ދިވެހި', turkishName: 'Divehi', flag: '🇲🇻'),
  JuzzioLanguageOption(code: 'ba', nativeName: 'Башҡортса', turkishName: 'Başkurtça', flag: '🌐'),
  JuzzioLanguageOption(code: 'cv', nativeName: 'Чӑвашла', turkishName: 'Çuvaşça', flag: '🌐'),
  JuzzioLanguageOption(code: 'ce', nativeName: 'Нохчийн', turkishName: 'Çeçence', flag: '🌐'),
];

class JuzzioChatThemePreset {
  final String id;
  final String nameTr;
  final String nameEn;
  final Color primaryColor;
  final Color secondaryColor;
  final Color incomingDarkColor;

  const JuzzioChatThemePreset({
    required this.id,
    required this.nameTr,
    required this.nameEn,
    required this.primaryColor,
    required this.secondaryColor,
    required this.incomingDarkColor,
  });

  /// Arayüz diline göre tema adı (tr/en yerleşik, diğer diller dil paketinden).
  String get localizedName => JuzzioAppController.instance.translateUiDynamic(nameTr, enText: nameEn);
}

// v0.5 nötr cam: tüm sohbet temaları gri-beyaz tonlarındadır (eski kimlikler korunur)
// v0.8.1: her sohbet temasının gerçek, birbirinden ayrı rengi var (kimlikler korunur)
const List<JuzzioChatThemePreset> kJuzzioChatThemes = [
  JuzzioChatThemePreset(
    id: 'cool_monochrome_white',
    nameTr: 'Cam (Temaya uyumlu, Varsayılan)',
    nameEn: 'Glass (Matches theme, Default)',
    primaryColor: Color(0xFF3A3A40),
    secondaryColor: Color(0xFF8E8E99),
    incomingDarkColor: Color(0xFF1C1C22),
  ),
  JuzzioChatThemePreset(
    id: 'royal_indigo_cobalt',
    nameTr: 'Kobalt İndigo',
    nameEn: 'Cobalt Indigo',
    primaryColor: Color(0xFF3B4BDB),
    secondaryColor: Color(0xFF6D7CFF),
    incomingDarkColor: Color(0xFF161A33),
  ),
  JuzzioChatThemePreset(
    id: 'royal_emerald',
    nameTr: 'Zümrüt',
    nameEn: 'Emerald',
    primaryColor: Color(0xFF059669),
    secondaryColor: Color(0xFF34D399),
    incomingDarkColor: Color(0xFF0E2A22),
  ),
  JuzzioChatThemePreset(
    id: 'ocean_sapphire',
    nameTr: 'Okyanus Safiri',
    nameEn: 'Ocean Sapphire',
    primaryColor: Color(0xFF0369A1),
    secondaryColor: Color(0xFF38BDF8),
    incomingDarkColor: Color(0xFF0D2233),
  ),
  JuzzioChatThemePreset(
    id: 'amethyst_velvet',
    nameTr: 'Ametist Kadife',
    nameEn: 'Amethyst Velvet',
    primaryColor: Color(0xFF7C3AED),
    secondaryColor: Color(0xFFC084FC),
    incomingDarkColor: Color(0xFF231636),
  ),
  JuzzioChatThemePreset(
    id: 'rose_quartz',
    nameTr: 'Gül Kuvars',
    nameEn: 'Rose Quartz',
    primaryColor: Color(0xFFDB2777),
    secondaryColor: Color(0xFFF9A8D4),
    incomingDarkColor: Color(0xFF2E1424),
  ),
  JuzzioChatThemePreset(
    id: 'cyber_cyan',
    nameTr: 'Siber Camgöbeği',
    nameEn: 'Cyber Cyan',
    primaryColor: Color(0xFF0891B2),
    secondaryColor: Color(0xFF22D3EE),
    incomingDarkColor: Color(0xFF0B2830),
  ),
  JuzzioChatThemePreset(
    id: 'nordic_slate',
    nameTr: 'Kuzey Arduvazı',
    nameEn: 'Nordic Slate',
    primaryColor: Color(0xFF475569),
    secondaryColor: Color(0xFF94A3B8),
    incomingDarkColor: Color(0xFF1A2130),
  ),
  JuzzioChatThemePreset(
    id: 'indigo_night',
    nameTr: 'İndigo Gece',
    nameEn: 'Indigo Night',
    primaryColor: Color(0xFF312E81),
    secondaryColor: Color(0xFF818CF8),
    incomingDarkColor: Color(0xFF14132E),
  ),
  JuzzioChatThemePreset(
    id: 'crimson_glow',
    nameTr: 'Kızıl Işıltı',
    nameEn: 'Crimson Glow',
    primaryColor: Color(0xFFBE123C),
    secondaryColor: Color(0xFFFB7185),
    incomingDarkColor: Color(0xFF2E0F18),
  ),
  JuzzioChatThemePreset(
    id: 'liquid_clear',
    nameTr: 'Sıvı Cam · Berrak',
    nameEn: 'Liquid Glass · Clear',
    primaryColor: Color(0xFF9AA4B8),
    secondaryColor: Color(0xFFE6ECF7),
    incomingDarkColor: Color(0xFF1A1D26),
  ),
  JuzzioChatThemePreset(
    id: 'liquid_aqua',
    nameTr: 'Sıvı Cam · Akuamarin',
    nameEn: 'Liquid Glass · Aqua',
    primaryColor: Color(0xFF06B6D4),
    secondaryColor: Color(0xFF67E8F9),
    incomingDarkColor: Color(0xFF0B2530),
  ),
  JuzzioChatThemePreset(
    id: 'liquid_violet',
    nameTr: 'Sıvı Cam · Lavanta',
    nameEn: 'Liquid Glass · Lavender',
    primaryColor: Color(0xFF8B5CF6),
    secondaryColor: Color(0xFFC4B5FD),
    incomingDarkColor: Color(0xFF1F1736),
  ),
  JuzzioChatThemePreset(
    id: 'liquid_rose',
    nameTr: 'Sıvı Cam · Pembe İnci',
    nameEn: 'Liquid Glass · Pearl Pink',
    primaryColor: Color(0xFFEC4899),
    secondaryColor: Color(0xFFFBCFE8),
    incomingDarkColor: Color(0xFF2B1222),
  ),
  JuzzioChatThemePreset(
    id: 'liquid_mint',
    nameTr: 'Sıvı Cam · Nane',
    nameEn: 'Liquid Glass · Mint',
    primaryColor: Color(0xFF10B981),
    secondaryColor: Color(0xFFA7F3D0),
    incomingDarkColor: Color(0xFF0D261E),
  ),
  JuzzioChatThemePreset(
    id: 'liquid_aurora',
    nameTr: 'Sıvı Cam · Kutup Işığı',
    nameEn: 'Liquid Glass · Aurora',
    primaryColor: Color(0xFF6366F1),
    secondaryColor: Color(0xFF5EEAD4),
    incomingDarkColor: Color(0xFF141A30),
  ),
];

class JuzzioAppController extends ChangeNotifier {
  JuzzioAppController._() {
    _initDefaults();
  }
  static final JuzzioAppController instance = JuzzioAppController._();

  /// Gizlilik/bildirim tercihleri kaydedildiğinde Supabase profiline de yansıtılması için
  /// (SupabaseService tarafından atanır; döngüsel bağımlılığı önler).
  static void Function(Map<String, dynamic> prefs)? remotePreferenceSync;
  static List<JuzzioLanguageOption> get supportedLanguages => kJuzzioSupportedLanguages;

  static const MethodChannel _notifChannel = MethodChannel('juzzio/notifications');

  // Tema ve Görünüm: Instagram.jpg Beyaz Tema Varsayılan (ThemeMode.light)
  // v0.5.0: varsayılan Gece Modu (Obsidyen cam tema)
  ThemeMode _themeMode = ThemeMode.dark;
  String _themeSelectionMode = 'dark'; // 'system' | 'light' | 'dark'
  int _selectedChatThemeIndex = 0;
  // v0.6 Glassmorphism: seçili aurora cam teması (boşsa yöneticinin varsayılanı / ilk palet)
  String _glassPaletteId = '';
  bool _reducedEffects = false;
  bool _reducedEffectsUserSet = false;
  // v0.8.4: sohbet teması olarak seçilen uygulama teması ('' → sohbet ön ayarı kullanılır)
  String _chatPaletteId = '';
  double _glassIntensity = 1.0;
  // v0.8.2 Tema Stüdyosu
  List<JuzzioCustomTheme> _customThemes = <JuzzioCustomTheme>[];
  String _activeCustomThemeId = '';
  JuzzioCustomTheme? _previewTheme;
  // v0.8.3 küresel (yönetici yayını) tema
  JuzzioCustomTheme? _globalTheme;
  int _globalThemeVersion = 0;
  bool _followGlobalTheme = false;
  int _darkStartMin = 20 * 60; // 20:00
  int _darkEndMin = 7 * 60; // 07:00
  Timer? _scheduleTimer;
  String _defaultGlassPaletteId = 'juzzio_liquid';
  double _chatThemeIntensity = 1.0;

  // Dil Ayarları (Cihaz Dilini Otomatik Baz Alır, 142 Dili Destekler)
  String _uiLang = 'tr';
  String _subtitleLang = 'tr';
  final Map<String, String> _dynamicUiCache = {};
  final Set<String> _pendingDynamicKeys = {};
  // Cihaz düzeyinde seçilen arayüz dili: giriş/çıkış yapılsa da korunur
  // (ilk sayfadaki dil seçici ile Ayarlar > Dil aynı değeri kullanır).
  String? _deviceUiLang;
  final Set<String> _loadedPackLangs = {};
  final Map<String, Future<bool>> _packJobs = {};
  Timer? _cachePersistDebounce;
  /// Dil paketi hazırlanırken 0.0-1.0 arası ilerleme; null = hazırlanmıyor.
  final ValueNotifier<double?> languagePackProgress = ValueNotifier<double?>(null);
  static const Set<String> kBuiltInUiLangs = {'tr', 'en', 'de'};

  // Sohbet Ayarları
  bool _enterSendsMessage = true;
  bool _mediaVisibility = false;
  String _fontSizeOption = 'medium';
  bool _keepChatsArchived = true;

  // Bildirim & Sessiz Mod
  bool _isSilentMode = false;
  bool _notificationsEnabled = true;
  bool _lockChatEnabled = false;
  bool _securityNotificationsOnDevice = true;

  // Gizlilik Ayarları
  String _lastSeenPrivacy = 'everyone';
  String _onlinePrivacy = 'everyone';
  String _profilePhotoPrivacy = 'everyone';
  String _aboutPrivacy = 'everyone';
  String _statusPrivacy = 'everyone';
  bool _readReceiptsEnabled = true;
  String _defaultMessageTimer = 'off';
  String _whoCanAddMeToGroups = 'everyone';
  bool _silenceUnknownCallers = false;
  bool _syncContactsAcrossDevices = true;
  final List<String> _blockedUsernames = [];

  // Kamera ve Görüntülü Arama Efektleri
  bool _allowCameraEffects = true;
  bool _cameraBeautyEnabled = true;
  String _doubleTapReaction = '❤️‍🔥';
  final List<String> _starredMessageIds = <String>[];

  // Gizlilik -> Gelişmiş Ayarlar
  bool _blockUnknownVolumeMessages = true;
  bool _protectIpInCalls = false;
  bool _disableLinkPreviews = false;
  bool _strictAccountSettings = false;

  // Erişilebilirlik & Sosyal Akış Tercihleri
  bool _highContrastMode = false;
  bool _reduceMotion = false;
  bool _autoplayVideos = true;
  bool _isPrivateAccount = false;
  String _postsPrivacy = 'public';

  // Kategori Bazlı Bildirim Tercihleri (Bölüm 29.7)
  bool _notifyDirectMessages = true;
  bool _notifyGroupMessages = true;
  bool _notifyCalls = true;
  bool _notifyFollows = true;
  bool _notifyLikesComments = true;
  bool _notifyStories = true;
  bool _notifySystem = true;

  // Aktif Kullanıcı Kimliği Bazlı Kalıcı Tercih Yönetimi (Bölüm 6.17 & 29)
  String _activePrefsUserId = 'guest';

  /// v0.8.2: özel tema kendi açık/koyu modunu, zamanlama saat aralığını belirler
  ThemeMode get themeMode {
    final ct = effectiveCustomTheme;
    if (ct != null) return ct.dark ? ThemeMode.dark : ThemeMode.light;
    if (_themeSelectionMode == 'scheduled') return isDark ? ThemeMode.dark : ThemeMode.light;
    return _themeMode;
  }
  String get themeSelectionMode => _themeSelectionMode;

  /// Gece aralığı [start, end) dakika cinsinden; gece yarısını aşan aralıkları destekler.
  static bool isWithinDarkWindow(int nowMin, int startMin, int endMin) {
    final n = nowMin % 1440, a = startMin % 1440, b = endMin % 1440;
    if (a == b) return true;
    return a < b ? (n >= a && n < b) : (n >= a || n < b);
  }

  int get darkStartMinutes => _darkStartMin;
  int get darkEndMinutes => _darkEndMin;
  void setThemeSchedule({int? startMinutes, int? endMinutes}) {
    if (startMinutes != null) _darkStartMin = startMinutes.clamp(0, 1439);
    if (endMinutes != null) _darkEndMin = endMinutes.clamp(0, 1439);
    _persistUserPreferences();
    notifyListeners();
  }

  bool _lastScheduledDark = true;
  void _syncScheduleTimer() {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    if (_themeSelectionMode != 'scheduled') return;
    _lastScheduledDark = isDark;
    _scheduleTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final d = isDark;
      if (d != _lastScheduledDark) {
        _lastScheduledDark = d;
        notifyListeners();
      }
    });
  }

  /// Sistem görünümü / erişilebilirlik ayarı değişince (main.dart gözlemcisi çağırır)
  void onSystemAppearanceChanged() => notifyListeners();

  bool get isDark {
    final ct = effectiveCustomTheme;
    if (ct != null) return ct.dark;
    if (_themeSelectionMode == 'scheduled') {
      final now = DateTime.now();
      return isWithinDarkWindow(now.hour * 60 + now.minute, _darkStartMin, _darkEndMin);
    }
    if (_themeSelectionMode == 'system') {
      final brightness = ui.PlatformDispatcher.instance.platformBrightness;
      return brightness == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  int get selectedChatThemeIndex => _selectedChatThemeIndex;
  JuzzioChatThemePreset get currentChatTheme =>
      kJuzzioChatThemes[_selectedChatThemeIndex.clamp(0, kJuzzioChatThemes.length - 1)];
  double get chatThemeIntensity => _chatThemeIntensity;

  String get uiLang => _uiLang;
  String get subtitleLang => _subtitleLang;

  bool get enterSendsMessage => _enterSendsMessage;
  bool get mediaVisibility => _mediaVisibility;
  String get fontSizeOption => _fontSizeOption;
  double get messageFontScale =>
      _fontSizeOption == 'small' ? 0.90 : (_fontSizeOption == 'large' ? 1.15 : 1.0);
  bool get keepChatsArchived => _keepChatsArchived;

  bool get isSilentMode => _isSilentMode;
  bool get notificationsEnabled => _notificationsEnabled;
  bool get lockChatEnabled => _lockChatEnabled;
  bool get securityNotificationsOnDevice => _securityNotificationsOnDevice;

  String get lastSeenPrivacy => _lastSeenPrivacy;
  String get onlinePrivacy => _onlinePrivacy;
  String get profilePhotoPrivacy => _profilePhotoPrivacy;
  String get aboutPrivacy => _aboutPrivacy;
  String get statusPrivacy => _statusPrivacy;
  bool get readReceiptsEnabled => _readReceiptsEnabled;
  String get defaultMessageTimer => _defaultMessageTimer;
  String get whoCanAddMeToGroups => _whoCanAddMeToGroups;
  bool get silenceUnknownCallers => _silenceUnknownCallers;
  bool get syncContactsAcrossDevices => _syncContactsAcrossDevices;
  List<String> get blockedUsernames => List.unmodifiable(_blockedUsernames);

  bool get allowCameraEffects => _allowCameraEffects;
  bool get cameraBeautyEnabled => _cameraBeautyEnabled;

  /// Mesaja çift dokununca bırakılan tepki (❤️‍🔥 veya 🌸)
  String get doubleTapReaction => _doubleTapReaction;

  /// Yıldızlı mesajlar (cihazda saklanır)
  bool isMessageStarred(String id) => _starredMessageIds.contains(id);
  List<String> get starredMessageIds => List.unmodifiable(_starredMessageIds);

  bool get blockUnknownVolumeMessages => _blockUnknownVolumeMessages;
  bool get protectIpInCalls => _protectIpInCalls;
  bool get disableLinkPreviews => _disableLinkPreviews;
  bool get strictAccountSettings => _strictAccountSettings;

  bool get highContrastMode => _highContrastMode;
  bool get reduceMotion => _reduceMotion;
  bool get autoplayVideos => _autoplayVideos && !_reduceMotion;
  bool get isPrivateAccount => _isPrivateAccount;
  String get postsPrivacy => _postsPrivacy;

  bool get notifyDirectMessages => _notifyDirectMessages;
  bool get notifyGroupMessages => _notifyGroupMessages;
  bool get notifyCalls => _notifyCalls;
  bool get notifyFollows => _notifyFollows;
  bool get notifyLikesComments => _notifyLikesComments;
  bool get notifyStories => _notifyStories;
  bool get notifySystem => _notifySystem;

  bool get canViewOthersLastSeenAndOnline => _lastSeenPrivacy != 'nobody';

  String t(String key) => JuzzioStrings(_uiLang).t(key);

  /// Cihazın dilini otomatik algılar (örn. tr -> Türkçe, en -> İngilizce, de -> Almanca ve 142 dil)
  void _initDefaults() {
    try {
      final locale = ui.PlatformDispatcher.instance.locale;
      final sysCode = locale.languageCode.toLowerCase();
      final supported = kJuzzioSupportedLanguages.any((l) => l.code.toLowerCase() == sysCode);
      final chosen = supported ? sysCode : 'en';
      _uiLang = chosen;
      _subtitleLang = chosen;
    } catch (_) {
      _uiLang = 'tr';
      _subtitleLang = 'tr';
    }
    _bootstrapLanguage();
  }

  Future<void> _bootstrapLanguage() async {
    await _loadDeviceUiLang();
    await loadUserPreferences('guest');
    if (!kBuiltInUiLangs.contains(_uiLang)) {
      // Dil paketi daha önce indirildiyse diskten anında yüklenir; yoksa arka planda hazırlanır.
      unawaited(prepareLanguagePack(_uiLang));
    }
  }

  Future<File> _deviceLangFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/juzzio_device_lang.json');
  }

  Future<void> _loadDeviceUiLang() async {
    try {
      final f = await _deviceLangFile();
      if (!f.existsSync()) return;
      final raw = jsonDecode(await f.readAsString());
      if (raw is Map && raw['uiLang'] is String && (raw['uiLang'] as String).trim().isNotEmpty) {
        _deviceUiLang = (raw['uiLang'] as String).trim().toLowerCase();
        _uiLang = _deviceUiLang!;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _saveDeviceUiLang(String code) async {
    _deviceUiLang = code;
    try {
      final f = await _deviceLangFile();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({'uiLang': code}));
      await tmp.rename(f.path);
    } catch (_) {}
  }

  Future<File> _packFile(String code) async {
    final dir = await getApplicationSupportDirectory();
    final safe = code.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File('${dir.path}/juzzio_lang_pack_$safe.json');
  }

  Future<void> _loadPackFromDisk(String code) async {
    if (_loadedPackLangs.contains(code)) return;
    try {
      final f = await _packFile(code);
      if (!f.existsSync()) return;
      final raw = jsonDecode(await f.readAsString());
      if (raw is Map) {
        raw.forEach((k, v) {
          if (k is String && v is String && v.isNotEmpty) _dynamicUiCache['$code|$k'] = v;
        });
        _loadedPackLangs.add(code);
      }
    } catch (_) {}
  }

  void _schedulePackPersist(String code) {
    _cachePersistDebounce?.cancel();
    _cachePersistDebounce = Timer(const Duration(seconds: 2), () => _persistPack(code));
  }

  Future<void> _persistPack(String code) async {
    try {
      final prefix = '$code|';
      final out = <String, String>{};
      _dynamicUiCache.forEach((k, v) {
        if (k.startsWith(prefix)) out[k.substring(prefix.length)] = v;
      });
      if (out.isEmpty) return;
      final f = await _packFile(code);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(out));
      await tmp.rename(f.path);
    } catch (_) {}
  }

  /// Seçilen dil için tüm arayüz metinlerini (anahtarlı katalog) tek seferde çevirip
  /// diske kaydeder. Başarılıysa true döner. İnternet yoksa ve paket daha önce
  /// indirilmemişse false döner; bu durumda dil DEĞİŞTİRİLMEZ (karışık dil oluşmaz).
  Future<bool> prepareLanguagePack(String code) {
    final lang = code.trim().toLowerCase();
    if (lang.isEmpty || kBuiltInUiLangs.contains(lang)) return Future.value(true);
    // Aynı dil için eşzamanlı ikinci istek, devam eden indirmeyi bekler.
    return _packJobs[lang] ??= _preparePackImpl(lang).whenComplete(() => _packJobs.remove(lang));
  }

  Future<bool> _preparePackImpl(String lang) async {
    languagePackProgress.value = 0;
    await _loadPackFromDisk(lang);
    if (lang == _uiLang) notifyListeners();
    final catalog = JuzzioStrings.englishCatalog();
    final missing = catalog.where((en) => !_dynamicUiCache.containsKey('$lang|$en')).toList();
    if (missing.isEmpty) {
      languagePackProgress.value = null;
      return true;
    }
    final alreadyHad = catalog.length - missing.length;
    languagePackProgress.value = alreadyHad / catalog.length;
    var done = 0;
    var ok = 0;
    // Çok satırlı olmayan metinler 20'şerli paketlerle (tek istekte, satır satır) çevrilir;
    // satır sayısı tutmazsa paket tek tek çevrilir.
    final batches = <List<String>>[];
    var current = <String>[];
    for (final en in missing) {
      if (en.contains('\n')) {
        batches.add([en]);
        continue;
      }
      current.add(en);
      if (current.length == 20) {
        batches.add(current);
        current = <String>[];
      }
    }
    if (current.isNotEmpty) batches.add(current);
    var cursor = 0;
    var consecutiveFailures = 0;
    Future<void> worker() async {
      while (true) {
        // Ağ tamamen koptuysa boşuna beklenmez; kalan metinler sonraki açılışta tamamlanır.
        if (cursor >= batches.length || consecutiveFailures >= 6) return;
        final batch = batches[cursor++];
        var results = batch.length > 1 ? await _translateBatch(batch, lang) : null;
        if (results == null && batch.length > 1) {
          // Toplu çeviri satır sayısını tutturamadıysa kısa zaman aşımıyla tek tek denenir
          results = await Future.wait(batch.map((en) => _translateProtected(en, lang, timeout: const Duration(seconds: 4))));
        }
        results ??= [await _translateProtected(batch.first, lang)];
        var batchOk = 0;
        for (var i = 0; i < batch.length; i++) {
          done++;
          final res = results[i];
          if (res != null) {
            _dynamicUiCache['$lang|${batch[i]}'] = res;
            ok++;
            batchOk++;
          }
        }
        consecutiveFailures = batchOk == 0 ? consecutiveFailures + 1 : 0;
        languagePackProgress.value = (alreadyHad + done) / catalog.length;
        if (lang == _uiLang) notifyListeners();
      }
    }
    await Future.wait(List.generate(6, (_) => worker()));
    languagePackProgress.value = null;
    await _persistPack(lang);
    if (ok > 0) _loadedPackLangs.add(lang);
    if (lang == _uiLang) notifyListeners();
    // Paketin en az %90'ı hazır değilse dil geçişi yapılmaz.
    return (alreadyHad + ok) >= (catalog.length * 0.9);
  }

  /// Birden çok tek satırlık metni tek istekte çevirir. Satır sayısı ya da yer
  /// tutucular tutmazsa null döner (çağıran taraf tek tek çevirir).
  Future<List<String?>?> _translateBatch(List<String> sources, String lang) async {
    final out = await _translateProtected(sources.join('\n'), lang, timeout: const Duration(seconds: 8));
    if (out == null) return null;
    final lines = out.split('\n').map((l) => l.trim()).toList();
    if (lines.length != sources.length) return null;
    return lines.map<String?>((l) => l.isEmpty ? null : l).toList();
  }

  /// {name} gibi yer tutucuları makine çevirisinden korur; çeviri yer tutucuları
  /// bozarsa null döner (İngilizce kaynak kullanılır).
  Future<String?> _translateProtected(String source, String lang, {Duration timeout = const Duration(seconds: 6)}) async {
    final holders = RegExp(r'\{[a-zA-Z_]+\}').allMatches(source).map((m) => m.group(0)!).toList();
    var masked = source;
    for (var i = 0; i < holders.length; i++) {
      masked = masked.replaceFirst(holders[i], '__${i}__');
    }
    try {
      final uri = Uri.parse(
        'https://translate.googleapis.com/translate_a/single'
        '?client=gtx&sl=en&tl=$lang&dt=t&q=${Uri.encodeComponent(masked)}',
      );
      final res = await http.get(uri).timeout(timeout);
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! List || decoded.isEmpty || decoded[0] is! List) return null;
      final buf = StringBuffer();
      for (final seg in decoded[0] as List) {
        if (seg is List && seg.isNotEmpty && seg[0] != null) buf.write(seg[0].toString());
      }
      var out = buf.toString().trim();
      if (out.isEmpty) return null;
      for (var i = 0; i < holders.length; i++) {
        final token = RegExp('_\\s*_\\s*$i\\s*_\\s*_');
        if (!token.hasMatch(out)) return null;
        out = out.replaceFirst(token, holders[i]);
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<File> _prefsFileForUser(String uid) async {
    final dir = await getApplicationSupportDirectory();
    final safeUid = uid.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File('${dir.path}/juzzio_prefs_$safeUid.json');
  }

  Future<void> loadUserPreferences(String? userId) async {
    final uid = (userId == null || userId.trim().isEmpty) ? 'guest' : userId.trim();
    _activePrefsUserId = uid;
    try {
      final f = await _prefsFileForUser(uid);
      if (!f.existsSync()) {
        // v0.7.0: yeni kullanıcı → yöneticinin varsayılan cam teması YALNIZCA ilk açılışta uygulanır
        _isFreshPrefsUser = true;
        _glassPaletteId = '';
        _reducedEffects = false;
        JuzzioGlassTokens.reducedEffects = false;
        _glassIntensity = 1.0;
        JuzzioGlassTokens.intensity = 1.0;
        _customThemes = <JuzzioCustomTheme>[];
        _activeCustomThemeId = '';
        _previewTheme = null;
        // yeni kullanıcı tema seçene kadar yöneticinin yayınladığı temayı görür
        _followGlobalTheme = true;
        _syncCustomTokens();
        return;
      }
      _isFreshPrefsUser = false;
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map) return;
      // v0.5.0'a ilk geçişte herkes Gece Modu ile başlar; sonra kullanıcının seçimi korunur
      _themeSelectionMode = raw['themeV5'] == true
          ? (raw['themeSelectionMode'] ?? _themeSelectionMode).toString()
          : 'dark';
      if (_themeSelectionMode == 'dark') {
        _themeMode = ThemeMode.dark;
      } else if (_themeSelectionMode == 'light') {
        _themeMode = ThemeMode.light;
      } else {
        if (_themeSelectionMode != 'system' && _themeSelectionMode != 'scheduled') _themeSelectionMode = 'dark';
        _themeMode = _themeSelectionMode == 'dark' ? ThemeMode.dark : ThemeMode.system;
      }
      _syncScheduleTimer();
      _selectedChatThemeIndex = ((raw['selectedChatThemeIndex'] as num?)?.toInt() ?? _selectedChatThemeIndex).clamp(0, kJuzzioChatThemes.length - 1);
      _chatThemeIntensity = ((raw['chatThemeIntensity'] as num?)?.toDouble() ?? _chatThemeIntensity).clamp(0.6, 1.4);
      _glassPaletteId = (raw['glassPalette'] ?? '').toString();
      final cp = (raw['chatPalette'] ?? '').toString();
      _chatPaletteId = kJuzzioAuroraPalettes.any((p) => p.id == cp) ? cp : '';
      _reducedEffects = raw['reducedEffects'] == true;
      JuzzioGlassTokens.reducedEffects = _reducedEffects;
      final gi = raw['glassIntensity'];
      _glassIntensity = (gi is num && gi.isFinite) ? gi.toDouble().clamp(0.6, 1.4) : 1.0;
      JuzzioGlassTokens.intensity = _glassIntensity;
      _reducedEffectsUserSet = raw['reducedEffectsUserSet'] == true;
      final ctList = raw['customThemes'];
      _customThemes = <JuzzioCustomTheme>[
        if (ctList is List)
          for (final e in ctList.take(maxCustomThemes))
            if (JuzzioCustomTheme.fromStored(e) case final t?) t,
      ];
      final act = (raw['activeCustomTheme'] ?? '').toString();
      _activeCustomThemeId = _customThemes.any((t) => t.id == act) ? act : '';
      _previewTheme = null;
      final sch = raw['themeSchedule'];
      if (sch is Map) {
        final a = sch['start'], b = sch['end'];
        if (a is int) _darkStartMin = a.clamp(0, 1439);
        if (b is int) _darkEndMin = b.clamp(0, 1439);
      }
      _followGlobalTheme = raw['followGlobalTheme'] == true;
      final gc = raw['globalThemeCache'];
      if (gc is Map && gc['payload'] is Map) {
        _globalThemeVersion = (gc['version'] as num?)?.toInt() ?? 0;
        _globalTheme = JuzzioCustomTheme.fromMap(Map<String, dynamic>.from(gc['payload'] as Map),
                newId: 'global_v$_globalThemeVersion')
            .theme;
      }
      _syncCustomTokens();
      // Mevcut kullanıcılar yönetici değişikliğinden etkilenmez: seçim yoksa kendi
      // görmekte olduğu temaya sabitlenir.
      if (_glassPaletteId.isEmpty) _glassPaletteId = kJuzzioAuroraPalettes.first.id;
      _uiLang = _deviceUiLang ?? (raw['uiLang'] ?? _uiLang).toString();
      _subtitleLang = (raw['subtitleLang'] ?? _subtitleLang).toString();
      _enterSendsMessage = raw['enterSendsMessage'] is bool ? raw['enterSendsMessage'] as bool : _enterSendsMessage;
      _mediaVisibility = raw['mediaVisibility'] is bool ? raw['mediaVisibility'] as bool : _mediaVisibility;
      _fontSizeOption = (raw['fontSizeOption'] ?? _fontSizeOption).toString();
      _keepChatsArchived = raw['keepChatsArchived'] is bool ? raw['keepChatsArchived'] as bool : _keepChatsArchived;
      _isSilentMode = raw['isSilentMode'] is bool ? raw['isSilentMode'] as bool : _isSilentMode;
      _notificationsEnabled = raw['notificationsEnabled'] is bool ? raw['notificationsEnabled'] as bool : _notificationsEnabled;
      _lockChatEnabled = raw['lockChatEnabled'] is bool ? raw['lockChatEnabled'] as bool : _lockChatEnabled;
      _securityNotificationsOnDevice = raw['securityNotificationsOnDevice'] is bool ? raw['securityNotificationsOnDevice'] as bool : _securityNotificationsOnDevice;
      _lastSeenPrivacy = (raw['lastSeenPrivacy'] ?? _lastSeenPrivacy).toString();
      _onlinePrivacy = (raw['onlinePrivacy'] ?? _onlinePrivacy).toString();
      _profilePhotoPrivacy = (raw['profilePhotoPrivacy'] ?? _profilePhotoPrivacy).toString();
      _aboutPrivacy = (raw['aboutPrivacy'] ?? _aboutPrivacy).toString();
      _statusPrivacy = (raw['statusPrivacy'] ?? _statusPrivacy).toString();
      _postsPrivacy = (raw['postsPrivacy'] ?? _postsPrivacy).toString();
      _isPrivateAccount = raw['isPrivateAccount'] == true;
      _readReceiptsEnabled = raw['readReceiptsEnabled'] is bool ? raw['readReceiptsEnabled'] as bool : _readReceiptsEnabled;
      _defaultMessageTimer = (raw['defaultMessageTimer'] ?? _defaultMessageTimer).toString();
      _whoCanAddMeToGroups = (raw['whoCanAddMeToGroups'] ?? _whoCanAddMeToGroups).toString();
      _silenceUnknownCallers = raw['silenceUnknownCallers'] == true;
      _syncContactsAcrossDevices = raw['syncContactsAcrossDevices'] is bool ? raw['syncContactsAcrossDevices'] as bool : _syncContactsAcrossDevices;
      _allowCameraEffects = raw['allowCameraEffects'] is bool ? raw['allowCameraEffects'] as bool : _allowCameraEffects;
      _cameraBeautyEnabled = raw['cameraBeautyEnabled'] is bool ? raw['cameraBeautyEnabled'] as bool : _cameraBeautyEnabled;
      final dtr = raw['doubleTapReaction']?.toString() ?? '';
      if (dtr.isNotEmpty) _doubleTapReaction = dtr;
      final starred = raw['starredMessageIds'];
      if (starred is List) {
        _starredMessageIds
          ..clear()
          ..addAll(starred.map((e) => e.toString()));
      }
      _blockUnknownVolumeMessages = raw['blockUnknownVolumeMessages'] is bool ? raw['blockUnknownVolumeMessages'] as bool : _blockUnknownVolumeMessages;
      _protectIpInCalls = raw['protectIpInCalls'] == true;
      _disableLinkPreviews = raw['disableLinkPreviews'] == true;
      _strictAccountSettings = raw['strictAccountSettings'] == true;
      _highContrastMode = raw['highContrastMode'] == true;
      _reduceMotion = raw['reduceMotion'] == true;
      _autoplayVideos = raw['autoplayVideos'] is bool ? raw['autoplayVideos'] as bool : _autoplayVideos;
      _notifyDirectMessages = raw['notifyDirectMessages'] is bool ? raw['notifyDirectMessages'] as bool : _notifyDirectMessages;
      _notifyGroupMessages = raw['notifyGroupMessages'] is bool ? raw['notifyGroupMessages'] as bool : _notifyGroupMessages;
      _notifyCalls = raw['notifyCalls'] is bool ? raw['notifyCalls'] as bool : _notifyCalls;
      _notifyFollows = raw['notifyFollows'] is bool ? raw['notifyFollows'] as bool : _notifyFollows;
      _notifyLikesComments = raw['notifyLikesComments'] is bool ? raw['notifyLikesComments'] as bool : _notifyLikesComments;
      _notifyStories = raw['notifyStories'] is bool ? raw['notifyStories'] as bool : _notifyStories;
      _notifySystem = raw['notifySystem'] is bool ? raw['notifySystem'] as bool : _notifySystem;
      if (raw['blockedUsernames'] is List) {
        _blockedUsernames
          ..clear()
          ..addAll((raw['blockedUsernames'] as List).map((e) => e.toString()).where((s) => s.isNotEmpty));
      }
      notifyListeners();
    } catch (_) {}
  }

  /// v0.8.0: Google Drive yedeğinden ayarları geri yükler (tema, gizlilik, yıldızlı mesajlar...).
  Future<void> restorePreferencesSnapshot(Map<String, dynamic> snapshot) async {
    try {
      final f = await _prefsFileForUser(_activePrefsUserId);
      await f.writeAsString(jsonEncode(snapshot));
      await loadUserPreferences(_activePrefsUserId);
      _persistUserPreferences();
    } catch (_) {}
  }

  Future<void> _persistUserPreferences() async {
    try {
      final f = await _prefsFileForUser(_activePrefsUserId);
      final map = preferencesSnapshot();
      await f.writeAsString(jsonEncode(map));
      remotePreferenceSync?.call(map);
    } catch (_) {}
  }

  /// Mevcut tercihlerin anlık görüntüsü (sunucu senkronu için temel değer olarak da kullanılır).
  Map<String, dynamic> preferencesSnapshot() {
    return <String, dynamic>{
        'themeSelectionMode': _themeSelectionMode,
        'themeV5': true,
        'selectedChatThemeIndex': _selectedChatThemeIndex,
        'chatThemeIntensity': _chatThemeIntensity,
        'glassPalette': _glassPaletteId,
        'chatPalette': _chatPaletteId,
        'reducedEffects': _reducedEffects,
        if (_reducedEffectsUserSet) 'reducedEffectsUserSet': true,
        'glassIntensity': _glassIntensity,
        'customThemes': _customThemes.map((t) => t.toJson()).toList(),
        'activeCustomTheme': _activeCustomThemeId,
        'themeSchedule': {'start': _darkStartMin, 'end': _darkEndMin},
        'followGlobalTheme': _followGlobalTheme,
        if (_globalTheme != null) 'globalThemeCache': {'version': _globalThemeVersion, 'payload': _globalTheme!.toJson()},
        'uiLang': _uiLang,
        'subtitleLang': _subtitleLang,
        'enterSendsMessage': _enterSendsMessage,
        'mediaVisibility': _mediaVisibility,
        'fontSizeOption': _fontSizeOption,
        'keepChatsArchived': _keepChatsArchived,
        'isSilentMode': _isSilentMode,
        'notificationsEnabled': _notificationsEnabled,
        'lockChatEnabled': _lockChatEnabled,
        'securityNotificationsOnDevice': _securityNotificationsOnDevice,
        'lastSeenPrivacy': _lastSeenPrivacy,
        'onlinePrivacy': _onlinePrivacy,
        'profilePhotoPrivacy': _profilePhotoPrivacy,
        'aboutPrivacy': _aboutPrivacy,
        'statusPrivacy': _statusPrivacy,
        'postsPrivacy': _postsPrivacy,
        'isPrivateAccount': _isPrivateAccount,
        'readReceiptsEnabled': _readReceiptsEnabled,
        'defaultMessageTimer': _defaultMessageTimer,
        'whoCanAddMeToGroups': _whoCanAddMeToGroups,
        'silenceUnknownCallers': _silenceUnknownCallers,
        'syncContactsAcrossDevices': _syncContactsAcrossDevices,
        'blockedUsernames': _blockedUsernames,
        'allowCameraEffects': _allowCameraEffects,
        'cameraBeautyEnabled': _cameraBeautyEnabled,
        'doubleTapReaction': _doubleTapReaction,
        'starredMessageIds': _starredMessageIds,
        'blockUnknownVolumeMessages': _blockUnknownVolumeMessages,
        'protectIpInCalls': _protectIpInCalls,
        'disableLinkPreviews': _disableLinkPreviews,
        'strictAccountSettings': _strictAccountSettings,
        'highContrastMode': _highContrastMode,
        'reduceMotion': _reduceMotion,
        'autoplayVideos': _autoplayVideos,
        'notifyDirectMessages': _notifyDirectMessages,
        'notifyGroupMessages': _notifyGroupMessages,
        'notifyCalls': _notifyCalls,
        'notifyFollows': _notifyFollows,
        'notifyLikesComments': _notifyLikesComments,
        'notifyStories': _notifyStories,
        'notifySystem': _notifySystem,
    };
  }

  /// Dinamik 139+ dil çevirisi (Sözlükte olmayan diller için arka planda çevirip önbelleğe alır)
  String translateUiDynamic(String trText, {String? enText, String? deText}) {
    final code = _uiLang.toLowerCase();
    if (code == 'tr') return trText;
    final enVal = enText ?? _enSettingsMap[trText] ?? trText;
    if (code == 'en') return enVal;
    if (code == 'de') {
      if (deText != null && deText.isNotEmpty) return deText;
      if (_deSettingsMap.containsKey(trText)) return _deSettingsMap[trText]!;
      if (_deSettingsMap.containsKey(enVal)) return _deSettingsMap[enVal]!;
    }
    final cacheKey = '$code|$enVal';
    final cached = _dynamicUiCache[cacheKey];
    if (cached != null) return cached;

    if (!_pendingDynamicKeys.contains(cacheKey)) {
      _pendingDynamicKeys.add(cacheKey);
      _fetchDynamicUiTranslation(enVal, code, cacheKey);
    }
    return enVal;
  }

  Future<void> _fetchDynamicUiTranslation(String sourceText, String targetLang, String cacheKey) async {
    final out = await _translateProtected(sourceText, targetLang);
    if (out == null) {
      // Bir sonraki görüntülemede yeniden denenebilsin.
      _pendingDynamicKeys.remove(cacheKey);
      return;
    }
    _dynamicUiCache[cacheKey] = out;
    _schedulePackPersist(targetLang);
    notifyListeners();
  }


  /// Hem 1 parametreli `_app.loc('Şifre Değiştir')` hem de 2/3 parametreli
  /// `_app.loc('Canlı Çeviri Geçmişi', 'Live Translation History')` çağrılarını
  /// 142 dilin tamamında hatasız destekler! (push.txt içindeki 14 hatayı kesin çözer)
  String loc(String keyOrTr, [String? enFallback, String? deFallback]) {
    return translateUiDynamic(keyOrTr, enText: enFallback, deText: deFallback);
  }

  String trEn(String trText, String enText, [String? deText]) {
    return translateUiDynamic(trText, enText: enText, deText: deText);
  }

  void toggleThemeMode() {
    if (isDark) {
      setThemeSelectionMode('light');
    } else {
      setThemeSelectionMode('dark');
    }
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    _themeSelectionMode = mode == ThemeMode.dark
        ? 'dark'
        : (mode == ThemeMode.light ? 'light' : 'system');
    _persistUserPreferences();
    notifyListeners();
  }

  void setThemeSelectionMode(String mode) {
    if (!const {'light', 'dark', 'system', 'scheduled'}.contains(mode)) mode = 'dark';
    _themeSelectionMode = mode;
    if (mode == 'scheduled') {
      _themeMode = ThemeMode.system;
    } else if (mode == 'dark') {
      _themeMode = ThemeMode.dark;
    } else if (mode == 'light') {
      _themeMode = ThemeMode.light;
    } else {
      _themeMode = ThemeMode.system;
    }
    _syncScheduleTimer();
    _persistUserPreferences();
    notifyListeners();
  }

  String get glassPaletteId => _glassPaletteId.isEmpty ? _defaultGlassPaletteId : _glassPaletteId;
  JuzzioAuroraPalette get glassPalette =>
      effectiveCustomTheme?.toPalette() ?? juzzioAuroraPaletteById(glassPaletteId);

  // ---------------------------------------------------------------------------
  // v0.8.2 TEMA STÜDYOSU (yerel, kullanıcı başına; Drive yedeğine dahil)
  // ---------------------------------------------------------------------------
  static const int maxCustomThemes = 30;
  List<JuzzioCustomTheme> get customThemes => List.unmodifiable(_customThemes);
  String get activeCustomThemeId => _activeCustomThemeId;
  JuzzioCustomTheme? get activeCustomTheme {
    for (final t in _customThemes) {
      if (t.id == _activeCustomThemeId) return t;
    }
    return null;
  }

  /// Önizleme (düzenleme) sırasında taslak, aksi halde etkin özel tema
  /// Öncelik: önizleme › kullanıcının özel teması › (kullanıcı tema seçmediyse) küresel tema.
  /// Kendi temasını seçmiş kullanıcıyı yönetici yayını asla etkilemez.
  JuzzioCustomTheme? get effectiveCustomTheme =>
      _previewTheme ?? activeCustomTheme ?? (_followGlobalTheme ? _globalTheme : null);

  bool get followGlobalTheme => _followGlobalTheme;
  JuzzioCustomTheme? get globalTheme => _globalTheme;
  int get globalThemeVersion => _globalThemeVersion;

  /// "Juzzio'nun önerdiği temayı kullan" (kullanıcı seçimi; kalıcı)
  void setFollowGlobalTheme(bool v) {
    _followGlobalTheme = v;
    if (v) {
      _activeCustomThemeId = '';
      _previewTheme = null;
    }
    _syncCustomTokens();
    _persistUserPreferences();
    notifyListeners();
  }

  /// Sunucudaki geçerli küresel tema (get_active_global_theme). null → yayın yok.
  void setGlobalThemeFromServer(Map<String, dynamic>? row) {
    JuzzioCustomTheme? next;
    var ver = 0;
    if (row != null && row['payload'] is Map) {
      ver = (row['version'] as num?)?.toInt() ?? 0;
      next = JuzzioCustomTheme.fromMap(Map<String, dynamic>.from(row['payload'] as Map), newId: 'global_v$ver').theme;
    }
    if (ver == _globalThemeVersion && (next == null) == (_globalTheme == null)) return;
    _globalTheme = next;
    _globalThemeVersion = next == null ? 0 : ver;
    _syncCustomTokens();
    _persistUserPreferences();
    notifyListeners();
  }
  bool get isPreviewingTheme => _previewTheme != null;

  void _syncCustomTokens() {
    JuzzioGlassTokens.custom = effectiveCustomTheme;
  }

  String newCustomThemeId() {
    final r = math.Random.secure();
    return 'ct_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${r.nextInt(1 << 20).toRadixString(36)}';
  }

  String _uniqueName(String base, {String? exceptId}) {
    var name = JuzzioCustomTheme.sanitizeName(base);
    final taken = _customThemes.where((t) => t.id != exceptId).map((t) => t.name.toLowerCase()).toSet();
    if (!taken.contains(name.toLowerCase())) return name;
    for (var i = 2; i < 999; i++) {
      final n = JuzzioCustomTheme.sanitizeName('$name ($i)');
      if (!taken.contains(n.toLowerCase())) return n;
    }
    return name;
  }

  /// Şu anki görünümden yeni tema taslağı (kaydedilmez)
  JuzzioCustomTheme draftFromCurrent() => JuzzioCustomTheme.fromPalette(
        id: newCustomThemeId(),
        name: _uniqueName(trEn('Temam', 'My theme', 'Mein Design')),
        palette: juzzioAuroraPaletteById(glassPaletteId),
        dark: isDark,
      );

  /// Ekle veya güncelle. Sınır aşılırsa false.
  bool saveCustomTheme(JuzzioCustomTheme t) {
    final i = _customThemes.indexWhere((x) => x.id == t.id);
    final fixed = t.copyWith(name: _uniqueName(t.name, exceptId: t.id));
    if (i >= 0) {
      _customThemes[i] = fixed;
    } else {
      if (_customThemes.length >= maxCustomThemes) return false;
      _customThemes.add(fixed);
    }
    _syncCustomTokens();
    _persistUserPreferences();
    notifyListeners();
    return true;
  }

  void renameCustomTheme(String id, String name) {
    final i = _customThemes.indexWhere((x) => x.id == id);
    if (i < 0) return;
    _customThemes[i] = _customThemes[i].copyWith(name: _uniqueName(name, exceptId: id));
    _persistUserPreferences();
    notifyListeners();
  }

  JuzzioCustomTheme? duplicateCustomTheme(String id) {
    final src = _customThemes.where((x) => x.id == id).firstOrNull;
    if (src == null || _customThemes.length >= maxCustomThemes) return null;
    final copy = src.copyWith(id: newCustomThemeId(), name: _uniqueName('${src.name} ${trEn('kopya', 'copy', 'Kopie')}'));
    _customThemes.add(copy);
    _persistUserPreferences();
    notifyListeners();
    return copy;
  }

  void deleteCustomTheme(String id) {
    _customThemes.removeWhere((x) => x.id == id);
    if (_activeCustomThemeId == id) _activeCustomThemeId = '';
    _syncCustomTokens();
    _persistUserPreferences();
    notifyListeners();
  }

  void applyCustomTheme(String id) {
    if (!_customThemes.any((x) => x.id == id)) return;
    _activeCustomThemeId = id;
    _followGlobalTheme = false;
    _previewTheme = null;
    _syncCustomTokens();
    _persistUserPreferences();
    notifyListeners();
  }

  /// "Varsayılana dön": özel tema kapatılır, seçili hazır cam teması ve açık/koyu modu geri gelir
  void clearCustomTheme() {
    _activeCustomThemeId = '';
    _previewTheme = null;
    _syncCustomTokens();
    _persistUserPreferences();
    notifyListeners();
  }

  /// Canlı önizleme: taslak tüm uygulamaya geçici uygulanır (kaydedilmez)
  void previewCustomTheme(JuzzioCustomTheme? draft) {
    _previewTheme = draft;
    _syncCustomTokens();
    notifyListeners();
  }

  String exportCustomThemeJson(String id) =>
      _customThemes.firstWhere((x) => x.id == id).toPrettyJson();

  /// JSON'dan içe aktarır (güvenli doğrulama). Başarılıysa kaydeder.
  JuzzioThemeParseResult importCustomThemeJson(String raw) {
    if (_customThemes.length >= maxCustomThemes) {
      return JuzzioThemeParseResult(null, [trEn('En fazla $maxCustomThemes tema saklanabilir.', 'At most $maxCustomThemes themes.', 'Maximal $maxCustomThemes Designs.')], const []);
    }
    final res = JuzzioCustomTheme.parse(raw, newId: newCustomThemeId());
    if (res.ok) saveCustomTheme(res.theme!);
    return res;
  }


  /// v0.8.1 Performans modu: blur kapalı, statik yarı saydam yüzeyler
  bool get reducedEffects => _reducedEffects;

  /// v0.8.2: düşük donanımlı cihaz algılanırsa ve kullanıcı performans modunu kendisi
  /// hiç değiştirmediyse blur otomatik kapatılır (kalıcı seçim değildir).
  bool _autoReducedEffects = false;
  bool get autoReducedEffects => _autoReducedEffects;
  void applyDeviceProfile({required bool lowEnd}) {
    if (_reducedEffectsUserSet || !lowEnd) return;
    _autoReducedEffects = true;
    JuzzioGlassTokens.reducedEffects = true;
    notifyListeners();
  }

  /// v0.8.1 Cam yoğunluğu (0.6–1.4, güvenli sınırlar)
  double get glassIntensity => _glassIntensity;
  void setGlassIntensity(double v, {bool persist = true}) {
    _glassIntensity = v.isFinite ? v.clamp(0.6, 1.4) : 1.0;
    JuzzioGlassTokens.intensity = _glassIntensity;
    if (persist) _persistUserPreferences();
    notifyListeners();
  }
  void setReducedEffects(bool v) {
    _reducedEffects = v;
    _reducedEffectsUserSet = true;
    JuzzioGlassTokens.reducedEffects = v;
    _persistUserPreferences();
    notifyListeners();
  }

  void setGlassPalette(String id) {
    _isFreshPrefsUser = false;
    // hazır tema seçilince özel tema ve küresel tema takibi devreden çıkar
    _activeCustomThemeId = '';
    _followGlobalTheme = false;
    _previewTheme = null;
    _syncCustomTokens();
    _glassPaletteId = juzzioAuroraPaletteById(id).id;
    _persistUserPreferences();
    notifyListeners();
  }

  bool _isFreshPrefsUser = false;

  /// v0.7.0: Yönetici panelindeki "varsayılan cam teması" YALNIZCA yeni kullanıcılara
  /// (bu cihazda ilk kez açanlara) bir kez uygulanır ve onların seçimi olarak kaydedilir.
  /// Yönetici dahil mevcut kullanıcılar etkilenmez; herkes temasını serbestçe değiştirir.
  void applyDefaultGlassPalette(String id) {
    final next = juzzioAuroraPaletteById(id).id;
    _defaultGlassPaletteId = next;
    if (_isFreshPrefsUser && _glassPaletteId.isEmpty) {
      _isFreshPrefsUser = false;
      _glassPaletteId = next;
      _persistUserPreferences();
      notifyListeners();
    }
  }

  /// v0.8.4: 12 uygulama temasından biri sohbet teması olarak (balon renkleri)
  String get chatPaletteId => _chatPaletteId;
  JuzzioAuroraPalette? get chatPalette => _chatPaletteId.isEmpty ? null : juzzioAuroraPaletteById(_chatPaletteId);
  void setChatPalette(String id) {
    _chatPaletteId = kJuzzioAuroraPalettes.any((p) => p.id == id) ? id : '';
    _persistUserPreferences();
    notifyListeners();
  }

  /// Yalnızca parlaklık/vurgu yoğunluğu; seçili tema (cam paleti ya da ön ayar) korunur.
  void setChatThemeIntensity(double intensity) {
    _chatThemeIntensity = intensity.clamp(0.6, 1.4);
    _persistUserPreferences();
    notifyListeners();
  }

  void setChatTheme(int index, {double? intensity}) {
    _chatPaletteId = '';
    _selectedChatThemeIndex = index.clamp(0, kJuzzioChatThemes.length - 1);
    if (intensity != null) {
      _chatThemeIntensity = intensity.clamp(0.6, 1.4);
    }
    _persistUserPreferences();
    notifyListeners();
  }

  /// Arayüz dilini uygulamayı yeniden başlatmadan değiştirir.
  /// Yerleşik olmayan dillerde önce dil paketi indirilir; indirilemezse eski dil
  /// korunur ve false döner (çağıran taraf `lang_pack_failed` uyarısını gösterir).
  /// v0.8.3 cihazlar arası dil senkronu: bu cihazda kullanıcı henüz dil seçmediyse
  /// (yeni kurulum / yeni telefon) hesabındaki uygulama dili uygulanır.
  bool get hasDeviceUiLangChoice => _deviceUiLang != null;
  Future<void> adoptAccountUiLanguage(String? accountLang) async {
    final code = (accountLang ?? '').trim().toLowerCase();
    if (code.isEmpty || hasDeviceUiLangChoice || code == _uiLang) return;
    if (!kJuzzioSupportedLanguages.any((l) => l.code.toLowerCase() == code)) return;
    await setUiLanguage(code);
  }

  Future<bool> setUiLanguage(String langCode) async {
    final clean = langCode.trim().toLowerCase();
    if (clean.isEmpty) return false;
    if (_uiLang == clean) {
      await _saveDeviceUiLang(clean);
      return true;
    }
    if (!kBuiltInUiLangs.contains(clean)) {
      // Daha önce indirilmiş paket varsa diskten anında yüklenir. Yoksa çeviri
      // servisine kısa bir erişim denemesi yapılır (en fazla ~5 sn); erişim yoksa
      // eski dil korunur. Erişim varsa dil hemen değişir, paket arka planda dolar.
      await _loadPackFromDisk(clean);
      final hasPack = _loadedPackLangs.contains(clean);
      if (!hasPack) {
        final probe = await _translateProtected('Hello', clean, timeout: const Duration(seconds: 5));
        if (probe == null) return false;
      }
    }
    _uiLang = clean;
    await _saveDeviceUiLang(clean);
    _persistUserPreferences();
    notifyListeners();
    if (!kBuiltInUiLangs.contains(clean)) {
      unawaited(prepareLanguagePack(clean));
    }
    return true;
  }

  void setSubtitleLanguage(String langCode) {
    final clean = langCode.trim().toLowerCase();
    if (clean.isEmpty || _subtitleLang == clean) return;
    _subtitleLang = clean;
    _persistUserPreferences();
    notifyListeners();
  }

  void setEnterSendsMessage(bool val) {
    _enterSendsMessage = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setMediaVisibility(bool val) {
    _mediaVisibility = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setFontSizeOption(String val) {
    _fontSizeOption = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setKeepChatsArchived(bool val) {
    _keepChatsArchived = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setSilentMode(bool val) {
    _isSilentMode = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setNotificationsEnabled(bool val) {
    _notificationsEnabled = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setLockChatEnabled(bool val) {
    _lockChatEnabled = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setSecurityNotificationsOnDevice(bool val) {
    _securityNotificationsOnDevice = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setLastSeenPrivacy(String val) {
    _lastSeenPrivacy = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setOnlinePrivacy(String val) {
    _onlinePrivacy = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setProfilePhotoPrivacy(String val) {
    _profilePhotoPrivacy = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setAboutPrivacy(String val) {
    _aboutPrivacy = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setStatusPrivacy(String val) {
    _statusPrivacy = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setReadReceiptsEnabled(bool val) {
    _readReceiptsEnabled = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setDefaultMessageTimer(String val) {
    _defaultMessageTimer = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setWhoCanAddMeToGroups(String val) {
    _whoCanAddMeToGroups = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setSilenceUnknownCallers(bool val) {
    _silenceUnknownCallers = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setSyncContactsAcrossDevices(bool val) {
    _syncContactsAcrossDevices = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void blockUsername(String uname) {
    final clean = uname.trim().replaceAll('@', '');
    if (clean.isNotEmpty && !_blockedUsernames.contains(clean)) {
      _blockedUsernames.add(clean);
      _persistUserPreferences();
    notifyListeners();
    }
  }

  void unblockUsername(String uname) {
    _blockedUsernames.remove(uname);
    _persistUserPreferences();
    notifyListeners();
  }

  void setAllowCameraEffects(bool val) {
    _allowCameraEffects = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setCameraBeautyEnabled(bool val) {
    _cameraBeautyEnabled = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setDoubleTapReaction(String emoji) {
    if (emoji.trim().isEmpty) return;
    _doubleTapReaction = emoji;
    _persistUserPreferences();
    notifyListeners();
  }

  /// Mesajı yıldızlar / yıldızı kaldırır. Yeni durumu döndürür.
  bool toggleStarredMessage(String id) {
    final starred = !_starredMessageIds.remove(id);
    if (starred) {
      _starredMessageIds.insert(0, id);
      if (_starredMessageIds.length > 500) _starredMessageIds.removeRange(500, _starredMessageIds.length);
    }
    _persistUserPreferences();
    notifyListeners();
    return starred;
  }

  void setBlockUnknownVolumeMessages(bool val) {
    _blockUnknownVolumeMessages = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setProtectIpInCalls(bool val) {
    _protectIpInCalls = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setDisableLinkPreviews(bool val) {
    _disableLinkPreviews = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setStrictAccountSettings(bool val) {
    _strictAccountSettings = val;
    if (val) {
      _blockUnknownVolumeMessages = true;
      _silenceUnknownCallers = true;
      _whoCanAddMeToGroups = 'friends';
      _disableLinkPreviews = true;
      _protectIpInCalls = true;
    }
    _persistUserPreferences();
    notifyListeners();
  }

  void setHighContrastMode(bool val) {
    _highContrastMode = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setReduceMotion(bool val) {
    _reduceMotion = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setAutoplayVideos(bool val) {
    _autoplayVideos = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setPrivateAccount(bool val) {
    _isPrivateAccount = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setPostsPrivacy(String val) {
    _postsPrivacy = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setNotifyDirectMessages(bool val) {
    _notifyDirectMessages = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setNotifyGroupMessages(bool val) {
    _notifyGroupMessages = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setNotifyCalls(bool val) {
    _notifyCalls = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setNotifyFollows(bool val) {
    _notifyFollows = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setNotifyLikesComments(bool val) {
    _notifyLikesComments = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setNotifyStories(bool val) {
    _notifyStories = val;
    _persistUserPreferences();
    notifyListeners();
  }

  void setNotifySystem(bool val) {
    _notifySystem = val;
    _persistUserPreferences();
    notifyListeners();
  }

  JuzzioLanguageOption getLanguageOption(String code) {
    return kJuzzioSupportedLanguages.firstWhere(
      (e) => e.code.toLowerCase() == code.toLowerCase(),
      orElse: () => kJuzzioSupportedLanguages.first,
    );
  }

  // OTA Güncelleme & Pil Ayarları
  String _otaDownloadChannel = 'both';
  bool _otaUpdateAvailable = false;
  String _otaRemoteVersion = JuzzioConfig.appVersion;
  int _otaRemoteCode = JuzzioConfig.appVersionCode;
  String _otaReleaseNotesTr = '';
  String _otaReleaseNotesEn = '';
  String _otaReleaseNotesDe = '';
  // v0.6.1 şeffaf güncelleme notları: zorunluluk ve yapılandırılmış ayrıntılar
  bool _otaMandatory = false;
  Map<String, dynamic> _otaDetails = const <String, dynamic>{};
  String _otaApkUrl = JuzzioConfig.otaDirectApkUrl;
  DateTime? _otaSnoozedUntil;
  DateTime? _lastUpdateCheckTime;
  bool _isCheckingUpdate = false;
  bool _isDownloadingOta = false;
  double _otaDownloadProgress = 0.0;

  bool _callBatterySaverEnabled = true;
  String _callVideoFpsMode = '30fps';
  bool _oledPixelSaverEnabled = true;
  bool _backgroundPushGuardEnabled = true;

  String get otaDownloadChannel => _otaDownloadChannel;
  /// v0.7.0: Kullanıcı ertelediyse (zorunlu olsa bile) seçilen süre boyunca gösterilmez.
  bool get otaUpdateAvailable => _otaUpdateAvailable && !isOtaSnoozed;
  bool get otaMandatory => _otaMandatory;
  /// {"tr": {"reason", "features", "fixes", "security"}, "en": {...}, "de": {...}}
  Map<String, dynamic> get otaDetails => _otaDetails;

  /// Güncellemenin neden getirildiği (kullanıcının dilinde; yoksa otomatik çeviri)
  String get otaReason {
    String pick(String lang) {
      final m = _otaDetails[lang];
      return m is Map ? (m['reason'] ?? '').toString().trim() : '';
    }

    final tr = pick('tr');
    if (tr.isEmpty) return '';
    final en = pick('en');
    final de = pick('de');
    return translateUiDynamic(tr, enText: en.isEmpty ? null : en, deText: de.isEmpty ? null : de);
  }
  String get otaRemoteVersion => _otaRemoteVersion;
  int get otaRemoteCode => _otaRemoteCode;
  String get otaReleaseNotes =>
      translateUiDynamic(
        _otaReleaseNotesTr,
        enText: _otaReleaseNotesEn.isNotEmpty ? _otaReleaseNotesEn : null,
        deText: _otaReleaseNotesDe.isNotEmpty ? _otaReleaseNotesDe : null,
      );
  String get otaApkUrl => _otaApkUrl;
  DateTime? get otaSnoozedUntil => _otaSnoozedUntil;
  DateTime? get lastUpdateCheckTime => _lastUpdateCheckTime;
  bool get isCheckingUpdate => _isCheckingUpdate;
  bool get isDownloadingOta => _isDownloadingOta;
  double get otaDownloadProgress => _otaDownloadProgress;

  bool get isOtaSnoozed {
    if (_otaSnoozedUntil == null) return false;
    return DateTime.now().isBefore(_otaSnoozedUntil!);
  }

  bool get callBatterySaverEnabled => _callBatterySaverEnabled;
  String get callVideoFpsMode => _callVideoFpsMode;
  bool get oledPixelSaverEnabled => _oledPixelSaverEnabled;
  bool get backgroundPushGuardEnabled => _backgroundPushGuardEnabled;

  static const Map<String, String> _enSettingsMap = {
    'Şifre Değiştir': 'Change Password',
    'Mevcut Şifreniz': 'Current Password',
    'Kullandığınız mevcut şifreyi girin': 'Enter your current password',
    'Yeni Şifre': 'New Password',
    'Yeni şifrenizi girin': 'Enter your new password',
    'Yeni Şifreyi Doğrula (2. Kez)': 'Confirm New Password (2nd Time)',
    'Yeni şifrenizi tekrar girin': 'Re-enter your new password',
    'Şifre Değişikliğini Onayla': 'Confirm Password Change',
    'Şifre değişikliği yapıldı ve başarıyla onaylandı.': 'Password has been changed and verified.',
    'Güvenlik bildirimleri': 'Security notifications',
    'Sohbetleriniz ve aramalarınız gizlidir': 'Your chats and calls are private',
    'Uçtan uca şifreleme özelliği sayesinde kişisel mesajlarınız ve aramalarınız seçtiğiniz kişilerle aranızda kalır. JUZZIO da dahil olmak üzere sohbet dışındaki hiç kimse bu içerikleri okuyamaz, dinleyemez veya paylaşamaz. Bu içerikler arasında aşağıdakiler bulunur:': 'End-to-end encryption keeps your personal messages and calls between you and the people you choose. Not even JUZZIO can read, listen to, or share them. This includes:',
    'Yazılı ve sesli mesajlarınız': 'Your text and voice messages',
    'Sesli ve görüntülü aramalarınız': 'Your audio and video calls',
    'Fotoğraf, video ve belgeleriniz': 'Your photos, videos, and documents',
    'Konum paylaşımlarınız': 'Your location shares',
    'Durum güncellemeleriniz': 'Your status updates',
    'Bu cihazda güvenlik bildirimlerini göster': 'Show security notifications on this device',
    'Uçtan uca şifrelenmiş bir sohbetteki herhangi bir kişinin telefonu için güvenlik kodunuz değiştiğinde bildirim alın. Birden fazla cihazınız varsa bildirim almak istediğiniz her cihazda bu ayarın etkinleştirilmesi gerekir.': 'Get notified when your security code changes for a contact in an end-to-end encrypted chat. If you have multiple devices, this setting must be enabled on each device where you want to receive notifications.',
    'Kullanıcı adı': 'Username',
    'Düzenleyin': 'Edit',
    'Kullanıcı adını değiştir': 'Change username',
    'Kullanıcı adını sil': 'Delete username',
    'Mevcut Kullanıcı Adınız': 'Your Current Username',
    'Bu kullanıcı adı müsait, kullanılabilir.': 'This username is available and can be used.',
    'Bu kullanıcı adı şu anda başka bir kullanıcıya aittir ve kullanılamaz.': 'This username currently belongs to another user and is unavailable.',
    'Hesabımı Sil': 'Delete My Account',
    'Hesabınızı silmeyi onaylıyor musunuz?': 'Do you confirm deleting your account?',
    'Bu işlem geri alınamaz. Hesabınız, mesaj geçmişiniz, oluşturduğunuz gruplar ve kanallar veritabanından kalıcı olarak silinecektir.': 'This action cannot be undone. Your account, chat history, and all created groups and channels will be permanently deleted from the database.',
    'Onaylıyorum': 'I Confirm',
    'Bu hesabı silerseniz:': 'If you delete this account:',
    'Bu hesabı silerseniz hesap hem JUZZIO hem de tüm cihazlarınızdan silinir.': 'Deleting this account removes it from both JUZZIO and all your devices.',
    'Sohbet geçmişiniz silinecek.': 'Your chat history will be erased.',
    'Üyesi olduğunuz tüm JUZZIO gruplarından çıkarılırsınız.': 'You will be removed from all your JUZZIO groups.',
    'Oluşturduğunuz tüm grup ve tüm kanallar silinir.': 'All groups and channels you created will be deleted.',
    'Onaylamak için şifrenizi iki kez girin:': 'Enter your password twice to confirm:',
    'Şifreniz (1. Kez)': 'Your Password (1st Time)',
    'Şifrenizi Doğrulayın (2. Kez)': 'Confirm Password (2nd Time)',
    'Gizlilik': 'Privacy',
    'Kişisel bilgilerimi kimler görebilir': 'Who can see my personal info',
    'Son görülme ve çevrim içi': 'Last seen and online',
    'Profil resmi': 'Profile photo',
    'Hakkında': 'About (Bio)',
    'Durum': 'Status',
    'Okundu Bilgisi': 'Read Receipts',
    'Bu özelliği devre dışı bırakırsanız okundu bilgisi gönderemez veya alamazsınız. Grup sohbetleri için okundu bilgisi her zaman gönderilir.': 'If turned off, you will not send or receive read receipts. Read receipts are always sent for group chats.',
    'Süreli mesajlar': 'Disappearing messages',
    'Varsayılan mesaj süresi': 'Default message timer',
    'Gruplar, Aramalar, Kişiler ve Kamera': 'Groups, Calls, Contacts & Camera',
    'Gruplar (Beni gruba kimler ekleyebilir)': 'Groups (Who can add me to groups)',
    'Aramalar: Bilinmeyen kullanıcıları sessize al': 'Calls: Silence unknown callers',
    'Kişilerinizde olmayan numaralardan ve hesaplardan gelen aramaları sessize alır.': 'Silences calls from unknown accounts not in your contacts.',
    'Kişiler ve Engellenmiş Hesaplar': 'Contacts & Blocked Accounts',
    'Kamera efektlerine izin ver': 'Allow camera effects',
    'Kamerada veya görüntülü aramalarda efekt kullan': 'Use effects in camera and video calls',
    'Kamerada güzelleştirme uygula': 'Apply camera beauty filter',
    'Görüntülü aramada yüz pürüzsüzleştirme, sivilce izi yumuşatma ve daha temiz/net görüntü aktarımını otomatik uygular (Varsayılan: Açık).': 'Automatically applies face smoothing, blemish softening, and clearer video quality during video calls (Default: On).',
    'Gelişmiş': 'Advanced',
    'Bilinmeyen mesaj engelleme, IP koruma, bağlantı önizlemeleri ve Katı hesap ayarları': 'Block unknown volume messages, protect IP in calls, link previews & Strict account settings',
    'Son görülme bilgimi kimler görebilir?': 'Who can see my last seen?',
    'Çevrimiçi olduğumu kimler görebilir?': 'Who can see when I am online?',
    'Son görülme bilgisi ile aynı': 'Same as last seen',
    'Son görülme veya çevrim içi bilginizi paylaşmazsanız diğer kullanıcıların son görülme ve çevrim içi bilgisini de göremezsiniz.': 'If you do not share your last seen or online status, you will not be able to see other users last seen or online status.',
    'Herkes': 'Everyone',
    'Kişilerim': 'My contacts',
    'Hiç kimse': 'Nobody',
    'Arkadaşlarım': 'My friends',
    'Yeni sohbetlere şu süreli mesaj süresi ayarı ile başlayın:': 'Start new chats with disappearing messages set to:',
    '24 saat': '24 hours',
    '7 gün': '7 days',
    '90 gün': '90 days',
    'Kapalı': 'Off',
    'Açık': 'On',
    'Bu özellik açıldığında tüm yeni bireysel sohbetler seçtiğiniz süre dolduğunda kaybolacak süreli mesajlarla başlatılır. Mevcut sohbetleriniz bu ayardan etkilenmez.': 'When enabled, all new individual chats will start with disappearing messages that expire after the selected duration. Existing chats are not affected.',
    'Beni gruba kimler ekleyebilir?': 'Who can add me to groups?',
    'Hiç kimse (Yalnızca özel davet bağlantısı gönderilebilir)': 'Nobody (Only private group invite link can be sent via message)',
    'Hiç kimse seçeneğini seçtiğinizde, sizi gruba eklemek isteyen yönetici yalnızca mesaj olarak grup davet bağlantısını gönderebilir. Bağlantıya tıkladığınızda kendi isteğiniz ile gruba katılım sağlayabilirsiniz.': 'When Nobody is selected, admins trying to add you can only send a group invite link as a chat message so you can join on your own terms.',
    'Kişiler': 'Contacts',
    'WhatsApp / Juzzio Kişileri': 'WhatsApp / Juzzio Contacts Sync',
    'Kişiler, cihazlar genelinde yönetebilmeniz için hesabınıza kaydedilir. Windows / Masaüstü uygulamasında QR kodunuzu okuttuğunuzda engellenen kişiler dahil tüm listeniz senkronize gelir.': 'Contacts and blocked accounts are saved to your account so they stay synced across all devices including Windows / Desktop via QR code.',
    'Engelle': 'Block',
    'Engeli Kaldır': 'Unblock',
    'Bilinmeyen hesaplardan gelen mesajları engelle': 'Block messages from unknown accounts',
    'Juzzio hesabınızı korumak ve cihazınızın performansını iyileştirmek için bilinmeyen hesaplardan belirli bir hacmin üzerine gelen mesajları engeller.': 'To protect your Juzzio account and device performance, blocks high-volume messages from unknown accounts.',
    'Aramalarda IP adresini koru': 'Protect IP address in calls',
    'Konumunuzun başka kişiler tarafından tahmin edilmesini zorlaştırmak amacıyla bu cihazdan yapılan aramalar sunucuları üzerinden güvenli bir şekilde aktarılır. Bu işlem arama kalitesini düşürür.': 'To make it harder for others to infer your location, calls on this device are securely relayed through Juzzio servers. This reduces call quality.',
    'Bağlantı önizlemelerini devre dışı bırak': 'Disable link previews',
    'IP adresinizi üçüncü taraf web siteleri tarafından anlaşılmaya karşı korumaya yardımcı olmak için bundan böyle sohbetlerde paylaştığınız bağlantıların önizlemelerini oluşturmayacağız.': 'To help protect your IP address from being inferred by third-party websites, previews will no longer be generated for links shared in chats.',
    'Katı hesap ayarları': 'Strict account settings',
    'Hedefli siber saldırı riski altında olma ihtimaliniz yüksekse hesabınızı korumak için belirli ayarlar kilitlenir.': 'Locks certain settings to help protect your account if you are at high risk of targeted cyberattacks.',
    'İleri': 'Next',
    'İptal': 'Cancel',
    'Devam Et': 'Continue',
    'Sohbetler': 'Chats',
    'Görüntüleme': 'Display',
    'Tema': 'Theme',
    'Varsayılan sistem ayarı': 'System default',
    'Aydınlık (Gündüz)': 'Light (White Theme)',
    'Karanlık (Gece)': 'Dark (Night)',
    'Varsayılan sohbet teması': 'Default chat theme',
    'Sohbet ayarları': 'Chat settings',
    'Enter tuşu mesajı gönderir': 'Enter is send',
    'Enter tuşuna basıldığında mesajınız gönderilir': 'Enter key will send your message',
    'Medya görünürlüğü': 'Media visibility',
    'Yeni indirilen medyaları cihazınızın galerisinde gösterir': 'Show newly downloaded media in your device gallery',
    'Yazı tipi boyutu': 'Font size',
    'Küçük': 'Small',
    'Orta': 'Medium',
    'Büyük': 'Large',
    'Arşivlenmiş sohbetler': 'Archived chats',
    'Sohbetleri arşivde tut': 'Keep chats archived',
    'Arşivlenen sohbetler yeni mesaj aldığınızda arşivde kalır': 'Archived chats will remain archived when you receive a new message',
    'Sohbet yedeklemesi': 'Chat backup',
    'Uçtan uca şifreli bulut yedeklemesi oluşturun': 'Create end-to-end encrypted cloud backups',
    'Sohbetleri aktarma': 'Transfer chats',
    'Sohbet geçmişinizi başka bir Android veya Windows cihaza aktarın': 'Transfer your chat history to another Android or Windows device',
    'Sohbet geçmişi': 'Chat history',
    'Dışa aktar, arşivle, içeriği temizle veya tüm sohbetleri sil': 'Export, archive, clear, or delete all chats',
    'Şimdi Yedekle': 'Back Up Now',
    'Uçtan uca şifreli yedekleme': 'End-to-end encrypted backup',
    'Videoları ve sesli notları dahil et': 'Include videos and voice notes',
    'Aktarımı Başlat': 'Start Transfer',
    'Sohbeti dışa aktar': 'Export chat',
    'Tüm sohbetleri arşivle': 'Archive all chats',
    'Tüm sohbetlerin içeriğini temizle': 'Clear all chats',
    'Tüm sohbetleri sil': 'Delete all chats',
    'Görünüm': 'Appearance',
    'Depolama ve veriler': 'Storage and data',
    'Depolama alanını yönet': 'Manage storage',
    'Ağ kullanımı': 'Network usage',
    'Bildirimler': 'Notifications',
    'Yüksek öncelikli bildirimleri kullan': 'Use high priority notifications',
    'Erişilebilirlik': 'Accessibility',
    'Kontrastı artır': 'Increase contrast',
    'Animasyonları azalt': 'Reduce motion',
    'Yapımcı': 'Developer / Creator',
    'Instagram Bağlantısı': 'Instagram Link',
  };

  static const Map<String, String> _deSettingsMap = {
    'Şifre Değiştir': 'Passwort ändern',
    'Mevcut Şifreniz': 'Aktuelles Passwort',
    'Yeni Şifre': 'Neues Passwort',
    'Şifre Değişikliğini Onayla': 'Passwortänderung bestätigen',
    'Güvenlik bildirimleri': 'Sicherheitsbenachrichtigungen',
    'Kullanıcı adı': 'Benutzername',
    'Düzenleyin': 'Bearbeiten',
    'Hesabımı Sil': 'Mein Konto löschen',
    'Gizlilik': 'Datenschutz',
    'Son görülme ve çevrim içi': 'Zuletzt online & Status',
    'Profil resmi': 'Profilbild',
    'Hakkında': 'Info (Biografie)',
    'Durum': 'Status',
    'Okundu Bilgisi': 'Lesebestätigungen',
    'Süreli mesajlar': 'Selbstlöschende Nachrichten',
    'Herkes': 'Jeder',
    'Kişilerim': 'Meine Kontakte',
    'Hiç kimse': 'Niemand',
    'Arkadaşlarım': 'Meine Freunde',
    'Kapalı': 'Aus',
    'Açık': 'Ein',
    'Kişiler': 'Kontakte',
    'Engelle': 'Blockieren',
    'Engeli Kaldır': 'Freigeben',
    'Gelişmiş': 'Erweitert',
    'İleri': 'Weiter',
    'İptal': 'Abbrechen',
    'Devam Et': 'Fortfahren',
    'Sohbetler': 'Chats',
    'Tema': 'Design',
    'Varsayılan sistem ayarı': 'Systemstandard',
    'Aydınlık (Gündüz)': 'Hell (Weißes Design)',
    'Karanlık (Gece)': 'Dunkel (Nacht)',
    'Sohbet ayarları': 'Chat-Einstellungen',
    'Medya görünürlüğü': 'Mediensichtbarkeit',
    'Yazı tipi boyutu': 'Schriftgröße',
    'Küçük': 'Klein',
    'Orta': 'Mittel',
    'Büyük': 'Groß',
    'Görünüm': 'Darstellung',
    'Depolama ve veriler': 'Speicher und Daten',
    'Bildirimler': 'Benachrichtigungen',
    'Erişilebilirlik': 'Barrierefreiheit',
    'Yapımcı': 'Entwickler',
    'Canlı Çeviri Geçmişi': 'Live-Übersetzungsverlauf',
    'Tüm Geçmişi Kopyala': 'Gesamten Verlauf kopieren',
    'Geçmişi Temizle': 'Verlauf löschen',
    'Çeviri Geçmişi': 'Übersetzungsverlauf',
    'SON ÇEVİRİ GEÇMİŞİ': 'LETZTER ÜBERSETZUNGSVERLAUF',
    'Tümünü Aç ↗': 'Alle öffnen ↗',
    'SEN': 'DU',
    'Sen': 'Du',
    'Mini Geçmiş: Açık': 'Mini-Protokoll: Ein',
    'Mini Geçmiş: Kapalı': 'Mini-Protokoll: Aus',
  };

  void setOtaDownloadChannel(String channel) {
    _otaDownloadChannel = channel;
    notifyListeners();
  }

  void setCallBatterySaverEnabled(bool val) {
    _callBatterySaverEnabled = val;
    notifyListeners();
  }

  void setCallVideoFpsMode(String mode) {
    _callVideoFpsMode = mode;
    notifyListeners();
  }

  void setOledPixelSaverEnabled(bool val) {
    _oledPixelSaverEnabled = val;
    notifyListeners();
  }

  void setBackgroundPushGuardEnabled(bool val) {
    _backgroundPushGuardEnabled = val;
    notifyListeners();
  }

  Future<void> requestAndroidBatteryExemption() async {
    try {
      await _notifChannel.invokeMethod('requestBatteryOptimizationExemption');
    } catch (_) {}
  }

  void snoozeOtaUpdate(Duration duration) {
    _otaSnoozedUntil = DateTime.now().add(duration);
    notifyListeners();
    _saveOtaState();
  }

  // ---------------------------------------------------------------------------
  // v0.7.0 KALICI OTA DURUMU (cihaz bazlı): erteleme süresi, bildirimi gönderilen
  // sürüm ve "Yenilikler" penceresinin görüldüğü sürüm. Uygulama kapatılıp açılsa
  // bile erteleme korunur; aynı sürüm için bildirim tekrar tekrar gelmez.
  // ---------------------------------------------------------------------------
  bool _otaStateLoaded = false;
  Future<void>? _otaStateLoading;
  int _otaNotifiedCode = 0;
  String _whatsNewSeenVersion = '';
  bool _whatsNewPending = false;

  /// Güncellemeden sonra ilk açılışta "Sürüm X ile neler geldi?" penceresi gösterilmeli mi?
  bool get whatsNewPending => _whatsNewPending;

  Future<File> _otaStateFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/juzzio_ota_state.json');
  }

  Future<void> ensureOtaStateLoaded() {
    if (_otaStateLoaded) return Future<void>.value();
    return _otaStateLoading ??= _loadOtaState();
  }

  Future<void> _loadOtaState() async {
    try {
      final f = await _otaStateFile();
      if (f.existsSync()) {
        final raw = jsonDecode(await f.readAsString());
        if (raw is Map) {
          final until = DateTime.tryParse((raw['snoozedUntil'] ?? '').toString());
          if (until != null && until.isAfter(DateTime.now())) _otaSnoozedUntil = until;
          _otaNotifiedCode = (raw['notifiedCode'] as num?)?.toInt() ?? 0;
          _whatsNewSeenVersion = (raw['whatsNewSeen'] ?? '').toString();
        }
        _whatsNewPending = _whatsNewSeenVersion.isNotEmpty &&
            _compareSemver(JuzzioConfig.appVersion, _whatsNewSeenVersion) > 0;
      } else {
        // İlk kurulum: pencere gösterilmez, bu sürüm görülmüş sayılır
        _whatsNewSeenVersion = JuzzioConfig.appVersion;
        _whatsNewPending = false;
      }
    } catch (_) {}
    _otaStateLoaded = true;
    if (!_whatsNewPending && _whatsNewSeenVersion.isEmpty) _whatsNewSeenVersion = JuzzioConfig.appVersion;
    await _saveOtaState();
    notifyListeners();
  }

  Future<void> _saveOtaState() async {
    try {
      final f = await _otaStateFile();
      await f.writeAsString(jsonEncode(<String, dynamic>{
        'snoozedUntil': _otaSnoozedUntil?.toIso8601String() ?? '',
        'notifiedCode': _otaNotifiedCode,
        'whatsNewSeen': _whatsNewPending ? _whatsNewSeenVersion : JuzzioConfig.appVersion,
      }));
    } catch (_) {}
  }

  void markWhatsNewSeen() {
    _whatsNewPending = false;
    _whatsNewSeenVersion = JuzzioConfig.appVersion;
    notifyListeners();
    _saveOtaState();
  }

  /// Ayrıntılar boşsa GitHub sürüm sayfasındaki notlardan otomatik doldurulur.
  Future<Map<String, dynamic>> fetchGithubReleaseDetails(String versionName) async {
    try {
      final uri = Uri.parse(
          'https://api.github.com/repos/${JuzzioConfig.githubOwner}/${JuzzioConfig.githubRepo}/releases/tags/v$versionName');
      final res = await http.get(uri, headers: const {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return const <String, dynamic>{};
      final body = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['body']?.toString() ?? '';
      return parseReleaseMarkdown(body);
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  /// GitHub sürüm notu (Markdown) → {"tr": {reason, features, fixes, security}}
  static Map<String, dynamic> parseReleaseMarkdown(String md) {
    final trPart = md.split(RegExp(r'<details>|^---\s*$', multiLine: true)).first;
    String? current;
    final reason = StringBuffer();
    final buckets = <String, List<String>>{'features': [], 'fixes': [], 'security': []};
    for (final raw in trPart.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('#')) {
        final h = line.replaceAll('#', '').toLowerCase();
        if (h.contains('neden') || h.contains('why')) {
          current = 'reason';
        } else if (h.contains('özellik') || h.contains('yenilik') || h.contains('feature')) {
          current = 'features';
        } else if (h.contains('düzelt') || h.contains('hata') || h.contains('fix')) {
          current = 'fixes';
        } else if (h.contains('güvenlik') || h.contains('gizlilik') || h.contains('security')) {
          current = 'security';
        } else {
          current = null;
        }
        continue;
      }
      if (current == null || line.isEmpty) continue;
      if (current == 'reason') {
        reason.write(reason.isEmpty ? line : ' $line');
      } else if (RegExp(r'^[-*•]\s+').hasMatch(line)) {
        buckets[current]!.add(line.replaceFirst(RegExp(r'^[-*•]\s+'), '').replaceAll('**', ''));
      }
    }
    if (reason.isEmpty && buckets.values.every((l) => l.isEmpty)) return const <String, dynamic>{};
    return <String, dynamic>{
      'tr': <String, dynamic>{'reason': reason.toString(), ...buckets},
    };
  }

  static int? _asInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  /// version.json'ı bozulmalara dayanıklı okur: UTF-8 BOM, UTF-16, NUL baytları ve
  /// JSON'dan sonra gelen fazlalık ("Extra data") temizlenir. Okunamazsa null döner.
  static Map<String, dynamic>? parseVersionManifest(List<int> bytes) {
    String text;
    try {
      final nulCount = bytes.where((b) => b == 0).length;
      if (bytes.length >= 2 && ((bytes[0] == 0xFF && bytes[1] == 0xFE) || nulCount > bytes.length ~/ 3)) {
        final start = (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) ? 2 : 0;
        final units = <int>[];
        for (var i = start; i + 1 < bytes.length; i += 2) {
          units.add(bytes[i] | (bytes[i + 1] << 8));
        }
        text = String.fromCharCodes(units);
      } else {
        text = utf8.decode(bytes.where((b) => b != 0).toList(), allowMalformed: true);
      }
    } catch (_) {
      return null;
    }
    text = text.replaceAll('\uFEFF', '').trim();
    final start = text.indexOf('{');
    if (start < 0) return null;
    // İlk dengeli { ... } bloğunu bul (string içindeki parantezleri yok sayarak)
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          try {
            final decoded = jsonDecode(text.substring(start, i + 1));
            return decoded is Map<String, dynamic> ? decoded : null;
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  int _compareSemver(String v1, String v2) {
    final p1 = v1.replaceAll('v', '').split('+').first.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final p2 = v2.replaceAll('v', '').split('+').first.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final a = i < p1.length ? p1[i] : 0;
      final b = i < p2.length ? p2[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }

  /// v0.8.0: version.json'un ML-DSA-65 (FIPS 204) imzasını doğrular. Uygulama
  /// açık anahtarla derlenmemişse true döner (imza zorunlu değil).
  static bool verifyReleaseSignature(Map<String, dynamic> data) {
    final pkB64 = JuzzioConfig.mlDsaPublicKey.trim();
    if (pkB64.isEmpty) return true;
    try {
      final sig = base64Decode('${data['mldsa65Sig'] ?? ''}');
      final build = _asIntStatic(data['build']) ?? _asIntStatic(data['buildNumber']) ?? _asIntStatic(data['versionCode']) ?? 0;
      final msg = utf8.encode('juzzio-release|${'${data['version'] ?? ''}'.trim()}|$build|${'${data['apkSha256'] ?? ''}'.trim().toLowerCase()}');
      return JuzzioMlDsa65.verify(base64Decode(pkB64), msg, sig, ctx: utf8.encode('juzzio-release'));
    } catch (_) {
      return false;
    }
  }

  static int? _asIntStatic(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim()));

  Future<bool> checkForOtaUpdate({bool manualCheck = false}) async {
    if (_isCheckingUpdate) return false;
    _isCheckingUpdate = true;
    notifyListeners();

    try {
      final uri = Uri.parse(
        '${JuzzioConfig.otaVersionJsonUrl}?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      _lastUpdateCheckTime = DateTime.now();

      if (res.statusCode == 200) {
        final data = parseVersionManifest(res.bodyBytes);
        if (data == null) throw const FormatException('version.json okunamadı');
        final remoteVer = (data['version'] ?? JuzzioConfig.appVersion).toString().trim();
        final remoteCode = _asInt(data['build']) ??
            _asInt(data['buildNumber']) ??
            _asInt(data['versionCode']) ??
            JuzzioConfig.appVersionCode;
        final changelog = data['changelog'] is Map ? (data['changelog'] as Map) : const {};
        final notesTr = (data['changelog_tr'] ?? changelog['tr'] ?? 'Yeni Juzzio sürümü v$remoteVer hazır!').toString();
        final notesEn = (data['changelog_en'] ?? changelog['en'] ?? 'New Juzzio version v$remoteVer is ready!').toString();
        final apkUrl = (data['url'] ?? data['apkUrl'] ?? data['apkDownloadUrl'] ?? JuzzioConfig.otaDirectApkUrl).toString();
        final details = data['details'] is Map ? Map<String, dynamic>.from(data['details'] as Map) : const <String, dynamic>{};

        if ((_compareSemver(remoteVer, JuzzioConfig.appVersion) > 0 ||
                remoteCode > JuzzioConfig.appVersionCode) &&
            verifyReleaseSignature(data)) {
          await applyDetectedRemoteRelease(
            mandatory: data['mandatory'] == true,
            details: details,
            versionName: remoteVer,
            versionCode: remoteCode,
            notesTr: notesTr,
            notesEn: notesEn,
            notesDe: (data['changelog_de'] ?? changelog['de'] ?? '').toString(),
            apkUrl: apkUrl,
            ignoreSnooze: manualCheck,
          );
          _isCheckingUpdate = false;
          notifyListeners();
          return true;
        }
      }
    } catch (_) {}

    _isCheckingUpdate = false;
    notifyListeners();
    return false;
  }

  Future<void> applyDetectedRemoteRelease({
    required String versionName,
    required int versionCode,
    required String notesTr,
    required String notesEn,
    String notesDe = '',
    String? apkUrl,
    bool ignoreSnooze = false,
    bool mandatory = false,
    Map<String, dynamic> details = const <String, dynamic>{},
  }) async {
    if (_compareSemver(versionName, JuzzioConfig.appVersion) <= 0 &&
        versionCode <= JuzzioConfig.appVersionCode) {
      return;
    }
    await ensureOtaStateLoaded();
    if (details.isEmpty) {
      // Yönetici not yazmadıysa notlar GitHub sürüm sayfasından otomatik çekilir
      details = await fetchGithubReleaseDetails(versionName);
    }
    _otaRemoteVersion = versionName;
    _otaRemoteCode = versionCode;
    _otaReleaseNotesTr = notesTr;
    _otaReleaseNotesEn = notesEn;
    _otaReleaseNotesDe = notesDe;
    _otaMandatory = mandatory;
    _otaDetails = details;
    if (apkUrl != null && apkUrl.isNotEmpty) {
      _otaApkUrl = apkUrl;
    }
    if (ignoreSnooze) {
      _otaSnoozedUntil = null;
      _saveOtaState();
    }
    _otaUpdateAvailable = true;
    notifyListeners();

    // Erteleme süresince hiç bildirim yok; aynı sürüm için bildirim yalnızca bir kez
    if (!isOtaSnoozed && (ignoreSnooze || _otaNotifiedCode != versionCode)) {
      _otaNotifiedCode = versionCode;
      _saveOtaState();
      await triggerSystemNotification(
        title: trEn(
          '🎉 Güncelleme geldi! (v$versionName)',
          '🎉 Update available! (v$versionName)',
          '🎉 Update verfügbar! (v$versionName)',
        ),
        body: otaReason.isNotEmpty
            ? otaReason
            : trEn(
                'Yeni güncelleme algılandı. Ayrıntıları okuyup uygulama içinden güncelleyebilirsiniz.',
                'A new update was detected. Read the details and update inside the app.',
                'Ein neues Update wurde erkannt. Lies die Details und aktualisiere in der App.',
              ),
        isUpdate: true,
      );
    }
  }

  Future<String> startOtaDownloadAndInstall() async {
    String connType = 'wifi';
    try {
      final res = await _notifChannel.invokeMethod<String>('getNetworkConnectionType');
      if (res != null) connType = res;
    } catch (_) {}

    if (_otaDownloadChannel == 'wifi' && connType != 'wifi') {
      return trEn(
        'Wi-Fi ile indirme seçili. Wi-Fi bağlantısı algılandığında v$_otaRemoteVersion otomatik indirilecek.',
        'Wi-Fi only is selected. v$_otaRemoteVersion will download automatically when Wi-Fi is detected.', 'Nur WLAN ist ausgewählt. v$_otaRemoteVersion wird automatisch heruntergeladen, sobald WLAN verfügbar ist.',
      );
    }
    if (_otaDownloadChannel == 'mobile' && connType != 'mobile') {
      return trEn(
        'Mobil veri ile indirme seçili. Mobil veri aktif olduğunda indirme başlayacak.',
        'Mobile data only is selected. Download will start when mobile data is active.', 'Nur mobile Daten ist ausgewählt. Der Download startet, sobald mobile Daten aktiv sind.',
      );
    }

    if (_isDownloadingOta) {
      return trEn('Güncelleme zaten indiriliyor...', 'The update is already downloading...', 'Das Update wird bereits heruntergeladen...');
    }
    _isDownloadingOta = true;
    _otaDownloadProgress = 0.0;
    notifyListeners();

    // APK uygulama içinde indirilir (GitHub/tarayıcı açılmaz), ardından Android paket
    // yükleyicisi mevcut uygulamanın ÜZERİNE kurar. Aynı paket adı (com.juzzio.app) ve aynı
    // imza anahtarı kullanıldığı için veriler korunur; eski uygulamayı silmek gerekmez.
    File? apkFile;
    final client = http.Client();
    try {
      final dir = await getTemporaryDirectory();
      final otaDir = Directory('${dir.path}/ota');
      if (!otaDir.existsSync()) otaDir.createSync(recursive: true);
      for (final old in otaDir.listSync()) {
        try {
          old.deleteSync();
        } catch (_) {}
      }
      apkFile = File('${otaDir.path}/juzzio-update.apk');
      final req = http.Request('GET', Uri.parse(_otaApkUrl));
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('status ${res.statusCode}');
      final total = res.contentLength ?? 0;
      final sink = apkFile.openWrite();
      var received = 0;
      var lastNotify = DateTime.now();
      try {
        await for (final chunk in res.stream.timeout(const Duration(seconds: 45))) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0 && DateTime.now().difference(lastNotify).inMilliseconds > 150) {
            _otaDownloadProgress = (received / total).clamp(0.0, 0.99);
            lastNotify = DateTime.now();
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      if (received < 1024 * 100 || (total > 0 && received < total)) {
        throw const FileSystemException('incomplete');
      }
      _otaDownloadProgress = 1.0;
      notifyListeners();
    } catch (_) {
      _isDownloadingOta = false;
      _otaDownloadProgress = 0.0;
      notifyListeners();
      client.close();
      return trEn(
        'Güncelleme indirilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        'The update could not be downloaded. Check your internet connection and try again.',
        'Das Update konnte nicht heruntergeladen werden. Prüfe deine Internetverbindung und versuche es erneut.',
      );
    }
    client.close();
    _isDownloadingOta = false;
    notifyListeners();
    return installDownloadedOta(apkFile.path);
  }

  String? _lastOtaApkPath;

  /// İndirilmiş güncellemeyi kurar. Bilinmeyen kaynak izni yoksa izin ekranını açar;
  /// izin verildikten sonra aynı düğmeye tekrar basmak yeterlidir (yeniden indirmez).
  Future<String> installDownloadedOta([String? path]) async {
    final apkPath = path ?? _lastOtaApkPath;
    if (apkPath == null) {
      return trEn('Önce güncellemeyi indirin.', 'Download the update first.', 'Lade das Update zuerst herunter.');
    }
    _lastOtaApkPath = apkPath;
    String result = 'error';
    try {
      result = await _notifChannel.invokeMethod<String>('installApk', {'path': apkPath}) ?? 'error';
    } catch (_) {}
    if (result == 'started') {
      return trEn(
        'Kurulum ekranı açıldı. "Güncelle" deyin; uygulamanız ve verileriniz korunur.',
        'The installer opened. Tap "Update"; your app and data are kept.',
        'Das Installationsfenster wurde geöffnet. Tippe auf „Aktualisieren“; App und Daten bleiben erhalten.',
      );
    }
    if (result == 'needs_permission') {
      try {
        await _notifChannel.invokeMethod('openInstallPermissionSettings');
      } catch (_) {}
      return trEn(
        'Juzzio için "Bilinmeyen uygulamaları yükle" iznini açın, sonra tekrar "Güncelle"ye basın.',
        'Allow "Install unknown apps" for Juzzio, then tap "Update" again.',
        'Erlaube „Unbekannte Apps installieren“ für Juzzio und tippe dann erneut auf „Aktualisieren“.',
      );
    }
    return trEn(
      'Güncelleme kurulamadı. Lütfen tekrar deneyin.',
      'The update could not be installed. Please try again.',
      'Das Update konnte nicht installiert werden. Bitte versuche es erneut.',
    );
  }

  bool get hasDownloadedOta => _lastOtaApkPath != null && File(_lastOtaApkPath!).existsSync();

  Future<void> ensureBackgroundNotificationReady() async {
    try {
      await _notifChannel.invokeMethod('requestNotificationPermission');
      await _notifChannel.invokeMethod('ensureBackgroundLock');
    } catch (_) {}
  }

  Future<void> triggerSystemNotification({
    required String title,
    required String body,
    bool isUpdate = false,
    bool isCall = false,
    String? channelId,
  }) async {
    if (!_notificationsEnabled && !isUpdate && !isCall) return;
    try {
      await _notifChannel.invokeMethod('showSystemNotification', {
        'title': title,
        'body': body,
        'isUpdate': isUpdate,
        'isCall': isCall,
        if (channelId != null && channelId.isNotEmpty) 'channelId': channelId,
        'id': DateTime.now().millisecondsSinceEpoch % 100000,
      });
    } catch (_) {}
  }

}

/// Instagram.jpg Beyaz Tema + "Cool!" Siyah Hap Butonlar & Hey Joseph Düzeni Renk Paleti
class JuzzioPalette {
  final bool isDark;
  const JuzzioPalette(this.isDark);

  JuzzioChatThemePreset get _preset => JuzzioAppController.instance.currentChatTheme;

  // Instagram.jpg saf beyaz arka plan ve yumuşak inci grisi katmanlar
  // v0.6 Glassmorphism: sayfa zemini saydam, arkada aurora cam teması görünür
  Color get bgPrimary => Colors.transparent;
  Color get bgSecondary => isDark ? const Color(0x14FFFFFF) : const Color(0x8CFFFFFF);
  /// Alt pencere / diyalog gibi içeriğin üstüne açılan yüzeyler (okunurluk için yarı opak cam)
  Color get sheetBg => (JuzzioGlassTokens.custom == null ? null : JuzzioGlassTokens.sheet) ?? (isDark ? const Color(0xC7101116) : const Color(0xE0F7F8FB));
  Color get bgGlowTop => isDark ? JuzzioColors.slate900 : const Color(0xFFEEF2FF);
  Color get bgGlowBottom => isDark ? JuzzioColors.surface191D26 : const Color(0xFFF3E8FF);

  // v0.5 nötr cam: koyu modda kartlar hafif saydam grafit + ince kristal kenar
  // v0.8.1 sıvı cam: yüzeyler yarı saydam, seçili tema arkadan görünür
  Color get cardBg => (JuzzioGlassTokens.custom == null ? null : JuzzioGlassTokens.surfaceSolid) ?? (isDark
      ? const Color(0x5C15161B)
      : const Color(0x8CFFFFFF));
  Color get cardBgElevated => (JuzzioGlassTokens.custom == null ? null : JuzzioGlassTokens.surfaceSolid) ?? (isDark
      ? const Color(0x7A1C1D23)
      : const Color(0xB3FFFFFF));
  Color get glassPanelBg => (JuzzioGlassTokens.custom == null ? null : JuzzioGlassTokens.surfaceSolid) ?? (isDark
      ? const Color(0x70121318)
      : const Color(0xA6FFFFFF));
  Color get glassCardBg => glassPanelBg;
  Color get inputBg => (JuzzioGlassTokens.custom == null ? null : JuzzioGlassTokens.surface) ?? (isDark
      ? const Color(0x14FFFFFF)
      : const Color(0x8CFFFFFF));
  Color get pillBg => (JuzzioGlassTokens.custom == null ? null : JuzzioGlassTokens.surfaceStrong) ?? (isDark
      ? const Color(0x1AFFFFFF)
      : const Color(0x99FFFFFF));

  Color get glassBorder => (JuzzioGlassTokens.custom == null ? null : JuzzioGlassTokens.border) ?? (isDark
      ? const Color(0x2EFFFFFF)
      : const Color(0xB3FFFFFF));
  Color get glassHighlight => isDark
      ? Colors.white.withOpacity(0.08)
      : Colors.white;

  // "Cool!" ve "Turn on notifications" butonlarının karakteristik derin siyah (#161618) tonu
  Color get coolButtonBg => JuzzioGlassTokens.custom?.button ?? (isDark ? JuzzioColors.white : JuzzioColors.ink);
  Color get coolButtonFg => JuzzioGlassTokens.custom?.buttonText ?? (isDark ? JuzzioColors.surface141416 : JuzzioColors.white);

  // Vurgu renkleri: Modern Orman Siyahı (#07120C) + Kraliyet İndigo/Mavisi (#2563EB / #3B28CC)
  // Gece modunda eski turuncu tonlar tamamen kaldırıldı.
  Color get amberPrimary => JuzzioColors.blue600;
  Color get amberLight => isDark ? JuzzioColors.blue500 : JuzzioColors.slate800;
  Color get amberDark => JuzzioColors.surface0B0F17;
  Color get amberGlow => JuzzioGlassTokens.custom?.icon ?? (isDark ? JuzzioColors.blue400 : JuzzioColors.blue600);
  Color get badgeOrange => JuzzioColors.red500;
  Color get badgeBlue => JuzzioColors.blueVivid;
  Color get headerDarkForest => Colors.transparent;
  Color get activeNavIndigo => isDark ? JuzzioColors.indigo500 : JuzzioColors.brandIndigo;

  Color get textPrimary => JuzzioGlassTokens.custom?.text ?? (isDark ? JuzzioColors.slate50 : JuzzioColors.slate900);
  Color get textSecondary => (JuzzioGlassTokens.custom == null ? null : JuzzioGlassTokens.textSecondary) ?? (isDark ? JuzzioColors.slate400 : JuzzioColors.slate500);
  Color get textMuted => (JuzzioGlassTokens.custom == null ? null : JuzzioGlassTokens.textMuted) ?? (isDark ? JuzzioColors.slate500 : JuzzioColors.slate400);

  Color get onlineGreen => JuzzioColors.emerald500;
  Color get dangerRed => JuzzioColors.red500;

  // Nötr cam: giden balon grafit, beyaz yazı her iki modda okunur
  // v0.6 Glassmorphism: giden balon seçili cam temasının tonunda yarı saydam cam,
  // gelen balon buzlu beyaz/gri cam. Beyaz yazı her iki modda okunur.
  // v0.8.1: giden balon seçili SOHBET TEMASININ rengi + parlaklık/vurgu yoğunluğu.
  // "Cam (Varsayılan)" teması seçili cam temasının tonunu kullanır.
  Color get outgoingBubble {
    final ct = JuzzioGlassTokens.custom;
    if (ct != null) return ct.bubbleOut.withValues(alpha: (ct.bubbleOut.a * 0.9).clamp(0.3, 1.0));
    final ctrl = JuzzioAppController.instance;
    final k = ctrl.chatThemeIntensity;
    final cp = ctrl.chatPalette;
    final rawTint = cp?.swatchA ?? (_preset.id == kJuzzioChatThemes.first.id ? ctrl.glassPalette.swatchA : _preset.primaryColor);
    // açık tonlarda (Cam Beyaz, Krom) beyaz yazı okunur kalsın diye ton koyulaştırılır
    var tint = rawTint;
    final hsl = HSLColor.fromColor(rawTint);
    for (var i = 1; i <= 12 && tint.computeLuminance() > 0.12; i++) {
      tint = hsl.withLightness((hsl.lightness * (1 - i * 0.07)).clamp(0.08, 1.0)).toColor();
    }
    // sıvı cam: renkli ama yarı saydam; beyaz yazı okunur kalsın diye koyu cam taban
    final a = ((isDark ? 0.52 : 0.72) * k).clamp(0.3, 0.9);
    return Color.alphaBlend(tint.withValues(alpha: a), isDark ? const Color(0x5C15161B) : const Color(0x8C2C2C2E));
  }
  Color get incomingBubble {
    final ct = JuzzioGlassTokens.custom;
    if (ct != null) return ct.bubbleIn.withValues(alpha: (ct.bubbleIn.a * 0.82).clamp(0.3, 1.0));
    final k = JuzzioAppController.instance.chatThemeIntensity;
    final cp = JuzzioAppController.instance.chatPalette;
    final accent = cp?.swatchB ?? (_preset.id == kJuzzioChatThemes.first.id ? JuzzioAppController.instance.glassPalette.swatchB : _preset.secondaryColor);
    return isDark
        ? Color.alphaBlend(accent.withValues(alpha: (0.12 * k).clamp(0.05, 0.2)), _preset.incomingDarkColor.withValues(alpha: 0.55))
        : Color.alphaBlend(accent.withValues(alpha: (0.14 * k).clamp(0.06, 0.22)), const Color(0xB3FFFFFF));
  }

  List<BoxShadow> get softCardShadow => isDark
      ? [
          BoxShadow(
            color: Colors.black.withOpacity(0.32),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ]
      : [
          BoxShadow(
            color: JuzzioColors.slate900.withOpacity(0.06),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
        ];

  List<BoxShadow> get coolButtonShadow => [
        BoxShadow(
          color: JuzzioColors.surface141416.withOpacity(isDark ? 0.38 : 0.22),
          blurRadius: 24,
          spreadRadius: 0,
          offset: const Offset(0, 10),
        ),
      ];

  LinearGradient get backgroundGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [
                JuzzioColors.obsidianRaised,
                JuzzioColors.obsidian,
                Color(0xFF070708),
              ]
            : const [
                JuzzioColors.white,
                JuzzioColors.surfaceF9FAFC,
                JuzzioColors.surfaceF3F5F9,
              ],
      );

  LinearGradient get amberButtonGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? const [Color(0xFF636366), Color(0xFF3A3A3C)]
            : const [JuzzioColors.deepForest, JuzzioColors.slate800],
      );
}

/// Instagram.jpg içerisindeki "Cool!" ve "Turn on notifications" tarzı geniş oval hap buton bileşeni
class JuzzioCoolPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool isLoading;
  final double height;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const JuzzioCoolPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.isLoading = false,
    this.height = 56,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    final bg = backgroundColor ?? JuzzioColors.ink;
    final fg = foregroundColor ?? Colors.white;

    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          boxShadow: p.coolButtonShadow,
        ),
        child: Center(
          child: isLoading
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(color: fg, strokeWidth: 2.4),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: fg, size: 19),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: JuzzioConfig.fontRegularBold,
                          color: fg,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class JuzzioStrings {
  final String lang;
  const JuzzioStrings(this.lang);

  bool get isTr => lang.toLowerCase() == 'tr';

  /// Dil paketleri için çevrilecek tüm anahtarlı İngilizce kaynak metinler.
  static List<String> englishCatalog() {
    final set = <String>{};
    final en = _dict['en'] ?? const <String, String>{};
    final tr = _dict['tr'] ?? const <String, String>{};
    for (final k in tr.keys) {
      final v = en[k] ?? tr[k];
      if (v != null && v.trim().isNotEmpty) set.add(v);
    }
    for (final entry in kJuzzioV030Strings.values) {
      final v = entry['en'] ?? entry['tr'];
      if (v != null && v.trim().isNotEmpty) set.add(v);
    }
    for (final v in kJuzzioInlineEnglishCatalog) {
      if (v.trim().isNotEmpty) set.add(v);
    }
    return set.toList();
  }

  static final Map<String, Map<String, String>> _dict = {
    'tr': {
      'app_name': 'Juzzio',
      'skip': 'Başka zaman',
      'hey_prefix': 'Hey ',
      'new_messages_sub': '5 yeni mesajınız var',
      'onb1_title': 'İlham veren kişiler',
      'onb1_sub': 'Dil bariyeri olmadan anlık çeviriyle bağlandığınız ve ilham verdiğiniz kişiler.',
      'onb1_cta': 'Harika!',
      'onb2_title': 'Arkadaşlarınızın neler\nyaptığını kaçırmayın.',
      'onb2_sub': 'O değerli anları, mesajları ve canlı çevirili aramaları asla kaçırmayın.',
      'onb2_cta': 'Bildirimleri aç',
      'login_tab': 'Giriş Yap',
      'register_tab': 'Kayıt Ol',
      'auth_welcome_login': 'Tekrar Hoş Geldiniz',
      'auth_welcome_register': 'Yeni Hesap Oluştur',
      'auth_sub_login': 'Kullanıcı adınız (@kullanici) veya e-posta adresiniz ile giriş yapın.',
      'auth_sub_register': 'Cihaz diliniz otomatik algılandı. Saniyeler içinde kayıt olun; tüm çeviriler otomatiktir.',
      'username_label': 'Kullanıcı Adı',
      'username_hint': '@tugkancr',
      'username_or_email_label': 'Kullanıcı Adı veya E-Posta',
      'username_or_email_hint': 'tugkancr veya ornek@eposta.com',
      'email_label': 'E-Posta Bilgisi',
      'email_hint': 'ornek@eposta.com',
      'password_label': 'Şifre',
      'password_hint': '••••••••',
      'password_confirm_label': 'Şifreni Doğrula',
      'password_confirm_hint': 'Şifrenizi tekrar girin',
      'password_mismatch': 'Girdiğiniz iki şifre birbiriyle eşleşmiyor. Lütfen kontrol edin.',
      'login_btn': 'Giriş Yap',
      'register_btn': 'Hesap Oluştur ve Başla',
      'chats_title': 'Sohbetler',
      'calls_title': 'Aramalar',
      'updates_title': 'Durumlar',
      'friends_title': 'Arkadaşlar',
      'profile_title': 'Profil ve Ayarlar',
      'search_placeholder': 'Mesajlarda veya kişilerde ara...',
      'filter_all': 'Tümü',
      'filter_favorites': 'Favoriler',
      'filter_work': 'İş',
      'filter_design': 'Tasarım',
      'filter_groups': 'Gruplar',
      'filter_communities': 'Arkadaşlar',
      'nav_chats': 'Sohbetler',
      'nav_call': 'Aramalar',
      'nav_updates': 'Durum',
      'nav_friends': 'Arkadaşlar',
      'nav_profile': 'Ayarlar',
      'edit_profile': 'Profili Düzenle',
      'save_changes': 'Kaydet',
      'bio_label': 'Biyografi',
      'bio_hint': 'Kendinizden kısaca bahsedin...',
      'change_photo': 'Fotoğrafı Seç ve Kırp',
      'notification': 'Bildirimler',
      'media_visibility': 'Medya Görünürlüğü',
      'bookmarked': 'Yıldızlı Mesajlar',
      'lock_chat': 'Sohbet Kilidi',
      'silent_mode': 'Cihaz Sessiz Modu (Aramayı Otomatik Meşgule Al)',
      'subtitle_lang_title': 'Altyazı Çeviri Diliniz (139+ Dil)',
      'subtitle_lang_sub': 'Gelen mesaj, ses, hikaye ve canlı altyazıların çevrileceği dil',
      'app_lang_title': 'Uygulama Dili (139+ Dil)',
      'app_lang_sub': 'Cihaz dilinize göre otomatik başlar; tüm menüleri anında çevirir',
      'theme_mode_title': 'Görünüm ve Tema Modu',
      'dark_mode': 'Gece Modu',
      'light_mode': 'Açık Tema',
      'logout': 'Çıkış Yap',
      'type_message': 'Mesaj yazın (Otomatik çevrilir)...',
      'hold_to_record': 'Sesli mesaj için basılı tutun',
      'recording_voice': 'Ses kaydediliyor... Göndermek için bırakın',
      'react_hint': 'Tekli emoji tepkisi seçin',
      'friend_search_title': 'Arkadaş Ekle & Kişilerim',
      'friend_search_hint': '@kullaniciadi yazarak ara...',
      'send_friend_req': 'Arkadaş Ekle',
      'friend_req_sent': 'İstek Gönderildi',
      'friend_accepted': 'Arkadaşsınız',
      'incoming_friend_reqs': 'Gelen Arkadaşlık İstekleri',
      'accept_req': 'Onayla',
      'reject_req': 'Reddet',
      'create_call_link': 'Arama bağlantısı oluştur',
      'create_call_link_sub': 'Juzzio konferans aramanız için bir bağlantı paylaşın',
      'recent_calls': 'Son Aramalar',
      'call_info_title': 'Arama Bilgisi',
      'incoming_voice_call': 'Gelen Sesli Arama',
      'outgoing_voice_call': 'Giden Sesli Arama',
      'incoming_video_call': 'Gelen Görüntülü Arama',
      'outgoing_video_call': 'Giden Görüntülü Arama',
      'missed_call': 'Cevapsız Arama',
      'answered_call': 'Cevaplandı',
      'silent_auto_busy': "Cihazınız sessiz modda olduğu için arama otomatik meşgul'e alındı",
      'select_friend_to_call': 'Aramak İçin Arkadaş veya Grup Seçin',
      'stories_24h_title': '24 Saatlik Fotoğraf & Video Durumlar',
      'add_story': 'Durum Ekle',
      'story_hold_hint': 'Durdurmak için basılı tutun • Yanıtlamak için aşağıdan yazın',
      'story_swipe_up_hint': 'Duruma Yanıt Ver veya Emoji Gönder',
      'crop_title': 'Stüdyo: Görseli Düzenle & Kırp',
      'crop_confirm': 'Uygula ve Kullan',
      'quick_reply_hint': 'Bildirimden hızlı yanıt yazın...',
      'send': 'Gönder',
      'accept_call': 'Aramaya Katıl',
      'decline_call': 'Reddet',
      'you_badge': 'Ben',
      'hd_audio_call': 'Juzzio HD Sesli Görüşme',
      'instant_translate_title': 'Juzzio Canlı Çeviri',
      'translation_label': 'Canlı Çeviri',
      'drag_to_move_hint': 'Taşımak için sürükleyin',
      'minimized_prefix': 'Canlı Çeviri',
      'menu_new_group': 'Yeni Grup Oluştur (Kişi Seçmeli)',
      'menu_new_channel': 'Yeni Kanal Oluştur',
      'menu_linked_devices': 'Bağlı Cihazlar (QR)',
      'menu_starred': 'Yıldızlı Mesajlar',
      'menu_settings': 'Ayarlar',
      'settings_account': 'Hesap',
      'settings_privacy': 'Gizlilik',
      'settings_chats': 'Sohbetler',
      'settings_appearance': 'Görünüm',
      'settings_storage': 'Depolama ve veriler',
      'settings_notifications': 'Bildirimler',
      'settings_app_lang': 'Uygulama dili (139+ Dil)',
      'settings_accessibility': 'Erişilebilirlik',
      'settings_invite': 'Kişi Davet Et',
      'settings_developer': 'Yapımcı',
      'same_lang_tr_info': 'İki Türk kullanıcı görüşüyor • Canlı çeviri otomatik kapalı',
      'foreign_joined_info': 'Yabancı katılımcı algılandı • Canlı altyazı çevirisi aktif',
      'tap_to_swap_hint': 'Görüntünüzü büyütmek / yer değiştirmek için dokunun (Yalnızca sizin ekranınızda)',
      'select_group_members': 'Gruba Eklenecek Arkadaşları Seçin',
      'no_friends_yet': 'Henüz ekli arkadaşınız yok. Önce @kullanıcıadı ile arkadaş ekleyin.',
      'message_friend': 'Mesaj Gönder',
    },
    'en': {
      'app_name': 'Juzzio',
      'skip': 'Another time',
      'hey_prefix': 'Hey ',
      'new_messages_sub': 'You have 5 new messages',
      'onb1_title': 'Inspired people',
      'onb1_sub': 'Number of people inspired by your conversations and real-time translation.',
      'onb1_cta': 'Cool!',
      'onb2_title': "Don't miss out on what your\nfriend's are up to.",
      'onb2_sub': 'Never miss those precious moments.',
      'onb2_cta': 'Turn on notifications',
      'login_tab': 'Sign In',
      'register_tab': 'Create Account',
      'auth_welcome_login': 'Welcome Back',
      'auth_welcome_register': 'Create Your Account',
      'auth_sub_login': 'Sign in with your @username or email address.',
      'auth_sub_register': 'Device language detected automatically. Register in seconds with instant translation.',
      'username_label': 'Username',
      'username_hint': '@tugkancr',
      'username_or_email_label': 'Username or Email',
      'username_or_email_hint': 'tugkancr or name@email.com',
      'email_label': 'Email Address',
      'email_hint': 'name@email.com',
      'password_label': 'Password',
      'password_hint': '••••••••',
      'password_confirm_label': 'Confirm Password',
      'password_confirm_hint': 'Re-enter your password',
      'password_mismatch': 'Passwords do not match. Please verify both fields.',
      'login_btn': 'Sign In',
      'register_btn': 'Create Account & Start',
      'chats_title': 'Chats',
      'calls_title': 'Calls',
      'updates_title': 'Status',
      'friends_title': 'Friends',
      'profile_title': 'Profile & Settings',
      'search_placeholder': 'Search messages or contacts...',
      'filter_all': 'All',
      'filter_favorites': 'Favorites',
      'filter_work': 'Work',
      'filter_design': 'Design',
      'filter_groups': 'Groups',
      'filter_communities': 'Friends',
      'nav_chats': 'Chats',
      'nav_call': 'Calls',
      'nav_updates': 'Status',
      'nav_friends': 'Friends',
      'nav_profile': 'Settings',
      'edit_profile': 'Edit Profile',
      'save_changes': 'Save',
      'bio_label': 'Bio',
      'bio_hint': 'Write a short bio about yourself...',
      'change_photo': 'Pick & Crop Photo',
      'notification': 'Notifications',
      'media_visibility': 'Media Visibility',
      'bookmarked': 'Starred Messages',
      'lock_chat': 'Lock Chat',
      'silent_mode': 'Silent Mode (Auto-Busy Incoming Calls)',
      'subtitle_lang_title': 'Subtitle Translation Language (139+)',
      'subtitle_lang_sub': 'Target language for incoming messages, voice notes, stories & live subtitles',
      'app_lang_title': 'App Language (139+ Languages)',
      'app_lang_sub': 'Follows your device language automatically; translates all menus',
      'theme_mode_title': 'Appearance & Theme Mode',
      'dark_mode': 'Night Mode',
      'light_mode': 'Light Theme',
      'logout': 'Sign Out',
      'type_message': 'Type a message (Auto-translates)...',
      'hold_to_record': 'Hold mic to record voice note',
      'recording_voice': 'Recording voice... Release to send',
      'react_hint': 'Tap an emoji reaction',
      'friend_search_title': 'Add Friend & My Contacts',
      'friend_search_hint': 'Search by @username...',
      'send_friend_req': 'Add Friend',
      'friend_req_sent': 'Request Sent',
      'friend_accepted': 'Friends',
      'incoming_friend_reqs': 'Incoming Friend Requests',
      'accept_req': 'Accept',
      'reject_req': 'Decline',
      'create_call_link': 'Create call link',
      'create_call_link_sub': 'Share a link for your Juzzio conference call',
      'recent_calls': 'Recent Calls',
      'call_info_title': 'Call Info',
      'incoming_voice_call': 'Incoming Voice Call',
      'outgoing_voice_call': 'Outgoing Voice Call',
      'incoming_video_call': 'Incoming Video Call',
      'outgoing_video_call': 'Outgoing Video Call',
      'missed_call': 'Missed Call',
      'answered_call': 'Answered',
      'silent_auto_busy': 'Call was automatically set to busy because your device is in silent mode',
      'select_friend_to_call': 'Select a Friend or Group to Call',
      'stories_24h_title': '24-Hour Photo & Video Status Updates',
      'add_story': 'Add Status',
      'story_hold_hint': 'Hold to pause • Type below to reply',
      'story_swipe_up_hint': 'Reply to Status or Send Emoji',
      'crop_title': 'Studio: Edit & Crop Image',
      'crop_confirm': 'Apply & Save',
      'quick_reply_hint': 'Reply directly from notification...',
      'send': 'Send',
      'accept_call': 'Join Call',
      'decline_call': 'Decline',
      'you_badge': 'You',
      'hd_audio_call': 'Juzzio HD Audio Call',
      'instant_translate_title': 'Juzzio Live Translation',
      'translation_label': 'Live Translation',
      'drag_to_move_hint': 'Drag to move',
      'minimized_prefix': 'Live Translation',
      'menu_new_group': 'Create New Group (Select Friends)',
      'menu_new_channel': 'Create New Channel',
      'menu_linked_devices': 'Linked Devices (QR)',
      'menu_starred': 'Starred Messages',
      'menu_settings': 'Settings',
      'settings_account': 'Account',
      'settings_privacy': 'Privacy',
      'settings_chats': 'Chats',
      'settings_appearance': 'Appearance',
      'settings_storage': 'Storage and data',
      'settings_notifications': 'Notifications',
      'settings_app_lang': 'App language (139+)',
      'settings_accessibility': 'Accessibility',
      'settings_invite': 'Invite a friend',
      'settings_developer': 'Developer / Creator',
      'same_lang_tr_info': 'Same native language detected • Live translation paused',
      'foreign_joined_info': 'Foreign participant detected • Live subtitle translation active',
      'tap_to_swap_hint': 'Tap your camera to enlarge / swap view (Only on your screen)',
      'select_group_members': 'Select Friends to Add to Group',
      'no_friends_yet': 'No friends added yet. Search by @username to add friends first.',
      'message_friend': 'Send Message',
    },
    'de': {
      'app_name': 'Juzzio',
      'skip': 'Später',
      'hey_prefix': 'Hey ',
      'new_messages_sub': 'Du hast 5 neue Nachrichten',
      'onb1_title': 'Inspirierte Menschen',
      'onb1_sub': 'Verbinde dich ohne Sprachbarrieren durch Echtzeit-Übersetzung.',
      'onb1_cta': 'Cool!',
      'onb2_title': 'Verpasse nicht, was deine\nFreunde gerade machen.',
      'onb2_sub': 'Verpasse nie wieder diese wertvollen Momente.',
      'onb2_cta': 'Benachrichtigungen aktivieren',
      'login_tab': 'Anmelden',
      'register_tab': 'Registrieren',
      'auth_welcome_login': 'Willkommen zurück',
      'auth_welcome_register': 'Neues Konto erstellen',
      'auth_sub_login': 'Melde dich mit deinem @Benutzernamen oder deiner E-Mail-Adresse an.',
      'auth_sub_register': 'Gerätesprache automatisch erkannt. In Sekunden registrieren; Übersetzung erfolgt automatisch.',
      'username_label': 'Benutzername',
      'username_hint': '@tugkancr',
      'username_or_email_label': 'Benutzername oder E-Mail',
      'username_or_email_hint': 'tugkancr oder name@email.com',
      'email_label': 'E-Mail-Adresse',
      'email_hint': 'name@email.com',
      'password_label': 'Passwort',
      'password_hint': '••••••••',
      'password_confirm_label': 'Passwort bestätigen',
      'password_confirm_hint': 'Passwort erneut eingeben',
      'password_mismatch': 'Die Passwörter stimmen nicht überein.',
      'login_btn': 'Anmelden',
      'register_btn': 'Konto erstellen & starten',
      'chats_title': 'Chats',
      'calls_title': 'Anrufe',
      'updates_title': 'Status',
      'friends_title': 'Freunde',
      'profile_title': 'Profil & Einstellungen',
      'search_placeholder': 'Nachrichten oder Kontakte suchen...',
      'filter_all': 'Alle',
      'filter_favorites': 'Favoriten',
      'filter_work': 'Arbeit',
      'filter_design': 'Design',
      'filter_groups': 'Gruppen',
      'filter_communities': 'Freunde',
      'nav_chats': 'Chats',
      'nav_call': 'Anrufe',
      'nav_updates': 'Status',
      'nav_friends': 'Freunde',
      'nav_profile': 'Einstellungen',
      'edit_profile': 'Profil bearbeiten',
      'save_changes': 'Speichern',
      'bio_label': 'Biografie',
      'bio_hint': 'Schreibe etwas über dich...',
      'change_photo': 'Foto auswählen & zuschneiden',
      'notification': 'Benachrichtigungen',
      'media_visibility': 'Mediensichtbarkeit',
      'bookmarked': 'Markierte Nachrichten',
      'lock_chat': 'Chat sperren',
      'silent_mode': 'Lautlos-Modus (Anrufe automatisch beschäftigt)',
      'subtitle_lang_title': 'Untertitel-Übersetzungssprache (139+)',
      'subtitle_lang_sub': 'Zielsprache für Nachrichten, Sprachnotizen, Storys & Live-Untertitel',
      'app_lang_title': 'App-Sprache (139+ Sprachen)',
      'app_lang_sub': 'Richtet sich automatisch nach der Gerätesprache',
      'theme_mode_title': 'Darstellung & Designmodus',
      'dark_mode': 'Nachtmodus',
      'light_mode': 'Helles Design',
      'logout': 'Abmelden',
      'type_message': 'Nachricht schreiben (Automatisch übersetzt)...',
      'hold_to_record': 'Gedrückt halten für Sprachnotiz',
      'recording_voice': 'Sprachaufnahme läuft... Loslassen zum Senden',
      'react_hint': 'Emoji-Reaktion auswählen',
      'friend_search_title': 'Freund hinzufügen & Kontakte',
      'friend_search_hint': 'Nach @Benutzername suchen...',
      'send_friend_req': 'Freund hinzufügen',
      'friend_req_sent': 'Anfrage gesendet',
      'friend_accepted': 'Befreundet',
      'incoming_friend_reqs': 'Eingehende Freundschaftsanfragen',
      'accept_req': 'Annehmen',
      'reject_req': 'Ablehnen',
      'create_call_link': 'Anruflink erstellen',
      'create_call_link_sub': 'Teile einen Link für deinen Juzzio-Konferenzanruf',
      'recent_calls': 'Letzte Anrufe',
      'call_info_title': 'Anrufinfo',
      'incoming_voice_call': 'Eingehender Sprachanruf',
      'outgoing_voice_call': 'Ausgehender Sprachanruf',
      'incoming_video_call': 'Eingehender Videoanruf',
      'outgoing_video_call': 'Ausgehender Videoanruf',
      'missed_call': 'Verpasster Anruf',
      'answered_call': 'Angenommen',
      'silent_auto_busy': 'Anruf wurde automatisch abgelehnt, da der Lautlos-Modus aktiv ist',
      'select_friend_to_call': 'Freund oder Gruppe zum Anrufen wählen',
      'stories_24h_title': '24-Stunden Foto- & Video-Status',
      'add_story': 'Status teilen',
      'story_hold_hint': 'Gedrückt halten zum Pausieren • Unten antworten',
      'story_swipe_up_hint': 'Auf Status antworten oder Emoji senden',
      'crop_title': 'Studio: Bild bearbeiten & zuschneiden',
      'crop_confirm': 'Anwenden & speichern',
      'quick_reply_hint': 'Schnellantwort schreiben...',
      'send': 'Senden',
      'accept_call': 'Anruf beitreten',
      'decline_call': 'Ablehnen',
      'you_badge': 'Du',
      'hd_audio_call': 'Juzzio HD-Sprachanruf',
      'instant_translate_title': 'Juzzio Live-Übersetzung',
      'translation_label': 'Live-Übersetzung',
      'drag_to_move_hint': 'Zum Verschieben ziehen',
      'minimized_prefix': 'Live-Übersetzung',
      'menu_new_group': 'Neue Gruppe erstellen (Freunde wählen)',
      'menu_new_channel': 'Neuen Kanal erstellen',
      'menu_linked_devices': 'Verknüpfte Geräte (QR)',
      'menu_starred': 'Markierte Nachrichten',
      'menu_settings': 'Einstellungen',
      'settings_account': 'Konto',
      'settings_privacy': 'Datenschutz',
      'settings_chats': 'Chats',
      'settings_appearance': 'Darstellung',
      'settings_storage': 'Speicher und Daten',
      'settings_notifications': 'Benachrichtigungen',
      'settings_app_lang': 'App-Sprache (139+)',
      'settings_accessibility': 'Barrierefreiheit',
      'settings_invite': 'Freund einladen',
      'settings_developer': 'Entwickler',
      'same_lang_tr_info': 'Gleiche Sprache erkannt • Live-Übersetzung pausiert',
      'foreign_joined_info': 'Fremdsprachiger Teilnehmer erkannt • Live-Untertitel aktiv',
      'tap_to_swap_hint': 'Tippe auf dein Bild zum Vergrößern/Tauschen (Nur für dich sichtbar)',
      'select_group_members': 'Freunde für die Gruppe auswählen',
      'no_friends_yet': 'Noch keine Freunde hinzugefügt. Suche zuerst über @Benutzername.',
      'message_friend': 'Nachricht senden',
    },
  };

  String t(String key) {
    final code = lang.toLowerCase();
    final v030 = kJuzzioV030Strings[key];
    if (v030 != null) {
      final direct = v030[code];
      if (direct != null) return direct;
      return JuzzioAppController.instance.translateUiDynamic(
        v030['tr'] ?? key,
        enText: v030['en'],
        deText: v030['de'],
      );
    }
    final directMap = _dict[code];
    if (directMap != null && directMap.containsKey(key)) {
      return directMap[key]!;
    }
    final trVal = _dict['tr']![key] ?? key;
    final enVal = _dict['en']![key] ?? trVal;
    final deVal = _dict['de']?[key];
    return JuzzioAppController.instance.translateUiDynamic(
      trVal,
      enText: enVal,
      deText: deVal,
    );
  }
}

// =============================================================================
// TELEGRAM / WHATSAPP SEVİYESİ MODERN GÖRSEL KIRPMA, DÖNDÜRME & FİLTRE STÜDYOSU
// =============================================================================
class JuzzioImageCropperModal extends StatefulWidget {
  final File sourceFile;
  final bool isCircular;
  final double aspectRatio;
  final String title;

  const JuzzioImageCropperModal({
    super.key,
    required this.sourceFile,
    this.isCircular = true,
    this.aspectRatio = 1.0,
    this.title = 'Görseli Düzenle ve Kırp',
  });

  static Future<File?> show(
    BuildContext context, {
    required File sourceFile,
    bool isCircular = true,
    double aspectRatio = 1.0,
    String? title,
  }) {
    final s = JuzzioStrings(JuzzioAppController.instance.uiLang);
    return Navigator.of(context).push<File?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => JuzzioImageCropperModal(
          sourceFile: sourceFile,
          isCircular: isCircular,
          aspectRatio: aspectRatio,
          title: title ?? s.t('crop_title'),
        ),
      ),
    );
  }

  @override
  State<JuzzioImageCropperModal> createState() => _JuzzioImageCropperModalState();
}

class _JuzzioImageCropperModalState extends State<JuzzioImageCropperModal> {
  final GlobalKey _cropBoundaryKey = GlobalKey();
  final TransformationController _transformController = TransformationController();
  double _currentScale = 1.0;
  int _quarterTurns = 0;
  bool _flipHorizontal = false;
  late double _selectedAspect;
  int _selectedFilterIndex = 0;
  bool _isExporting = false;

  static const List<Map<String, dynamic>> _filters = [
    {
      'name': 'Orijinal',
      'matrix': <double>[
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
      ],
    },
    {
      'name': 'Canlı HD',
      'matrix': <double>[
        1.15, -0.05, -0.05, 0, 4,
        -0.05, 1.12, -0.05, 0, 4,
        -0.05, -0.05, 1.15, 0, 4,
        0, 0, 0, 1, 0,
      ],
    },
    {
      'name': 'Sıcak Gün',
      'matrix': <double>[
        1.12, 0.04, 0.0, 0, 10,
        0.02, 1.04, 0.0, 0, 4,
        0.0, 0.0, 0.92, 0, -6,
        0, 0, 0, 1, 0,
      ],
    },
    {
      'name': 'Sinematik',
      'matrix': <double>[
        1.05, 0.0, 0.05, 0, -4,
        0.0, 1.06, 0.05, 0, 2,
        0.04, 0.06, 1.16, 0, 12,
        0, 0, 0, 1, 0,
      ],
    },
    {
      'name': 'Mono S&B',
      'matrix': <double>[
        0.33, 0.59, 0.11, 0, 0,
        0.33, 0.59, 0.11, 0, 0,
        0.33, 0.59, 0.11, 0, 0,
        0, 0, 0, 1, 0,
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _selectedAspect = widget.aspectRatio;
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _applySliderZoom(double zoom) {
    setState(() {
      _currentScale = zoom;
      _transformController.value = Matrix4.identity()..scale(zoom);
    });
  }

  Future<void> _exportCroppedImage() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final boundary = _cropBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        Navigator.of(context).pop(widget.sourceFile);
        return;
      }
      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        Navigator.of(context).pop(widget.sourceFile);
        return;
      }
      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final outPath = '${tempDir.path}/juzzio_studio_${DateTime.now().millisecondsSinceEpoch}.png';
      final outFile = File(outPath);
      await outFile.writeAsBytes(pngBytes, flush: true);
      if (!mounted) return;
      Navigator.of(context).pop(outFile);
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop(widget.sourceFile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appCtrl = JuzzioAppController.instance;
    final s = JuzzioStrings(appCtrl.uiLang);
    final screenW = MediaQuery.of(context).size.width;
    final cropW = screenW - 36;
    final cropH = widget.isCircular
        ? cropW
        : (cropW / _selectedAspect).clamp(240.0, 440.0);
    final matrix = _filters[_selectedFilterIndex]['matrix'] as List<double>;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontFamily: JuzzioConfig.fontRegularBold,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: appCtrl.trEn('90° Döndür', 'Rotate 90°', '90° drehen'),
            onPressed: () => setState(() => _quarterTurns = (_quarterTurns + 1) % 4),
            icon: const Icon(Icons.rotate_90_degrees_ccw_rounded, color: Colors.white),
          ),
          IconButton(
            tooltip: appCtrl.trEn('Yatay Çevir', 'Flip Horizontal', 'Horizontal spiegeln'),
            onPressed: () => setState(() => _flipHorizontal = !_flipHorizontal),
            icon: const Icon(Icons.flip_rounded, color: Colors.white),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!widget.isCircular)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final ratioItem in [
                    {'label': '9:16 Hikaye', 'val': 9 / 14},
                    {'label': '1:1 Kare', 'val': 1.0},
                    {'label': '4:5 Portre', 'val': 4 / 5},
                    {'label': '16:9 Geniş', 'val': 16 / 9},
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(
                          ratioItem['label'] as String,
                          style: TextStyle(
                            fontFamily: JuzzioConfig.fontRegularBold,
                            fontSize: 11.5,
                            color: (_selectedAspect - (ratioItem['val'] as double)).abs() < 0.05
                                ? Colors.black
                                : Colors.white70,
                          ),
                        ),
                        selected: (_selectedAspect - (ratioItem['val'] as double)).abs() < 0.05,
                        selectedColor: Colors.white,
                        backgroundColor: JuzzioColors.surface1F2128,
                        onSelected: (_) => setState(() => _selectedAspect = ratioItem['val'] as double),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: Center(
              child: Container(
                width: cropW,
                height: cropH,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.isCircular ? cropW / 2 : 26),
                  border: Border.all(color: Colors.white, width: 2.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.55),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.isCircular ? cropW / 2 : 24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        key: _cropBoundaryKey,
                        child: Container(
                          color: Colors.black,
                          child: InteractiveViewer(
                            transformationController: _transformController,
                            minScale: 1.0,
                            maxScale: 5.0,
                            panEnabled: true,
                            scaleEnabled: true,
                            boundaryMargin: const EdgeInsets.all(140),
                            onInteractionUpdate: (_) {
                              final scale = _transformController.value.getMaxScaleOnAxis();
                              setState(() => _currentScale = scale.clamp(1.0, 5.0));
                            },
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()..scale(_flipHorizontal ? -1.0 : 1.0, 1.0),
                              child: RotatedBox(
                                quarterTurns: _quarterTurns,
                                child: ColorFiltered(
                                  colorFilter: ColorFilter.matrix(matrix),
                                  child: Image.file(
                                    widget.sourceFile,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _CropGridPainter(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Filtre Seçici Şeridi
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, idx) {
                final active = _selectedFilterIndex == idx;
                return GestureDetector(
                  onTap: () => setState(() => _selectedFilterIndex = idx),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? JuzzioColors.blue600 : JuzzioColors.surface1E2028,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _filters[idx]['name'] as String,
                      style: const TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.zoom_out_rounded, color: JuzzioColors.ink),
                    Expanded(
                      child: Slider(
                        value: _currentScale.clamp(1.0, 5.0),
                        min: 1.0,
                        max: 5.0,
                        activeColor: JuzzioColors.ink,
                        inactiveColor: JuzzioColors.gray200,
                        onChanged: _applySliderZoom,
                      ),
                    ),
                    const Icon(Icons.zoom_in_rounded, color: JuzzioColors.ink),
                    const SizedBox(width: 8),
                    Text(
                      '${_currentScale.toStringAsFixed(1)}x',
                      style: const TextStyle(
                        fontFamily: JuzzioConfig.fontRegularBold,
                        color: JuzzioColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                JuzzioCoolPillButton(
                  label: s.t('crop_confirm'),
                  icon: Icons.check_circle_rounded,
                  isLoading: _isExporting,
                  onTap: _exportCroppedImage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CropGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.26)
      ..strokeWidth = 1.0;

    final thirdW = size.width / 3;
    final thirdH = size.height / 3;
    for (int i = 1; i <= 2; i++) {
      canvas.drawLine(Offset(thirdW * i, 0), Offset(thirdW * i, size.height), paint);
      canvas.drawLine(Offset(0, thirdH * i), Offset(size.width, thirdH * i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// =============================================================================
// TAM EKRAN / ARAMALI 139+ DİL SEÇİM SAYFASI
// =============================================================================
class JuzzioLanguagePickerSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final String currentCode;
  final ValueChanged<String> onSelected;

  const JuzzioLanguagePickerSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.currentCode,
    required this.onSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String currentCode,
    required ValueChanged<String> onSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => JuzzioLanguagePickerSheet(
        title: title,
        subtitle: subtitle,
        currentCode: currentCode,
        onSelected: onSelected,
      ),
    );
  }

  @override
  State<JuzzioLanguagePickerSheet> createState() => _JuzzioLanguagePickerSheetState();
}

class _JuzzioLanguagePickerSheetState extends State<JuzzioLanguagePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final p = JuzzioPalette(JuzzioAppController.instance.isDark);
    final filtered = kJuzzioSupportedLanguages.where((lang) {
      if (_query.trim().isEmpty) return true;
      final q = _query.toLowerCase();
      return lang.nativeName.toLowerCase().contains(q) ||
          lang.turkishName.toLowerCase().contains(q) ||
          lang.code.toLowerCase().contains(q);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      decoration: BoxDecoration(
        color: p.bgPrimary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(color: p.glassBorder),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: p.textMuted.withOpacity(0.4),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontFamily: JuzzioConfig.fontRegularBold,
                          color: p.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: JuzzioColors.ink,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${kJuzzioSupportedLanguages.length} Dil',
                        style: const TextStyle(
                          fontFamily: JuzzioConfig.fontRegularBold,
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  widget.subtitle,
                  style: TextStyle(color: p.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  style: TextStyle(color: p.textPrimary, fontFamily: JuzzioConfig.fontRegularBold),
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: JuzzioAppController.instance.t('lang_search_hint'),
                    hintStyle: TextStyle(color: p.textMuted),
                    prefixIcon: Icon(Icons.search_rounded, color: p.textPrimary),
                    filled: true,
                    fillColor: p.inputBg,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(color: p.glassBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide(color: p.glassBorder),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final item = filtered[idx];
                final isSelected = item.code.toLowerCase() == widget.currentCode.toLowerCase();
                return InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    widget.onSelected(item.code.toLowerCase());
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: isSelected ? JuzzioColors.ink : p.cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? JuzzioColors.ink : p.glassBorder,
                        width: isSelected ? 1.6 : 1.0,
                      ),
                      boxShadow: p.softCardShadow,
                    ),
                    child: Row(
                      children: [
                        Text(item.flag, style: const TextStyle(fontSize: 25)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.nativeName,
                                style: TextStyle(
                                  fontFamily: JuzzioConfig.fontRegularBold,
                                  color: isSelected ? Colors.white : p.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${item.turkishName} (${item.code.toUpperCase()})',
                                style: TextStyle(
                                  color: isSelected ? Colors.white70 : p.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle_rounded, color: JuzzioColors.blue600, size: 24)
                        else
                          Icon(Icons.circle_outlined, color: p.textMuted, size: 22),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// MODERN ANİMASYONLU BEYAZ (COOL) / GECE TEMA SEÇİCİ KARTI
// =============================================================================
class JuzzioModernThemeSelector extends StatelessWidget {
  const JuzzioModernThemeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = JuzzioAppController.instance;
    final p = JuzzioPalette(ctrl.isDark);
    final s = JuzzioStrings(ctrl.uiLang);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.glassBorder),
        boxShadow: p.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: p.pillBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  ctrl.isDark ? Icons.nights_stay_rounded : Icons.wb_sunny_rounded,
                  color: p.textPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  s.t('theme_mode_title'),
                  style: TextStyle(
                    fontFamily: JuzzioConfig.fontRegularBold,
                    color: p.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => ctrl.setThemeMode(ThemeMode.light),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    decoration: BoxDecoration(
                      color: !ctrl.isDark ? JuzzioColors.ink : p.inputBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.wb_sunny_rounded,
                          color: !ctrl.isDark ? Colors.white : p.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            s.t('light_mode'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: JuzzioConfig.fontRegularBold,
                              color: !ctrl.isDark ? Colors.white : p.textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => ctrl.setThemeMode(ThemeMode.dark),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    decoration: BoxDecoration(
                      color: ctrl.isDark ? JuzzioColors.blue600 : p.inputBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.dark_mode_rounded,
                          color: ctrl.isDark ? Colors.white : p.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            s.t('dark_mode'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: JuzzioConfig.fontRegularBold,
                              color: ctrl.isDark ? Colors.white : p.textSecondary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dil seçicilerden (ilk sayfa ve Ayarlar) çağrılır: gerekirse dil paketini
/// ilerleme göstergesiyle hazırlar, başarısızlıkta eski dili koruyup uyarı verir.
Future<void> juzzioSwitchUiLanguage(BuildContext context, String code, {bool alsoSubtitle = false}) async {
  final app = JuzzioAppController.instance;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final ok = await app.setUiLanguage(code);
  if (ok && alsoSubtitle) app.setSubtitleLanguage(code);
  messenger?.hideCurrentSnackBar();
  if (!ok) {
    messenger?.showSnackBar(SnackBar(content: Text(app.t('lang_pack_failed'))));
    return;
  }
  // Dil hemen değişti; yerleşik olmayan dillerde kalan metinler arka planda
  // çevrilirken ilerleme gösterilir (uygulama kullanılmaya devam edilebilir).
  if (app.languagePackProgress.value != null) {
    messenger?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: ValueListenableBuilder<double?>(
          valueListenable: app.languagePackProgress,
          builder: (_, value, __) => Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, value: value ?? 1),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(app.t('lang_pack_downloading').replaceAll('{p}', '${((value ?? 1) * 100).round()}')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
