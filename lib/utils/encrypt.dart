import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';
import 'dart:io';

/// 密钥常量
class Constant {
  // schild的盐
  static const String schildSalt = r"ipL$TkeiEmfy1gTXb2XHrdLN0a@7c^vu";

  // 网页登录
  static const String webLoginKey = "u2oh6Vu^HWe4_AES";

  // 发送验证码
  static const String sendCaptchaKey = "jsDyctOCnay7uotq";

  // APP登录
  static const String appLoginKey = "z4ok6lu^oWp4_AES";
  
  // 设备指纹
  static const String deviceCodeKey = 'QrCbNY@MuK1X8HGw';

  // inf_enc
  static const String infEncToken = "4faa8662c59590c6f43ae9fe5b002b42";
  static const String infEncKey = "Z(AfY@XS";

  // 学习通验证码
  static const String cxCaptchaId = "Qt9FIw9o4pwRjOyqM6yizZBh682qN2TU";

  // 雨课堂腾讯验证码
  static const String  tCaptchaAppId = '2091064951';
}

class EncryptionUtil {
  /// AES CBC加密
  static String aesCbcEncrypt(String text, String key) {
    final keyObj = encrypt.Key.fromUtf8(key);
    final iv = encrypt.IV.fromUtf8(key);
    
    final encrypter = encrypt.Encrypter(
      encrypt.AES(
        keyObj,
        mode: encrypt.AESMode.cbc,
        padding: 'PKCS7'
      )
    );

    final encrypted = encrypter.encrypt(text, iv: iv);
    return encrypted.base64;
  }
  
  /// AES ECB加密
  static String aesEcbEncrypt(String text, String key) {
    final keyObj = encrypt.Key.fromUtf8(key);
    final iv = encrypt.IV.fromLength(0); // ECB模式不需要IV
    
    final encrypter = encrypt.Encrypter(
      encrypt.AES(
        keyObj,
        mode: encrypt.AESMode.ecb,
        padding: 'PKCS7'
      )
    );

    final encrypted = encrypter.encrypt(text, iv: iv);
    return encrypted.base64;
  }

  static String md5Hash(String text) {
    return md5.convert(utf8.encode(text)).toString();
  }

  /// UID生成 用于登录识别设备
  /// 与'_c_0_'的生成方式一致
  static String getUniqueId() {
    var uuid = Uuid();
    return uuid.v4().replaceAll(r'-', '');
  }
  
  /// 设备指纹生成
  static String getDeviceCode() {
    String oaid = getUuid(); // 伪装OAID
    return aesEcbEncrypt(oaid, Constant.deviceCodeKey);
  }

  static Map<String, String> getEncParams(Map<String, String> params) {
    Map<String, String> encParams = {
      '_c_0_': getUniqueId(),
      'token': Constant.infEncToken,
      '_time': DateTime.now().millisecondsSinceEpoch.toString()
    };
    params.addAll(encParams);

    String queryString = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    encParams['inf_enc'] = md5Hash('$queryString&DESKey=${Constant.infEncKey}');
    return encParams;
  }

  static String getUuid() {
    var uuid = Uuid();
    return uuid.v4();
  }

  /// 获取文件的CRC（非标准）
  static Future<String> getCRC(File file) async {
    final totalSize = await file.length();
    final raf = await file.open();
    try {
      List<int> bytesToHash;
      if (totalSize > 1048576) { // 1MB
        // 读取首尾各 512KB
        final first = await raf.read(524288);
        await raf.setPosition(totalSize - 524288);
        final last = await raf.read(524288);
        bytesToHash = [...first, ...last];
      } else {
        bytesToHash = await raf.read(totalSize);
      }

      final sizeHex = totalSize.toRadixString(16);
      bytesToHash.addAll(utf8.encode(sizeHex));

      final digest = md5.convert(bytesToHash);
      return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    } finally {
      await raf.close();
    }
  }
}