import { TOTPUtil } from '../utils/TOTPUtil';
import promptAction from '@ohos.promptAction';
import common from '@ohos.app.ability.common';
import { scanBarcode } from '@kit.ScanKit';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import pasteboard from '@ohos.pasteboard';
import { StorageUtil } from '../utils/StorageUtil';
import { hilog } from '@kit.PerformanceAnalysisKit';

// 定义账户接口类型
interface Account {
  account: string,
  code: string,
  issuer: string,
  secret: string
}

type PermissionType = 'ohos.permission.CAMERA';

// 首先在文件顶部定义一个常量用于 hilog 的 domain
const TAG = '[Index]';
const DOMAIN = 0x0001;

@CustomDialog
struct QRCodeDialog {
  controller: CustomDialogController
  uri: string = ''

  build(): void {
    Column() {
      Text('扫描二维码')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 16 })

      QRCode(this.uri)
        .width(200)
        .height(200)
        .margin({ bottom: 16 })

      Button('关闭')
        .width(120)
        .onClick(() => {
          this.controller.close();
        })
    }
    .padding(24)
  }
}

@CustomDialog
struct ManualInputDialog {
  controller: CustomDialogController
  cancel: () => void = () => {}
  confirm: (account: Account) => void = () => {}
  @State issuer: string = ''
  @State account: string = ''
  @State secret: string = ''

  @Builder
  dialogContent() {
    Column() {
      Text('手动输入')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 24 })

      TextInput({ placeholder: '发行方名称' })
        .width('100%')
        .height(48)
        .margin({ bottom: 12 })
        .borderRadius(8)
        .backgroundColor('#F5F5F5')
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.issuer = value;
        })

      TextInput({ placeholder: '账户名称' })
        .width('100%')
        .height(48)
        .margin({ bottom: 12 })
        .borderRadius(8)
        .backgroundColor('#F5F5F5')
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.account = value;
        })

      TextInput({ placeholder: '密钥' })
        .width('100%')
        .height(48)
        .margin({ bottom: 24 })
        .borderRadius(8)
        .backgroundColor('#F5F5F5')
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.secret = value;
        })

      Row() {
        Button('取消')
          .width(120)
          .height(40)
          .backgroundColor('#F5F5F5')
          .fontColor('#333333')
          .borderRadius(20)
          .margin({ right: 12 })
          .onClick(() => {
            this.controller.close();
            this.cancel();
          })

        Button('确定')
          .width(120)
          .height(40)
          .backgroundColor('#007DFF')
          .borderRadius(20)
          .onClick(async () => {
            if (!this.secret) {
              promptAction.showToast({ message: '请输入密钥' });
              return;
            }
            if (!this.account) {
              promptAction.showToast({ message: '请输入账户名称' });
              return;
            }

            try {
              // 1. 验证密钥格式
              if (!this.validateBase32(this.secret)) {
                promptAction.showToast({ message: '密钥格式不正确，应为有效的 Base32 编码' });
                return;
              }

              // 2. 验证密钥是否能生成有效的验证码
              const code = await TOTPUtil.generateTOTP(this.secret);
              if (!code || code.length !== 6 || !/^\d{6}$/.test(code)) {
                promptAction.showToast({ message: '无效的密钥' });
                return;
              }

              const newAccount: Account = {
                issuer: this.issuer,
                account: this.account,
                secret: this.secret.toUpperCase().replace(/[^A-Z2-7]/g, ''), // 清理并标准化密钥
                code: code
              };
              this.controller.close();
              this.confirm(newAccount);
            } catch (error) {
              promptAction.showToast({ message: '无效的密钥' });
            }
          })
      }
      .justifyContent(FlexAlign.Center)
      .width('100%')
    }
    .width('100%')
    .padding(24)
    .backgroundColor(Color.White)
    .borderRadius(16)
  }

  private validateBase32(input: string): boolean {
    // 1. 移除所有填充字符
    const base32 = input.replace(/=+$/, '').toUpperCase();
    
    // 2. 检查是否只包含有效字符
    if (!/^[A-Z2-7]+$/.test(base32)) {
      return false;
    }
    
    // 3. 检查长度是否有效（去掉填充后应该是 8 的倍数）
    const unpadded = base32.length;
    if (unpadded === 0 || unpadded % 8 !== 0) {
      return false;
    }
    
    // 4. 检查长度是否在合理范围内（通常是 16 或 32 个字符）
    if (unpadded < 16 || unpadded > 32) {
      return false;
    }

    return true;
  }

  build() {
    Column() {
      this.dialogContent()
    }
  }
}

@Entry
@Component
struct Index {
  @State accounts: Array<Account> = []
  @State private countdown: number = 30
  @State private showQR: boolean = false
  @State private currentQRUri: string = ''
  private timer: number = -1
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
  private atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager()
  private qrDialogController: CustomDialogController = new CustomDialogController({
    builder: () => {
      const dialog = new QRCodeDialog();
      dialog.controller = this.qrDialogController;
      dialog.uri = '';
      return dialog;
    },
    autoCancel: true,
    alignment: DialogAlignment.Center
  })
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: ManualInputDialog({
      cancel: () => {
        hilog.info(DOMAIN, TAG, 'Dialog cancelled');
      },
      confirm: async (account: Account) => {
        this.accounts.push(account);
        await StorageUtil.saveAccounts(this.context, this.accounts);
        promptAction.showToast({ message: '添加成功' });
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  })

  async aboutToAppear(): Promise<void> {
    try {
      this.accounts = await StorageUtil.loadAccounts(this.context);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load accounts: %{public}s', error.toString());
      promptAction.showToast({ message: '加载账户失败' });
    }

    this.startTimer();
    this.updateCodes();
  }

  aboutToDisappear(): void {
    this.clearTimer()
  }

  private async updateCodes(): Promise<void> {
    try {
      for (let i = 0; i < this.accounts.length; i++) {
        const account = this.accounts[i];
        hilog.info(DOMAIN, TAG, 'Updating code for account: %{public}s', account.account);
        const code = await TOTPUtil.generateTOTP(account.secret);
        hilog.info(DOMAIN, TAG, 'Got new code: %{private}s', code);
        this.accounts[i] = {
          account: account.account,
          code: code,
          issuer: account.issuer,
          secret: account.secret
        };
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to update codes: %{public}s', error.toString());
    }
  }

  private startTimer(): void {
    if (this.timer !== -1) {
      return
    }

    hilog.info(DOMAIN, TAG, 'Starting timer');
    this.countdown = TOTPUtil.getRemainingSeconds();

    this.timer = setInterval(() => {
      const newCountdown = TOTPUtil.getRemainingSeconds();

      if (newCountdown > this.countdown) {
        hilog.info(DOMAIN, TAG, 'New period detected, updating codes');
        this.updateCodes();
      }

      this.countdown = newCountdown;
    }, 1000);
  }

  private clearTimer(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer)
      this.timer = -1
    }
  }

  private async copyCode(code: string): Promise<void> {
    try {
      const systemPasteboard = pasteboard.getSystemPasteboard();
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, '');
      data.addRecord(pasteboard.MIMETYPE_TEXT_PLAIN, code);
      await systemPasteboard.setData(data);
      promptAction.showToast({ message: '验证码已复制' });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Copy failed: %{public}s', error.toString());
      promptAction.showToast({ message: '复制失败' });
    }
  }

  private generateOTPAuthURI(account: Account): string {
    const params: string[] = [];
    params.push(`secret=${account.secret}`);
    if (account.issuer) {
      params.push(`issuer=${encodeURIComponent(account.issuer)}`);
    }

    const label = account.issuer
      ? `${encodeURIComponent(account.issuer)}:${encodeURIComponent(account.account)}`
      : encodeURIComponent(account.account);

    return `otpauth://totp/${label}?${params.join('&')}`;
  }

  private showQRCode(uri: string): void {
    this.currentQRUri = uri;
    this.showQR = true;
  }

  private getTimerColor(): string {
    return this.countdown <= 5 ? '#FF6B6B' : '#007DFF';
  }

  private async requestPermission(permission: PermissionType): Promise<void> {
    try {
      const atManager = this.atManager;
      const result = await atManager.requestPermissionsFromUser(this.context, [permission]);
      if (result.authResults[0] !== 0) {
        promptAction.showToast({ message: '未获得相机权限' });
        return;
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Permission request failed: %{public}s', error.toString());
      promptAction.showToast({ message: '权限请求失败' });
    }
  }

  private async startScan(): Promise<void> {
    try {
      await this.requestPermission('ohos.permission.CAMERA');

      const result = await scanBarcode.startScanForResult(this.context);
      hilog.info(DOMAIN, TAG, 'Scan result: %{public}s', JSON.stringify(result));

      if (result && result.originalValue) {
        await this.handleScanResult(result.originalValue);
      } else {
        promptAction.showToast({ message: '未获取到扫描结果' });
      }
    } catch (error) {
      if (error.code && error.code == 1000500002) {
        hilog.info(DOMAIN, TAG, 'Scan cancelled by user');
        return;
      }

      hilog.error(DOMAIN, TAG, 'Failed to startScanForResult. Code: %{public}d, message: %{public}s', 
        error.code, error.message);
      promptAction.showToast({ message: '扫描失败' });
    }
  }

  private async handleScanResult(result: string): Promise<void> {
    if (result && result.startsWith('otpauth://totp/')) {
      const pathStart = result.indexOf('/totp/') + 6;
      const pathEnd = result.indexOf('?');
      const path = decodeURIComponent(result.substring(pathStart, pathEnd));

      const queryString = result.substring(pathEnd + 1);
      const paramPairs = queryString.split('&');
      let secret = '';
      let issuer = '';

      for (let i = 0; i < paramPairs.length; i++) {
        const pair = paramPairs[i].split('=');
        const key = pair[0];
        const value = decodeURIComponent(pair[1]);
        if (key === 'secret') {
          secret = value;
        } else if (key === 'issuer') {
          issuer = value;
        }
      }

      let account = '';
      const parts = path.split(':');
      if (parts.length > 1) {
        issuer = parts[0];
        account = parts[1];
      } else {
        account = path;
      }

      if (!secret) {
        promptAction.showToast({ message: '无效的二维码：缺少密钥' });
        return;
      }

      const newAccount: Account = {
        account: account,
        issuer: issuer,
        secret: secret,
        code: await TOTPUtil.generateTOTP(secret)
      };

      this.accounts.push(newAccount);
      await StorageUtil.saveAccounts(this.context, this.accounts);
      promptAction.showToast({ message: '添加成功' });

    } else {
      promptAction.showToast({ message: '无效的二维码格式' });
    }
  }

  private async deleteAccount(index: number): Promise<void> {
    try {
      AlertDialog.show({
        title: '删除验证码',
        message: '确定要删除这个验证码吗？',
        primaryButton: {
          value: '删除',
          fontColor: '#FF0000',
          action: async () => {
            this.accounts.splice(index, 1);
            await StorageUtil.saveAccounts(this.context, this.accounts);
            promptAction.showToast({ message: '删除成功' });
          }
        },
        secondaryButton: {
          value: '取消',
          action: () => {
            hilog.info(DOMAIN, TAG, 'Delete cancelled');
          }
        }
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to delete account: %{public}s', error.message);
      promptAction.showToast({ message: '删除失败' });
    }
  }

  build(): void {
    Stack() {
      Column() {
        Row() {
          Text('OpenAuthenticator')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 8,
          bottom: 8
        })
        .margin({ top: 8 })

        Row() {
          Blank()
          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.ic_add'))
              .width(20)
              .height(20)
          }
          .width(36)
          .height(36)
          .backgroundColor('#007DFF')
          .onClick(() => {
            this.showActionSheet();
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .margin({ top: 8, bottom: 8 })

        List({ space: 8 }) {
          ForEach(this.accounts, (account: Account, index: number) => {
            ListItem() {
              Column() {
                Column() {
                  Row() {
                    Text(account.issuer)
                      .fontSize(16)
                      .fontWeight(FontWeight.Bold)
                    Blank()
                    Image($r('app.media.ic_qrcode'))
                      .width(20)
                      .height(20)
                      .margin({ left: 8 })
                      .onClick(() => {
                        const uri = this.generateOTPAuthURI(account);
                        this.showQRCode(uri);
                      })
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.Start)

                  Row() {
                    Blank()
                    Text(account.code)
                      .fontSize(32)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.getTimerColor())
                      .onClick(() => {
                        this.copyCode(account.code);
                      })
                    Blank()
                    Progress({
                      value: this.countdown,
                      total: 30,
                      type: ProgressType.Ring,
                      style: ProgressStyle.Ring
                    })
                      .width(24)
                      .height(24)
                      .color(this.getTimerColor())
                      .backgroundColor('#EEEEEE')
                  }
                  .width('100%')
                  .margin({ top: 8, bottom: 8 })
                  .alignItems(VerticalAlign.Center)

                  Row() {
                    Text(account.account)
                      .fontSize(14)
                      .fontColor('#666666')
                  }
                  .width('100%')
                }
                .padding(16)
                .backgroundColor('#F5F5F5')
                .borderRadius(8)
                .width('100%')
              }
            }
            .swipeAction({
              end: this.SwipeDeleteButton(index)
            })
          })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#FFFFFF')

      if (this.showQR) {
        Column() {
          Column() {
            QRCode(this.currentQRUri)
              .width(200)
              .height(200)
              .backgroundColor(Color.White)
          }
          .width(240)
          .height(240)
          .backgroundColor(Color.White)
          .borderRadius(12)
          .padding(20)
          .justifyContent(FlexAlign.Center)
          .shadow({
            radius: 12,
            color: '#00000026',
            offsetX: 0,
            offsetY: 2
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#00000066')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.showQR = false;
        })
      }
    }
  }

  private showActionSheet(): void {
    AlertDialog.show({
      title: '添加验证码',
      message: '请选择添加方式',
      primaryButton: {
        value: '扫描二维码',
        action: () => {
          this.startScan();
        }
      },
      secondaryButton: {
        value: '手动输入',
        action: () => {
          this.showManualInput();
        }
      },
      alignment: DialogAlignment.Center
    });
  }

  private showManualInput(): void {
    this.dialogController.open();
  }

  @Builder
  SwipeDeleteButton(index: number) {
    Row() {
      Image($r('app.media.ic_delete'))
        .width(20)
        .height(20)
        .fillColor(Color.White)
      Text('')
        .fontSize(14)
        .fontColor(Color.White)
        .margin({ left: 4 })
    }
    .width(80)
    .height('100%')
    .backgroundColor('#FF4444')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.deleteAccount(index);
    })
  }
}