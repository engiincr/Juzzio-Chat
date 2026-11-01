package com.juzzio.app

import androidx.core.content.FileProvider

/** Uygulama içi güncellemede indirilen APK'yı paket yükleyiciye vermek için ayrı sağlayıcı
 *  (diğer eklentilerin FileProvider tanımlarıyla çakışmaz). */
class JuzzioOtaFileProvider : FileProvider()
