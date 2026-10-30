'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { createConverter } = require('../');

const libraryPath = process.env.MADEITPX_LIBRARY_PATH;

test('converts RGBA8 input using the native library', { skip: !libraryPath }, () => {
  const convert = createConverter({ libraryPath });
  const output = convert(Buffer.from([
    255, 0, 0, 255,
    0, 255, 0, 255,
    0, 0, 255, 255,
    255, 255, 255, 255
  ]), {
    inputWidth: 2,
    inputHeight: 2,
    targetWidth: 2,
    targetHeight: 2,
    paletteColors: 4,
    clusterCleanup: false
  });

  assert.equal(output.length, 16);
  for (let index = 3; index < output.length; index += 4) {
    assert.equal(output[index], 255);
  }
});

test('converts with the pixelart preset', { skip: !libraryPath }, () => {
  const convert = createConverter({ libraryPath });
  const output = convert(Buffer.from([90, 120, 150, 255]), {
    inputWidth: 1,
    inputHeight: 1,
    targetWidth: 1,
    targetHeight: 1,
    preset: 'pixelart',
    paletteColors: 2
  });

  assert.deepEqual([...output], [90, 120, 150, 255]);
});

test('accepts padded source rows', { skip: !libraryPath }, () => {
  const convert = createConverter({ libraryPath });
  const output = convert(Buffer.from([
    255, 0, 0, 255, 0, 255, 0, 255, 9, 9, 9, 9,
    0, 0, 255, 255, 255, 255, 255, 255, 9, 9, 9, 9
  ]), {
    inputWidth: 2,
    inputHeight: 2,
    inputStride: 12,
    targetWidth: 2,
    targetHeight: 2
  });

  assert.equal(output.length, 16);
});

test('composites transparent pixels onto the configured background', { skip: !libraryPath }, () => {
  const convert = createConverter({ libraryPath });
  const output = convert(Buffer.from([255, 0, 255, 0]), {
    inputWidth: 1,
    inputHeight: 1,
    targetWidth: 1,
    targetHeight: 1,
    backgroundRgb: 0x123456
  });

  assert.deepEqual([...output], [0x12, 0x34, 0x56, 255]);
});

test('rejects invalid arguments', { skip: !libraryPath }, () => {
  const convert = createConverter({ libraryPath });
  assert.throws(
    () => convert(Buffer.from([1, 2, 3]), {
      inputWidth: 1,
      inputHeight: 1,
      targetWidth: 1,
      targetHeight: 1
    }),
    /input does not contain enough bytes/
  );
  assert.throws(
    () => convert(Buffer.from([1, 2, 3, 4]), {
      inputWidth: 1,
      inputHeight: 1,
      targetWidth: 1,
      targetHeight: 1,
      paletteColors: 1
    }),
    /paletteColors/
  );
});
