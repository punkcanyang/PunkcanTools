import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';

test('package.json exposes electron entrypoint and build targets', async () => {
  const packagePath = new URL('../package.json', import.meta.url);
  const pkg = JSON.parse(await fs.readFile(packagePath, 'utf8'));

  assert.equal(pkg.main, 'src/main.js');
  assert.equal(pkg.scripts.electron, 'electron .');
  assert.equal(pkg.scripts.build, 'electron-builder');
  assert.deepEqual(pkg.build.mac.target, ['dmg', 'zip']);
  assert.deepEqual(pkg.build.win.target, ['nsis', 'portable']);
});
