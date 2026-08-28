/*
 * SiYuan - From thought to insight, with agents
 * Copyright (c) 2020-present, b3log.org
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import { AbilityConstant, UIAbility, Want, } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import napi from 'libentry.so';
import { fileIo } from '@kit.CoreFileKit';
import { ShorthandDraftStore } from '../shorthand/ShorthandDraftStore';

/**
 * 闪念速记入口。
 *
 * @author <a href="https://88250.b3log.org">Liang Ding</a>
 * @version 1.0.0.1, Jul 6, 2026
 * @since 3.7.0
 */
export default class ShorthandAbility extends UIAbility {
  // 加载速记页面需要“首个分享数据解析完成”与“窗口舞台就绪”两个条件同时满足。
  private windowStage: window.WindowStage | null = null;
  private initialWantResolved: boolean = false;
  private windowStageReady: boolean = false;
  private pageLoaded: boolean = false;
  private pendingWantCount: number = 0;
  private wantQueue: Promise<void> = Promise.resolve();

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'siyuan', 'ShorthandAbility onCreate');
    AppStorage.setOrCreate('shorthandContext', this.context);
    AppStorage.setOrCreate('shorthandText', '');
    AppStorage.setOrCreate('shorthandPending', 0);
    this.wantQueue = ShorthandDraftStore.initialize(this.context).then((draft: string) => {
      AppStorage.setOrCreate('shorthandText', draft);
    }).catch((error: Error) => {
      hilog.error(0x0000, 'siyuan', 'load shorthand draft failed: ' + error.message);
    });
    this.enqueueWant(want);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'siyuan', 'ShorthandAbility onNewWant');
    this.enqueueWant(want);
  }

  private enqueueWant(want: Want): void {
    ShorthandDraftStore.invalidateSubmission();
    this.pendingWantCount++;
    AppStorage.setOrCreate('shorthandPending', this.pendingWantCount);
    this.wantQueue = this.wantQueue.then(async () => {
      try {
        await this.handleWant(want);
      } finally {
        this.pendingWantCount--;
        AppStorage.setOrCreate('shorthandPending', this.pendingWantCount);
        if (!this.initialWantResolved) {
          this.initialWantResolved = true;
          this.loadShorthandPage();
        }
      }
    }).catch((error: Error) => {
      hilog.error(0x0000, 'siyuan', 'process shorthand want failed: ' + error.message);
    });
  }

  private async handleWant(want: Want): Promise<void> {
    let shareInput = "";
    try {
      const data = await systemShare.getSharedData(want);
      const records = data.getRecords();
      const recordInputs: string[] = [];
      for (const record of records) {
        let recordInput = "";
        if (utd.UniformDataType.HTML == record.utd) {
          recordInput = napi.html2Markdown(record.content);
        } else if (utd.UniformDataType.TEXT == record.utd) {
          recordInput = record.content ?? "";
        } else {
          recordInput = this.handleFileRecord(record);
        }
        const trimmedRecordInput = recordInput.trim();
        if (trimmedRecordInput) {
          recordInputs.push(trimmedRecordInput);
        }
      }
      shareInput = recordInputs.join("\n\n");
    } catch (e) {
      // 解析失败时仍加载页面，避免界面卡死空白。
      hilog.error(0x0000, 'siyuan', 'handle want failed: ' + e);
    }

    if (shareInput) {
      const current = ShorthandDraftStore.getText();
      const merged = this.joinContent(current, shareInput);
      AppStorage.setOrCreate('shorthandText', merged);
      await ShorthandDraftStore.saveNow(merged);
    }
  }

  private joinContent(existing: string, incoming: string): string {
    if (!existing) {
      return incoming;
    }
    if (!incoming) {
      return existing;
    }
    if (existing.endsWith('\n\n')) {
      return existing + incoming;
    }
    if (existing.endsWith('\n')) {
      return existing + '\n' + incoming;
    }
    return existing + '\n\n' + incoming;
  }

  private handleFileRecord(record: systemShare.SharedRecord): string {
    try {
      const context = AppStorage.get<Context>('shorthandContext');
      if (!context) {
        hilog.error(0x0000, 'siyuan', 'handle file record failed: no context');
        return "";
      }

      const workspaceBaseDir = context.filesDir + '/workspaces';
      const shorthandsDir = workspaceBaseDir + '/home/.config/siyuan/shortcuts/shorthands/';
      const assetsDir = shorthandsDir + 'assets/';

      try {
        fileIo.mkdirSync(shorthandsDir, true);
        fileIo.mkdirSync(assetsDir, true);
      } catch (e) {
        // ignore File exists
      }

      const file = fileIo.openSync(record.uri, fileIo.OpenMode.READ_ONLY);
      let baseName = napi.filepathBase(record.uri);
      baseName = napi.filterUploadFileName(baseName);
      const fileName = napi.assetName(baseName);
      const destPath = assetsDir + fileName;
      const outFile =
        fileIo.openSync(destPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.copyFileSync(file.fd, outFile.fd);
      fileIo.closeSync(file);
      fileIo.closeSync(outFile);

      let ret = ""
      if (this.isImageRecord(record)) {
        ret += '![' + baseName + '](assets/' + fileName + ')\n\n';
      } else {
        ret += '[' + baseName + '](assets/' + fileName + ')\n\n';
      }
      return ret;
    } catch (e) {
      hilog.error(0x0000, 'siyuan', 'handle file record failed: ' + e);
      return "";
    }
  }

  // 判断分享记录是否为图片。record.utd 可能是 general.image 大类或其子类型，
  // 先用大类枚举快速匹配，再用扩展名兜底覆盖 webp 等具体格式
  private isImageRecord(record: systemShare.SharedRecord): boolean {
    if (utd.UniformDataType.IMAGE === record.utd) {
      return true;
    }

    // record.uri 在纯文本/HTML 记录上可能为 undefined，这里仅用于文件记录的图片判断
    const uri = record.uri;
    if (!uri) {
      return false;
    }

    const imageExts = ['.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.svg', '.heif', '.heic', '.tiff', '.ico'];
    const lowerUri = uri.toLowerCase();
    for (const ext of imageExts) {
      if (lowerUri.endsWith(ext)) {
        return true;
      }
    }
    return false;
  }

  // 等首个分享数据解析完成且窗口舞台就绪后再加载页面，保证首屏即可读到合并后的草稿。
  private loadShorthandPage(): void {
    if (this.pageLoaded || !this.initialWantResolved || !this.windowStageReady || null === this.windowStage) {
      return;
    }
    this.pageLoaded = true;
    this.windowStage.loadContent('pages/Shorthand');
  }

  onDestroy(): void {
    ShorthandDraftStore.flush().catch((error: Error) => {
      hilog.error(0x0000, 'siyuan', 'flush shorthand draft failed: ' + error.message);
    });
    hilog.info(0x0000, 'siyuan', 'ShorthandAbility onDestroy');
  }

  onBackground(): void {
    ShorthandDraftStore.flush().catch((error: Error) => {
      hilog.error(0x0000, 'siyuan', 'flush shorthand draft failed: ' + error.message);
    });
  }

  async onWindowStageCreate(windowStage: window.WindowStage) {
    hilog.info(0x0000, 'siyuan', 'ShorthandAbility onWindowStageCreate');

    this.windowStage = windowStage;
    const wnd = windowStage.getMainWindowSync();
    try {
      wnd.setWindowLayoutFullScreen(true);
      wnd.setSpecificSystemBarEnabled('status', false);
      wnd.setSpecificSystemBarEnabled('navigationIndicator', false);
    } catch (e) {
      hilog.error(0x0000, 'siyuan', 'set main window system bar failed: ' + e);
    }

    this.windowStageReady = true;
    this.loadShorthandPage();
  }

  onWindowStageDestroy(): void {
    hilog.info(0x0000, 'siyuan', 'ShorthandAbility onWindowStageDestroy');
  }
};
