// 異形紳士の登場「硝子の弾痕」の音（2026-11-23）。時刻は登場の振付の T（src/bossmaker/visuals/encounter/intro/rbm_intro_gentleman.gd）
// を読む。登場の再生の0秒＝音の0秒（振付は T.track の時刻に、この音の T.track 秒から鳴らす）。
// 素材: 紳士の登場の音（encounter/gent_*）、銃声は紳士の単体攻撃の元の音（src/single_base.wav）から切り出す、
// ほかは合成（../../hero_boss/audio/dsp.mjs）。
// 出力: assets_bossmaker/audio/encounter/gent_intro_v2.wav
// 実行: node tools/gentleman/audio/build_intro.mjs
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
	SR, db, smooth, stereo, wavRead, wavWrite, resample, analyze, slice, fade, pan as panIt,
	filt, sweepNoise, subDrop, drone, crackle, rumble, shatter, reverb, limiter, metalRing,
} from "../../hero_boss/audio/dsp.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "../../..");
const ASSET = path.join(ROOT, "assets_bossmaker/audio");
const CHOREO = path.join(ROOT, "src/bossmaker/visuals/encounter/intro/rbm_intro_gentleman.gd");

function choreo() {
	const src = fs.readFileSync(CHOREO, "utf8");
	const t = JSON.parse(src.match(/const T := (\{[^\n]*\})\n/)[1]);
	const shots = [...src.matchAll(/\["(shot\d)", (-?[\d.]+), Vector2\((\d+), (\d+)\)/g)].map((m) => ({ key: m[1], dx: +m[2], x: +m[3] }));
	return { t, shots };
}

const cache = new Map();
function load(file, speed = 1) {
	const key = `${file}@${speed}`;
	if (!cache.has(key)) {
		const { rate, buf } = wavRead(file);
		cache.set(key, resample(buf, rate, speed));
	}
	const b = cache.get(key);
	return [Float32Array.from(b[0]), Float32Array.from(b[1])];
}
const asset = (name, speed) => load(path.join(ASSET, name + ".wav"), speed);
// 銃声（紳士の単体攻撃の元の音の 2.55〜3.25 秒）
function gunshot(speed = 1) {
	const s = slice(load(path.join(HERE, "src/single_base.wav"), speed), 2.55 / speed, 3.25 / speed);
	fade(s, 0.002, 0.08);
	return s;
}

const mixLevel = (lvl) => lvl + (lvl > -10.5 ? -6.5 : -8.5);
const fall = (u, p = 1.5) => Math.pow(1 - u, p);
const hitDecay = (p = 1.5, attack = 0.03) => (_, u) => smooth(0, attack, u) * fall(u, p);
const rise = (a = 0, b = 0.85, c = 0.95) => (_, u) => smooth(a, b, u) * (1 - smooth(c, 1, u));

class Track {
	constructor(sec) {
		this.sec = sec;
		this.dry = stereo(sec + 0.05);
		this.wet = stereo(sec + 0.05);
	}
	put(s, at, { db: lvl = -20, pan = 0, send = 0, align = "start" } = {}) {
		const a = analyze(s);
		const g = db(mixLevel(lvl)) / Math.max(a.rmsMax, 1e-6);
		const shift = align === "peak" ? a.peakAt : align === "onset" ? a.onset : 0;
		const start = Math.round((at - shift) * SR);
		panIt(s, pan);
		for (let c = 0; c < 2; c++) {
			const d = this.dry[c], w = this.wet[c], src = s[c];
			for (let i = 0; i < src.length; i++) {
				const k = start + i;
				if (k < 0 || k >= d.length) continue;
				d[k] += src[i] * g;
				w[k] += src[i] * g * send;
			}
		}
		return this;
	}
	sfx(name, at, { speed = 1, lp, hp, from, to, fin = 0.001, fout = 0.03, ...rest } = {}) {
		let s = asset(name, speed);
		if (from != null || to != null) s = slice(s, from ?? 0, to);
		if (lp) s = filt(s, "lp", lp, 0.7);
		if (hp) s = filt(s, "hp", hp, 0.7);
		fade(s, fin, fout);
		return this.put(s, at, rest);
	}
	gun(at, opts = {}) {
		const s = gunshot(opts.speed ?? 1);
		return this.put(s, at, { align: "peak", ...opts });
	}
	finish(sendGain = 0.5, room = 0.86, damp = 0.4) {
		const wet = reverb(this.wet, { room, damp, wet: sendGain, tail: 0.1 });
		const n = Math.ceil(this.sec * SR);
		const mix = stereo(this.sec);
		for (let c = 0; c < 2; c++) for (let i = 0; i < n; i++) mix[c][i] = this.dry[c][i] + wet[c][i];
		fade(mix, 0.002, 0.3);
		return limiter(mix, db(-1.6));
	}
}

const BOSS = 0.35; // 紳士は画面の右
const panOf = (x) => Math.max(-0.7, Math.min(0.7, ((x - 640) / 640) * 0.7));

function intro() {
	const { t, shots } = choreo();
	const tr = new Track(t.end + 0.4);
	// 闇: 低い唸りと、時を刻む時計（最後の一発で途切れる）・遠くの鐘
	tr.put(drone({ sec: t.final - t.track, f0: 40, f1: 47, cutoff: 420, seed: 2301, env: rise(0, 0.5, 0.96), wob: 0.15 }), t.track, { db: -19, send: 0.3 });
	for (let k = 0, at = 0.62; at < t.final - 0.1; k++, at += 0.5) {
		tr.put(metalRing({ sec: 0.07, base: k % 2 ? 2350 : 2900, decay: 70, seed: 2310 + k }), at, { db: -29, pan: -0.25, send: 0.35 });
	}
	tr.sfx("encounter/gent_bell", t.bell, { db: -18, pan: 0.1, send: 0.7, lp: 1800, fout: 0.8 });
	tr.sfx("encounter/gent_eyes", t.eyes, { db: -18, pan: BOSS, send: 0.4 });
	// 闇の中の三発: 銃声・ガラスに当たる鈍い音・ひびが走る音
	for (const [i, s] of shots.entries()) {
		const at = t[s.key];
		const p = panOf(s.x);
		tr.gun(at, { db: -9, speed: 1.0 + 0.03 * i, pan: BOSS * 0.6 + p * 0.4, send: 0.45 });
		tr.put(subDrop({ sec: 0.22, f0: 190, f1: 70, decay: 14, click: 1.0, seed: 2330 + i }), at + 0.025, { db: -19, pan: p });
		tr.put(shatter({ sec: 0.5, count: 26, seed: 2340 + i, f0: 2600, f1: 8200, env: hitDecay(2.4, 0.004) }), at + 0.03, { db: -17, pan: p, send: 0.4 });
		tr.put(crackle({ sec: 0.22, density: 70, seed: 2350 + i, env: hitDecay(1.6, 0.01) }), at + 0.035, { db: -22, pan: p, send: 0.3 });
	}
	// 間: 撃鉄を起こす
	tr.sfx("encounter/gent_cock", t.cock, { db: -13, pan: BOSS, send: 0.35 });
	// 最後の一発: 真ん中に当たり、ひびが画面じゅうへ走って軋む（張りつめた高い音）
	tr.gun(t.final, { db: -7, speed: 0.94, pan: BOSS * 0.5, send: 0.5 });
	tr.put(subDrop({ sec: 0.3, f0: 160, f1: 55, decay: 10, click: 1.0, seed: 2361 }), t.final + 0.025, { db: -15 });
	tr.put(crackle({ sec: t.break - t.final, density: 110, seed: 2363, env: rise(0, 0.15, 0.97) }), t.final + 0.03, { db: -19, send: 0.35 });
	tr.put(shatter({ sec: 0.4, count: 30, seed: 2365, f0: 2400, f1: 7600, env: hitDecay(2.0, 0.004) }), t.final + 0.03, { db: -18, send: 0.4 });
	tr.put(sweepNoise({ sec: t.break - t.final, f0: 1600, f1: 4800, q: 7, curve: 1.5, seed: 2367, env: rise(0.1, 0.95, 0.99) }), t.final + 0.02, { db: -25, send: 0.3 });
	// 砕け散る: 大きなガラスの崩れ・低い衝撃・舞う破片のきらめき
	tr.put(shatter({ sec: 2.0, count: 240, seed: 2371, f0: 2000, f1: 11000, env: hitDecay(1.3, 0.003) }), t.break, { db: -8, send: 0.45 });
	tr.put(shatter({ sec: 1.6, count: 130, seed: 2373, f0: 1500, f1: 7000, env: hitDecay(1.1, 0.01) }), t.break + 0.06, { db: -13, pan: -0.3, send: 0.45 });
	tr.put(shatter({ sec: 1.6, count: 130, seed: 2375, f0: 1500, f1: 7000, env: hitDecay(1.1, 0.01) }), t.break + 0.09, { db: -13, pan: 0.3, send: 0.45 });
	tr.put(subDrop({ sec: 1.3, f0: 95, f1: 26, decay: 3, click: 1.0, seed: 2377 }), t.break, { db: -9 });
	tr.put(rumble({ sec: 1.4, cutoff: 130, seed: 2379, env: hitDecay(1.0, 0.03) }), t.break + 0.02, { db: -17, send: 0.3 });
	tr.put(shatter({ sec: 2.2, count: 70, seed: 2381, f0: 5200, f1: 12000, env: (_, u) => smooth(0, 0.05, u) * fall(u, 1.2) }), t.break + 0.35, { db: -24, send: 0.6 });
	// 霧の戻り・一礼
	tr.put(sweepNoise({ sec: t.end - t.break, f0: 300, f1: 900, q: 0.8, curve: 1.0, seed: 2383, env: rise(0, 0.3, 0.8) }), t.break + 0.2, { db: -27, send: 0.3 });
	tr.sfx("encounter/gent_bow", t.bow, { db: -16, pan: BOSS, send: 0.35 });
	return tr;
}

const { out, reducedSec } = intro().finish();
wavWrite(path.join(ASSET, "encounter", "gent_intro_v2.wav"), out);
console.log(`intro: ${(out[0].length / SR).toFixed(2)}秒, リミッターが働いた時間=${reducedSec.toFixed(2)}秒`);
