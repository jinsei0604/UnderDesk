// 異形紳士の単体攻撃の音（2026-11-20）: 承認済みの通しの音（src/single_base.wav）はそのまま、
// 本体が霧になって消える・相手の高さに現れる・戻る所（rbm_gentleman_vfx.gd の STEP_OUT・STEP_IN・BACK_OUT・BACK_IN）に
// 小さな霧の音を足す。元は無音の区間。出力 assets_bossmaker/audio/gentleman/single.wav（長さは元と同じ）。
// 実行: node tools/gentleman/audio/build_single.mjs
import path from "node:path";
import { fileURLToPath } from "node:url";
import { SR, db, smooth, wavRead, wavWrite, sweepNoise, subDrop, reverb } from "../../hero_boss/audio/dsp.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "../../..");
const base = wavRead(path.join(HERE, "src/single_base.wav"));
if (base.rate !== SR) throw new Error("rate " + base.rate);
const out = [Float32Array.from(base.buf[0]), Float32Array.from(base.buf[1])];
const wet = [new Float32Array(out[0].length), new Float32Array(out[1].length)];

function put(dst, s, at, lvl, pan = 0) {
	const o = Math.round(at * SR), g = db(lvl);
	const gl = g * Math.min(1, 1 - pan), gr = g * Math.min(1, 1 + pan);
	for (let i = 0; i < s[0].length && o + i < dst[0].length; i++) {
		if (o + i < 0) continue;
		dst[0][o + i] += s[0][i] * gl; dst[1][o + i] += s[1][i] * gr;
	}
}
// 消える: 布が翻るような、高い所から低く沈む息の音
function vanish(seed) {
	return sweepNoise({ sec: 0.32, f0: 2400, f1: 420, q: 1.4, curve: 0.8, seed, env: (t) => smooth(0, 0.05, t) * (1 - smooth(0.12, 0.32, t)) });
}
// 現れる: 低い所から立ち上がる息の音と、足が着く小さな重み
function appear(seed) {
	const w = sweepNoise({ sec: 0.3, f0: 380, f1: 1900, q: 1.3, curve: 1.4, seed, env: (t) => smooth(0, 0.18, t) * (1 - smooth(0.22, 0.3, t)) });
	const d = subDrop({ sec: 0.22, f0: 90, f1: 50, decay: 14, click: 0.2, seed: seed + 1 });
	const n = Math.max(w[0].length, d[0].length + Math.round(0.2 * SR));
	const s = [new Float32Array(n), new Float32Array(n)];
	for (let i = 0; i < w[0].length; i++) { s[0][i] += w[0][i]; s[1][i] += w[1][i]; }
	const o = Math.round(0.2 * SR);
	for (let i = 0; i < d[0].length; i++) { s[0][o + i] += d[0][i] * 0.5; s[1][o + i] += d[1][i] * 0.5; }
	return s;
}
const pan = 0.35; // 紳士は画面の右
for (const [at, s, lvl] of [[0.95, vanish(1101), -21], [1.18, appear(1103), -22], [3.98, vanish(1105), -22], [4.18, appear(1107), -23]]) {
	put(out, s, at, lvl, pan);
	put(wet, s, at, lvl - 6, pan);
}
const verb = reverb(wet, { room: 0.78, damp: 0.5, wet: 1, tail: 0.8 });
for (let c = 0; c < 2; c++) for (let i = 0; i < out[c].length; i++) out[c][i] += verb[c][i] * 0.5;
// 元の音は変えない（リミッターを掛けない）。足した音で 0dB を超えないことだけ確かめる。
let peak = 0;
for (let c = 0; c < 2; c++) for (let i = 0; i < out[c].length; i++) peak = Math.max(peak, Math.abs(out[c][i]));
if (peak >= 1) throw new Error("clip " + peak);
wavWrite(path.join(ROOT, "assets_bossmaker/audio/gentleman/single.wav"), out);
console.log("peak", (20 * Math.log10(peak)).toFixed(1) + "dBFS");
console.log("wrote single.wav", (base.buf[0].length / SR).toFixed(3) + "s");
