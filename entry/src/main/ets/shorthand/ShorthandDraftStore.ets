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

import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const FILE_NOT_FOUND: number = 13900002;
const SAVE_DELAY: number = 250;

export class ShorthandDraftFile {
  readonly path: string;

  constructor(path: string) {
    this.path = path;
  }

  read(): string {
    const atomicFile = new fileIo.AtomicFile(this.path);
    try {
      const data = atomicFile.readFully();
      const decoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(new Uint8Array(data));
    } catch (error) {
      const err = error as BusinessError;
      if (FILE_NOT_FOUND === err.code) {
        return '';
      }
      throw new Error(err.message);
    }
  }

  write(text: string): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const atomicFile = new fileIo.AtomicFile(this.path);
      let started: boolean = false;
      let settled: boolean = false;
      try {
        const writeStream = atomicFile.startWrite();
        started = true;
        const fail = (error: Error): void => {
          if (settled) {
            return;
          }
          settled = true;
          this.rollback(atomicFile, started);
          reject(error);
        };
        writeStream.on('error', () => {
          fail(new Error('Write shorthand draft stream failed'));
        });
        writeStream.write(text, 'utf-8', () => {
          if (settled) {
            return;
          }
          try {
            atomicFile.finishWrite();
            settled = true;
            resolve();
          } catch (error) {
            const err = error as BusinessError;
            fail(new Error(err.message));
          }
        });
      } catch (error) {
        const err = error as BusinessError;
        if (!settled) {
          settled = true;
          this.rollback(atomicFile, started);
          reject(new Error(err.message));
        }
      }
    });
  }

  delete(): void {
    const atomicFile = new fileIo.AtomicFile(this.path);
    try {
      atomicFile.delete();
    } catch (error) {
      const err = error as BusinessError;
      if (FILE_NOT_FOUND !== err.code) {
        throw new Error(err.message);
      }
    }
  }

  private rollback(atomicFile: fileIo.AtomicFile, started: boolean): void {
    if (!started) {
      return;
    }
    try {
      atomicFile.failWrite();
    } catch (error) {
      // 保留原始写入错误。
    }
  }
}

enum ShorthandDraftState {
  ACTIVE,
  PROMOTING,
  COMMITTED,
  UNAVAILABLE,
}

export class ShorthandDraftStore {
  private static draftFile: ShorthandDraftFile | null = null;
  private static draftPath: string = '';
  private static text: string = '';
  private static revision: number = 0;
  private static persistedRevision: number = -1;
  private static saveTimer: number = -1;
  private static writeChain: Promise<void> = Promise.resolve();
  private static state: ShorthandDraftState = ShorthandDraftState.ACTIVE;

  static initialize(context: common.UIAbilityContext): Promise<string> {
    const path = context.filesDir + '/shorthand-draft.md';
    if (path === ShorthandDraftStore.draftPath && null !== ShorthandDraftStore.draftFile &&
      ShorthandDraftState.UNAVAILABLE !== ShorthandDraftStore.state) {
      if (ShorthandDraftState.PROMOTING === ShorthandDraftStore.state) {
        return ShorthandDraftStore.writeChain.then(() => ShorthandDraftStore.text);
      }
      return Promise.resolve(ShorthandDraftStore.text);
    }
    ShorthandDraftStore.cancelScheduledSave();

    const operation = ShorthandDraftStore.writeChain.then(() => {
      const draftFile = new ShorthandDraftFile(path);
      ShorthandDraftStore.draftFile = draftFile;
      ShorthandDraftStore.draftPath = path;
      try {
        ShorthandDraftStore.text = draftFile.read();
        ShorthandDraftStore.persistedRevision = ++ShorthandDraftStore.revision;
        ShorthandDraftStore.state = ShorthandDraftState.ACTIVE;
        return ShorthandDraftStore.text;
      } catch (error) {
        ShorthandDraftStore.revision++;
        ShorthandDraftStore.state = ShorthandDraftState.UNAVAILABLE;
        const err = error as Error;
        throw new Error(err.message);
      }
    });
    ShorthandDraftStore.writeChain = operation.then(() => {
    }).catch(() => {
      // 后续初始化或写入仍需继续执行。
    });
    return operation;
  }

  static getText(): string {
    return ShorthandDraftStore.text;
  }

  static schedule(text: string): number {
    ShorthandDraftStore.text = text;
    const revision = ++ShorthandDraftStore.revision;
    ShorthandDraftStore.cancelScheduledSave();
    if (ShorthandDraftState.UNAVAILABLE === ShorthandDraftStore.state) {
      return revision;
    }
    ShorthandDraftStore.state = ShorthandDraftState.ACTIVE;
    if (text.length === 0) {
      ShorthandDraftStore.enqueueSnapshot(revision, text).catch((error: Error) => {
        hilog.error(0x0000, 'siyuan', 'clear shorthand draft failed: ' + error.message);
      });
      return revision;
    }

    ShorthandDraftStore.saveTimer = setTimeout(() => {
      ShorthandDraftStore.saveTimer = -1;
      ShorthandDraftStore.enqueueSnapshot(revision, text).catch((error: Error) => {
        hilog.error(0x0000, 'siyuan', 'save shorthand draft failed: ' + error.message);
      });
    }, SAVE_DELAY);
    return revision;
  }

  static saveNow(text: string): Promise<number> {
    ShorthandDraftStore.text = text;
    const revision = ++ShorthandDraftStore.revision;
    ShorthandDraftStore.cancelScheduledSave();
    if (ShorthandDraftState.UNAVAILABLE === ShorthandDraftStore.state) {
      return Promise.reject(new Error('Shorthand draft store is unavailable'));
    }
    ShorthandDraftStore.state = ShorthandDraftState.ACTIVE;
    return ShorthandDraftStore.enqueueSnapshot(revision, text);
  }

  static flush(): Promise<number> {
    ShorthandDraftStore.cancelScheduledSave();
    if (ShorthandDraftState.UNAVAILABLE === ShorthandDraftStore.state) {
      return Promise.reject(new Error('Shorthand draft store is unavailable'));
    }
    const revision = ShorthandDraftStore.revision;
    if (ShorthandDraftState.PROMOTING === ShorthandDraftStore.state ||
      ShorthandDraftState.COMMITTED === ShorthandDraftStore.state ||
      revision === ShorthandDraftStore.persistedRevision) {
      return ShorthandDraftStore.writeChain.then(() => revision);
    }
    return ShorthandDraftStore.enqueueSnapshot(revision, ShorthandDraftStore.text);
  }

  static clear(): Promise<void> {
    ShorthandDraftStore.text = '';
    const revision = ++ShorthandDraftStore.revision;
    ShorthandDraftStore.cancelScheduledSave();
    if (ShorthandDraftState.UNAVAILABLE === ShorthandDraftStore.state) {
      return Promise.reject(new Error('Shorthand draft store is unavailable'));
    }
    ShorthandDraftStore.state = ShorthandDraftState.ACTIVE;
    return ShorthandDraftStore.enqueueSnapshot(revision, '').then(() => {
    });
  }

  static promote(path: string, expectedRevision: number): Promise<number> {
    if (ShorthandDraftState.UNAVAILABLE === ShorthandDraftStore.state ||
      expectedRevision !== ShorthandDraftStore.revision) {
      return Promise.reject(new Error('Shorthand draft changed before submission'));
    }
    ShorthandDraftStore.cancelScheduledSave();
    ShorthandDraftStore.state = ShorthandDraftState.PROMOTING;
    const operation = ShorthandDraftStore.writeChain.then(async () => {
      if (ShorthandDraftState.PROMOTING !== ShorthandDraftStore.state ||
        expectedRevision !== ShorthandDraftStore.revision ||
        expectedRevision !== ShorthandDraftStore.persistedRevision) {
        throw new Error('Shorthand draft changed during submission');
      }
      const draftFile = ShorthandDraftStore.requireDraftFile();
      if (fileIo.accessSync(path)) {
        throw new Error('Shorthand file already exists');
      }
      fileIo.renameSync(draftFile.path, path);
      ShorthandDraftStore.text = '';
      ShorthandDraftStore.persistedRevision = ++ShorthandDraftStore.revision;
      ShorthandDraftStore.state = ShorthandDraftState.COMMITTED;
      return ShorthandDraftStore.revision;
    });
    ShorthandDraftStore.writeChain = operation.then(() => {
    }).catch(() => {
      if (ShorthandDraftState.PROMOTING === ShorthandDraftStore.state) {
        ShorthandDraftStore.state = ShorthandDraftState.ACTIVE;
      }
      // 后续写入仍需继续执行。
    });
    return operation;
  }

  static isCurrentRevision(revision: number): boolean {
    return revision === ShorthandDraftStore.revision;
  }

  static invalidateSubmission(): void {
    ShorthandDraftStore.schedule(ShorthandDraftStore.text);
  }

  static cancelScheduledSave(): void {
    if (0 <= ShorthandDraftStore.saveTimer) {
      clearTimeout(ShorthandDraftStore.saveTimer);
      ShorthandDraftStore.saveTimer = -1;
    }
  }

  private static enqueueSnapshot(revision: number, text: string): Promise<number> {
    const operation = ShorthandDraftStore.writeChain.then(async () => {
      if (ShorthandDraftState.UNAVAILABLE === ShorthandDraftStore.state) {
        throw new Error('Shorthand draft store is unavailable');
      }
      if (revision !== ShorthandDraftStore.revision) {
        return revision;
      }
      const draftFile = ShorthandDraftStore.requireDraftFile();
      if (0 === text.length) {
        draftFile.delete();
      } else {
        await draftFile.write(text);
      }
      ShorthandDraftStore.persistedRevision = revision;
      return revision;
    });
    ShorthandDraftStore.writeChain = operation.then(() => {
    }).catch(() => {
      // 后续写入仍需继续执行。
    });
    return operation;
  }

  private static requireDraftFile(): ShorthandDraftFile {
    if (null === ShorthandDraftStore.draftFile) {
      throw new Error('Shorthand draft store is not initialized');
    }
    return ShorthandDraftStore.draftFile;
  }
}
