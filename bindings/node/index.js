'use strict';

const koffi = require('koffi');
const { constants: bufferConstants } = require('node:buffer');

const STATUS = Object.freeze({
  ok: 0,
  invalidArgument: 1,
  bufferTooSmall: 2,
  sizeOverflow: 3,
  outOfMemory: 4
});

const PRESETS = Object.freeze({
  balanced: 0,
  detail: 1,
  bold: 2,
  pixelart: 3
});

const SAMPLE_MODES = Object.freeze({
  area: 0,
  nearest: 1
});

const PIXELART_MODES = Object.freeze({
  auto: 0,
  grid: 1,
  illustration: 2
});

const PIXELART_FIELDS = Object.freeze([
  { key: 'version', native: 'version', kind: 'int' },
  { key: 'mode', native: 'mode', kind: 'mode' },
  { key: 'gridFit', native: 'grid_fit', kind: 'bool' },
  { key: 'gridSearchPermille', native: 'grid_search_permille', kind: 'int' },
  { key: 'sampleInsetPercent', native: 'sample_inset_percent', kind: 'int' },
  { key: 'colorTolerance', native: 'color_tolerance', kind: 'int' },
  { key: 'paletteMax', native: 'palette_max', kind: 'int' },
  { key: 'refineIterations', native: 'refine_iterations', kind: 'int' },
  { key: 'inkPercent', native: 'ink_percent', kind: 'int' },
  { key: 'minRegion', native: 'min_region', kind: 'int' },
  { key: 'alphaThreshold', native: 'alpha_threshold', kind: 'int' },
  { key: 'keepTransparency', native: 'keep_transparency', kind: 'bool' }
]);

const NATIVE_PIXELART_OPTIONS = koffi.struct('madeitpx_pixelart_options', {
  struct_size: 'uint32_t',
  version: 'uint32_t',
  grid_fit: 'uint32_t',
  grid_search_permille: 'uint32_t',
  sample_inset_percent: 'uint32_t',
  color_tolerance: 'uint32_t',
  palette_max: 'uint32_t',
  refine_iterations: 'uint32_t',
  mode: 'uint32_t',
  ink_percent: 'uint32_t',
  min_region: 'uint32_t',
  alpha_threshold: 'uint32_t',
  keep_transparency: 'uint32_t',
  reserved: 'uint32_t'
});

const NATIVE_OPTIONS = koffi.struct('madeitpx_options', {
  struct_size: 'uint32_t',
  preset: 'uint32_t',
  palette_colors: 'uint32_t',
  background_rgb: 'uint32_t',
  sample_mode: 'uint32_t',
  cluster_cleanup: 'uint32_t',
  reserved: 'uint32_t'
});

function nativePackageName() {
  const platforms = {
    'win32-x64': '@madeitpx/pixelart-win32-x64',
    'win32-arm64': '@madeitpx/pixelart-win32-arm64',
    'linux-x64': '@madeitpx/pixelart-linux-x64-gnu',
    'linux-arm64': '@madeitpx/pixelart-linux-arm64-gnu',
    'darwin-x64': '@madeitpx/pixelart-darwin-x64',
    'darwin-arm64': '@madeitpx/pixelart-darwin-arm64'
  };
  const key = `${process.platform}-${process.arch}`;
  return platforms[key];
}

function resolveNativeLibrary(libraryPath) {
  const override = libraryPath || process.env.MADEITPX_LIBRARY_PATH;
  if (override) return override;

  const packageName = nativePackageName();
  if (!packageName) {
    throw new Error(`No prebuilt madeitpx library is available for ${process.platform}-${process.arch}`);
  }

  try {
    return require(packageName);
  } catch (error) {
    if (error && error.code === 'MODULE_NOT_FOUND') {
      throw new Error(`The native package ${packageName} is not installed; reinstall @madeitpx/pixelart for this platform`);
    }
    throw error;
  }
}

function statusError(status) {
  const names = Object.keys(STATUS);
  const name = names.find((key) => STATUS[key] === status) || `unknown status ${status}`;
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

function validateByteSize(value, name) {
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new RangeError(`${name} must be a positive safe integer`);
  }
}

function validateOptions(options) {
  const preset = options.preset === undefined ? 'balanced' : options.preset;
  const sampling = options.sampling === undefined ? 'nearest' : options.sampling;
  const paletteColors = options.paletteColors === undefined ? 0 : options.paletteColors;
  const backgroundRgb = options.backgroundRgb === undefined ? 0 : options.backgroundRgb;
  const clusterCleanup = options.clusterCleanup === undefined ? true : options.clusterCleanup;

  if (!Object.prototype.hasOwnProperty.call(PRESETS, preset)) {
    throw new RangeError('preset must be balanced, detail, bold, or pixelart');
  }
  if (!Object.prototype.hasOwnProperty.call(SAMPLE_MODES, sampling)) {
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

  return {
    preset: PRESETS[preset],
    sampleMode: SAMPLE_MODES[sampling],
    paletteColors,
    backgroundRgb,
    clusterCleanup
  };
}

function validatePixelArt(settings) {
  if (settings === undefined) return {};
  if (settings === null || typeof settings !== 'object' || Array.isArray(settings)) {
    throw new TypeError('pixelart must be an object');
  }
  const known = new Set(PIXELART_FIELDS.map((field) => field.key));
  for (const key of Object.keys(settings)) {
    if (!known.has(key)) throw new TypeError(`unknown pixelart setting: ${key}`);
  }
  const overrides = {};
  for (const field of PIXELART_FIELDS) {
    const value = settings[field.key];
    if (value === undefined) continue;
    if (field.kind === 'bool') {
      if (typeof value !== 'boolean') throw new TypeError(`pixelart.${field.key} must be a boolean`);
      overrides[field.native] = value ? 1 : 0;
    } else if (field.kind === 'mode') {
      if (!Object.prototype.hasOwnProperty.call(PIXELART_MODES, value)) {
        throw new RangeError('pixelart.mode must be auto, grid, or illustration');
      }
      overrides[field.native] = PIXELART_MODES[value];
    } else {
      if (!Number.isInteger(value) || value < 0 || value > 0xffffffff) {
        throw new RangeError(`pixelart.${field.key} must be a non-negative integer`);
      }
      overrides[field.native] = value;
    }
  }
  return overrides;
}

function decodePixelArt(native) {
  const result = {};
  for (const field of PIXELART_FIELDS) {
    const value = native[field.native];
    if (field.kind === 'bool') result[field.key] = value === 1;
    else if (field.kind === 'mode') result[field.key] = Object.keys(PIXELART_MODES).find((name) => PIXELART_MODES[name] === value);
    else result[field.key] = value;
  }
  return result;
}

function createNativeBindings(libraryPath) {
  const library = koffi.load(resolveNativeLibrary(libraryPath));

  return {
    optionsInit: library.func('int madeitpx_options_init(_Out_ madeitpx_options *options)'),
    getOutputSize: library.func('int madeitpx_get_output_size(uint32_t target_width, uint32_t target_height, _Out_ size_t *output_size)'),
    pixelartInit: library.func('int madeitpx_pixelart_options_init(_Out_ madeitpx_pixelart_options *options)'),
    convertPixelart: library.func('int madeitpx_convert_pixelart_rgba8(const uint8_t *input, size_t input_size, uint32_t input_width, uint32_t input_height, size_t input_stride, uint32_t target_width, uint32_t target_height, const madeitpx_options *options, const madeitpx_pixelart_options *pixelart, uint8_t *output, size_t output_capacity)'),
    convert: library.func('int madeitpx_convert_rgba8(const uint8_t *input, size_t input_size, uint32_t input_width, uint32_t input_height, size_t input_stride, uint32_t target_width, uint32_t target_height, const madeitpx_options *options, uint8_t *output, size_t output_capacity)')
  };
}

function createConverter(configuration = {}) {
  if (configuration === null || typeof configuration !== 'object' || Array.isArray(configuration)) {
    throw new TypeError('configuration must be an object');
  }
  const bindings = createNativeBindings(configuration.libraryPath);

  function pixelartDefaults() {
    const pointer = koffi.alloc(NATIVE_PIXELART_OPTIONS, 1);
    try {
      const status = bindings.pixelartInit(pointer);
      if (status !== STATUS.ok) throw statusError(status);
      return decodePixelArt(koffi.decode(pointer, NATIVE_PIXELART_OPTIONS));
    } finally {
      koffi.free(pointer);
    }
  }

  function convertRgba8(input, settings = {}) {
    if (!(input instanceof Uint8Array)) {
      throw new TypeError('input must be a Uint8Array or Buffer containing RGBA8 pixels');
    }
    if (settings === null || typeof settings !== 'object' || Array.isArray(settings)) {
      throw new TypeError('settings must be an object');
    }

    const {
      inputWidth,
      inputHeight,
      inputStride = inputWidth * 4,
      targetWidth,
      targetHeight
    } = settings;
    validatePositiveInteger(inputWidth, 'inputWidth');
    validatePositiveInteger(inputHeight, 'inputHeight');
    validateByteSize(inputStride, 'inputStride');
    validatePositiveInteger(targetWidth, 'targetWidth');
    validatePositiveInteger(targetHeight, 'targetHeight');
    if (inputStride < inputWidth * 4) {
      throw new RangeError('inputStride must be at least inputWidth * 4');
    }
    const requiredInputLength = (inputHeight - 1) * inputStride + inputWidth * 4;
    if (!Number.isSafeInteger(requiredInputLength) || requiredInputLength > input.byteLength) {
      throw new RangeError('input does not contain enough bytes for the dimensions and stride');
    }

    const options = validateOptions(settings);
    const pixelartOverrides = validatePixelArt(settings.pixelart);
    const nativeOptions = koffi.alloc(NATIVE_OPTIONS, 1);
    let outputSizePointer;
    let nativePixelart;
    try {
      let status = bindings.optionsInit(nativeOptions);
      if (status !== STATUS.ok) throw statusError(status);
      const nativeOptionsValue = koffi.decode(nativeOptions, NATIVE_OPTIONS);
      nativeOptionsValue.preset = options.preset;
      nativeOptionsValue.palette_colors = options.paletteColors;
      nativeOptionsValue.background_rgb = options.backgroundRgb;
      nativeOptionsValue.sample_mode = options.sampleMode;
      nativeOptionsValue.cluster_cleanup = options.clusterCleanup ? 1 : 0;
      koffi.encode(nativeOptions, NATIVE_OPTIONS, nativeOptionsValue);

      outputSizePointer = koffi.alloc('size_t', 1);
      status = bindings.getOutputSize(targetWidth, targetHeight, outputSizePointer);
      if (status !== STATUS.ok) throw statusError(status);
      const outputSize = koffi.decode(outputSizePointer, 'size_t');
      if (!Number.isSafeInteger(outputSize) || outputSize > bufferConstants.MAX_LENGTH) {
        throw new RangeError('output exceeds the maximum Buffer size');
      }

      let nativePixelartValue;
      if (options.preset === PRESETS.pixelart) {
        nativePixelart = koffi.alloc(NATIVE_PIXELART_OPTIONS, 1);
        status = bindings.pixelartInit(nativePixelart);
        if (status !== STATUS.ok) throw statusError(status);
        nativePixelartValue = Object.assign(koffi.decode(nativePixelart, NATIVE_PIXELART_OPTIONS), pixelartOverrides);
        koffi.encode(nativePixelart, NATIVE_PIXELART_OPTIONS, nativePixelartValue);
      }

      const source = Buffer.from(input.buffer, input.byteOffset, input.byteLength);
      const output = Buffer.allocUnsafe(outputSize);
      status = nativePixelart
        ? bindings.convertPixelart(
            source,
            source.byteLength,
            inputWidth,
            inputHeight,
            inputStride,
            targetWidth,
            targetHeight,
            nativeOptions,
            nativePixelart,
            output,
            output.length
          )
        : bindings.convert(
            source,
            source.byteLength,
            inputWidth,
            inputHeight,
            inputStride,
            targetWidth,
            targetHeight,
            nativeOptions,
            output,
            output.length
          );
      if (status !== STATUS.ok) throw statusError(status);
      return output;
    } finally {
      if (nativePixelart) koffi.free(nativePixelart);
      if (outputSizePointer) koffi.free(outputSizePointer);
      koffi.free(nativeOptions);
    }
  }

  convertRgba8.pixelartDefaults = pixelartDefaults;
  return convertRgba8;
}

module.exports = {
  createConverter,
  presets: PRESETS,
  pixelartModes: PIXELART_MODES,
  samplingModes: SAMPLE_MODES
};
