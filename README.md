# PeekForge

Finder'da Boşluk tuşuyla çalışan yerel Quick Look önizlemesi. Ayrı bir pencere veya Dock uygulaması açmaz.

## Kurulum

GitHub Releases sayfasındaki `PeekForge-macOS.zip` dosyasını indirin ve `PeekForge.app` uygulamasını `~/Applications` klasörüne taşıyın. Bir kez açın. Sistem Ayarları → Genel → Giriş Öğeleri ve Uzantılar → Quick Look bölümünde PeekForgePreview'ı etkinleştirin.

## Otomatik güncelleme

İlk açılışta kullanıcı hesabınız için `com.peekforge.update` adlı bir LaunchAgent kurulur. Bu görev, uygulama açık kalmadan günde bir kez GitHub'daki en son kararlı sürümü kontrol eder. Yeni sürüm varsa arşivi indirir, gömülü Ed25519 açık anahtarıyla imzayı doğrular, uygulama paketinin kimliğini ve sürümünü kontrol eder, ardından `~/Applications/PeekForge.app` dosyasını yeniler. Önceki sürüm `~/Applications/PeekForge.previous.app` olarak saklanır. Veri GitHub'a gönderilmez; yalnızca sürüm sorgusu yapılır.

Güncellemeleri devre dışı bırakmak için `~/Library/LaunchAgents/com.peekforge.update.plist` dosyasını kaldırın. Tek seferlik kontrol için `~/Library/Application Support/PeekForge/PeekForgeUpdater --check-updates` komutunu çalıştırabilirsiniz.

## Desteklenen dosyalar

- JSON ve JSONL / NDJSON
- Markdown, kaynak kod, YAML, TOML, INI, günlük ve UTF-8 metin
- `.env` dosyalarında gizlenen değerler
- CSV / TSV, SQLite (`.sqlite`, `.sqlite3`, `.db`)
- ZIP / TAR ve klasör listesi

Metin önizlemesi en fazla 2 MB, CSV/TSV en fazla 256 KB okur. JSONL 200 kayıtla, arşiv ve klasörler 100 öğeyle sınırlıdır. macOS bazı dosya türlerinde başka bir Quick Look sağlayıcısına öncelik verebilir.

## Geliştirme ve sürüm yayınlama

Xcode 26 ve macOS 15 veya sonrası gerekir. `./build-local.sh` ile yerel uygulamayı derleyin. Yeni sürümde proje içindeki `MARKETING_VERSION` ve `CURRENT_PROJECT_VERSION` değerlerini artırın. Kaynak değişikliklerini commit ettikten sonra `Tools/publish-release.sh` betiği uygulamayı derler, ZIP paketini imzalar ve GitHub Release oluşturur.

Yayın anahtarı varsayılan olarak bu çalışma alanındaki `work/peekforge-signing-private.key` dosyasındadır. Bu **özel anahtarı GitHub'a yüklemeyin**; güvenli bir yedeğini alın. İmza doğrulama için gereken açık anahtar `Updater.swift` içinde gömülüdür. Anahtar kaybolursa eski sürümler yeni imzalı güncellemeleri kabul edemez.
