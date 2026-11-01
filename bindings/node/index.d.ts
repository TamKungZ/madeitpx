export type Preset = 'balanced' | 'detail' | 'bold' | 'pixelart';
export type SamplingMode = 'area' | 'nearest';
export type PixelArtMode = 'auto' | 'grid' | 'illustration';

export interface ConverterConfiguration {
  libraryPath?: string;
}

export interface PixelArtSettings {
  version?: 1 | 2;
  mode?: PixelArtMode;
  gridFit?: boolean;
  gridSearchPermille?: number;
  sampleInsetPercent?: number;
  colorTolerance?: number;
  paletteMax?: number;
  refineIterations?: number;
  inkPercent?: number;
  minRegion?: number;
  alphaThreshold?: number;
  keepTransparency?: boolean;
}

export type PixelArtDefaults = Required<PixelArtSettings>;

export interface ConversionOptions {
  inputWidth: number;
  inputHeight: number;
  inputStride?: number;
  targetWidth: number;
  targetHeight: number;
  preset?: Preset;
  paletteColors?: number;
  backgroundRgb?: number;
  sampling?: SamplingMode;
  clusterCleanup?: boolean;
  pixelart?: PixelArtSettings;
}

export interface Converter {
  (input: Uint8Array, options: ConversionOptions): Uint8Array;
  pixelartDefaults(): PixelArtDefaults;
}

export declare function createConverter(configuration?: ConverterConfiguration): Converter;

export declare const presets: Readonly<Record<Preset, number>>;
export declare const samplingModes: Readonly<Record<SamplingMode, number>>;
export declare const pixelartModes: Readonly<Record<PixelArtMode, number>>;
