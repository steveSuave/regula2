// Node driver for the dart2wasm build of complex_bench.dart.
// Usage: node benchmark/wasm_driver.mjs build/bench/bench.wasm [scale]
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const wasmPath = process.argv[2];
const args = process.argv.slice(3);
const mjsPath = wasmPath.replace(/\.wasm$/, '.mjs');
const { compile, instantiate, invoke } = await import(pathToFileURL(mjsPath));

const module = await compile(await readFile(wasmPath));
const instance = await instantiate(Promise.resolve(module), Promise.resolve({}));
invoke(instance, ...args);
