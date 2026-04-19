import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:pointycastle/export.dart';
import 'package:convert/convert.dart';
import 'package:uuid/uuid.dart';
import 'dart:typed_data';
import 'dart:io';

/// 密钥常量
class Constant {
  // schild的盐
  static const schildSalt = r"ipL$TkeiEmfy1gTXb2XHrdLN0a@7c^vu";

  // 网页登录
  static const webLoginKey = "u2oh6Vu^HWe4_AES";

  // 发送验证码
  static const sendCaptchaKey = "jsDyctOCnay7uotq";

  // APP登录
  static const appLoginKey = "z4ok6lu^oWp4_AES";
  
  // 设备指纹
  static const deviceCodeKey = 'QrCbNY@MuK1X8HGw';

  // getDeviceInfo RSA公钥
  static const rsaPublicKey = 'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC79d8Ot0hCbxxSISC6x8SCwTBspFSzlLKHJUYqoFNu1TSRaw4hEYkOnvEaL1VyoxV6HXcDrzwYvaFZaZaPQPFnfCHZy5dQwxcmifgSHqS+oKXw40Ys4cVIqnU5d90S7EWSRdBglX489jlqVaNcQSkDx2TYmC+DbAq9FV/BU09ISQIDAQAB';

  // inf_enc
  static const infEncToken = "4faa8662c59590c6f43ae9fe5b002b42";
  static const infEncKey = "Z(AfY@XS";

  // IM密码解密
  static const imKey = "SL2(M/eD";

  // 学习通验证码
  static const cxCaptchaId = "Qt9FIw9o4pwRjOyqM6yizZBh682qN2TU";

  // 雨课堂腾讯验证码
  static const tCaptchaAppId = '2091064951';
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

  /// DES ECB解密 (DES/ECB/PKCS5Padding)
  static String desEcbDecrypt(String hexCipher, String key) {
    final cipherBytes = Uint8List.fromList(hex.decode(hexCipher));
    
    // DESede 模拟单 DES：将 8 字节密钥扩展为 24 字节 (K1||K2||K3, K1=K2=K3)
    final keyBytes = utf8.encode(key);
    final extendedKey = Uint8List(24);
    for (int i = 0; i < 3; i++) {
      extendedKey.setRange(i * 8, i * 8 + 8, keyBytes);
    }

    final desEngine = DESedeEngine();
    final ecbCipher = ECBBlockCipher(desEngine);

    final keyParams = KeyParameter(extendedKey);
    ecbCipher.init(false, keyParams);

    final decrypted = Uint8List(cipherBytes.length);
    var offset = 0;
    while (offset < cipherBytes.length) {
      final processed = ecbCipher.processBlock(cipherBytes, offset, decrypted, offset);
      offset += processed;
    }
    
    // PKCS5/PKCS7 去填充
    final paddedLength = decrypted.length;
    final padValue = decrypted[paddedLength - 1];
    final actualLength = paddedLength - padValue;
    
    return utf8.decode(decrypted.sublist(0, actualLength));
  }

  /// RSA 公钥加密（PKCS#1 v1.5） 自动分段
  static String rsaEncrypt(String text, String publicKeyBase64) {
    // 解析公钥
    final keyDer = base64.decode(publicKeyBase64);
    final asn1Parser = ASN1Parser(Uint8List.fromList(keyDer));
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;

    final asn1Objects = topLevelSeq.elements!;
    
    // 第二个元素是 BIT STRING，包含实际的 RSA 公钥
    final bitString = asn1Objects[1] as ASN1BitString;
    final publicKeyBytes = bitString.valueBytes!.sublist(1);
    
    // 解析内部的 RSAPublicKey
    final publicKeyParser = ASN1Parser(Uint8List.fromList(publicKeyBytes));
    final publicKeySeq = publicKeyParser.nextObject() as ASN1Sequence;
    final publicKeyElements = publicKeySeq.elements!;
    
    final modulusBigInt = (publicKeyElements[0] as ASN1Integer).integer!;
    final exponentBigInt = (publicKeyElements[1] as ASN1Integer).integer!;
    final publicKey = RSAPublicKey(modulusBigInt, exponentBigInt);

    final keyLength = (publicKey.modulus!.bitLength + 7) ~/ 8; // 1024 位 => 128 字节
    final maxChunkSize = keyLength - 11; // PKCS#1 填充最多 117 字节

    final plainBytes = Uint8List.fromList(utf8.encode(text));

    // 使用 PKCS#1 v1.5 填充进行分段加密
    final encryptedChunks = <Uint8List>[];
    for (int i = 0; i < plainBytes.length; i += maxChunkSize) {
      final end = (i + maxChunkSize) < plainBytes.length ? i + maxChunkSize : plainBytes.length;
      final chunk = plainBytes.sublist(i, end);
      
      final cipher = PKCS1Encoding(RSAEngine());
      cipher.init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
      final encrypted = cipher.process(chunk);
      encryptedChunks.add(encrypted);
    }

    // 拼接
    final totalLen = encryptedChunks.fold(0, (sum, chunk) => sum + chunk.length);
    final allEncrypted = Uint8List(totalLen);
    int offset = 0;
    for (final chunk in encryptedChunks) {
      allEncrypted.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    return base64.encode(allEncrypted);
  }

  static String md5Hash(String text) {
    return md5.convert(utf8.encode(text)).toString();
  }

  /// UID生成 用于登录识别设备
  /// 与'_c_0_'的生成方式一致
  static String getUniqueId() {
    return getUuid().replaceAll(r'-', '');
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
        bytesToHash = List<int>.from(await raf.read(totalSize));
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