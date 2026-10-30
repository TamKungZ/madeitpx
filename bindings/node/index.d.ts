export type Preset = 'balanced' | 'detail' | 'bold' | 'pixelart';
export type SamplingMode = 'area' | 'nearest';

export interface ConverterConfiguration {
  /** Path to a custom madeitpx shared library. Defaults to the matching optional platform package. */
  libraryPath?: string;
}

export interface ConversionOptions {
  inputWidth: number;
  inputHeight: number;
  /** Source row size in bytes. Defaults to inputWidth * 4. */
  inputStride?: number;
  targetWidth: number;
  targetHeight: number;
  preset?: Preset;
  /** 0 uses the preset palette size; otherwise a value from 2 to 64. */
  paletteColors?: number;
  /** Opaque compositing color in 0xRRGGBB format. */
  backgroundRgb?: number;
  sampling?: SamplingMode;
  clusterCleanup?: boolean;
}

export declare function createConverter(
  configuration?: ConverterConfiguration
): (input: Uint8Array, options: ConversionOptions) => Uint8Array;

export declare const presets: Readonly<Record<Preset, number>>;
export declare const samplingModes: Readonly<Record<SamplingMode, number>>;
