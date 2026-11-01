import type {
  ConversionOptions,
  PixelArtDefaults,
  PixelArtMode,
  PixelArtSettings,
  Preset,
  SamplingMode
} from './index';

export type { ConversionOptions, PixelArtDefaults, PixelArtMode, PixelArtSettings, Preset, SamplingMode };

export interface BrowserConverterConfiguration {
  wasm?: string | URL | Response | ArrayBuffer | ArrayBufferView | WebAssembly.Module;
}

export interface BrowserConverter {
  (input: Uint8Array | Uint8ClampedArray, options: ConversionOptions): Uint8Array;
  pixelartDefaults(): PixelArtDefaults;
}

export declare function createConverter(configuration?: BrowserConverterConfiguration): Promise<BrowserConverter>;

export declare const presets: Readonly<Record<Preset, number>>;
export declare const samplingModes: Readonly<Record<SamplingMode, number>>;
export declare const pixelartModes: Readonly<Record<PixelArtMode, number>>;
