import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const wasmUrl = new URL('../wasm/madeitpx.wasm', import.meta.url);
const available = existsSync(wasmUrl);

async function load() {
  const { createConverter } = await import('../browser.mjs');
  return createConverter({ wasm: await readFile(wasmUrl) });
}

test('wasm converter performs nearest sampling', { skip: !available }, async () => {
  const convert = await load();
  const output = convert(Uint8Array.from([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255]), {
    inputWidth: 2,
    inputHeight: 2,
    targetWidth: 1,
    targetHeight: 1
  });
  assert.deepEqual([...output], [255, 255, 255, 255]);
});

test('wasm converter exposes pixelart defaults and version 1', { skip: !available }, async () => {
  const convert = await load();
  const defaults = convert.pixelartDefaults();
  assert.equal(defaults.version, 2);
  assert.equal(defaults.alphaThreshold, 128);
  const base = { inputWidth: 1, inputHeight: 1, targetWidth: 1, targetHeight: 1, preset: 'pixelart' };
  const input = Uint8Array.from([90, 120, 150, 255]);
  assert.deepEqual([...convert(input, base)], [90, 120, 150, 255]);
  assert.deepEqual([...convert(input, { ...base, pixelart: { version: 1 } })], [90, 120, 150, 255]);
  assert.throws(() => convert(input, { ...base, pixelart: { paletteMax: 1 } }), { code: 'invalidArgument' });
});

test('wasm pixelart keeps transparent background cells transparent', { skip: !available }, async () => {
  const convert = await load();
  const input = new Uint8Array(8 * 8 * 4);
  for (let y = 2; y < 6; y++) {
    for (let x = 2; x < 6; x++) input.set([200, 100, 50, 255], (y * 8 + x) * 4);
  }
  const settings = { inputWidth: 8, inputHeight: 8, targetWidth: 4, targetHeight: 4, preset: 'pixelart' };
  const kept = convert(input, { ...settings, pixelart: { mode: 'illustration', minRegion: 1 } });
  assert.equal(kept[3], 0);
  assert.deepEqual([...kept.slice((4 + 1) * 4, (4 + 1) * 4 + 4)], [200, 100, 50, 255]);
  const opaque = convert(input, { ...settings, pixelart: { mode: 'illustration', minRegion: 1, keepTransparency: false } });
  assert.equal(opaque[3], 255);
});
