// ヒーロー（hero_boss）の5種類の技の「音の時間割」（2026-11-09〜10 試作で作り、ユーザーが採用した音）。
// 時刻は src/bossmaker/visuals/hero_boss/rbm_hero_fx_timing.gd から読むので、演出の時刻を直せば音も一緒に動く。
// 使い方: node tools/hero_boss/audio/build.mjs [blade|array|breach|shear|press ...] → tools/hero_boss/audio/out/<技>.wav
// できた音は次の名前で assets_bossmaker/audio/hero_boss/ へ置く（置いた後に --import）:
//   blade → single.wav, array → all.wav, breach → awakening.wav, shear → awakened_single.wav, press → awakened_all.wav, defeat → awakened_defeat.wav
// 素材: 既存のゲームの効果音（assets_bossmaker/audio/*.wav）を切り出し・速さ・重ね方で使い、合成の層（dsp.mjs）を足す。乱数は種つきで、毎回同じ音になる。
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
	SR, db, lerp, smooth, stereo, wavRead, wavWrite, resample, reverse, analyze, slice, fade, gain, envelope, pan as panIt,
	filt, drive, sweepNoise, subDrop, rumble, flame, electric, crackle, metalRing, beam, shatter, drone, rip, reverb, limiter,
} from "./dsp.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ASSET = path.resolve(HERE, "../../../assets_bossmaker/audio");
const OUT = path.join(HERE, "out");
fs.mkdirSync(OUT, { recursive: true });

// ---- 時刻表を読む ----
function readTiming() {
	const src = fs.readFileSync(path.resolve(HERE, "../../../src/bossmaker/visuals/hero_boss/rbm_hero_fx_timing.gd"), "utf8");
	const out = {};
	for (const m of src.matchAll(/const (\w+) := (\{[\s\S]*?\n\})/g)) {
		out[m[1]] = JSON.parse(m[2].replace(/,(\s*[}\]])/g, "$1"));
	}
	return out;
}
const T = readTiming();

// ---- 再生の土台 ----
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

// 音量の階層: 主役の命中（-10.5 より大きい指定）と、それ以外の差をここでまとめて決める。
const MAIN_TRIM = -6.5, REST_TRIM = -8.5;
const mixLevel = (lvl) => lvl + (lvl > -10.5 ? MAIN_TRIM : REST_TRIM);

class Track {
	constructor(sec) {
		this.sec = sec;
		this.dry = stereo(sec + 0.05);
		this.wet = stereo(sec + 0.05);
	}
	// lvl は「その音の一番大きい瞬間の音量」。素材ごとの音量差を吸収する。
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
				const v = src[i] * g;
				d[k] += v;
				w[k] += v * send;
			}
		}
		return this;
	}
	// 素材を鳴らす。speed は高さ（1 より小さいと低く長い）。
	sfx(name, at, { speed = 1, rev = false, lp, hp, from, to, fin = 0.001, fout = 0.03, ...rest } = {}) {
		let s = asset(name, speed);
		if (from != null || to != null) s = slice(s, from ?? 0, to);
		if (rev) s = reverse(s);
		if (lp) s = filt(s, "lp", lp, 0.7);
		if (hp) s = filt(s, "hp", hp, 0.7);
		fade(s, fin, fout);
		return this.put(s, at, rest);
	}
	finish(sendGain = 0.4, room = 0.84, damp = 0.5) {
		const wet = reverb(this.wet, { room, damp, wet: sendGain, tail: 0.1 });
		const n = Math.ceil(this.sec * SR);
		const mix = stereo(this.sec);
		for (let c = 0; c < 2; c++) for (let i = 0; i < n; i++) mix[c][i] = this.dry[c][i] + wet[c][i];
		fade(mix, 0.002, 0.09);
		return limiter(mix, db(-1.6));
	}
}

// 曲線の小物
const fall = (u, p = 1.5) => Math.pow(1 - u, p);
const rise = (a = 0, b = 0.85, c = 0.95) => (_, u) => smooth(a, b, u) * (1 - smooth(c, 1, u));
const hitDecay = (p = 1.5, attack = 0.03) => (_, u) => smooth(0, attack, u) * fall(u, p);

// 体の動きの小さな音（重い鎧・踏み込み・着地）
function armor(tr, at, lvl = -27, sp = 1, pan = 0.25) {
	tr.sfx("cover_move", at, { db: lvl, speed: 0.72 * sp, pan, lp: 2600 });
}
function hop(tr, at, lvl = -22, pan = 0) {
	tr.put(sweepNoise({ sec: 0.34, f0: 420, f1: 1700, q: 1, curve: 0.7, seed: Math.floor(at * 1000), env: (_, u) => smooth(0, 0.25, u) * fall(u, 1.5) }), at, { db: lvl, pan });
}
function land(tr, at, lvl = -19, pan = 0.25) {
	tr.sfx("encounter/knight_step", at, { db: lvl, speed: 0.9, align: "peak", pan });
}

// ---- ① 覚醒前・単体 ----
function blade() {
	const t = T.BLADE, C = t.contact, S = t.seam, H = t.tame_hold / 30;
	const tr = new Track(t.duration);
	const chargeLen = t.dash - t.charge;
	armor(tr, 0.4, -27);
	armor(tr, t.tame, -23, 0.9);
	// タメ: 圧が高まり、踏み出す直前に一瞬だけ音が引く
	const tm = t.dash - t.tame - 0.03;
	tr.put(drone({ sec: tm, f0: 150, f1: 310, curve: 1.6, cutoff: (_, u) => lerp(500, 2600, u), env: (_, u) => smooth(0, 0.4, u) * (1 - smooth(0.92, 1, u)) }), t.tame, { db: -18, pan: 0.2, send: 0.1 });
	tr.put(sweepNoise({ sec: tm, f0: 1200, f1: 5200, q: 5, curve: 1.8, seed: 9, env: (_, u) => Math.pow(u, 1.3) * (1 - smooth(0.92, 1, u)) }), t.tame, { db: -21, pan: 0.2, send: 0.25 });
	tr.put(metalRing({ sec: 0.5, base: 1500, decay: 8, seed: 23 }), t.tame + 0.02, { db: -26, pan: 0.2, send: 0.3 });
	// 青い炎が立ち上がり、光が胸へ集まる
	tr.put(flame({ sec: chargeLen, f: 760, q: 0.6, seed: 11, env: rise(0, 0.6, 0.92) }), t.charge, { db: -23, pan: 0.25, send: 0.12 });
	tr.put(drone({ sec: chargeLen, f0: 118, f1: 262, curve: 1.3, cutoff: (_, u) => lerp(300, 1500, u), env: rise(0, 0.75, 0.94) }), t.charge, { db: -24, pan: 0.2 });
	tr.put(sweepNoise({ sec: 0.82, f0: 1500, f1: 6800, q: 4, curve: 1.6, seed: 5, env: rise(0, 0.82, 0.96) }), t.charge + 0.02, { db: -29, pan: 0.25, send: 0.2 });
	tr.put(crackle({ sec: chargeLen, density: 20, seed: 7, env: rise(0, 0.5, 0.9) }), t.charge + 0.1, { db: -30, pan: 0.2 });
	// 抜刀の閃き
	tr.sfx("samurai_iai_draw", t.draw, { db: -13, speed: 0.85, send: 0.2, align: "peak", pan: 0.25 });
	tr.put(metalRing({ sec: 0.75, base: 2100, decay: 7, seed: 21 }), t.draw, { db: -19, send: 0.35, pan: 0.25 });
	// 突進
	tr.put(sweepNoise({ sec: 0.32, f0: 480, f1: 3600, q: 1.1, curve: 0.7, seed: 31, env: (_, u) => smooth(0, 0.25, u) * fall(u, 1.5) }), t.dash - 0.02, { db: -13, pan: 0.05, send: 0.15 });
	tr.sfx("wind_move", t.dash + 0.03, { db: -19, speed: 0.9, pan: -0.1 });
	// 命中の大斬撃
	tr.sfx("encounter/musha_slash", C, { db: -9, align: "peak", speed: 1.05, send: 0.22, pan: -0.2 });
	tr.sfx("neutral_impact_heavy", C, { db: -11, speed: 0.8, pan: -0.25 });
	tr.put(subDrop({ sec: 0.7, f0: 120, f1: 48, decay: 6, seed: 37 }), C, { db: -11 });
	tr.put(shatter({ sec: 0.55, count: 42, seed: 41, f0: 3500, f1: 10000 }), C + 0.01, { db: -25, pan: -0.25 });
	// 切断面がじりじり光る
	tr.put(sweepNoise({ sec: S - C + 0.04, f0: 3400, f1: 5400, q: 2.4, seed: 44, env: (_, u) => smooth(0, 0.25, u) * (1 - smooth(0.9, 1, u)) }), C + 0.04, { db: -24, pan: -0.2 });
	tr.put(electric({ sec: S - C, density: 80, seed: 45 }), C + 0.05, { db: -29, pan: -0.25 });
	// 二段目の爆光
	tr.put(sweepNoise({ sec: 0.16, f0: 1200, f1: 5200, q: 0.9, seed: 52, env: (_, u) => smooth(0, 0.3, u) * fall(u, 0.6) }), S - 0.07, { db: -15, pan: -0.2 });
	tr.sfx("encounter/musha_slash", S, { db: -11, align: "peak", speed: 0.86, send: 0.25, pan: 0.1 });
	tr.sfx("fire_burst", S, { db: -8, speed: 0.68, send: 0.35, pan: -0.15 });
	tr.sfx("hammer_burst_second", S, { db: -12, speed: 0.78, pan: -0.2 });
	tr.put(subDrop({ sec: 1.2, f0: 110, f1: 32, decay: 3.8, seed: 57 }), S, { db: -9 });
	tr.put(shatter({ sec: 0.9, count: 55, seed: 58, f0: 2400, f1: 8800 }), S + 0.03, { db: -23, pan: -0.2, send: 0.2 });
	// 余韻: 爆炎・地鳴り・火の粉・破片
	tr.put(flame({ sec: 1.25, f: 520, q: 0.55, seed: 60, env: hitDecay(1.7) }), S + 0.08, { db: -19, pan: -0.15, send: 0.2 });
	tr.put(rumble({ sec: 1.45, cutoff: 95, seed: 61, env: hitDecay(2) }), S + 0.04, { db: -18 });
	tr.put(crackle({ sec: 1.4, density: 28, seed: 63, env: (_, u) => fall(u, 1.2) }), S + 0.2, { db: -27, pan: -0.2 });
	tr.sfx("encounter/golem_pebbles", S + 0.32, { db: -24, pan: -0.25 });
	// 跳んで戻る
	hop(tr, 2.27 + H, -19, -0.05);
	land(tr, 2.73 + H, -18);
	armor(tr, 2.93 + H, -28);
	armor(tr, 3.17 + H, -29);
	return tr;
}

// ---- ② 覚醒前・全体 ----
function array() {
	const t = T.ARRAY, F = t.fire, E = t.final, CT = t.cut, D = t.duration, H = t.tame_hold / 30;
	const tr = new Track(D);
	armor(tr, 0.47, -27);
	armor(tr, 0.87, -26, 1.08);
	// 両手を前へ突き出す
	armor(tr, t.palms, -20, 0.9);
	tr.put(sweepNoise({ sec: 0.26, f0: 500, f1: 2400, q: 1.2, curve: 0.7, seed: 69, env: (_, u) => smooth(0, 0.3, u) * fall(u, 1.4) }), t.palms - 0.06, { db: -20, pan: 0.15 });
	tr.put(subDrop({ sec: 0.5, f0: 110, f1: 52, decay: 7, seed: 70 }), t.palms, { db: -13 });
	// 長い溜め: 炎と低いうなりが、三段階で高くなっていく
	const chg = F - t.charge - 0.04;
	const end = 0.985;
	tr.put(flame({ sec: chg, f: 820, q: 0.6, seed: 71, env: (_, u) => (0.25 + 0.75 * Math.pow(u, 1.2)) * smooth(0, 0.08, u) * (1 - smooth(end, 1, u)) }), t.charge, { db: -21, pan: 0.25, send: 0.1 });
	tr.put(drone({ sec: chg, f0: 68, f1: 430, curve: 1.7, cutoff: (_, u) => lerp(280, 3800, u * u), env: (_, u) => (0.35 + 0.65 * u) * smooth(0, 0.1, u) * (1 - smooth(end, 1, u)) }), t.charge, { db: -17, pan: 0.18 });
	tr.put(drone({ sec: F - t.stage2 - 0.04, f0: 130, f1: 860, curve: 1.9, cutoff: (_, u) => lerp(600, 6000, u), wob: 0.008, env: (_, u) => Math.pow(u, 1.1) * (1 - smooth(end, 1, u)) }), t.stage2, { db: -19, pan: 0.15, send: 0.12 });
	tr.put(sweepNoise({ sec: chg, f0: 900, f1: 7200, q: 4, curve: 1.8, seed: 73, env: (_, u) => Math.pow(u, 1.4) * (1 - smooth(0.95, 1, u)) }), t.charge, { db: -21, pan: 0.2, send: 0.2 });
	tr.sfx("lightning_cast", t.charge + 0.3, { db: -24, speed: 0.8, pan: 0.25, send: 0.2 });
	// 大地が応える: 地鳴りが育ち、岩が持ち上がる
	tr.put(rumble({ sec: F - t.stage2 - 0.04, cutoff: 88, seed: 75, env: (_, u) => Math.pow(u, 0.9) * (1 - smooth(end, 1, u)) }), t.stage2, { db: -16 });
	tr.sfx("encounter/golem_windup", t.stage2, { db: -21, speed: 0.75, pan: 0.2 });
	tr.sfx("encounter/golem_crack", t.stage2 + 0.3, { db: -21, speed: 0.72, pan: 0.15, align: "peak" });
	tr.sfx("encounter/golem_pebbles", t.stage2 + 0.7, { db: -24, pan: 0.2 });
	// 放電が増える
	tr.put(electric({ sec: F - t.stage2 - 0.08, density: 170, seed: 77, env: (_, u) => 0.15 + 0.85 * Math.pow(u, 1.5) }), t.stage2 + 0.04, { db: -20, pan: 0.15, send: 0.12 });
	// 集まる光: 両手を出してからの上昇
	const hold = t.pinch - t.palms;
	tr.put(sweepNoise({ sec: hold, f0: 500, f1: 3400, q: 1.1, curve: 1.6, seed: 79, env: (_, u) => smooth(0, 0.2, u) * (1 - smooth(0.93, 1, u)) }), t.palms, { db: -17, pan: 0.1, send: 0.15 });
	// 発射の直前: 空気を吸い込み、一瞬すべて途切れる
	const pn = F - t.pinch - 0.03;
	tr.put(sweepNoise({ sec: pn, f0: 6400, f1: 340, q: 1.0, curve: 0.6, seed: 81, env: (_, u) => smooth(0, 0.3, u) * (1 - smooth(0.9, 1, u)) }), t.pinch, { db: -12, pan: 0.1 });
	// 発射
	tr.sfx("encounter/dragon_detonation", F, { db: -9, align: "peak", speed: 1.1, send: 0.3, pan: -0.1 });
	tr.put(subDrop({ sec: 0.9, f0: 130, f1: 40, decay: 4, seed: 83 }), F, { db: -8 });
	tr.put(beam({ sec: 0.42, f0: 4200, f1: 520, seed: 84 }), F - 0.02, { db: -10, send: 0.3, pan: -0.15 });
	// ビームの持続音（太い噴射）
	const bl = CT - F + 0.16;
	const sustain = (_, u) => smooth(0, 0.04, u) * (1 - smooth(0.86, 1, u));
	tr.put(flame({ sec: bl, f: 1400, q: 0.45, seed: 85, env: sustain, flutter: 0.35 }), F + 0.02, { db: -15, pan: -0.12, send: 0.18 });
	tr.put(drone({ sec: bl, f0: 165, f1: 148, voices: [1, 1.006, 0.5, 2.01, 1.498], cutoff: 3400, wob: 0.006, env: sustain }), F, { db: -18, pan: -0.1, send: 0.2 });
	tr.put(sweepNoise({ sec: bl, f0: 5400, f1: 5000, q: 3, seed: 87, env: sustain }), F, { db: -21, pan: -0.15, send: 0.2 });
	tr.put(electric({ sec: bl, density: 90, seed: 88, env: sustain }), F, { db: -25, pan: -0.15 });
	// ビームが四人を焼く
	const hitPan = [-0.55, -0.32, -0.55, -0.32];
	t.pulses.forEach((at, j) => {
		tr.sfx("lightning_impact_light", at, { db: -13, speed: 0.86 + j * 0.06, pan: hitPan[j], send: 0.2, align: "peak" });
		tr.sfx("fire_impact_heavy", at, { db: -15, speed: 0.82 + j * 0.05, pan: hitPan[j] });
		tr.put(subDrop({ sec: 0.3, f0: 140, f1: 70, decay: 12, seed: 91 + j }), at, { db: -14, pan: hitPan[j] * 0.5 });
		tr.put(shatter({ sec: 0.34, count: 18, seed: 95 + j, f0: 3200, f1: 9000 }), at + 0.01, { db: -27, pan: hitPan[j] });
	});
	// 最大出力への盛り上がり
	tr.put(sweepNoise({ sec: 0.22, f0: 900, f1: 5200, q: 1, curve: 1.6, seed: 99, env: (_, u) => Math.pow(u, 1.2) }), E - 0.22, { db: -15, pan: -0.2 });
	// 全開放: 画面全体の爆炎
	tr.sfx("encounter/dragon_detonation", E, { db: -8, align: "peak", speed: 0.85, send: 0.35, pan: -0.15 });
	tr.sfx("encounter/final_hit", E, { db: -8, align: "peak", speed: 0.9, pan: -0.1 });
	tr.sfx("fire_burst", E, { db: -9, speed: 0.55, send: 0.4, pan: -0.2 });
	tr.put(subDrop({ sec: 1.4, f0: 90, f1: 26, decay: 2.2, seed: 110 }), E, { db: -7 });
	tr.put(shatter({ sec: 0.95, count: 70, seed: 112, f0: 2400, f1: 9000 }), E + 0.01, { db: -19, send: 0.3, pan: -0.1 });
	tr.put(flame({ sec: 1.2, f: 520, q: 0.5, seed: 114, env: hitDecay(1.3, 0.02), flutter: 0.5 }), E + 0.02, { db: -13, pan: -0.1, send: 0.25 });
	// 中心から外へ噴き出す炎
	tr.put(sweepNoise({ sec: 0.7, f0: 1600, f1: 240, q: 0.8, curve: 0.55, seed: 116, env: (_, u) => smooth(0, 0.06, u) * fall(u, 1.3) }), E + 0.02, { db: -13, pan: -0.15, send: 0.3 });
	// 余韻
	tr.put(rumble({ sec: D - E - 0.05, cutoff: 92, seed: 121, env: hitDecay(1.4, 0.015) }), E + 0.03, { db: -14 });
	tr.sfx("encounter/golem_crumble", E + 0.42, { db: -17, speed: 0.92, pan: -0.25 });
	tr.sfx("encounter/golem_crack", E + 0.25, { db: -21, speed: 0.8, pan: -0.3, align: "peak" });
	tr.put(crackle({ sec: D - E - 0.3, density: 34, seed: 125, env: (_, u) => smooth(0, 0.1, u) * fall(u, 1.1) }), E + 0.3, { db: -25 });
	armor(tr, 4.53 + H, -25);
	armor(tr, 4.93 + H, -28, 1.1);
	armor(tr, 5.23 + H, -29);
	return tr;
}

// ---- ③ 覚醒 ----
function breach() {
	const t = T.BREACH, RL = t.release, BO = t.blackout, COL = t.collapse, CP = t.complete, D = t.duration;
	const tr = new Track(D);
	armor(tr, 0.3, -27);
	// 体の青い炎が灯る
	tr.put(drone({ sec: t.runaway - 0.15, f0: 98, f1: 128, cutoff: 520, env: rise(0, 0.7, 0.96) }), 0.2, { db: -27, pan: 0.2 });
	tr.put(flame({ sec: t.runaway - 0.15, f: 720, q: 0.6, seed: 131, env: rise(0, 0.6, 0.96) }), 0.3, { db: -26, pan: 0.2, send: 0.1 });
	// 膝をつく
	tr.sfx("encounter/astro_land", 0.6, { db: -18, speed: 0.84, align: "peak", pan: 0.2 });
	armor(tr, 0.6, -24, 0.9);
	// 異常な明滅（4回）
	t.glitches.forEach((at, i) => {
		const p = [0.12, 0.3, 0.1, 0.25][i];
		tr.put(electric({ sec: 0.27, density: 130, seed: 140 + i, env: (_, u) => fall(u, 1.2) }), at, { db: -15, pan: p, send: 0.15 });
		tr.sfx("encounter/ghost_flicker", at, { db: -19, speed: [1, 0.9, 1.12, 0.95][i], align: "peak", pan: p });
		tr.sfx("lightning_impact_light", at, { db: -17, speed: [0.9, 0.8, 1.05, 0.85][i], pan: p, align: "peak" });
	});
	// 暴走: 青い力が上ずっていく（闇が来るまで）
	const run = t.invade - t.runaway;
	const whole = COL - t.runaway;
	tr.put(drone({ sec: run + 0.18, f0: 150, f1: 470, curve: 1.5, cutoff: (_, u) => lerp(700, 3800, u), wob: 0.012, env: (_, u) => smooth(0, 0.7, u) * (1 - smooth(0.78, 1, u)) }), t.runaway, { db: -15, pan: 0.2, send: 0.12 });
	tr.put(flame({ sec: whole + 0.05, f: 920, q: 0.5, seed: 151, env: (_, u) => smooth(0, 0.3, u) * (1 - 0.88 * smooth(0.33, 0.95, u)), flutter: 0.6 }), t.runaway, { db: -14, pan: 0.2 });
	tr.put(electric({ sec: whole, density: 220, seed: 153, env: (_, u) => (0.3 + 0.7 * Math.min(u / 0.35, 1)) * (1 - 0.75 * smooth(0.35, 1, u)) }), t.runaway, { db: -19, pan: 0.2, send: 0.1 });
	tr.sfx("encounter/golem_crack", t.runaway, { db: -17, speed: 0.78, align: "peak", pan: 0.25 });
	armor(tr, 1.63, -24, 0.85);
	// 足元から黒い炎が這い上がる: 青の高い音が押しつぶされ、低い炎のうなりに置き換わる
	const inv = COL - t.invade;
	tr.put(drone({ sec: inv + 0.16, f0: 300, f1: 86, curve: 0.7, voices: [1, 1.006, 0.5, 1.06], cutoff: (_, u) => lerp(1500, 420, u), env: (_, u) => smooth(0, 0.2, u) * (1 - smooth(0.92, 1, u)) }), t.invade, { db: -14, pan: 0.15, send: 0.1 });
	tr.put(flame({ sec: inv + 0.16, f: 280, q: 0.55, seed: 161, flutter: 0.5, env: (_, u) => (0.4 + 0.6 * u) * smooth(0, 0.12, u) * (1 - smooth(0.92, 1, u)) }), t.invade, { db: -12, pan: 0.15, send: 0.15 });
	tr.put(rumble({ sec: inv + 0.16, cutoff: 80, seed: 163, env: rise(0, 0.8, 0.96) }), t.invade, { db: -15 });
	// 黒い炎が燃え上がる三回の「ボッ」
	t.surges.forEach((at, i) => {
		tr.put(sweepNoise({ sec: 0.34, f0: 420, f1: 120, q: 0.9, curve: 0.5, seed: 170 + i, env: hitDecay(1.6, 0.06) }), at, { db: -16 + i * 1.5, pan: 0.15, send: 0.2 });
		tr.put(subDrop({ sec: 0.4, f0: 96 - i * 8, f1: 46, decay: 8, click: 0.1, seed: 175 + i }), at, { db: -15 + i, pan: 0.1 });
		tr.sfx("fire_burst", at, { db: -21 + i, speed: 0.5, lp: 900, pan: 0.15 });
	});
	// 崩壊: 吸い込まれて全部が消える
	const col = BO - COL;
	tr.put(sweepNoise({ sec: col, f0: 5200, f1: 200, q: 1.2, curve: 0.55, seed: 181, env: (_, u) => smooth(0, 0.15, u) * (1 - smooth(0.92, 1, u)) }), COL, { db: -11, pan: 0.2 });
	tr.put(drone({ sec: col, f0: 540, f1: 60, cutoff: 2400, env: (_, u) => smooth(0, 0.1, u) * (1 - smooth(0.9, 1, u)) }), COL, { db: -14, pan: 0.2 });
	// 暗転: 耳鳴りと一度の鼓動、三つの目
	tr.put(sweepNoise({ sec: RL - BO, f0: 8200, f1: 8200, q: 18, seed: 185, env: (_, u) => smooth(0, 0.2, u) * (1 - smooth(0.9, 1, u)) }), BO, { db: -38 });
	tr.put(subDrop({ sec: 0.22, f0: 74, f1: 42, decay: 13, click: 0.08, seed: 186 }), BO + 0.02, { db: -12 });
	for (let i = 0; i < 3; i++) {
		tr.put(metalRing({ sec: 0.22, base: 2600 + i * 320, partials: [1, 2.3, 3.7], decay: 26, seed: 187 + i }), BO + 0.05 + i * 0.05, { db: -21, pan: 0.2 });
	}
	// 解放: 黒紅の爆発、青い力が砕ける
	tr.sfx("encounter/final_hit", RL, { db: -7, align: "peak", speed: 0.92, send: 0.2, pan: 0.05 });
	tr.sfx("encounter/dragon_detonation", RL, { db: -8, align: "peak", speed: 0.72, send: 0.4, pan: 0.1 });
	tr.put(subDrop({ sec: 2.2, f0: 84, f1: 24, decay: 2, seed: 191 }), RL, { db: -7 });
	tr.put(shatter({ sec: 1.35, count: 170, seed: 192, f0: 2200, f1: 10500 }), RL + 0.01, { db: -15, send: 0.35 });
	tr.sfx("ice_burst", RL, { db: -16, speed: 0.9, send: 0.3, align: "peak" });
	tr.put(flame({ sec: 1.75, f: 420, q: 0.5, seed: 195, env: hitDecay(1.4, 0.02), flutter: 0.5 }), RL + 0.02, { db: -13, pan: 0.05, send: 0.25 });
	tr.put(rumble({ sec: 2.1, cutoff: 90, seed: 197, env: hitDecay(1.3, 0.015) }), RL + 0.03, { db: -14 });
	tr.sfx("encounter/golem_crumble", RL + 0.42, { db: -19, speed: 0.85 });
	tr.put(crackle({ sec: CP - RL - 0.35, density: 30, seed: 199, env: (_, u) => smooth(0, 0.15, u) * fall(u, 0.8) }), RL + 0.4, { db: -27 });
	armor(tr, 3.23, -24, 0.9);
	armor(tr, 4.07, -23, 0.82);
	// 黒い炎の持続
	tr.put(flame({ sec: D - t.settle, f: 340, q: 0.6, seed: 201, env: rise(0, 0.3, 0.9), flutter: 0.35 }), t.settle, { db: -27, pan: 0.2 });
	// 2段階目のタメ: 低いうなりがせり上がり、鼓動が近づいて、直前に一度すべて引く
	const tm = CP - t.tame - 0.1;
	tr.put(drone({ sec: tm, f0: 46, f1: 118, curve: 1.4, voices: [1, 1.006, 0.5, 1.498], cutoff: (_, u) => lerp(200, 1300, u * u), env: (_, u) => smooth(0, 0.3, u) * (1 - smooth(0.93, 1, u)) }), t.tame, { db: -16, pan: 0.15, send: 0.12 });
	tr.put(flame({ sec: tm, f: 300, q: 0.6, seed: 215, flutter: 0.5, env: (_, u) => (0.3 + 0.7 * u) * smooth(0, 0.15, u) * (1 - smooth(0.93, 1, u)) }), t.tame, { db: -19, pan: 0.15, send: 0.15 });
	tr.put(rumble({ sec: tm, cutoff: 84, seed: 216, env: (_, u) => smooth(0, 0.5, u) * (1 - smooth(0.93, 1, u)) }), t.tame, { db: -15 });
	[0.08, 0.46, 0.76].forEach((off, i) => {
		const at = t.tame + off;
		tr.put(subDrop({ sec: 0.24, f0: 72, f1: 42, decay: 13, click: 0.06, seed: 217 + i }), at, { db: -15 + i * 1.5 });
		tr.put(subDrop({ sec: 0.2, f0: 60, f1: 38, decay: 15, click: 0.04, seed: 221 + i }), at + 0.15, { db: -19 + i * 1.5 });
	});
	// 完了: 足を踏みしめ、黒紅の炎が噴き出す（一段目より低く重く）
	tr.put(sweepNoise({ sec: 0.32, f0: 110, f1: 620, q: 1, curve: 2, seed: 203, env: rise(0, 0.9, 0.97) }), CP - 0.33, { db: -17, pan: 0.2 });
	tr.sfx("encounter/knight_plant", CP, { db: -12, speed: 0.72, align: "peak", pan: 0.2, lp: 2400 });
	tr.sfx("encounter/musha_drop_hit", CP, { db: -10, align: "peak", speed: 0.58, send: 0.3, pan: 0.15 });
	tr.sfx("encounter/title_hit", CP, { db: -10, align: "peak", speed: 0.85, pan: 0.1 });
	tr.put(subDrop({ sec: 1.1, f0: 72, f1: 26, decay: 2.8, seed: 205 }), CP, { db: -8 });
	for (let i = 0; i < 3; i++) {
		tr.put(metalRing({ sec: 0.9, base: [300, 395, 520][i], partials: [1, 1.51, 2.27, 2.91], decay: 5, seed: 206 + i }), CP + i * 0.02, { db: -21, pan: [-0.4, 0.4, 0][i], send: 0.4 });
	}
	// 三つの目の光が走る（低く抑える）
	tr.put(sweepNoise({ sec: 0.5, f0: 2200, f1: 1100, q: 4, seed: 212, env: (_, u) => fall(u, 1.5) }), CP, { db: -25, pan: 0.2, send: 0.3 });
	tr.put(rumble({ sec: D - CP, cutoff: 80, seed: 213, env: hitDecay(1.5, 0.02) }), CP + 0.02, { db: -16 });
	return tr;
}

// ---- ④ 覚醒後・単体 ----
function shear() {
	const t = T.SHEAR, C1 = t.cut1, C2 = t.cut2, F = t.final, D = t.duration;
	const tr = new Track(D);
	armor(tr, 0.4, -26, 0.85);
	armor(tr, 0.8, -27, 0.8);
	armor(tr, 1.13, -25, 0.78);
	// 黒い炎と放電の溜め
	const chg = C1 - t.charge - 0.05;
	tr.put(drone({ sec: chg, f0: 62, f1: 104, curve: 1.3, cutoff: (_, u) => lerp(260, 900, u), env: rise(0, 0.7, 0.97) }), t.charge, { db: -19, pan: 0.2 });
	tr.put(flame({ sec: chg, f: 380, q: 0.6, seed: 221, env: rise(0, 0.6, 0.96) }), t.charge, { db: -24, pan: 0.2 });
	tr.put(electric({ sec: chg, density: 90, seed: 223, f: 2300, env: rise(0, 0.5, 0.95) }), t.charge, { db: -22, pan: 0.25, send: 0.12 });
	tr.put(sweepNoise({ sec: chg, f0: 1100, f1: 4300, q: 4, curve: 1.4, seed: 225, env: rise(0, 0.8, 0.97) }), t.charge, { db: -31, pan: 0.2 });
	// 逆刃を抜く
	tr.sfx("neutral_sword_swing", 1.2, { db: -14, speed: 0.72, align: "peak", pan: 0.25, send: 0.2 });
	tr.put(metalRing({ sec: 0.45, base: 1250, decay: 9, seed: 227 }), 1.2, { db: -22, pan: 0.25, send: 0.3 });
	// 闇の突進
	tr.put(sweepNoise({ sec: 0.24, f0: 300, f1: 2300, q: 1.2, curve: 0.65, seed: 229, env: (_, u) => smooth(0, 0.2, u) * fall(u, 1.2) }), t.dash + 0.03, { db: -13, pan: 0.05 });
	// 一撃目・二撃目: 空間が裂ける
	[[C1, 1, -0.3, 231], [C2, 0.86, -0.12, 241]].forEach(([at, sp, p, sd], i) => {
		tr.sfx("encounter/musha_slash", at, { db: -10 + i, align: "peak", speed: 0.96 * sp, send: 0.22, pan: p });
		tr.put(rip({ sec: 0.36, seed: sd, f0: 800 * sp, f1: 2800 * sp }), at - 0.02, { db: -13 - i * 0.5, pan: p, send: 0.2 });
		tr.sfx("boss_impact_mass", at, { db: -12, speed: 0.78 * sp, pan: p, align: "peak" });
		tr.put(subDrop({ sec: 0.55, f0: 120, f1: 42, decay: 7, seed: sd + 3 }), at, { db: -12 });
		tr.put(shatter({ sec: 0.45, count: 26, seed: sd + 5, f0: 1800, f1: 6400 }), at + 0.02, { db: -26, pan: p });
		// 斬った所から黒い炎が噴き出す
		tr.put(sweepNoise({ sec: 0.42, f0: 900, f1: 180, q: 0.8, curve: 0.55, seed: sd + 7, env: hitDecay(1.4, 0.05) }), at + 0.01, { db: -15, pan: p, send: 0.25 });
		tr.sfx("fire_burst", at, { db: -18, speed: 0.55, lp: 1400, pan: p });
	});
	// 裂け目がくすぶる
	tr.put(electric({ sec: F - C1 - 0.1, density: 60, seed: 251, f: 1800 }), C1 + 0.1, { db: -28, pan: -0.25 });
	// ×字が闇を吸い込む
	const pull = F - C2 - 0.08;
	tr.put(sweepNoise({ sec: pull, f0: 240, f1: 5800, q: 0.9, curve: 1.9, seed: 253, env: (_, u) => Math.pow(u, 1.2) * (1 - smooth(0.965, 1, u)) }), C2 + 0.08, { db: -13, pan: -0.25 });
	tr.put(drone({ sec: pull, f0: 86, f1: 640, curve: 2.1, cutoff: (_, u) => lerp(500, 4600, u), env: (_, u) => Math.pow(u, 1.1) * (1 - smooth(0.965, 1, u)) }), C2 + 0.08, { db: -15, pan: -0.2 });
	// 断裁: ×字が爆ぜて四方へ走る
	tr.sfx("hammer_impact", F, { db: -8, speed: 0.68, pan: -0.15, send: 0.2 });
	tr.sfx("encounter/musha_break", F, { db: -9, align: "peak", speed: 0.88, send: 0.35, pan: -0.15 });
	tr.sfx("encounter/final_hit", F, { db: -9, align: "peak", speed: 1.05, pan: -0.1 });
	tr.put(rip({ sec: 0.5, seed: 261, f0: 620, f1: 2100 }), F, { db: -13, send: 0.25, pan: -0.15 });
	tr.put(subDrop({ sec: 1.5, f0: 92, f1: 26, decay: 2.7, seed: 263 }), F, { db: -7 });
	tr.put(shatter({ sec: 0.95, count: 62, seed: 265, f0: 1700, f1: 7600 }), F + 0.02, { db: -19, send: 0.3, pan: -0.15 });
	// ×字に沿って噴き出す炎と、遅れて地面から噴き上がる余波
	tr.put(sweepNoise({ sec: 0.8, f0: 1400, f1: 200, q: 0.8, curve: 0.55, seed: 273, env: (_, u) => smooth(0, 0.06, u) * fall(u, 1.3) }), F + 0.02, { db: -12, pan: -0.15, send: 0.3 });
	tr.sfx("fire_burst", F, { db: -10, speed: 0.5, send: 0.35, lp: 2200, pan: -0.15 });
	tr.put(subDrop({ sec: 0.5, f0: 80, f1: 34, decay: 6, seed: 275 }), F + 0.12, { db: -14 });
	tr.put(sweepNoise({ sec: 0.6, f0: 300, f1: 1500, q: 0.9, curve: 0.8, seed: 276, env: hitDecay(1.5, 0.08) }), F + 0.12, { db: -18, pan: -0.15, send: 0.2 });
	// 余韻
	tr.put(flame({ sec: 1.05, f: 360, q: 0.55, seed: 267, env: hitDecay(1.6, 0.02) }), F + 0.03, { db: -15, pan: -0.15, send: 0.2 });
	tr.put(rumble({ sec: 1.6, cutoff: 84, seed: 269, env: hitDecay(1.6, 0.02) }), F + 0.03, { db: -15 });
	tr.sfx("encounter/golem_crack", F + 0.14, { db: -18, speed: 0.82, align: "peak", pan: -0.3 });
	tr.sfx("encounter/golem_pebbles", F + 0.34, { db: -22, speed: 0.9, pan: -0.25 });
	tr.put(crackle({ sec: 1.3, density: 28, seed: 271, env: (_, u) => smooth(0, 0.1, u) * fall(u, 1.2) }), F + 0.3, { db: -27, pan: -0.15 });
	// 低く構えたまま残す
	armor(tr, 2.53, -23, 0.78);
	tr.sfx("encounter/knight_step", 2.53, { db: -21, speed: 0.85, align: "peak", pan: -0.1 });
	// 跳んで戻る
	hop(tr, 3.0, -19, 0.0);
	land(tr, 3.43, -17);
	armor(tr, 3.63, -27, 0.85);
	armor(tr, 3.87, -29, 0.85);
	return tr;
}

// ---- ⑤ 覚醒後・全体（断罪） ----
// 左右へ動かす（右上から左下へ走る音に使う）
function sway(s, p0, p1) {
	const n = s[0].length;
	for (let i = 0; i < n; i++) {
		const a = (lerp(p0, p1, i / n) + 1) * 0.25 * Math.PI;
		s[0][i] *= Math.cos(a) * Math.SQRT2;
		s[1][i] *= Math.sin(a) * Math.SQRT2;
	}
	return s;
}

function press() {
	const t = T.PRESS, ST = t.strike, DR = t.drop, RU = t.rupture, CL = t.close, D = t.duration;
	const tr = new Track(D);
	armor(tr, 0.43, -26, 0.85);
	// 三つの目が灯る
	for (let i = 0; i < 3; i++) {
		const at = t.dock + 0.12 + i * 0.13;
		tr.put(subDrop({ sec: 0.34, f0: 88 - i * 6, f1: 44, decay: 10, click: 0.04, seed: 301 + i }), at, { db: -15 + i, pan: 0.2 });
		tr.put(electric({ sec: 0.2, density: 110, seed: 304 + i, f: 2300, env: (_, u) => fall(u, 1.3) }), at, { db: -21, pan: 0.25, send: 0.15 });
	}
	// 溜めの土台: 黒い炎と放電が、振り下ろしまで強くなり続ける
	const base = ST - t.dock;
	const swell = (_, u) => (0.35 + 0.65 * u) * smooth(0, 0.1, u) * (1 - smooth(0.98, 1, u));
	tr.put(drone({ sec: base, f0: 52, f1: 96, curve: 1.3, cutoff: (_, u) => lerp(240, 1000, u), env: swell }), t.dock, { db: -16, pan: 0.15 });
	tr.put(flame({ sec: base, f: 360, q: 0.6, seed: 307, flutter: 0.45, env: swell }), t.dock, { db: -18, pan: 0.2, send: 0.12 });
	tr.put(electric({ sec: base, density: 80, seed: 308, f: 2300, env: swell }), t.dock, { db: -24, pan: 0.25, send: 0.12 });
	armor(tr, t.edge, -21, 0.82);
	// 炎の刃が伸びる
	tr.sfx("fire_burst", t.edge, { db: -14, speed: 0.6, pan: 0.3, send: 0.25 });
	tr.put(sweepNoise({ sec: 0.7, f0: 180, f1: 1100, q: 0.8, curve: 0.8, seed: 311, env: (_, u) => smooth(0, 0.25, u) * fall(u, 1.1) }), t.edge, { db: -15, pan: 0.3, send: 0.2 });
	const eg = t.edge_off - t.edge;
	tr.put(flame({ sec: eg, f: 620, q: 0.5, seed: 312, flutter: 0.5, env: (_, u) => smooth(0, 0.3, u) * (1 - smooth(0.9, 1, u)) }), t.edge, { db: -17, pan: 0.3, send: 0.1 });
	// 断罪の線: 一本ごとに鋭く打ち込む
	const sp = [-0.55, -0.3, -0.55, -0.3];
	t.sentence.forEach((at, i) => {
		tr.put(rip({ sec: 0.2, seed: 321 + i, f0: 900, f1: 2400 }), at - 0.02, { db: -15, pan: sp[i], send: 0.25 });
		tr.sfx("boss_impact_mass", at + 0.03, { db: -12 + i * 0.4, speed: 0.85 - i * 0.03, pan: sp[i], align: "peak" });
		tr.put(subDrop({ sec: 0.45, f0: 110, f1: 46, decay: 7, click: 0.12, seed: 331 + i }), at + 0.03, { db: -12 + i * 0.4, pan: sp[i] * 0.4 });
		tr.put(metalRing({ sec: 0.9, base: 150 - i * 8, partials: [1, 2.0, 2.4, 3.0], decay: 3.2, seed: 341 + i }), at + 0.03, { db: -19, pan: sp[i] * 0.6, send: 0.5 });
	});
	// 跳ぶ
	armor(tr, 1.8, -21, 0.8);
	hop(tr, t.leap - 0.02, -13, 0.2);
	tr.sfx("fire_swing", t.leap, { db: -16, speed: 0.7, pan: 0.2, send: 0.2 });
	// 空中で力が刃に集まる: 振り下ろしの直前に頂点へ（直前で一瞬途切れる）
	const pullAt = 2.35;
	const pull = ST - pullAt - 0.02;
	const up = (_, u) => Math.pow(u, 1.2) * (1 - smooth(0.965, 1, u));
	tr.put(sweepNoise({ sec: pull, f0: 240, f1: 5800, q: 0.9, curve: 1.9, seed: 351, env: up }), pullAt, { db: -11, pan: 0.2, send: 0.15 });
	tr.put(drone({ sec: pull, f0: 86, f1: 640, curve: 2.1, cutoff: (_, u) => lerp(500, 4600, u), env: up }), pullAt, { db: -13, pan: 0.2 });
	// 切れた瞬間（振り下ろしのコマ）: 鋭い斬撃と、世界が裂ける音
	tr.sfx("encounter/musha_slash", ST, { db: -8, align: "peak", speed: 0.82, send: 0.3, pan: -0.2 });
	tr.sfx("encounter/knight_swing", ST, { db: -12, align: "peak", speed: 0.85, pan: 0.1, send: 0.2 });
	tr.put(sway(rip({ sec: 0.5, seed: 363, f0: 620, f1: 2300 }), 0.3, -0.6), ST, { db: -11, send: 0.25 });
	// 刃が地面に着いた所: 重い一撃
	tr.sfx("hammer_impact", DR, { db: -8, speed: 0.64, pan: -0.15, send: 0.2 });
	tr.sfx("encounter/musha_break", DR, { db: -10.4, align: "peak", speed: 0.88, send: 0.35, pan: -0.2 });
	tr.sfx("encounter/final_hit", DR, { db: -10.4, align: "peak", speed: 0.95, pan: -0.1 });
	tr.put(subDrop({ sec: 1.4, f0: 92, f1: 26, decay: 2.7, seed: 365 }), DR, { db: -8 });
	tr.put(shatter({ sec: 0.9, count: 70, seed: 366, f0: 1700, f1: 7600 }), DR + 0.02, { db: -17, send: 0.3, pan: -0.2 });
	tr.put(flame({ sec: 0.9, f: 420, q: 0.55, seed: 367, env: hitDecay(1.6, 0.02) }), DR + 0.03, { db: -15, pan: -0.2, send: 0.2 });
	// 四人に当たる
	t.hits.forEach((at, i) => {
		const p = [-0.3, -0.55, -0.3, -0.55][i];
		tr.sfx("boss_impact_mass", at + (i === 0 ? 0.05 : 0), { db: -12, speed: 0.82 + i * 0.05, pan: p, align: "peak" });
		tr.put(subDrop({ sec: 0.4, f0: 110, f1: 44, decay: 8, seed: 371 + i }), at, { db: -14, pan: p * 0.4 });
	});
	// 大地が裂ける
	tr.sfx("encounter/golem_crack", DR + 0.08, { db: -14, speed: 0.75, align: "peak", pan: -0.2, send: 0.2 });
	tr.put(rumble({ sec: RU - DR + 0.18, cutoff: 96, seed: 376, env: hitDecay(0.5, 0.02) }), DR + 0.02, { db: -13 });
	// 切れたままの間の、低いうなりと裂け目を抜ける風
	const op = CL - DR;
	const hold = (_, u) => smooth(0, 0.1, u) * (1 - smooth(0.86, 0.985, u));
	tr.put(drone({ sec: op, f0: 76, f1: 62, cutoff: 620, env: hold }), DR + 0.02, { db: -17 });
	tr.put(sweepNoise({ sec: op, f0: 2100, f1: 1400, q: 6, seed: 378, env: hold }), DR + 0.02, { db: -23, send: 0.35 });
	// 亀裂に沿って黒い炎の柱が噴き上がる
	t.jets.forEach(([x, d], i) => {
		const at = DR + d;
		const p = Math.max(-0.9, Math.min(0.9, (x - 320) / 380));
		tr.sfx("fire_burst", at, { db: -15 - i * 0.4, speed: 0.55 + (i % 3) * 0.05, pan: p, lp: 2600 });
		tr.put(sweepNoise({ sec: 0.38, f0: 200, f1: 1300, q: 0.8, curve: 0.6, seed: 381 + i, env: (_, u) => smooth(0, 0.12, u) * fall(u, 1.5) }), at - 0.02, { db: -18 - i * 0.4, pan: p, send: 0.2 });
		if (i % 2 === 0) tr.put(subDrop({ sec: 0.3, f0: 90, f1: 44, decay: 9, seed: 391 + i }), at, { db: -17, pan: p * 0.5 });
	});
	tr.put(flame({ sec: 0.9, f: 340, q: 0.55, seed: 399, flutter: 0.5, env: (_, u) => smooth(0, 0.2, u) * fall(u, 1.2) }), DR + 0.36, { db: -15, send: 0.2 });
	tr.sfx("encounter/golem_crumble", DR + 0.4, { db: -17, speed: 0.9, pan: -0.1 });
	// 破断: 全部が砕け、黒紅の炎が噴き出す
	tr.sfx("hammer_burst", RU, { db: -8, speed: 0.61, pan: -0.1, send: 0.25 });
	tr.sfx("encounter/musha_break", RU, { db: -9, align: "peak", speed: 0.78, send: 0.4, pan: 0.05 });
	tr.sfx("encounter/final_hit", RU, { db: -10.4, align: "peak", speed: 0.86 });
	tr.sfx("encounter/dragon_detonation", RU, { db: -10.4, align: "peak", speed: 0.72, send: 0.4, pan: -0.05 });
	tr.sfx("fire_burst", RU, { db: -12, speed: 0.5, send: 0.35, pan: -0.15 });
	tr.put(subDrop({ sec: 1.6, f0: 84, f1: 24, decay: 2.4, seed: 401 }), RU, { db: -8 });
	tr.put(shatter({ sec: 1.2, count: 130, seed: 403, f0: 1500, f1: 7600 }), RU + 0.01, { db: -15, send: 0.35 });
	tr.put(flame({ sec: 1.3, f: 400, q: 0.5, seed: 405, env: hitDecay(1.2, 0.02), flutter: 0.5 }), RU + 0.02, { db: -13, send: 0.25 });
	tr.put(sweepNoise({ sec: 0.8, f0: 1500, f1: 200, q: 0.8, curve: 0.55, seed: 406, env: (_, u) => smooth(0, 0.06, u) * fall(u, 1.3) }), RU + 0.02, { db: -12, send: 0.3 });
	// 閉じる: 切れた画面が叩き戻される
	tr.put(sweepNoise({ sec: 0.14, f0: 300, f1: 2400, q: 1, curve: 1.6, seed: 411, env: (_, u) => Math.pow(u, 1.4) }), CL - 0.15, { db: -13 });
	tr.sfx("hammer_impact", CL, { db: -10.4, speed: 0.72, send: 0.25 });
	tr.sfx("encounter/title_hit", CL, { db: -9, align: "peak", speed: 1.0, send: 0.3 });
	tr.sfx("encounter/musha_slash", CL, { db: -11, align: "peak", speed: 0.9, send: 0.3 });
	tr.put(subDrop({ sec: 0.9, f0: 78, f1: 28, decay: 4, seed: 413 }), CL, { db: -9 });
	tr.put(shatter({ sec: 0.6, count: 40, seed: 414, f0: 1500, f1: 6400 }), CL + 0.01, { db: -21, send: 0.3 });
	// 余韻
	tr.put(rumble({ sec: D - CL, cutoff: 90, seed: 417, env: hitDecay(1.5, 0.02) }), CL + 0.03, { db: -14 });
	tr.sfx("encounter/golem_crumble", CL + 0.1, { db: -19, speed: 0.92, pan: -0.15 });
	tr.sfx("encounter/golem_pebbles", CL + 0.62, { db: -23, pan: 0.1 });
	tr.put(crackle({ sec: D - RU - 0.5, density: 34, seed: 419, env: (_, u) => smooth(0, 0.1, u) * fall(u, 1.0) }), RU + 0.4, { db: -24 });
	armor(tr, 3.87, -23, 0.85);
	armor(tr, 4.83, -21, 0.82);
	hop(tr, 5.42, -18, 0.1);
	land(tr, 5.87, -15);
	armor(tr, 6.13, -26, 0.85);
	return tr;
}

// 覚醒後の撃破（2026-11-11）。撃破の演出（RBMVictoryPlayer の begin から）の時刻。とどめの音（enc:final_hit）は共通で先に鳴る。
function defeatScene() {
	const t = T.FALL, BU = t.burst, RE = t.restore, FA = t.fade, GO = t.gone, D = t.duration;
	const tr = new Track(D);
	// 闇が暴れる: 低い炎のうなりが鼓動のたびにせり上がる
	tr.put(flame({ sec: BU + 0.05, f: 300, q: 0.6, seed: 401, flutter: 0.5, env: (_, u) => (0.35 + 0.65 * u) * smooth(0, 0.12, u) * (1 - smooth(0.95, 1, u)) }), 0, { db: -17, pan: 0.15, send: 0.15 });
	tr.put(drone({ sec: BU, f0: 44, f1: 104, curve: 1.4, voices: [1, 1.006, 0.5, 1.498], cutoff: (_, u) => lerp(200, 1200, u * u), env: (_, u) => smooth(0, 0.25, u) * (1 - smooth(0.94, 1, u)) }), 0.05, { db: -17, pan: 0.15, send: 0.12 });
	tr.put(rumble({ sec: BU, cutoff: 84, seed: 403, env: (_, u) => smooth(0, 0.5, u) * (1 - smooth(0.94, 1, u)) }), 0, { db: -16 });
	// 膝をつく
	tr.sfx("encounter/astro_land", t.kneel, { db: -17, speed: 0.84, align: "peak", pan: 0.2 });
	armor(tr, t.kneel, -23, 0.9);
	// 鼓動3回（だんだん強く）と、内から漏れる青い光のはぜる音
	t.beats.forEach((at, i) => {
		tr.put(subDrop({ sec: 0.24, f0: 72, f1: 42, decay: 13, click: 0.06, seed: 405 + i }), at, { db: -15 + i * 1.5 });
		tr.put(subDrop({ sec: 0.2, f0: 60, f1: 38, decay: 15, click: 0.04, seed: 409 + i }), at + 0.13, { db: -19 + i * 1.5 });
		tr.put(electric({ sec: 0.18, density: 120, seed: 413 + i, env: (_, u) => fall(u, 1.3) }), at + 0.02, { db: -23 + i, pan: 0.2, send: 0.15 });
	});
	// 爆発の直前: 吸い込むようにせり上がる
	tr.put(sweepNoise({ sec: 0.3, f0: 110, f1: 620, q: 1, curve: 2, seed: 417, env: rise(0, 0.9, 0.97) }), BU - 0.31, { db: -17, pan: 0.15 });
	// 闇が爆ぜる: 低く重い炸裂と、鋭い立ち上がり。闇の破片が砕け、青い光が噴き上がる
	tr.sfx("encounter/dragon_detonation", BU, { db: -8, align: "peak", speed: 0.72, send: 0.4, pan: 0.1 });
	tr.sfx("encounter/musha_drop_hit", BU, { db: -11, align: "peak", speed: 0.58, send: 0.3, pan: 0.1 });
	tr.sfx("encounter/title_hit", BU, { db: -11, align: "peak", speed: 0.85, pan: 0.05 });
	tr.put(subDrop({ sec: 1.6, f0: 80, f1: 24, decay: 2.4, seed: 421 }), BU, { db: -7 });
	tr.put(flame({ sec: 1.5, f: 420, q: 0.5, seed: 423, env: hitDecay(1.4, 0.02), flutter: 0.5 }), BU + 0.02, { db: -14, pan: 0.05, send: 0.25 });
	tr.put(rumble({ sec: 1.8, cutoff: 90, seed: 425, env: hitDecay(1.3, 0.015) }), BU + 0.03, { db: -14 });
	tr.put(shatter({ sec: 1.0, count: 110, seed: 427, f0: 1800, f1: 7000 }), BU + 0.01, { db: -19, send: 0.35 });
	tr.sfx("ice_burst", BU + 0.02, { db: -17, speed: 0.8, send: 0.35, align: "peak" });
	// 元の姿に戻る: やわらかい光の和音がふくらむ
	tr.put(drone({ sec: GO - RE + 0.1, f0: 196, f1: 220, curve: 1, voices: [1, 1.5, 2, 1.26], cutoff: (_, u) => lerp(900, 2400, u), env: (_, u) => smooth(0, 0.35, u) * (1 - smooth(0.7, 1, u)) }), RE, { db: -24, pan: 0.15, send: 0.5 });
	tr.sfx("heal_hp", RE + 0.04, { db: -20, speed: 0.8, send: 0.4, pan: 0.15 });
	// 光の粒になって昇る
	tr.sfx("encounter/sparkle", FA + 0.05, { db: -20, speed: 0.9, send: 0.4, pan: 0.15 });
	tr.sfx("encounter/sparkle", FA + 0.45, { db: -22, speed: 1.08, send: 0.4, pan: 0.25 });
	tr.put(sweepNoise({ sec: GO - FA + 0.1, f0: 900, f1: 3000, q: 3, curve: 1, seed: 431, env: (_, u) => smooth(0, 0.3, u) * (1 - smooth(0.6, 1, u)) }), FA, { db: -30, pan: 0.15, send: 0.4 });
	return tr;
}

const scenes = { blade, array, breach, shear, press, defeat: defeatScene };
const only = process.argv.slice(2);
for (const [name, fn] of Object.entries(scenes)) {
	if (only.length && !only.includes(name)) continue;
	const tr = fn();
	const { out, reducedSec } = tr.finish();
	wavWrite(path.join(OUT, name + ".wav"), out);
	console.log(`${name}: ${dur2(out)}秒, リミッターが働いた時間=${reducedSec.toFixed(2)}秒`);
}
function dur2(s) { return (s[0].length / SR).toFixed(2); }
