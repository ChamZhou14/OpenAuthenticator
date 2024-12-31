import cryptoFramework from '@ohos.security.cryptoFramework';
import { hilog } from '@kit.PerformanceAnalysisKit';

interface DataBlob {
  data: Uint8Array;
}

const TAG = '[TOTPUtil]';
const DOMAIN = 0x0002;
const PERIOD = 30;  // 使用常量替代类属性

export class TOTPUtil {
  static getRemainingSeconds(): number {
    const now = Math.floor(Date.now() / 1000);
    return PERIOD - (now % PERIOD);
  }

  static async generateTOTP(secret: string): Promise<string> {
    try {
      hilog.info(DOMAIN, TAG, 'Generating TOTP for secret');
      const counter = Math.floor(Date.now() / 1000 / PERIOD);
      hilog.info(DOMAIN, TAG, `Counter: ${counter}`);
      
      // 将计数器转换为 8 字节的 buffer
      const counterBytes = new ArrayBuffer(8);
      const view = new DataView(counterBytes);
      view.setBigInt64(0, BigInt(counter), false);
      
      // Base32 解码密钥并创建 DataBlob
      const keyBytes: DataBlob = {
        data: TOTPUtil.base32Decode(secret)
      };
      
      // 创建 HMAC 实例，使用 HmacSha1 作为算法
      const mac = await cryptoFramework.createMac('SHA1');
      // 创建对称密钥
      const symKeyGenerator = await cryptoFramework.createSymKeyGenerator('HMAC');
      const key = await symKeyGenerator.convertKey(keyBytes);
      // 确保等待 init 完成
      await mac.init(await key);
      
      // 创建数据
      const inputData: DataBlob = {
        data: new Uint8Array(counterBytes)
      };
      await mac.update(inputData);
      const hmacResult = await mac.doFinal();
      
      // 将结果转换为 Uint8Array 以便操作
      const resultArray = new Uint8Array(hmacResult.data);
      
      // 动态截断
      const offset = resultArray[resultArray.length - 1] & 0xf;
      const binary = ((resultArray[offset] & 0x7f) << 24) |
                    ((resultArray[offset + 1] & 0xff) << 16) |
                    ((resultArray[offset + 2] & 0xff) << 8) |
                    (resultArray[offset + 3] & 0xff);
      
      // 生成指定位数的验证码
      const otp = binary % Math.pow(10, 6);
      const result = otp.toString().padStart(6, '0');
      hilog.info(DOMAIN, TAG, `Generated code: ${result}`);
      return result;
      
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to generate TOTP: %{public}s', error.message);
      return '000000';  // 返回默认值而不是抛出错误
    }
  }

  private static base32Decode(base32: string): Uint8Array {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    const bytes: number[] = [];
    let buffer = 0;
    let bitsLeft = 0;
    
    // 移除所有非字母数字字符并转换为大写
    base32 = base32.replace(/[^A-Za-z2-7]/g, '').toUpperCase();
    
    for (let i = 0; i < base32.length; i++) {
      buffer = (buffer << 5) | alphabet.indexOf(base32[i]);
      bitsLeft += 5;
      
      if (bitsLeft >= 8) {
        bytes.push((buffer >> (bitsLeft - 8)) & 0xff);
        bitsLeft -= 8;
      }
    }
    
    return new Uint8Array(bytes);
  }
} 