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
  bold: 2
});

const SAMPLE_MODES = Object.freeze({
  area: 0,
  nearest: 1
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
    'win32-x64': '@madeit/pixelart-win32-x64',
    'win32-arm64': '@madeit/pixelart-win32-arm64',
    'linux-x64': '@madeit/pixelart-linux-x64-gnu',
    'linux-arm64': '@madeit/pixelart-linux-arm64-gnu',
    'darwin-x64': '@madeit/pixelart-darwin-x64',
    'darwin-arm64': '@madeit/pixelart-darwin-arm64'
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
      throw new Error(`The native package ${packageName} is not installed; reinstall @madeit/pixelart for this platform`);
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
    throw new RangeError('preset must be balanced, detail, or bold');
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

function createNativeBindings(libraryPath) {
  const library = koffi.load(resolveNativeLibrary(libraryPath));

  return {
    optionsInit: library.func('int madeitpx_options_init(_Out_ madeitpx_options *options)'),
    getOutputSize: library.func('int madeitpx_get_output_size(uint32_t target_width, uint32_t target_height, _Out_ size_t *output_size)'),
    convert: library.func('int madeitpx_convert_rgba8(const uint8_t *input, size_t input_size, uint32_t input_width, uint32_t input_height, size_t input_stride, uint32_t target_width, uint32_t target_height, const madeitpx_options *options, uint8_t *output, size_t output_capacity)')
  };
}

function createConverter(configuration = {}) {
  if (configuration === null || typeof configuration !== 'object' || Array.isArray(configuration)) {
    throw new TypeError('configuration must be an object');
  }
  const bindings = createNativeBindings(configuration.libraryPath);

  return function convertRgba8(input, settings = {}) {
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
    const nativeOptions = koffi.alloc(NATIVE_OPTIONS, 1);
    let outputSizePointer;
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

      const source = Buffer.from(input.buffer, input.byteOffset, input.byteLength);
      const output = Buffer.allocUnsafe(outputSize);
      status = bindings.convert(
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
      if (outputSizePointer) koffi.free(outputSizePointer);
      koffi.free(nativeOptions);
    }
  };
}

module.exports = {
  createConverter,
  presets: PRESETS,
  samplingModes: SAMPLE_MODES
};
