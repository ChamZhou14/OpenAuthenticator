import preferences from '@ohos.data.preferences';
import type common from '@ohos.app.ability.common';
import { hilog } from '@kit.PerformanceAnalysisKit';

interface Account {
  account: string;
  code: string;
  issuer: string;
  secret: string;
}

const TAG = '[StorageUtil]';
const DOMAIN = 0x0003;
const STORE_NAME = 'authenticator_store';
const ACCOUNTS_KEY = 'accounts';

export class StorageUtil {
  static async saveAccounts(context: common.UIAbilityContext, accounts: Account[]): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, 'Saving accounts');
      const pref = await preferences.getPreferences(context, STORE_NAME);
      await pref.put(ACCOUNTS_KEY, JSON.stringify(accounts));
      await pref.flush();
      hilog.info(DOMAIN, TAG, 'Accounts saved successfully');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to save accounts: %{public}s', error.message);
      return Promise.reject(new Error('Failed to save accounts'));
    }
  }

  static async loadAccounts(context: common.UIAbilityContext): Promise<Account[]> {
    try {
      hilog.info(DOMAIN, TAG, 'Loading accounts');
      const pref = await preferences.getPreferences(context, STORE_NAME);
      const value = await pref.get(ACCOUNTS_KEY, '[]');
      const accounts = JSON.parse(value.toString()) as Account[];
      hilog.info(DOMAIN, TAG, 'Accounts loaded successfully');
      return accounts;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load accounts: %{public}s', error.message);
      return [];  // 返回空数组而不是抛出错误
    }
  }
} 