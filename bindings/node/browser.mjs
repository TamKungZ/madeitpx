const STATUS = Object.freeze({
  ok: 0,
  invalidArgument: 1,
  bufferTooSmall: 2,
  sizeOverflow: 3,
  outOfMemory: 4
});

export const presets = Object.freeze({
  balanced: 0,
  detail: 1,
  bold: 2,
  pixelart: 3
});

export const samplingModes = Object.freeze({
  area: 0,
  nearest: 1
});

export const pixelartModes = Object.freeze({
  auto: 0,
  grid: 1,
  illustration: 2
});

const OPTIONS_WORDS = 7;
const PIXELART_WORDS = 14;

const PIXELART_FIELDS = Object.freeze([
  { key: 'version', word: 1, kind: 'int' },
  { key: 'gridFit', word: 2, kind: 'bool' },
  { key: 'gridSearchPermille', word: 3, kind: 'int' },
  { key: 'sampleInsetPercent', word: 4, kind: 'int' },
  { key: 'colorTolerance', word: 5, kind: 'int' },
  { key: 'paletteMax', word: 6, kind: 'int' },
  { key: 'refineIterations', word: 7, kind: 'int' },
  { key: 'mode', word: 8, kind: 'mode' },
  { key: 'inkPercent', word: 9, kind: 'int' },
  { key: 'minRegion', word: 10, kind: 'int' },
  { key: 'alphaThreshold', word: 11, kind: 'int' },
  { key: 'keepTransparency', word: 12, kind: 'bool' }
]);

function statusError(status) {
  const name = Object.keys(STATUS).find((key) => STATUS[key] === status) || `unknown status ${status}`;
  const error = new Error(`madeitpx conversion failed: ${name}`);
  error.code = name;
  error.status = status;
  return error;
}

function validatePositiveInteger(value, name) {
  if (!Number.isSafeInteger(value) || value <= 0 || value > 0xffffffff) {
    throw new RangeError(`${name} must be a positive 32-bit integer`);
  }
}

function validateOptions(options) {
  const preset = options.preset === undefined ? 'balanced' : options.preset;
  const sampling = options.sampling === undefined ? 'nearest' : options.sampling;
  const paletteColors = options.paletteColors === undefined ? 0 : options.paletteColors;
  const backgroundRgb = options.backgroundRgb === undefined ? 0 : options.backgroundRgb;
  const clusterCleanup = options.clusterCleanup === undefined ? true : options.clusterCleanup;

  if (!Object.prototype.hasOwnProperty.call(presets, preset)) {
    throw new RangeError('preset must be balanced, detail, bold, or pixelart');
  }
  if (!Object.prototype.hasOwnProperty.call(samplingModes, sampling)) {
    throw new RangeError('sampling must be nearest or area');
  }
  if (!Number.isInteger(paletteColors) || (paletteColors !== 0 && (paletteColors < 2 || paletteColors > 64))) {
    throw new RangeError('paletteColors must be 0 or an integer from 2 to 64');
  }
  if (!Number.isInteger(backgroundRgb) || backgroundRgb < 0 || backgroundRgb > 0xffffff) {
    throw new RangeError('backgroundRgb must be a 0xRRGGBB integer');
  }
  if (typeof clusterCleanup !== 'boolean') {
    throw new TypeError('clusterCleanup must be a boolean');
  }
  return { preset: presets[preset], sampleMode: samplingModes[sampling], paletteColors, backgroundRgb, clusterCleanup };
}

function validatePixelArt(settings) {
  if (settings === undefined) return [];
  if (settings === null || typeof settings !== 'object' || Array.isArray(settings)) {
    throw new TypeError('pixelart must be an object');
  }
  const known = new Set(PIXELART_FIELDS.map((field) => field.key));
  for (const key of Object.keys(settings)) {
    if (!known.has(key)) throw new TypeError(`unknown pixelart setting: ${key}`);
  }
  const overrides = [];
  for (const field of PIXELART_FIELDS) {
    const value = settings[field.key];
    if (value === undefined) continue;
    if (field.kind === 'bool') {
      if (typeof value !== 'boolean') throw new TypeError(`pixelart.${field.key} must be a boolean`);
      overrides.push([field.word, value ? 1 : 0]);
    } else if (field.kind === 'mode') {
      if (!Object.prototype.hasOwnProperty.call(pixelartModes, value)) {
        throw new RangeError('pixelart.mode must be auto, grid, or illustration');
      }
      overrides.push([field.word, pixelartModes[value]]);
    } else {
      if (!Number.isInteger(value) || value < 0 || value > 0xffffffff) {
        throw new RangeError(`pixelart.${field.key} must be a non-negative integer`);
      }
      overrides.push([field.word, value]);
    }
  }
  return overrides;
}

function decodePixelArt(words) {
  const result = {};
  for (const field of PIXELART_FIELDS) {
    const value = words[field.word];
    if (field.kind === 'bool') result[field.key] = value === 1;
    else if (field.kind === 'mode') result[field.key] = Object.keys(pixelartModes).find((name) => pixelartModes[name] === value);
    else result[field.key] = value;
  }
  return result;
}

async function loadModule(source) {
  if (source instanceof WebAssembly.Module) return WebAssembly.instantiate(source, {});
  if (source instanceof ArrayBuffer || ArrayBuffer.isView(source)) {
    return (await WebAssembly.instantiate(source, {})).instance;
  }
  const response = source instanceof Response ? source : await fetch(source);
  if (!response.ok) throw new Error(`could not load madeitpx.wasm (${response.status})`);
  if (typeof WebAssembly.instantiateStreaming === 'function' && response.headers.get('content-type') === 'application/wasm') {
    return (await WebAssembly.instantiateStreaming(response, {})).instance;
  }
  return (await WebAssembly.instantiate(await response.arrayBuffer(), {})).instance;
}

export async function createConverter(configuration = {}) {
  if (configuration === null || typeof configuration !== 'object' || Array.isArray(configuration)) {
    throw new TypeError('configuration must be an object');
  }
  const source = configuration.wasm === undefined
    ? new URL('./wasm/madeitpx.wasm', import.meta.url)
    : configuration.wasm;
  const exports = (await loadModule(source)).exports;

  function words(pointer, count) {
    return new Uint32Array(exports.memory.buffer, pointer, count);
  }

  function pixelartDefaults() {
    const pointer = exports.madeitpx_web_alloc(PIXELART_WORDS * 4);
    if (!pointer) throw statusError(STATUS.outOfMemory);
    try {
      const status = exports.madeitpx_pixelart_options_init(pointer);
      if (status !== STATUS.ok) throw statusError(status);
      return decodePixelArt(words(pointer, PIXELART_WORDS));
    } finally {
      exports.madeitpx_web_free(pointer, PIXELART_WORDS * 4);
    }
  }

  function convertRgba8(input, settings = {}) {
    if (!(input instanceof Uint8Array || input instanceof Uint8ClampedArray)) {
      throw new TypeError('input must be a Uint8Array or Uint8ClampedArray containing RGBA8 pixels');
    }
    if (settings === null || typeof settings !== 'object' || Array.isArray(settings)) {
      throw new TypeError('settings must be an object');
    }
    const { inputWidth, inputHeight, inputStride = inputWidth * 4, targetWidth, targetHeight } = settings;
    validatePositiveInteger(inputWidth, 'inputWidth');
    validatePositiveInteger(inputHeight, 'inputHeight');
    validatePositiveInteger(inputStride, 'inputStride');
    validatePositiveInteger(targetWidth, 'targetWidth');
    validatePositiveInteger(targetHeight, 'targetHeight');
    if (inputStride < inputWidth * 4) throw new RangeError('inputStride must be at least inputWidth * 4');
    const requiredInput = (inputHeight - 1) * inputStride + inputWidth * 4;
    if (requiredInput > input.byteLength) {
      throw new RangeError('input does not contain enough bytes for the dimensions and stride');
    }
    const options = validateOptions(settings);
    const overrides = validatePixelArt(settings.pixelart);
    const outputSize = targetWidth * targetHeight * 4;
    if (!Number.isSafeInteger(outputSize) || outputSize > 0x7fffffff) {
      throw new RangeError('output is too large for WebAssembly memory');
    }

    const optionsBytes = OPTIONS_WORDS * 4;
    const pixelartBytes = PIXELART_WORDS * 4;
    const allocations = [];
    const allocate = (size) => {
      const pointer = exports.madeitpx_web_alloc(size);
      if (!pointer) throw statusError(STATUS.outOfMemory);
      allocations.push([pointer, size]);
      return pointer;
    };

    try {
      const inputPointer = allocate(input.byteLength);
      const outputPointer = allocate(outputSize);
      const optionsPointer = allocate(optionsBytes);
      const pixelartPointer = allocate(pixelartBytes);

      new Uint8Array(exports.memory.buffer, inputPointer, input.byteLength).set(
        new Uint8Array(input.buffer, input.byteOffset, input.byteLength)
      );

      let status = exports.madeitpx_options_init(optionsPointer);
      if (status !== STATUS.ok) throw statusError(status);
      const optionWords = words(optionsPointer, OPTIONS_WORDS);
      optionWords[1] = options.preset;
      optionWords[2] = options.paletteColors;
      optionWords[3] = options.backgroundRgb;
      optionWords[4] = options.sampleMode;
      optionWords[5] = options.clusterCleanup ? 1 : 0;

      if (options.preset === presets.pixelart) {
        status = exports.madeitpx_pixelart_options_init(pixelartPointer);
        if (status !== STATUS.ok) throw statusError(status);
        const pixelartWords = words(pixelartPointer, PIXELART_WORDS);
        for (const [word, value] of overrides) pixelartWords[word] = value;
        status = exports.madeitpx_convert_pixelart_rgba8(
          inputPointer, input.byteLength, inputWidth, inputHeight, inputStride,
          targetWidth, targetHeight, optionsPointer, pixelartPointer, outputPointer, outputSize
        );
      } else {
        status = exports.madeitpx_convert_rgba8(
          inputPointer, input.byteLength, inputWidth, inputHeight, inputStride,
          targetWidth, targetHeight, optionsPointer, outputPointer, outputSize
        );
      }
      if (status !== STATUS.ok) throw statusError(status);
      return new Uint8Array(exports.memory.buffer.slice(outputPointer, outputPointer + outputSize));
    } finally {
      for (const [pointer, size] of allocations) exports.madeitpx_web_free(pointer, size);
    }
  }

  convertRgba8.pixelartDefaults = pixelartDefaults;
  return convertRgba8;
}
