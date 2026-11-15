// Copyright 2026 ProxyGrid
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import {promises as fs} from 'fs';
import * as path from 'path';

/** Desktop app preferences that the main process needs before the UI loads. */
export interface AppSettings {
  /** Check the update server for new versions. On by default. */
  autoUpdate: boolean;
}

const DEFAULTS: AppSettings = {autoUpdate: true};

export class AppSettingsStore {
  private readonly file: string;

  constructor(userDataDir: string) {
    this.file = path.join(userDataDir, 'app-settings.json');
  }

  async load(): Promise<AppSettings> {
    try {
      const parsed = JSON.parse(await fs.readFile(this.file, 'utf8'));
      return {
        autoUpdate:
          typeof parsed?.autoUpdate === 'boolean'
            ? parsed.autoUpdate
            : DEFAULTS.autoUpdate,
      };
    } catch {
      return {...DEFAULTS};
    }
  }

  async save(settings: AppSettings): Promise<void> {
    await fs.mkdir(path.dirname(this.file), {recursive: true});
    await fs.writeFile(this.file, JSON.stringify(settings), {mode: 0o600});
  }
}
