// =============================================================================
// JUZZIO v1.2.9 — Dosya Güvenlik Denetimi (otomatik)
//  Gönderilen her dosya şifrelenmeden ÖNCE cihazda, alınan her dosya şifresi çözüldükten
//  SONRA (açmadan/kaydetmeden önce) bu denetimden geçer. Uçtan uca şifreleme nedeniyle sunucu
//  içeriği göremez; bu yüzden içerik denetimi cihazda yapılır, sunucu ise ad/tür kısıtlar.
//
//  Engellenenler:
//   • Sunucu/web betikleri: .php .phtml .phar .jsp .jspx .asp .aspx .cgi .pl .py .rb .sh .ps1 …
//   • Tarayıcıda çalışan/XSS taşıyabilen: .html .htm .xhtml .svg .js .mjs .hta .xml(+betik)
//   • Çalıştırılabilir/kurulum: .exe .dll .msi .scr .com .bat .cmd .vbs .jar .apk .aab .xapk .dex …
//   • Gizli çift uzantı (fatura.pdf.php), Unicode sağdan-sola hilesi (fatura‮fdp.exe)
//   • Uzantısı ile içeriği uyuşmayan dosya (ör. .jpg adlı ama içi PHP/EXE)
//   • İçinde <?php, <%@, <script, <iframe, javascript: barındıran "metin" dosyaları
//   • İçinde APK / EXE / betik barındıran ZIP arşivleri
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Yükleme türü
enum JuzzioUploadKind { image, video, audio, document }

/// Denetim sonucu
enum JuzzioFileVerdict {
  ok,
  empty,
  tooLarge,
  badName,
  blockedExtension,
  doubleExtension,
  executableContent,
  scriptContent,
  signatureMismatch,
  dangerousArchive,
}

class JuzzioFileCheck {
  final JuzzioFileVerdict verdict;
  final String detail;
  final String sniffed;
  const JuzzioFileCheck(this.verdict, {this.detail = '', this.sniffed = 'unknown'});
  bool get ok => verdict == JuzzioFileVerdict.ok;
}

/// Kesin engellenen uzantılar (sunucu SQL'indeki listeyle aynı tutulur)
const Set<String> kJuzzioBlockedExtensions = {
  // sunucu tarafı betikler
  'php', 'php3', 'php4', 'php5', 'php7', 'php8', 'phtml', 'pht', 'phar', 'phps', 'inc',
  'jsp', 'jspx', 'jsw', 'jsv', 'jspf', 'asp', 'aspx', 'asa', 'asax', 'ascx', 'ashx', 'asmx', 'cer',
  'cgi', 'pl', 'pm', 'py', 'pyc', 'pyw', 'rb', 'sh', 'bash', 'zsh', 'ksh', 'csh', 'ps1', 'psm1', 'psd1',
  'cfm', 'cfml', 'shtml', 'shtm', 'stm', 'htaccess', 'htpasswd', 'war', 'ear',
  // tarayıcıda çalışan / XSS
  'html', 'htm', 'xhtml', 'xht', 'mht', 'mhtml', 'svg', 'svgz', 'js', 'mjs', 'cjs', 'jse', 'hta', 'xsl', 'xslt',
  'swf', 'xbap', 'url', 'webloc', 'desktop',
  // çalıştırılabilir / kurulum / sistem
  'exe', 'dll', 'msi', 'msp', 'mst', 'scr', 'com', 'pif', 'bat', 'cmd', 'vbs', 'vbe', 'wsf', 'wsh', 'wsc',
  'jar', 'class', 'apk', 'apks', 'aab', 'xapk', 'apkm', 'dex', 'so', 'elf', 'bin', 'run', 'out', 'ko',
  'reg', 'lnk', 'inf', 'cpl', 'msc', 'gadget', 'scf', 'sys', 'drv', 'ocx',
  'app', 'dmg', 'pkg', 'deb', 'rpm', 'appx', 'appxbundle', 'msix', 'msixbundle', 'ipa', 'iso', 'img', 'vhd', 'vhdx',
  'docm', 'dotm', 'xlsm', 'xltm', 'xlam', 'pptm', 'potm', 'ppam', 'sldm', // makrolu Office
};

/// Bilinen güvenli belge uzantıları (içerik imzası doğrulanır)
const Set<String> kJuzzioDocumentExtensions = {
  'pdf', 'txt', 'csv', 'tsv', 'md', 'json', 'rtf', 'log',
  'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp', 'pages', 'numbers', 'key', 'epub',
  'zip', 'rar', '7z', 'tar', 'gz',
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp',
  'mp3', 'm4a', 'aac', 'ogg', 'oga', 'opus', 'wav', 'flac', 'amr',
  'mp4', 'mov', 'm4v', 'webm', '3gp', 'mkv',
  // CNC / CAD (Juzzio kullanıcılarının iş dosyaları)
  'dwg', 'dxf', 'nc', 'tap', 'gcode', 'ngc', 'mpf', 'cnc', 'eia', 'step', 'stp', 'igs', 'iges', 'stl',
};

const Set<String> _textLike = {'txt', 'csv', 'tsv', 'md', 'json', 'log', 'nc', 'tap', 'gcode', 'ngc', 'mpf', 'cnc', 'eia', 'dxf', 'step', 'stp', 'igs', 'iges', 'rtf'};

/// Dosya adındaki tüm uzantılar (küçük harf; "a.tar.gz" → [tar, gz]) — saf; test edilir
List<String> juzzioFileExtensions(String name) {
  final base = name.split(RegExp(r'[\\/]')).last.trim().toLowerCase();
  final parts = base.split('.');
  if (parts.length < 2) return const [];
  return parts.sublist(1).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}

String juzzioFileExt(String name) {
  final e = juzzioFileExtensions(name);
  return e.isEmpty ? '' : e.last;
}

/// Görünmez/yön değiştiren Unicode karakterleri (RTL hilesi) — saf
final RegExp _bidiTricks = RegExp('[​-‏‪-‮⁦-⁩﻿]');

/// Dosya adını güvenli hâle getirir: yol ayırıcı, kontrol karakteri, RTL hilesi, sondaki
/// nokta/boşluk temizlenir; en çok 120 karakter (uzantı korunur). Saf; test edilir.
String juzzioCleanFileName(String raw) {
  var n = raw.split(RegExp(r'[\\/]')).last;
  n = n.replaceAll(_bidiTricks, '').replaceAll(RegExp(r'[\x00-\x1F\x7F<>:"|?*]'), '_').trim();
  n = n.replaceAll(RegExp(r'[. ]+$'), '');
  while (n.startsWith('.')) {
    n = n.substring(1);
  }
  if (n.isEmpty) n = 'dosya';
  if (n.length > 120) {
    final dot = n.lastIndexOf('.');
    final ext = dot > 0 && n.length - dot <= 10 ? n.substring(dot) : '';
    n = n.substring(0, 120 - ext.length) + ext;
  }
  return n;
}

bool _startsWith(Uint8List b, List<int> sig, [int at = 0]) {
  if (b.length < at + sig.length) return false;
  for (var i = 0; i < sig.length; i++) {
    if (b[at + i] != sig[i]) return false;
  }
  return true;
}

/// İçerik imzasından tür tahmini (saf; test edilir). Dönen: jpeg png gif webp heic bmp mp4 webm
/// mkv ogg wav mp3 flac amr pdf zip ole rar 7z gz exe elf macho dex java php jsp script html svg
/// xml text unknown
String juzzioSniffKind(Uint8List b) {
  if (b.isEmpty) return 'unknown';
  if (_startsWith(b, [0xFF, 0xD8, 0xFF])) return 'jpeg';
  if (_startsWith(b, [0x89, 0x50, 0x4E, 0x47])) return 'png';
  if (_startsWith(b, ascii.encode('GIF8'))) return 'gif';
  if (_startsWith(b, ascii.encode('RIFF')) && _startsWith(b, ascii.encode('WEBP'), 8)) return 'webp';
  if (_startsWith(b, ascii.encode('RIFF')) && _startsWith(b, ascii.encode('WAVE'), 8)) return 'wav';
  if (_startsWith(b, ascii.encode('BM')) && b.length > 14) return 'bmp';
  if (b.length > 12 && _startsWith(b, ascii.encode('ftyp'), 4)) {
    final brand = ascii.decode(b.sublist(8, 12), allowInvalid: true).toLowerCase();
    if (brand.startsWith('hei') || brand.startsWith('mif') || brand.startsWith('hev') || brand == 'avif') return 'heic';
    if (brand.startsWith('m4a') || brand == 'm4b ') return 'mp4';
    return 'mp4';
  }
  if (_startsWith(b, [0x1A, 0x45, 0xDF, 0xA3])) return 'webm';
  if (_startsWith(b, ascii.encode('OggS'))) return 'ogg';
  if (_startsWith(b, ascii.encode('fLaC'))) return 'flac';
  if (_startsWith(b, ascii.encode('#!AMR'))) return 'amr';
  if (_startsWith(b, ascii.encode('ID3')) || (b.length > 1 && b[0] == 0xFF && (b[1] & 0xE0) == 0xE0)) return 'mp3';
  if (_startsWith(b, ascii.encode('%PDF'))) return 'pdf';
  if (_startsWith(b, [0x50, 0x4B, 0x03, 0x04]) || _startsWith(b, [0x50, 0x4B, 0x05, 0x06])) return 'zip';
  if (_startsWith(b, [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])) return 'ole';
  if (_startsWith(b, ascii.encode('Rar!'))) return 'rar';
  if (_startsWith(b, [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])) return '7z';
  if (_startsWith(b, [0x1F, 0x8B])) return 'gz';
  if (_startsWith(b, ascii.encode('MZ'))) return 'exe';
  if (_startsWith(b, [0x7F, 0x45, 0x4C, 0x46])) return 'elf';
  if (_startsWith(b, [0xCF, 0xFA, 0xED, 0xFE]) || _startsWith(b, [0xFE, 0xED, 0xFA, 0xCF]) ||
      _startsWith(b, [0xCA, 0xFE, 0xBA, 0xBE])) {
    return 'macho';
  }
  if (_startsWith(b, ascii.encode('dex\n'))) return 'dex';
  // metin tabanlı türler: ilk 8 KB küçük harfle incelenir
  final head = latin1.decode(b.length > 8192 ? b.sublist(0, 8192) : b, allowInvalid: true).toLowerCase();
  final printable = head.codeUnits.where((c) => c == 9 || c == 10 || c == 13 || (c >= 32 && c != 127)).length;
  final isText = head.isNotEmpty && printable / head.length > 0.92;
  if (!isText) return 'unknown';
  final t = head.trimLeft();
  if (head.contains('<?php') || RegExp(r'<\?=').hasMatch(head)) return 'php';
  if (head.contains('<%@') || head.contains('<jsp:') || RegExp(r'<%[=!]?\s').hasMatch(head)) return 'jsp';
  if (t.startsWith('#!')) return 'script';
  if (t.startsWith('<svg') || head.contains('<svg ')) return 'svg';
  if (t.startsWith('<!doctype html') || t.startsWith('<html') || head.contains('<script') ||
      head.contains('<iframe') || head.contains('<object') || head.contains('<embed') ||
      RegExp(r'on(load|error|click|mouseover)\s*=').hasMatch(head) || head.contains('javascript:')) {
    return 'html';
  }
  if (t.startsWith('<?xml')) return 'xml';
  if (RegExp(r'^\s*(@echo off|powershell|set-executionpolicy|cmd /c|wscript\.|createobject\()').hasMatch(head)) return 'script';
  return 'text';
}

/// ZIP içindeki dosya adlarını (yerel başlıklardan) çıkarır; tehlikeli içerik var mı? (saf)
bool juzzioZipLooksDangerous(Uint8List b) {
  var i = 0;
  var seen = 0;
  while (i + 30 < b.length && seen < 400) {
    if (b[i] == 0x50 && b[i + 1] == 0x4B && b[i + 2] == 0x03 && b[i + 3] == 0x04) {
      final nameLen = b[i + 26] | (b[i + 27] << 8);
      final extraLen = b[i + 28] | (b[i + 29] << 8);
      if (i + 30 + nameLen > b.length) break;
      final name = utf8.decode(b.sublist(i + 30, i + 30 + nameLen), allowMalformed: true).toLowerCase();
      seen++;
      if (name == 'androidmanifest.xml' || name == 'classes.dex' || name.endsWith('/classes.dex')) return true;
      final exts = juzzioFileExtensions(name);
      if (exts.isNotEmpty && kJuzzioBlockedExtensions.contains(exts.last) && !const {'xml', 'inc', 'bin'}.contains(exts.last)) {
        // Office belgeleri (docx/xlsx) iç .xml/.bin içerir — bunlar masumdur; diğer engelli türler tehlikelidir
        return true;
      }
      if (name.contains('../') || name.startsWith('/')) return true; // zip-slip
      i += 30 + nameLen + extraLen;
      continue;
    }
    i++;
  }
  return false;
}

const Set<String> _dangerSniff = {'exe', 'elf', 'macho', 'dex', 'php', 'jsp', 'script', 'html', 'svg'};

/// Ana denetim (saf; test edilir). [head]: dosyanın ilk ≤ 64 KB'ı.
JuzzioFileCheck juzzioCheckFile({
  required String name,
  required Uint8List head,
  required int size,
  required JuzzioUploadKind kind,
  int maxBytes = 100 * 1024 * 1024,
}) {
  if (size <= 0 || head.isEmpty) return const JuzzioFileCheck(JuzzioFileVerdict.empty);
  if (size > maxBytes) return const JuzzioFileCheck(JuzzioFileVerdict.tooLarge);
  if (_bidiTricks.hasMatch(name)) return const JuzzioFileCheck(JuzzioFileVerdict.badName, detail: 'bidi');
  final exts = juzzioFileExtensions(name);
  for (final e in exts) {
    if (kJuzzioBlockedExtensions.contains(e)) {
      return JuzzioFileCheck(exts.last == e ? JuzzioFileVerdict.blockedExtension : JuzzioFileVerdict.doubleExtension, detail: e);
    }
  }
  final sniff = juzzioSniffKind(head);
  if (const {'exe', 'elf', 'macho', 'dex'}.contains(sniff)) {
    return JuzzioFileCheck(JuzzioFileVerdict.executableContent, detail: sniff, sniffed: sniff);
  }
  if (_dangerSniff.contains(sniff)) {
    return JuzzioFileCheck(JuzzioFileVerdict.scriptContent, detail: sniff, sniffed: sniff);
  }
  final ext = exts.isEmpty ? '' : exts.last;
  bool isImage(String s) => const {'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'}.contains(s);
  bool isVideo(String s) => const {'mp4', 'webm'}.contains(s);
  bool isAudio(String s) => const {'mp4', 'ogg', 'wav', 'mp3', 'flac', 'amr', 'webm', 'unknown'}.contains(s);
  switch (kind) {
    case JuzzioUploadKind.image:
      if (!isImage(sniff)) return JuzzioFileCheck(JuzzioFileVerdict.signatureMismatch, detail: 'image≠$sniff', sniffed: sniff);
      break;
    case JuzzioUploadKind.video:
      if (!isVideo(sniff)) return JuzzioFileCheck(JuzzioFileVerdict.signatureMismatch, detail: 'video≠$sniff', sniffed: sniff);
      break;
    case JuzzioUploadKind.audio:
      if (!isAudio(sniff)) return JuzzioFileCheck(JuzzioFileVerdict.signatureMismatch, detail: 'audio≠$sniff', sniffed: sniff);
      break;
    case JuzzioUploadKind.document:
      // uzantı ↔ içerik tutarlılığı (bilinen türlerde)
      final expect = <String, Set<String>>{
        'pdf': {'pdf'},
        'docx': {'zip'}, 'xlsx': {'zip'}, 'pptx': {'zip'}, 'odt': {'zip'}, 'ods': {'zip'}, 'odp': {'zip'}, 'epub': {'zip'},
        'pages': {'zip'}, 'numbers': {'zip'}, 'key': {'zip'}, 'zip': {'zip'},
        'doc': {'ole'}, 'xls': {'ole'}, 'ppt': {'ole'},
        'rar': {'rar'}, '7z': {'7z'}, 'gz': {'gz'},
        'jpg': {'jpeg'}, 'jpeg': {'jpeg'}, 'png': {'png'}, 'gif': {'gif'}, 'webp': {'webp'}, 'heic': {'heic'}, 'heif': {'heic'}, 'bmp': {'bmp'},
        'mp4': {'mp4'}, 'mov': {'mp4'}, 'm4v': {'mp4'}, 'm4a': {'mp4'}, '3gp': {'mp4'}, 'webm': {'webm'}, 'mkv': {'webm'},
        'mp3': {'mp3'}, 'ogg': {'ogg'}, 'oga': {'ogg'}, 'opus': {'ogg'}, 'wav': {'wav'}, 'flac': {'flac'}, 'amr': {'amr'},
      };
      final want = expect[ext];
      if (want != null && !want.contains(sniff)) {
        return JuzzioFileCheck(JuzzioFileVerdict.signatureMismatch, detail: '$ext≠$sniff', sniffed: sniff);
      }
      if (_textLike.contains(ext) && !(sniff == 'text' || sniff == 'xml' || sniff == 'unknown' || (ext == 'rtf' && sniff == 'text'))) {
        return JuzzioFileCheck(JuzzioFileVerdict.signatureMismatch, detail: '$ext≠$sniff', sniffed: sniff);
      }
      if (sniff == 'xml' && head.length > 5 && latin1.decode(head, allowInvalid: true).toLowerCase().contains('<!entity')) {
        return const JuzzioFileCheck(JuzzioFileVerdict.scriptContent, detail: 'xxe', sniffed: 'xml'); // XXE
      }
      if (sniff == 'zip' && juzzioZipLooksDangerous(head)) {
        return const JuzzioFileCheck(JuzzioFileVerdict.dangerousArchive, sniffed: 'zip');
      }
      break;
  }
  return JuzzioFileCheck(JuzzioFileVerdict.ok, sniffed: sniff);
}

/// Sonucu kullanıcıya gösterilecek metne çevirir (tr/en/de)
String juzzioFileVerdictMessage(JuzzioFileCheck c, String Function(String tr, String en, String de) l) {
  switch (c.verdict) {
    case JuzzioFileVerdict.ok:
      return '';
    case JuzzioFileVerdict.empty:
      return l('Dosya boş veya okunamadı.', 'The file is empty or unreadable.', 'Die Datei ist leer oder unlesbar.');
    case JuzzioFileVerdict.tooLarge:
      return l('Dosya çok büyük.', 'The file is too large.', 'Die Datei ist zu groß.');
    case JuzzioFileVerdict.badName:
      return l('Dosya adında gizli/yanıltıcı karakterler var; güvenlik için gönderilmedi.',
          'The file name contains hidden/misleading characters; blocked for safety.', 'Der Dateiname enthält irreführende Zeichen; blockiert.');
    case JuzzioFileVerdict.blockedExtension:
      return l('Bu dosya türü (.${c.detail}) güvenlik nedeniyle gönderilemez (betik/çalıştırılabilir dosya).',
          'This file type (.${c.detail}) cannot be sent for security reasons (script/executable).',
          'Dieser Dateityp (.${c.detail}) ist aus Sicherheitsgründen gesperrt.');
    case JuzzioFileVerdict.doubleExtension:
      return l('Dosya adında gizli bir tehlikeli uzantı (.${c.detail}) var; gönderilmedi.',
          'The file name hides a dangerous extension (.${c.detail}); blocked.', 'Der Dateiname versteckt eine gefährliche Endung (.${c.detail}).');
    case JuzzioFileVerdict.executableContent:
      return l('Dosyanın içi çalıştırılabilir program; güvenlik nedeniyle engellendi.',
          'The file contains an executable program; blocked for safety.', 'Die Datei enthält ein ausführbares Programm; blockiert.');
    case JuzzioFileVerdict.scriptContent:
      return l('Dosyada çalıştırılabilir kod (betik/HTML) bulundu; engellendi.',
          'Executable code (script/HTML) was found in the file; blocked.', 'In der Datei wurde ausführbarer Code gefunden; blockiert.');
    case JuzzioFileVerdict.signatureMismatch:
      return l('Dosyanın içeriği uzantısıyla uyuşmuyor (sahte dosya olabilir); gönderilmedi.',
          'The file content does not match its extension (may be disguised); blocked.', 'Inhalt und Endung passen nicht zusammen; blockiert.');
    case JuzzioFileVerdict.dangerousArchive:
      return l('Arşivde uygulama/betik dosyası var; güvenlik nedeniyle engellendi.',
          'The archive contains an app or script; blocked for safety.', 'Das Archiv enthält eine App oder ein Skript; blockiert.');
  }
}

/// Dosyanın ilk [n] baytı
Future<Uint8List> juzzioReadHead(File f, [int n = 65536]) async {
  final b = BytesBuilder(copy: false);
  await for (final chunk in f.openRead(0, n)) {
    b.add(chunk);
  }
  return b.takeBytes();
}

/// Dosya üzerinde denetim (giden ve gelen dosyalar için)
Future<JuzzioFileCheck> juzzioInspectFile(File f, {required String name, required JuzzioUploadKind kind, int maxBytes = 100 * 1024 * 1024}) async {
  try {
    final size = await f.length();
    final head = await juzzioReadHead(f);
    return juzzioCheckFile(name: name, head: head, size: size, kind: kind, maxBytes: maxBytes);
  } catch (_) {
    return const JuzzioFileCheck(JuzzioFileVerdict.empty);
  }
}

/// Bellekteki baytlar (ör. şifresi çözülmüş gelen dosya) üzerinde denetim
JuzzioFileCheck juzzioInspectBytes(Uint8List bytes, {required String name, required JuzzioUploadKind kind}) =>
    juzzioCheckFile(
      name: name,
      head: bytes.length > 65536 ? Uint8List.sublistView(bytes, 0, 65536) : bytes,
      size: bytes.length,
      kind: kind,
      maxBytes: 1 << 31,
    );

/// Sunucuya yazılacak güvenli içerik türü: tarayıcıda çalışabilecek türler asla gönderilmez
String juzzioSafeUploadMime(String mime) {
  final m = mime.toLowerCase().trim();
  if (m.isEmpty || m.contains('html') || m.contains('svg') || m.contains('javascript') || m.contains('ecmascript') ||
      m.contains('php') || m.contains('xml') || m.contains('x-sh') || m.contains('msdownload') || m.contains('java-archive') ||
      m.contains('android.package')) {
    return 'application/octet-stream';
  }
  return m;
}
