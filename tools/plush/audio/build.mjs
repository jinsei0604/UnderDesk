// つぎはぎのぬいぐるみ（plush）の登場「縫い直し」の音（2026-11-17、2026-11-19 部位ごとの糸に作り直し・針で縫う音を足した）。
// 時刻は src/bossmaker/visuals/encounter/intro/rbm_intro_plush.gd の T から読むので、演出の時刻を直せば音も一緒に動く。
// 使い方: node tools/plush/audio/build.mjs → tools/plush/audio/out/intro.wav
// できた音は assets_bossmaker/audio/plush/intro.wav へ置く（置いた後に --import）。
// 素材: 既存のゲームの効果音（assets_bossmaker/audio/*.wav）と、ヒーローの音の部品（tools/hero_boss/audio/dsp.mjs）。乱数は種つきで、毎回同じ音になる。
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
	SR, db, smooth, stereo, wavRead, wavWrite, resample, analyze, slice, fade, pan as panIt,
	filt, sweepNoise, subDrop, drone, metalRing, crackle, reverb, limiter,
} from "../../hero_boss/audio/dsp.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ASSET = path.resolve(HERE, "../../../assets_bossmaker/audio");
const OUT = path.join(HERE, "out");
fs.mkdirSync(OUT, { recursive: true });

// ---- 時刻表を読む ----
function readTiming() {
	const src = fs.readFileSync(path.resolve(HERE, "../../../src/bossmaker/visuals/encounter/intro/rbm_intro_plush.gd"), "utf8");
	const m = src.match(/const T := (\{[\s\S]*?\n\})/);
	return JSON.parse(m[1].replace(/,(\s*[}\]])/g, "$1"));
}
const T = readTiming();

const cache = new Map();
function asset(name, speed) {
	const key = `${name}@${speed}`;
	if (!cache.has(key)) {
		const { rate, buf } = wavRead(path.join(ASSET, name + ".wav"));
		cache.set(key, resample(buf, rate, speed));
	}
	const b = cache.get(key);
	return [Float32Array.from(b[0]), Float32Array.from(b[1])];
}

// ヒーローの音と同じ音量の階層（主役の音とそれ以外の差）
const mixLevel = (lvl) => lvl + (lvl > -10.5 ? -6.5 : -8.5);

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
	finish(sendGain = 0.4, room = 0.7, damp = 0.55) {
		const wet = reverb(this.wet, { room, damp, wet: sendGain, tail: 0.1 });
		const n = Math.ceil(this.sec * SR);
		const mix = stereo(this.sec);
		for (let c = 0; c < 2; c++) for (let i = 0; i < n; i++) mix[c][i] = this.dry[c][i] + wet[c][i];
		fade(mix, 0.002, 0.09);
		return limiter(mix, db(-1.6));
	}
}

const fall = (u, p = 1.5) => Math.pow(1 - u, p);
const hitDecay = (p = 1.5, attack = 0.03) => (_, u) => smooth(0, attack, u) * fall(u, p);

// 布がこすれる・ふわっと落ちる小さな音
function cloth(tr, at, lvl, sp = 1, pan = 0.2) {
	tr.sfx("cover_move", at, { db: lvl, speed: 0.9 * sp, pan, lp: 2200 });
}

function intro() {
	const t = T, D = t.end;
	const tr = new Track(D);
	const pans = { leg_l: -0.25, leg_r: 0.3, arm_l: -0.35, arm_r: 0.45, head: -0.5 };
	const order = ["leg_l", "leg_r", "arm_l", "arm_r", "head"];
	// 静かな裁縫部屋（低い部屋の音と、時計のような小さな刻み）
	tr.put(drone({ sec: D, f0: 82, voices: [1, 1.003, 0.5], cutoff: 260, seed: 801, env: (_, u) => smooth(0, 0.08, u) * (1 - smooth(0.9, 1, u)) }), 0, { db: -31, send: 0.2 });
	for (let k = 0; k * 0.5 < t.shoot[0]; k++) tr.sfx("encounter/watch_tick", 0.05 + k * 0.5, { db: -30, speed: 1.1, pan: -0.4 });
	// 部位ごとに糸が飛ぶ（高い風切り）→ 刺す（小さな音）
	order.forEach((part, i) => {
		const s0 = t.shoot[i];
		tr.put(sweepNoise({ sec: t.shot + 0.02, f0: 2600, f1: 5600, q: 2.5, curve: 1, seed: 803 + i, env: (_, u) => smooth(0, 0.3, u) * (1 - smooth(0.85, 1, u)) }), s0, { db: -26, pan: pans[part] });
		tr.sfx("neutral_staff_tap", s0 + t.shot, { db: -24, speed: 2.1, align: "onset", pan: pans[part], lp: 7000 });
	});
	// 糸が張る（きしむ高い音）
	tr.put(drone({ sec: t.pull[0] - t.tighten + 0.05, f0: 1250, f1: 1480, voices: [1, 1.004], cutoff: 3200, seed: 813, env: (_, u) => smooth(0, 0.2, u) * (1 - smooth(0.9, 1, u)) }), t.tighten, { db: -31, send: 0.2 });
	// 引き寄せて縫い付ける（布のこすれ → 刺す音 → やわらかい当たり）。頭は最後に大きく
	order.forEach((part, i) => {
		const a = t.pull[i], arrive = a + t.travel[i], head = part === "head";
		tr.put(sweepNoise({ sec: t.travel[i], f0: 380, f1: 1100, q: 1, curve: 1, seed: 821 + i, env: (_, u) => smooth(0, 0.4, u) * (1 - smooth(0.9, 1, u)) }), a, { db: head ? -22 : -25, pan: pans[part] * 0.5 });
		cloth(tr, arrive - 0.02, head ? -19 : -22, 1.0 + i * 0.06, pans[part] * 0.3);
		tr.put(subDrop({ sec: head ? 0.4 : 0.25, f0: head ? 90 : 110, f1: head ? 46 : 60, decay: head ? 8 : 12, click: 0.02, seed: 841 + i }), arrive, { db: head ? -16 : -21 });
	});
	tr.sfx("encounter/slime_splat", t.pull[4] + t.travel[4], { db: -23, speed: 1.4, align: "peak", pan: 0.1, lp: 1800 });
	// 針が飛んでくる（高い風切りと、小さな金属の響き）
	tr.put(sweepNoise({ sec: t.sew[0] - t.needle_in, f0: 5200, f1: 2400, q: 2.5, curve: 1, seed: 861, env: (_, u) => smooth(0, 0.3, u) * (1 - smooth(0.85, 1, u)) }), t.needle_in, { db: -24, pan: 0.45 });
	tr.put(metalRing({ sec: 0.5, base: 3400, decay: 9, seed: 863 }), t.needle_in + 0.05, { db: -30, pan: 0.5, send: 0.4 });
	// 縫う: 1針ごとに布を刺す小さな音と、糸を引く「しゅっ」（初版と同じ）
	order.forEach((part, i) => {
		for (let k = 0; k < 3; k++) {
			const at = t.sew[i] + t.stitch * k;
			tr.sfx("neutral_staff_tap", at, { db: -22 + (part === "head" ? 1 : 0), speed: 1.9 + k * 0.08, align: "onset", pan: pans[part] * 0.3, lp: 6000 });
			tr.put(sweepNoise({ sec: 0.09, f0: 2600, f1: 5200, q: 3, curve: 1, seed: 871 + i * 3 + k, env: hitDecay(1.2, 0.2) }), at + 0.03, { db: -27, pan: pans[part] * 0.3 });
		}
	});
	// 針が上へ抜け、糸がぷつっと切れる
	tr.put(sweepNoise({ sec: t.snap - t.needle_out, f0: 1800, f1: 5200, q: 2, curve: 1.2, seed: 891, env: (_, u) => smooth(0, 0.3, u) }), t.needle_out, { db: -26, pan: 0.05 });
	tr.sfx("neutral_staff_tap", t.snap, { db: -20, speed: 2.4, align: "onset", pan: 0.05, hp: 900 });
	tr.put(sweepNoise({ sec: 0.25, f0: 4000, f1: 9000, q: 3, curve: 1, seed: 893, env: hitDecay(2, 0.05) }), t.snap + 0.01, { db: -27, pan: 0.05 });
	// 色が戻る（やわらかい和音）→ ボタンの目が赤く光る（低く不気味な一音）
	tr.put(drone({ sec: 0.9, f0: 392, voices: [1, 1.26, 1.5, 2], cutoff: 1800, seed: 819, env: (_, u) => smooth(0, 0.25, u) * (1 - smooth(0.6, 1, u)) }), t.alive, { db: -27, pan: 0.1, send: 0.5 });
	tr.sfx("encounter/ghost_eyes", t.eye, { db: -21, speed: 0.9, align: "onset", pan: 0.1, send: 0.3 });
	// かわいく手を振る（小さな鈴の音）
	t.wave.forEach((at, i) => tr.put(metalRing({ sec: 0.4, base: 2200 + i * 260, decay: 10, seed: 851 + i }), at, { db: -27, pan: 0.15, send: 0.4 }));
	return tr;
}

const tr = intro();
const { out, reducedSec } = tr.finish();
wavWrite(path.join(OUT, "intro.wav"), out);
console.log(`intro: ${(out[0].length / SR).toFixed(2)}秒, リミッターが働いた時間=${reducedSec.toFixed(2)}秒`);
