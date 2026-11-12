// 音の部品: WAV の読み書き・再サンプル・フィルタ・合成音・残響・リミッター。
// すべて乱数の種から決まるので、同じ入力なら同じ音になる。
import fs from "node:fs";

export const SR = 48000;
export const TAU = Math.PI * 2;

export function rng(seed) {
	let s = (seed * 2654435761) >>> 0 || 1;
	return () => {
		s ^= s << 13; s >>>= 0;
		s ^= s >>> 17;
		s ^= s << 5; s >>>= 0;
		return s / 4294967296;
	};
}

export const db = (x) => Math.pow(10, x / 20);
export const lerp = (a, b, t) => a + (b - a) * t;
export const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
export const smooth = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };

// ---- ステレオの入れ物 ----
export function stereo(sec) {
	const n = Math.ceil(sec * SR);
	return [new Float32Array(n), new Float32Array(n)];
}
export const dur = (s) => s[0].length / SR;

export function wavRead(file) {
	const b = fs.readFileSync(file);
	let p = 12, fmt = null, data = null;
	while (p + 8 <= b.length) {
		const id = b.toString("ascii", p, p + 4);
		const size = b.readUInt32LE(p + 4);
		if (id === "fmt ") fmt = { format: b.readUInt16LE(p + 8), ch: b.readUInt16LE(p + 10), rate: b.readUInt32LE(p + 12), bits: b.readUInt16LE(p + 22) };
		if (id === "data") data = { start: p + 8, size: Math.min(size, b.length - p - 8) };
		p += 8 + size + (size & 1);
	}
	const bytes = fmt.bits / 8;
	const n = Math.floor(data.size / bytes / fmt.ch);
	const out = [new Float32Array(n), new Float32Array(n)];
	const read = (o) => {
		if (fmt.bits === 16) return b.readInt16LE(o) / 32768;
		if (fmt.bits === 24) return b.readIntLE(o, 3) / 8388608;
		if (fmt.bits === 32 && fmt.format === 3) return b.readFloatLE(o);
		if (fmt.bits === 32) return b.readInt32LE(o) / 2147483648;
		return (b[o] - 128) / 128;
	};
	for (let i = 0; i < n; i++) {
		const o = data.start + i * fmt.ch * bytes;
		out[0][i] = read(o);
		out[1][i] = fmt.ch > 1 ? read(o + bytes) : out[0][i];
	}
	return { rate: fmt.rate, buf: out };
}

export function wavWrite(file, s) {
	const n = s[0].length;
	const b = Buffer.alloc(44 + n * 4);
	b.write("RIFF", 0); b.writeUInt32LE(36 + n * 4, 4); b.write("WAVEfmt ", 8);
	b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(2, 22);
	b.writeUInt32LE(SR, 24); b.writeUInt32LE(SR * 4, 28); b.writeUInt16LE(4, 32); b.writeUInt16LE(16, 34);
	b.write("data", 36); b.writeUInt32LE(n * 4, 40);
	for (let i = 0; i < n; i++) {
		b.writeInt16LE(Math.round(clamp(s[0][i], -1, 1) * 32767), 44 + i * 4);
		b.writeInt16LE(Math.round(clamp(s[1][i], -1, 1) * 32767), 46 + i * 4);
	}
	fs.writeFileSync(file, b);
}

// 高さ（speed>1 で高く短く）を変えて SR へ。4点補間。
export function resample(src, rate, speed = 1) {
	const step = (rate / SR) * speed;
	const len = Math.max(1, Math.floor(src[0].length / step));
	const out = [new Float32Array(len), new Float32Array(len)];
	for (let c = 0; c < 2; c++) {
		const a = src[c], o = out[c];
		for (let i = 0; i < len; i++) {
			const x = i * step, k = Math.floor(x), f = x - k;
			const p0 = a[k - 1] ?? a[k] ?? 0, p1 = a[k] ?? 0, p2 = a[k + 1] ?? p1, p3 = a[k + 2] ?? p2;
			o[i] = p1 + 0.5 * f * (p2 - p0 + f * (2 * p0 - 5 * p1 + 4 * p2 - p3 + f * (3 * (p1 - p2) + p3 - p0)));
		}
	}
	return out;
}

export function reverse(s) {
	return [Float32Array.from(s[0]).reverse(), Float32Array.from(s[1]).reverse()];
}

// 音の頭の無音を切る。一番大きい瞬間（20ms の窓）の位置も返す。
export function analyze(s) {
	const win = Math.floor(SR * 0.01);
	let max = 0, at = 0;
	const env = [];
	for (let i = 0; i + win <= s[0].length; i += win) {
		let e = 0;
		for (let j = 0; j < win; j++) e += s[0][i + j] ** 2 + s[1][i + j] ** 2;
		const v = Math.sqrt(e / (2 * win));
		env.push(v);
		if (v > max) { max = v; at = i; }
	}
	let onset = 0;
	for (let i = 0; i < env.length; i++) if (env[i] > max * 0.12) { onset = i * win; break; }
	return { peakAt: at / SR, onset: onset / SR, rmsMax: max };
}

export function slice(s, a, b) {
	const i = Math.floor(a * SR), j = b == null ? s[0].length : Math.min(s[0].length, Math.floor(b * SR));
	return [s[0].slice(i, j), s[1].slice(i, j)];
}

export function fade(s, inSec = 0.002, outSec = 0.02) {
	const n = s[0].length, ni = Math.max(1, Math.floor(inSec * SR)), no = Math.max(1, Math.floor(outSec * SR));
	for (let c = 0; c < 2; c++) {
		for (let i = 0; i < Math.min(ni, n); i++) s[c][i] *= i / ni;
		for (let i = 0; i < Math.min(no, n); i++) s[c][n - 1 - i] *= i / no;
	}
	return s;
}

export function gain(s, g) {
	for (let c = 0; c < 2; c++) for (let i = 0; i < s[c].length; i++) s[c][i] *= g;
	return s;
}

export function envelope(s, fn) {
	const n = s[0].length;
	for (let i = 0; i < n; i++) { const g = fn(i / SR, i / n); s[0][i] *= g; s[1][i] *= g; }
	return s;
}

export function pan(s, p) {
	const a = (p + 1) * 0.25 * Math.PI, l = Math.cos(a) * Math.SQRT2, r = Math.sin(a) * Math.SQRT2;
	for (let i = 0; i < s[0].length; i++) { s[0][i] *= l; s[1][i] *= r; }
	return s;
}

// バイクアッド（周波数は時間で動かせる）
export function biquad(a, type, fnF, q = 0.7) {
	const f = typeof fnF === "function" ? fnF : () => fnF;
	let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
	const o = new Float32Array(a.length);
	let b0, b1, b2, a1, a2;
	for (let i = 0; i < a.length; i++) {
		if (i % 16 === 0) {
			const w = TAU * clamp(f(i / SR), 15, SR * 0.45) / SR, cw = Math.cos(w), al = Math.sin(w) / (2 * q);
			const a0 = 1 + al;
			if (type === "lp") { b0 = (1 - cw) / 2 / a0; b1 = (1 - cw) / a0; b2 = b0; }
			else if (type === "hp") { b0 = (1 + cw) / 2 / a0; b1 = -(1 + cw) / a0; b2 = b0; }
			else { b0 = al / a0; b1 = 0; b2 = -al / a0; }
			a1 = -2 * cw / a0; a2 = (1 - al) / a0;
		}
		const y = b0 * a[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
		x2 = x1; x1 = a[i]; y2 = y1; y1 = y; o[i] = y;
	}
	return o;
}
export function filt(s, type, f, q) { return [biquad(s[0], type, f, q), biquad(s[1], type, f, q)]; }

export function drive(s, amount) {
	const norm = Math.tanh(amount);
	for (let c = 0; c < 2; c++) for (let i = 0; i < s[c].length; i++) s[c][i] = Math.tanh(s[c][i] * amount) / norm;
	return s;
}

// ---- 合成音 ----
function noise(sec, seed) {
	const r1 = rng(seed), r2 = rng(seed + 991), n = Math.ceil(sec * SR);
	const l = new Float32Array(n), m = new Float32Array(n);
	for (let i = 0; i < n; i++) { l[i] = r1() * 2 - 1; m[i] = r2() * 2 - 1; }
	return [l, m];
}

// 帯域を動かすノイズ（風切り・上昇音・炎）
export function sweepNoise({ sec, f0, f1, q = 1.2, curve = 2, env, seed = 1, wide = 1 }) {
	const s = noise(sec, seed);
	const f = (t) => f0 * Math.pow(f1 / f0, Math.pow(clamp(t / sec, 0, 1), curve));
	const o = [biquad(s[0], "bp", f, q), biquad(s[1], "bp", (t) => f(t) * (1 + 0.04 * wide), q)];
	const norm = 1.9 * Math.sqrt(q);
	for (let i = 0; i < o[0].length; i++) {
		const g = (env ? env(i / SR, i / o[0].length) : 1) * norm;
		o[0][i] *= g; o[1][i] *= g;
	}
	return o;
}

// 低音の落下（命中の重さ）
export function subDrop({ sec, f0, f1, decay = 6, click = 0.5, seed = 1 }) {
	const n = Math.ceil(sec * SR);
	const o = new Float32Array(n);
	let ph = 0;
	const r = rng(seed);
	for (let i = 0; i < n; i++) {
		const t = i / SR, u = t / sec;
		ph += TAU * (f1 + (f0 - f1) * Math.exp(-t * 18)) / SR;
		const c = t < 0.006 ? (r() * 2 - 1) * click * (1 - t / 0.006) : 0;
		o[i] = (Math.sin(ph) + 0.25 * Math.sin(ph * 2.01)) * Math.exp(-t * decay) * Math.min(1, t * 900) * (1 - smooth(0.85, 1, u)) + c;
	}
	return [o, Float32Array.from(o)];
}

// 低い地鳴り
export function rumble({ sec, cutoff = 110, seed = 1, env }) {
	const s = noise(sec, seed);
	const o = [biquad(biquad(s[0], "lp", cutoff, 0.8), "lp", cutoff * 1.4, 0.7), biquad(biquad(s[1], "lp", cutoff * 1.1, 0.8), "lp", cutoff * 1.5, 0.7)];
	const r = rng(seed + 5);
	const wob = [r() * TAU, r() * TAU];
	for (let i = 0; i < o[0].length; i++) {
		const t = i / SR;
		const g = 9 * (env ? env(t, t / sec) : 1) * (0.72 + 0.28 * Math.sin(t * 17 + wob[0]) * Math.sin(t * 7.3 + wob[1]));
		o[0][i] *= g; o[1][i] *= g;
	}
	return o;
}

// 持続する炎（帯域のノイズに、ゆらぎと細かい破裂）
export function flame({ sec, f = 620, q = 0.7, env, seed = 1, flutter = 0.45 }) {
	const s = sweepNoise({ sec, f0: f, f1: f, q, seed });
	const low = sweepNoise({ sec, f0: f * 0.32, f1: f * 0.32, q: 0.8, seed: seed + 9 });
	const r = rng(seed + 33);
	let v = 0, tgt = 0.5;
	for (let i = 0; i < s[0].length; i++) {
		if (i % 480 === 0) tgt = r();
		v += (tgt - v) * 0.004;
		const t = i / SR;
		const g = (env ? env(t, t / sec) : 1) * (1 - flutter + flutter * 2 * v);
		s[0][i] = (s[0][i] * 0.6 + low[0][i]) * g;
		s[1][i] = (s[1][i] * 0.6 + low[1][i]) * g;
	}
	return s;
}

// 放電: 不規則に弾ける短い音の列
export function electric({ sec, density = 40, seed = 1, env, f = 3400 }) {
	const out = stereo(sec);
	const r = rng(seed);
	const n = Math.floor(density * sec);
	for (let k = 0; k < n; k++) {
		const u = r();
		const at = u * sec;
		const lvl = env ? env(at, u) : 1;
		if (lvl <= 0.01) continue;
		const len = Math.floor((0.003 + r() * 0.03) * SR);
		const start = Math.floor(at * SR);
		const buzz = 90 + r() * 260;
		const p = r() * 2 - 1;
		for (let i = 0; i < len && start + i < out[0].length; i++) {
			const t = i / SR;
			const a = Math.exp(-i / (len * 0.35)) * lvl * (0.5 + 0.5 * r());
			const v = (r() * 2 - 1) * 0.7 + Math.sign(Math.sin(TAU * buzz * t)) * 0.45;
			out[0][start + i] += v * a * (1 - p * 0.6);
			out[1][start + i] += v * a * (1 + p * 0.6);
		}
	}
	return filt(filt(out, "hp", f * 0.45, 0.7), "lp", f * 3.4, 0.7);
}

// 熾火のぱちぱち
export function crackle({ sec, density = 22, seed = 1, env }) {
	const out = stereo(sec);
	const r = rng(seed);
	const n = Math.floor(density * sec);
	for (let k = 0; k < n; k++) {
		const u = r();
		const lvl = (env ? env(u * sec, u) : 1) * (0.25 + r() * 0.75);
		const start = Math.floor(u * sec * SR);
		const len = Math.floor((0.0015 + r() * 0.006) * SR);
		const p = r() * 2 - 1;
		for (let i = 0; i < len && start + i < out[0].length; i++) {
			const v = (r() * 2 - 1) * Math.exp(-i / (len * 0.3)) * lvl;
			out[0][start + i] += v * (1 - p * 0.7);
			out[1][start + i] += v * (1 + p * 0.7);
		}
	}
	return filt(out, "hp", 1400, 0.7);
}

// 金属・刃の響き（整数倍にならない倍音の束）
export function metalRing({ sec, base = 1800, partials = [1, 1.51, 2.27, 2.91, 3.76, 5.02], decay = 7, seed = 1, env }) {
	const out = stereo(sec);
	const r = rng(seed);
	for (let k = 0; k < partials.length; k++) {
		const f = base * partials[k] * (1 + (r() - 0.5) * 0.01);
		const beat = 1 + r() * 0.004;
		const amp = (0.9 - k * 0.11) * (0.7 + r() * 0.3);
		const dk = decay * (1 + k * 0.32);
		const pl = r() * TAU, pr = r() * TAU;
		for (let i = 0; i < out[0].length; i++) {
			const t = i / SR;
			const e = Math.exp(-t * dk) * amp * Math.min(1, t * 2500);
			out[0][i] += Math.sin(TAU * f * t + pl) * e * 0.3;
			out[1][i] += Math.sin(TAU * f * beat * t + pr) * e * 0.3;
		}
	}
	if (env) envelope(out, env);
	return out;
}

// 光線の発射音（周波数が急に落ちる）
export function beam({ sec = 0.3, f0 = 2600, f1 = 340, seed = 1 }) {
	const n = Math.ceil(sec * SR), out = [new Float32Array(n), new Float32Array(n)];
	const r = rng(seed);
	let ph = 0, ph2 = 0;
	for (let i = 0; i < n; i++) {
		const t = i / SR, u = t / sec;
		const f = f1 + (f0 - f1) * Math.exp(-u * 7);
		ph += TAU * f / SR; ph2 += TAU * f * 1.503 / SR;
		const e = Math.exp(-u * 5.5) * Math.min(1, t * 1400);
		const v = Math.sin(ph + 1.8 * Math.sin(ph2) * Math.exp(-u * 3)) * e + (r() * 2 - 1) * 0.12 * e;
		out[0][i] = v; out[1][i] = v * 0.94;
	}
	return out;
}

// 砕けるガラスの粒
export function shatter({ sec = 1.2, count = 90, seed = 1, f0 = 2600, f1 = 9000, env }) {
	const out = stereo(sec);
	const r = rng(seed);
	for (let k = 0; k < count; k++) {
		const u = Math.pow(r(), 1.9);
		const at = Math.floor(u * sec * SR);
		const f = lerp(f0, f1, r());
		const len = Math.floor((0.012 + r() * 0.07) * SR);
		const amp = (env ? env(u * sec, u) : Math.exp(-u * 3)) * (0.3 + r() * 0.7);
		const p = r() * 2 - 1, f2 = f * (1.27 + r() * 0.5);
		for (let i = 0; i < len && at + i < out[0].length; i++) {
			const t = i / SR;
			const a = Math.exp(-i / (len * 0.28)) * amp * Math.min(1, i / 8);
			const v = (Math.sin(TAU * f * t) + 0.6 * Math.sin(TAU * f2 * t)) * a;
			out[0][at + i] += v * (1 - p * 0.65) * 0.5;
			out[1][at + i] += v * (1 + p * 0.65) * 0.5;
		}
	}
	return out;
}

// 太い持続音（高さが動く、のこぎり波を低域だけ）。力の高まり・闇の持続に使う。
export function drone({ sec, f0, f1 = f0, voices = [1, 1.004, 0.5, 1.498], cutoff = 900, env, curve = 1, wob = 0.0, seed = 1 }) {
	const n = Math.ceil(sec * SR), out = [new Float32Array(n), new Float32Array(n)];
	const r = rng(seed);
	const ph = voices.map(() => r());
	const dt = voices.map(() => (r() - 0.5) * 0.002);
	for (let i = 0; i < n; i++) {
		const t = i / SR, u = t / sec;
		const f = f0 * Math.pow(f1 / f0, Math.pow(u, curve)) * (1 + wob * Math.sin(t * 31));
		let l = 0, m = 0;
		for (let k = 0; k < voices.length; k++) {
			ph[k] += (f * voices[k] * (1 + dt[k])) / SR; if (ph[k] >= 1) ph[k] -= 1;
			const v = (2 * ph[k] - 1) * (k < 2 ? 1 : 0.6);
			if (k % 2 === 0) l += v; else m += v;
			if (k >= 2) { l += v * 0.5; m += v * 0.5; }
		}
		const e = env ? env(t, u) : 1;
		out[0][i] = l * e * 0.32; out[1][i] = m * e * 0.32;
	}
	const fc = typeof cutoff === "function" ? cutoff : () => cutoff;
	return filt(out, "lp", (t) => fc(t, t / sec), 0.75);
}

// 裂ける音（ノイズを低い周波数で刻み、刻みを速くする）
export function rip({ sec = 0.3, seed = 1, f0 = 900, f1 = 2600 }) {
	const s = sweepNoise({ sec, f0, f1, q: 0.9, curve: 0.7, seed });
	const r = rng(seed + 3);
	let ph = 0;
	const flut = 0.3 + r() * 0.1;
	for (let i = 0; i < s[0].length; i++) {
		const t = i / SR, u = t / sec;
		ph += TAU * lerp(70, 260, Math.pow(u, 1.4)) / SR;
		const g = (0.55 + 0.45 * Math.sign(Math.sin(ph)) * (1 - flut)) * Math.min(1, t * 700) * Math.pow(1 - u, 1.4);
		s[0][i] *= g; s[1][i] *= g;
	}
	return s;
}

// 残響（櫛形 8 本＋全通過 4 本）
export function reverb(s, { room = 0.82, damp = 0.45, wet = 1, tail = 1.6 }) {
	const combs = [1557, 1617, 1491, 1422, 1277, 1356, 1188, 1116];
	const alls = [556, 441, 341, 225];
	const n = s[0].length + Math.floor(tail * SR);
	const out = [new Float32Array(n), new Float32Array(n)];
	for (let c = 0; c < 2; c++) {
		const spread = c === 0 ? 0 : 23;
		const mix = new Float32Array(n);
		const inp = s[c];
		for (const len0 of combs) {
			const len = Math.round((len0 + spread) * (SR / 44100));
			const b = new Float32Array(len);
			let p = 0, store = 0;
			for (let i = 0; i < n; i++) {
				const v = b[p];
				store = v * (1 - damp) + store * damp;
				b[p] = (i < inp.length ? inp[i] * 0.04 : 0) + store * room;
				p = (p + 1) % len;
				mix[i] += v;
			}
		}
		for (const len0 of alls) {
			const len = Math.round((len0 + spread) * (SR / 44100));
			const b = new Float32Array(len);
			let p = 0;
			for (let i = 0; i < n; i++) {
				const bv = b[p], v = mix[i];
				mix[i] = -v + bv;
				b[p] = v + bv * 0.5;
				p = (p + 1) % len;
			}
		}
		for (let i = 0; i < n; i++) out[c][i] = mix[i] * wet;
	}
	return out;
}

// 先読みリミッター（ふだんは働かない安全網）
export function limiter(s, ceiling = 0.84, lookMs = 3, relMs = 110) {
	const n = s[0].length, look = Math.floor((lookMs / 1000) * SR);
	const need = new Float32Array(n);
	for (let i = 0; i < n; i++) { const p = Math.max(Math.abs(s[0][i]), Math.abs(s[1][i])); need[i] = p > ceiling ? ceiling / p : 1; }
	const rel = Math.exp(-1 / ((relMs / 1000) * SR));
	let g = 1, reduced = 0;
	const out = [new Float32Array(n), new Float32Array(n)];
	for (let i = 0; i < n; i++) {
		let m = 1;
		for (let j = i; j < Math.min(n, i + look); j++) if (need[j] < m) m = need[j];
		if (m < g) g = m; else g = m + (g - m) * rel;
		if (g < 0.995) reduced++;
		out[0][i] = s[0][i] * g; out[1][i] = s[1][i] * g;
	}
	return { out, reducedSec: reduced / SR };
}
