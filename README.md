# Chameleon CLI — Android

Chameleon Ultra için Material 3 tabanlı, telefonda çalışan bir kontrol uygulaması.
Masaüstü [Chameleon CLI](https://github.com/RfidResearchGroup/ChameleonUltra/wiki/cli)
iş akışlarını dokunmatik arayüze taşır; slot yönetimi, HF/LF okuma, döküm arşivi,
emülatör kontrolü ve MIFARE Classic anahtar kurtarma içerir.

> Bu proje Proxgrind / RFID Research Group ile bağlantılı değildir. Kendi
> etiketleriniz ve yetkili olduğunuz sistemlerle kullanın.

## Öne çıkanlar

- **BLE bağlantısı** — Nordic UART Service üzerinden resmi ikili protokol
  (`SOF 0x11`, LRC, big-endian komutlar). Cihaz adı veya NUS servisi ile keşif.
- **Cihaz paneli** — model, yazılım/git sürümü, çip kimliği, BLE adresi, pil,
  okuyucu/emülatör modu.
- **8 slot** — HF/LF türü seçimi, varsayılan veri ile başlatma, etkinleştirme,
  takma ad, arayüz kaldırma, aktif slot ve flash'a kaydetme.
- **HF okuyucu** — ISO14443-A tarama (UID/ATQA/SAK/ATS), MIFARE Classic PRNG
  tespiti, MF1 ve MFU/NTAG döküm okuma.
- **Döküm arşivi** — `.bin`, `.eml`, `.json` içe/dışa aktarma, blok/sayfa hex
  görüntüleyici ve düzenleyici, sektör anahtarları, paylaşım.
- **MF1 emülatör** — bellek okuma/yazma, Gen1a/Gen2/block0 anti-coll, yazma
  modu, field-off reset, PRNG türü, MFKey32 algılama günlüğü ve günlükten
  anahtar kurtarma.
- **MFU/NTAG emülatör** — sayfa belleği, UID magic, yazma modu, sürüm, imza,
  sayaçlar, kimlik doğrulama sayacı.
- **125 kHz** — EM410x, HID Prox, ioProx, PAC/Stanley, Viking, Jablotron,
  Pyramid tarama; T55xx'ye yazma; slotta emülasyon.
- **Anahtar araçları** — hazır + kullanıcı sözlüğü, `.dic` içe/dışa aktarma,
  `fchk` tabanlı toplu anahtar denetimi.
- **MIFARE Classic kurtarma** — native `crapto1` çözücüleriyle darkside,
  nested ve static-nested; algılama günlüğünden MFKey32v2. Çözücü öz testi
  uygulama içinden çalıştırılabilir.
- **Blok araçları** — tek blok okuma/yazma ve value block inc/dec/restore.
- **Ham konsol** — komut kimliği + hex veri gönderimi, durum ve yanıt inceleme.
- **APDU konsolu** — JavaCard / ISO14443-4 geliştirmesi için ISO7816-4 APDU gönderimi,
  SW1/SW2 çözümlemesi ve genel BER-TLV görüntüleyici. Kart numarası okuyucu
  PPSE → PSE → GPO → READ RECORD adımlarını izleyip yalnızca PAN'ı gösterir.
- **Cihaz ayarları** — animasyon, A/B kısa/uzun basış işlevleri, BLE eşleştirme
  anahtarı, eşleşmeleri temizleme, uyku süresi, uzun basış eşiği, reset,
  fabrika sıfırlama ve bootloader'a girme.
- **Türkçe / English**, açık/koyu tema, Material 3.

## CLI komut karşılıkları

| CLI | Uygulama |
| --- | --- |
| `hw connect/version/chipid/address/mode/battery` | Bağlan ekranı + Ana sayfa |
| `hw slot list/type/init/enable/disable/change/nick/delete/store` | Slotlar |
| `hw settings animation/btnpress/blekey/blepair/bleclearbonds/sleep/longpress/save/reset` | Ayarlar → Cihaz ayarları |
| `hw factory_reset`, `hw dfu` | Cihaz ayarları (DFU yalnızca bootloader'a girer) |
| `hf 14a scan/info` | Oku → HF |
| `hf 14a raw` | Ham konsol (komut 2010) |
| `hf14a_4_reader_apdu` (ISO14443-4 reader APDU) | APDU konsolu (ham ISO7816-4) |
| `hf mf rdbl/wrbl/value` | Araçlar → MIFARE Classic blok araçları |
| `hf mf fchk` | Araçlar → Anahtar denetleyici |
| `hf mf nested/darkside` | Araçlar → MIFARE anahtar kurtarma |
| `hf mf elog` | MF1 emülatör → Algılama günlüğü |
| `hf mf eload/esave/eview/econfig` | MF1 emülatör |
| `hf mfu dump` | Oku → HF (MFU/NTAG dökümü) |
| `hf mfu eload/esave/eview/econfig/ercnt/ewcnt` | MFU emülatör |
| `lf em 410x`, `lf hid prox`, `lf io prox`, `lf pac`, `lf viking`, `lf jablotron`, `lf pyramid` | Oku → LF |
| `lf ... write`, `lf ... econfig` | Oku → LF / LF emülatör |
| `lf t55xx` | Oku → LF → T55xx'ye yaz |

## Desteklenmeyenler / sınırlar

Bu sürüm bilinçli olarak şunları içermez:

- **Hardnested** (sert PRNG'li kartlar). Darkside/nested/static-nested ve
  MFKey32v2 vardır; hardnested için masaüstü CLI kullanın.
- **USB-OTG** taşıması. Telefon tarafı BLE üzerinden çalışır.
- **DFU firmware güncelleme** akışı (bootloader'a girme komutu vardır).
- SEOS, EMV son kullanma tarihi çıkarımı, HF/LF sniffing, EM4x05 ve T55xx raw
  komutları. APDU konsolu ham ISO7816-4 komutları gönderir; kart numarası okuyucu
  yalnızca PAN'ı gösterir, başka ödeme verisi ayıklamaz.
- IDTECK okuma (yazma/emülasyon vardır; okuma firmware'de özel LF örnekleme
  gerektirir).

## Mimari

```
lib/
  protocol/      frame, command IDs, client, BLE transport, key recovery
                 key_recovery.dart (FFI), native C solver bridge
  models/        cihaz, slot, tarama ve döküm modelleri
  services/      oturum, BLE tarayıcı, döküm deposu, anahtar sözlüğü
  ui/screens/    Material 3 ekranları
android/app/src/main/jni/   crapto1, crypto1, mfkey, nested, darkside + bridge
```

- Protokol çerçevesi: `11 EF | CMD(2) | STATUS(2) | LEN(2) | LRC2 | DATA | LRC3`.
- Komutlar tek tek serileştirilir; yanıtlar komut kimliğine göre eşleştirilir.
- BLE yazımı MTU'ya göre parçalanır; firmware bayt akışı olarak birleştirir.
- Dökümler uygulama belgelerinde JSON olarak tutulur; `.bin`/`.eml` uyumludur.
- UI durumu `ChangeNotifier` + `provider` ile yönetilir.

## Derleme

Gereksinimler:

- Flutter 3.41+ / Dart 3.11+
- Android SDK 36, build-tools, NDK 28.2 ve CMake 3.22
  (Gradle ilk derlemede otomatik indirebilir)
- Java 17

```bash
flutter pub get
flutter test
flutter build apk --release
```

Çıktı: `build/app/outputs/flutter-apk/app-release.apk`.

Debug için:

```bash
flutter run -d <android-device>
```

İlk açılışta BLE izinleri istenir. Uygulama yalnızca gerçek bir Chameleon Ultra
ile çalışır; demo modu yoktur.

## GitHub Actions

`.github/workflows/build-apk.yml` her `main` push'unda ve pull request'te:

1. Java 17, Android SDK 36, NDK 28.2 ve CMake 3.22 kurar.
2. `flutter analyze` ve `flutter test` çalıştırır.
3. `flutter build apk --release` ile APK üretir.
4. APK'yı **Artifacts → chameleon-cli-apk-<sha>** olarak yükler.

`main` branch'ine yapılan her push, **Latest APK** adlı rolling release'i
günceller ve APK'yı doğrudan Releases sayfasına koyar. `v*` biçiminde bir tag
push edilirse (`v1.0.0` gibi) sürümlü bir release de oluşturulur. Release
APK'sı şu an debug anahtarıyla imzalanır; mağaza dağıtımı için
`android/app/build.gradle.kts` içinde kendi keystore/signing config'inizi
tanımlayın.


## Doğrulama

- `flutter test`: çerçeve kodlama/çözme, bozuk LRC yeniden senkronizasyonu,
  döküm kodekleri, sahte transport üzerinden uçtan uca döküm okuma/yazma, slot
  yapılandırması ve Türkçe metin tablosu.
- Native çözücüler host'ta derlenip MFKey32v2/MFKey64 vektörleriyle
  karşılaştırıldı; aynı çözücüler release APK'da `librecovery.so` olarak
  paketlenir. Uygulama içindeki **Run solver self-test** bunu cihazda doğrular.
- UI ve protokol akışları testlerdeki sahte transport ile doğrulandı; native
  çözücü öz testi release APK'da çalıştırıldı.

## Lisans

GPL-3.0. Ayrıntılar için `LICENSE`.

Native çözücüler, Chameleon Ultra / Proxmark3 projelerindeki GPL lisanslı
`crapto1`, `crypto1`, `mfkey`, `nested_util` kaynaklarından türetilmiştir.
Kaynaklar `android/app/src/main/jni/` altında ve derleme `CMakeLists.txt`
ile yapılır. Uygulama tarafındaki protokol ve UI kodu bu depoya aittir.

Chameleon Ultra, Proxgrind / RFID Research Group'un ürün adıdır. Bu proje
bağımsızdır.
