// 金環の聖獣／日蝕の獅皇（lion）の5技の効果音（2026-11-12 ユーザーが確認動画で採用した音。試作 prototypes/four_bosses_2026-11-11/audio から移した）。
// 時刻は timing.json（tools/lion/dump_lion_timing.gd が本番のエフェクトの T・ヒットストップから書き出す）。
// 使い方: godot --headless --path . --script res://tools/lion/dump_lion_timing.gd → node tools/lion/audio/build.mjs → tools/lion/audio/out/<技>.wav
// できた音は次の名前で assets_bossmaker/audio/lion/ へ置く（置いた後に --import）:
//   pre_single → single.wav, pre_all → all.wav, awaken → awakening.wav, post_single → awakened_single.wav, post_all → awakened_all.wav
//   （2026-11-13 追加）intro → intro.wav（登場）, fall → defeat.wav（撃破）, fall_awakened → defeat_awakened.wav（覚醒後の撃破）, pre_support_heal → heal.wav, pre_support_buff → buff.wav,
//   post_support_heal → awakened_heal.wav, post_support_buff → awakened_buff.wav（支援。時刻は timing.json の support）
// 素材: 既存のゲームの効果音（assets_bossmaker/audio）を切り出し・速さ・重ね方で使い、合成の層（tools/hero_boss/audio/dsp.mjs を読むだけ）を足す。
// 数より質: 溜め・一撃・余韻の要所だけに絞る。音は演出の中の時刻で書き、ヒットストップの分は at() で実時間へ直す。
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
	SR, db, smooth, lerp, stereo, wavRead, wavWrite, resample, reverse, analyze, slice, fade, pan as panIt,
	filt, sweepNoise, subDrop, rumble, flame, electric, crackle, metalRing, beam, shatter, drone, rip, reverb, limiter,
} from "../../hero_boss/audio/dsp.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ASSET = path.resolve(HERE, "../../../assets_bossmaker/audio");
const TIMING = JSON.parse(fs.readFileSync(path.join(HERE, "timing.json"), "utf8"));

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

const MAIN_TRIM = -6.5, REST_TRIM = -8.5;
const mixLevel = (lvl) => lvl + (lvl > -10.5 ? MAIN_TRIM : REST_TRIM);

class Track {
	constructor(info) {
		this.info = info;
		this.sec = info.real_duration + 0.4;
		this.dry = stereo(this.sec + 0.05);
		this.wet = stereo(this.sec + 0.05);
	}
	// 演出の中の時刻 → 実時間（その時刻に始まるヒットストップの前）
	at(te) {
		let shift = 0;
		for (const s of this.info.stops) if (te > s[0] + 0.0001) shift += s[1];
		return te + shift - (this.info.origin || 0);
	}
	put(s, te, { db: lvl = -20, pan = 0, send = 0, align = "start" } = {}) {
		const a = analyze(s);
		const g = db(mixLevel(lvl)) / Math.max(a.rmsMax, 1e-6);
		const shift = align === "peak" ? a.peakAt : align === "onset" ? a.onset : 0;
		const start = Math.round((this.at(te) - shift) * SR);
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
	sfx(name, te, { speed = 1, rev = false, lp, hp, from, to, fin = 0.001, fout = 0.03, ...rest } = {}) {
		let s = asset(name, speed);
		if (from != null || to != null) s = slice(s, from ?? 0, to);
		if (rev) s = reverse(s);
		if (lp) s = filt(s, "lp", lp, 0.7);
		if (hp) s = filt(s, "hp", hp, 0.7);
		fade(s, fin, fout);
		return this.put(s, te, rest);
	}
	finish(sendGain = 0.4, room = 0.84, damp = 0.5) {
		const wet = reverb(this.wet, { room, damp, wet: sendGain, tail: 0.1 });
		const n = Math.ceil(this.sec * SR);
		const mix = stereo(this.sec);
		for (let c = 0; c < 2; c++) for (let i = 0; i < n; i++) mix[c][i] = this.dry[c][i] + wet[c][i];
		fade(mix, 0.002, 0.12);
		return limiter(mix, db(-1.6));
	}
}

const fall = (u, p = 1.5) => Math.pow(1 - u, p);
const swell = (a = 0, b = 0.85, c = 0.95) => (_, u) => smooth(a, b, u) * (1 - smooth(c, 1, u));
const hitDecay = (p = 1.5, attack = 0.03) => (_, u) => smooth(0, attack, u) * fall(u, p);
const choir = (sec, f, lvl, seed, voices = [1, 1.5, 2, 1.26]) => drone({ sec, f0: f, f1: f, voices, cutoff: 1800, env: swell(0, 0.4, 0.8), seed });
// 鐘（澄んだ和音）
const bell = (base, sec = 1.6, decay = 3, seed = 1, partials = [1, 2.0, 2.76, 3.42, 4.1]) => metalRing({ sec, base, partials, decay, seed });
// 心臓の鼓動（二つ打ち）
function beat(tr, te, lvl, seed) {
	tr.put(subDrop({ sec: 0.24, f0: 72, f1: 42, decay: 13, click: 0.06, seed }), te, { db: lvl });
	tr.put(subDrop({ sec: 0.2, f0: 60, f1: 38, decay: 15, click: 0.04, seed: seed + 1 }), te + 0.14, { db: lvl - 4 });
}
// 溜めのせり上がり（低いうなり＋地鳴り）
function build(tr, t0, t1, lvl, seed, f0 = 46, f1 = 118) {
	const sec = t1 - t0;
	tr.put(drone({ sec, f0, f1, curve: 1.4, voices: [1, 1.006, 0.5, 1.498], cutoff: (_, u) => lerp(200, 1300, u * u), env: (_, u) => smooth(0, 0.3, u) * (1 - smooth(0.94, 1, u)), seed }), t0, { db: lvl, pan: 0.15, send: 0.12 });
	tr.put(rumble({ sec, cutoff: 84, seed: seed + 1, env: (_, u) => smooth(0, 0.5, u) * (1 - smooth(0.94, 1, u)) }), t0, { db: lvl + 1 });
}
// 大爆発の低い核（どのボスにも共通の土台。上に素材感を重ねる）
function boomCore(tr, te, lvl, seed, len = 1.8) {
	tr.put(subDrop({ sec: len, f0: 82, f1: 24, decay: 2.2, seed }), te, { db: lvl });
	tr.put(rumble({ sec: len + 0.3, cutoff: 90, seed: seed + 1, env: hitDecay(1.3, 0.015) }), te + 0.02, { db: lvl - 6 });
}

// =============================== 金環の聖獣 / 日蝕の獅皇 ===============================
const lion = {
	pre_single(tr, T) {
		tr.sfx("encounter/wolf_growl", T.windup, { db: -19, speed: 0.78, pan: 0.2 });
		tr.put(choir(T.leap - T.windup + 0.2, 660, -28, 11), T.windup, { db: -28, pan: 0.2, send: 0.4 });
		tr.sfx("wind_swing", T.leap, { db: -16, speed: 0.85, pan: 0.1 });
		tr.sfx("neutral_sword_swing", T.contact, { db: -12, speed: 1.08, align: "peak", pan: -0.1 });
		tr.sfx("boss_impact_mass", T.contact, { db: -11, align: "peak", pan: -0.15 });
		tr.put(bell(1320, 0.9, 7, 13), T.contact, { db: -22, pan: -0.15, send: 0.5 });
		tr.put(sweepNoise({ sec: 0.3, f0: 600, f1: 2400, q: 1.2, curve: 0.8, seed: 15, env: swell(0, 0.5, 0.9) }), T.vanish, { db: -24, pan: 0.1 });
		tr.sfx("encounter/sparkle", T.back, { db: -22, speed: 1.0, pan: 0.2, send: 0.4 });
	},
	pre_all(tr, T) {
		tr.put(choir(T.roar - T.charge, 220, -24, 21), T.charge, { db: -24, pan: 0.15, send: 0.5 });
		build(tr, T.charge, T.roar, -20, 23, 50, 90);
		tr.put(sweepNoise({ sec: T.roar - T.charge, f0: 300, f1: 1400, q: 1, curve: 1.6, seed: 25, env: swell(0, 0.85, 0.97) }), T.charge, { db: -24, pan: 0.15 });
		tr.sfx("encounter/dragon_roar", T.roar, { db: -7, align: "onset", pan: 0.15, send: 0.3 });
		T.pulses.forEach((p, i) => {
			tr.put(subDrop({ sec: 0.4, f0: 90 - i * 8, f1: 40, decay: 8, click: 0.1, seed: 27 + i }), p, { db: -15 + i });
			tr.put(sweepNoise({ sec: 0.45, f0: 1800, f1: 400, q: 0.9, curve: 0.6, seed: 31 + i, env: hitDecay(1.4, 0.02) }), p, { db: -19, pan: -0.2 });
		});
		boomCore(tr, T.burst, -8, 35);
		tr.sfx("encounter/dragon_detonation", T.burst, { db: -11, speed: 0.95, align: "peak", send: 0.4 });
		tr.put(bell(523, 2.4, 2.2, 37, [1, 2, 3, 4, 5.04]), T.burst, { db: -15, send: 0.6 });
		tr.sfx("encounter/sparkle", T.burst + 0.4, { db: -20, speed: 0.9, send: 0.5, pan: -0.2 });
		tr.sfx("encounter/sparkle", T.burst + 0.9, { db: -23, speed: 1.1, send: 0.5, pan: 0.2 });
	},
	awaken(tr, T) {
		// 金の太陽が昇る（聖歌）→ 黒い月が重なり、音がゆっくり沈んでいく
		tr.put(choir(2.6, 330, -24, 41, [1, 1.25, 1.5, 2]), T.sun, { db: -24, pan: 0.15, send: 0.5 });
		tr.put(drone({ sec: T.total - T.bite, f0: 220, f1: 56, curve: 0.9, voices: [1, 1.06, 0.5, 1.41], cutoff: (_, u) => lerp(1600, 380, u), env: swell(0, 0.5, 0.98), seed: 43 }), T.bite, { db: -17, pan: 0.1, send: 0.25 });
		tr.put(rumble({ sec: T.total - T.bite, cutoff: 80, seed: 45, env: swell(0, 0.9, 0.98) }), T.bite, { db: -19 });
		tr.sfx("encounter/wolf_growl", T.distress, { db: -17, speed: 0.62, pan: 0.2 });
		// 皆既: 縁の一点の鋭い鐘 → 闇が落ちる低い音
		tr.put(bell(1760, 1.2, 6, 47, [1, 2.0, 3.01]), T.total - 0.06, { db: -15, pan: 0.15, send: 0.6 });
		tr.sfx("encounter/crt_off", T.total, { db: -16, speed: 0.55, pan: 0.1 });
		// 暗がりに目が灯る（機械武者の目の音を低く）
		tr.sfx("encounter/musha_eye", T.total + 0.3, { db: -13, speed: 0.8, align: "onset", pan: 0.15, send: 0.3 });
		tr.put(subDrop({ sec: 1.4, f0: 70, f1: 26, decay: 2.2, seed: 49 }), T.total, { db: -10 });
		tr.put(drone({ sec: T.done - T.total, f0: 55, f1: 62, voices: [1, 1.06, 0.5, 1.41, 0.71], cutoff: 700, env: swell(0, 0.2, 0.98), seed: 51 }), T.total, { db: -16, send: 0.3 });
		for (let k = 0; T.total + 0.1 + k * 0.42 < T.tame; k++) beat(tr, T.total + 0.1 + k * 0.42, -19 + k * 0.8, 53 + k * 2);
		tr.sfx("fire_burst", T.early, { db: -14, speed: 0.6, lp: 1600, pan: 0.15 });
		tr.put(flame({ sec: 1.0, f: 360, q: 0.6, seed: 61, env: hitDecay(1.2, 0.03) }), T.early, { db: -15, pan: 0.15, send: 0.2 });
		tr.sfx("encounter/dragon_roar", T.late, { db: -9, align: "onset", pan: 0.15, send: 0.3 });
		tr.put(flame({ sec: 1.0, f: 320, q: 0.6, seed: 63, env: hitDecay(1.0, 0.03) }), T.late, { db: -13, pan: 0.15 });
		build(tr, T.tame, T.done, -15, 65);
		T.beats.forEach((b, i) => beat(tr, b, -14 + i * 1.5, 67 + i * 3));
		tr.sfx("encounter/dragon_roar", T.done, { db: -5, align: "onset", pan: 0.1, send: 0.3 });
		boomCore(tr, T.done, -7, 71, 2.2);
		tr.sfx("encounter/dragon_detonation", T.done, { db: -9, speed: 0.72, align: "peak", send: 0.4 });
		tr.put(bell(196, 3.0, 1.4, 73, [1, 2.01, 2.76, 3.42]), T.done, { db: -15, send: 0.6 });
		tr.put(flame({ sec: 1.6, f: 420, q: 0.5, seed: 75, env: hitDecay(1.4, 0.02) }), T.done + 0.02, { db: -13, send: 0.25 });
	},
	post_single(tr, T) {
		tr.sfx("encounter/wolf_snarl", T.windup, { db: -15, speed: 0.74, pan: 0.2 });
		tr.put(flame({ sec: T.vanish - T.windup, f: 380, q: 0.6, seed: 81, env: swell(0, 0.6, 0.95) }), T.windup, { db: -21, pan: 0.2 });
		// 消える: 短く吸い込まれる音
		tr.sfx("encounter/gent_vanish", T.vanish, { db: -15, speed: 1.4, pan: 0.2 });
		tr.put(sweepNoise({ sec: 0.16, f0: 2200, f1: 500, q: 1.2, curve: 0.6, seed: 83, env: hitDecay(1.3, 0.01) }), T.vanish, { db: -18, pan: 0.2 });
		// 現れた瞬間にもう斬っている（前へ吸い込まれる音のあとに斬撃）
		tr.put(reverse(sweepNoise({ sec: 0.2, f0: 2600, f1: 700, q: 1, curve: 0.6, seed: 85, env: hitDecay(1.2, 0.01) })), T.appear - 0.2, { db: -17, pan: -0.1 });
		tr.sfx("neutral_sword_swing", T.appear, { db: -10, speed: 0.86, align: "peak", pan: -0.1 });
		tr.sfx("fire_impact_heavy", T.appear, { db: -11, speed: 0.85, align: "peak", pan: -0.15 });
		tr.put(rip({ sec: 0.25, seed: 87, f0: 700, f1: 2200 }), T.appear, { db: -18, pan: -0.1 });
		tr.sfx("encounter/golem_slam", T.slam, { db: -9, speed: 0.9, align: "peak", pan: -0.15 });
		tr.sfx("encounter/dragon_detonation", T.slam, { db: -12, speed: 1.15, align: "peak", pan: -0.15, send: 0.3 });
		tr.put(subDrop({ sec: 0.9, f0: 78, f1: 28, decay: 3.5, seed: 89 }), T.slam, { db: -9 });
		tr.sfx("encounter/golem_pebbles", T.slam + 0.05, { db: -18, pan: -0.2 });
		tr.sfx("encounter/gent_vanish", T.vanish2, { db: -18, speed: 1.4, pan: -0.1 });
		tr.put(sweepNoise({ sec: 0.18, f0: 700, f1: 2000, q: 1, curve: 1.2, seed: 91, env: hitDecay(1.2, 0.01) }), T.back, { db: -20, pan: 0.2 });
	},
	post_all(tr, T) {
		tr.sfx("encounter/wolf_growl", T.crouch, { db: -18, speed: 0.6, pan: 0.2 });
		// 咆哮は竜の登場・覚醒と同じ声（高さを変えない。2026-11-12 ユーザー指定）
		tr.sfx("encounter/dragon_roar", T.fall, { db: -5, align: "onset", pan: 0.15, send: 0.3 });
		tr.put(choir(1.8, 330, -24, 101, [1, 1.25, 1.5, 2]), T.sun, { db: -25, pan: -0.2, send: 0.5 });
		tr.put(drone({ sec: T.total - T.bite, f0: 220, f1: 58, curve: 0.9, voices: [1, 1.06, 0.5, 1.41], cutoff: (_, u) => lerp(1600, 380, u), env: swell(0, 0.5, 0.98), seed: 103 }), T.bite, { db: -16, pan: -0.2, send: 0.25 });
		tr.put(bell(1760, 1.2, 6, 105, [1, 2.0, 3.01]), T.total - 0.06, { db: -15, pan: -0.2, send: 0.6 });
		tr.sfx("encounter/crt_off", T.total, { db: -16, speed: 0.55 });
		tr.put(subDrop({ sec: 1.4, f0: 70, f1: 26, decay: 2.2, seed: 107 }), T.total, { db: -10 });
		tr.put(drone({ sec: T.collapse - T.total, f0: 55, f1: 60, voices: [1, 1.06, 0.5, 1.41, 0.71], cutoff: 700, env: swell(0, 0.2, 0.98), seed: 109 }), T.total, { db: -16, send: 0.3 });
		for (let k = 0; k < 3; k++) beat(tr, T.total + 0.1 + k * 0.4, -18 + k, 111 + k * 2);
		T.beams.forEach((b, i) => {
			tr.put(beam({ sec: 0.36, f0: 1800, f1: 260, seed: 121 + i }), b, { db: -17, pan: -0.3 + i * 0.15, send: 0.2 });
			tr.sfx("fire_impact_heavy", b, { db: -15, speed: 0.8 + i * 0.04, align: "peak", pan: -0.3 + i * 0.15 });
			tr.put(subDrop({ sec: 0.35, f0: 90, f1: 40, decay: 8, seed: 125 + i }), b, { db: -15 });
		});
		tr.put(sweepNoise({ sec: T.collapse - T.fall, f0: 900, f1: 120, q: 1, curve: 0.8, seed: 131, env: swell(0, 0.9, 0.98) }), T.fall, { db: -14, send: 0.2 });
		boomCore(tr, T.collapse, -6, 133, 2.4);
		tr.sfx("encounter/dragon_detonation", T.collapse, { db: -8, speed: 0.72, align: "peak", send: 0.45 });
		tr.sfx("encounter/final_hit", T.collapse, { db: -10, speed: 0.9, align: "peak" });
		tr.put(shatter({ sec: 1.2, count: 110, seed: 135, f0: 1600, f1: 6000 }), T.collapse + 0.02, { db: -19, send: 0.35 });
		tr.put(flame({ sec: 1.8, f: 400, q: 0.5, seed: 137, env: hitDecay(1.4, 0.02) }), T.collapse + 0.02, { db: -12, send: 0.25 });
		tr.put(crackle({ sec: 1.6, density: 28, seed: 139, env: (_, u) => smooth(0, 0.15, u) * fall(u, 0.8) }), T.collapse + 0.4, { db: -26 });
	},
	// 登場: 剣が次々と突き刺さる（落ちる風切り → 地面に刺さる金属の音・小さな鐘）→ 巨大な剣が現れて光を集める → 一気に落ちて突き刺さる
	// → 金の大爆発（剣が光になって砕ける）→ 竜と同じ声の咆哮 → 光の粒
	intro(tr, T) {
		build(tr, T.dim, T.giant_hit, -22, 201, 44, 96);
		tr.put(choir(T.giant_hit - T.dim, 330, -26, 203, [1, 1.25, 1.5, 2]), T.dim, { db: -26, pan: 0.15, send: 0.5 });
		T.swords.forEach((s, i) => {
			const pan = 0.05 + ((i % 3) - 1) * 0.12;
			tr.put(sweepNoise({ sec: 0.18, f0: 3200, f1: 700, q: 1.3, curve: 0.7, seed: 211 + i, env: swell(0, 0.85, 0.97) }), s - 0.17, { db: -24 + i * 0.3, pan });
			tr.sfx("encounter/knight_plant", s, { db: -15 + i * 0.25, speed: 1.12 - (i % 4) * 0.04, align: "peak", pan });
			tr.put(bell(1568 + (i % 3) * 196, 0.7, 7, 221 + i, [1, 2.0, 2.76]), s, { db: -25, pan, send: 0.5 });
			tr.put(subDrop({ sec: 0.25, f0: 90, f1: 46, decay: 11, click: 0.05, seed: 231 + i }), s, { db: -20 + i * 0.4 });
		});
		// 巨大な剣: 現れる（高い鐘・聖歌のせり上がり）→ 溜め → 落ちる風切り
		tr.sfx("encounter/knight_raise", T.giant_in, { db: -15, speed: 0.8, pan: 0.15, send: 0.3 });
		tr.put(bell(880, 1.6, 2.5, 241, [1, 2.0, 2.76, 3.42]), T.giant_in, { db: -19, pan: 0.15, send: 0.6 });
		tr.put(choir(T.giant_fall - T.giant_in + 0.1, 440, -21, 243, [1, 1.25, 1.5, 2]), T.giant_in, { db: -21, pan: 0.15, send: 0.5 });
		tr.put(sweepNoise({ sec: T.giant_fall - T.giant_in, f0: 400, f1: 2200, q: 1, curve: 1.5, seed: 245, env: swell(0, 0.9, 0.98) }), T.giant_in, { db: -22, pan: 0.15 });
		tr.put(sweepNoise({ sec: T.giant_hit - T.giant_fall + 0.02, f0: 2600, f1: 300, q: 1.1, curve: 0.6, seed: 247, env: swell(0, 0.9, 1.0) }), T.giant_fall, { db: -15, pan: 0.15 });
		tr.sfx("wind_swing", T.giant_fall, { db: -16, speed: 0.7, pan: 0.15 });
		// 突き刺さる → 大爆発
		tr.sfx("encounter/knight_plant", T.giant_hit, { db: -9, speed: 0.72, align: "peak", pan: 0.15 });
		tr.sfx("encounter/final_hit", T.giant_hit, { db: -11, speed: 0.9, align: "peak", pan: 0.15 });
		boomCore(tr, T.burst, -7, 251, 2.2);
		tr.sfx("encounter/dragon_detonation", T.burst, { db: -9, speed: 0.9, align: "peak", pan: 0.1, send: 0.45 });
		tr.put(shatter({ sec: 1.1, count: 90, seed: 253, f0: 2200, f1: 7000 }), T.burst + 0.02, { db: -19, pan: 0.1, send: 0.4 });
		tr.put(bell(392, 3.0, 1.6, 255, [1, 2.0, 2.76, 3.42, 4.1]), T.burst, { db: -15, send: 0.6 });
		tr.put(flame({ sec: 1.6, f: 420, q: 0.5, seed: 257, env: hitDecay(1.4, 0.02) }), T.burst + 0.02, { db: -14, send: 0.25 });
		// 咆哮は竜の登場・覚醒と同じ声（高さを変えない）
		tr.sfx("encounter/dragon_roar", T.roar, { db: -6, align: "onset", pan: 0.15, send: 0.3 });
		tr.sfx("encounter/sparkle", T.roar + 0.5, { db: -21, speed: 0.9, send: 0.5, pan: -0.1 });
		tr.sfx("encounter/sparkle", T.stance, { db: -23, speed: 1.1, send: 0.5, pan: 0.2 });
	},
	// 撃破: 金環が現れる（澄んだ和音）→ 欠けていく間ずっと、金の欠片がこぼれる細かな音と沈んでいく低い音
	// → 最後のひとかけらの小さな鐘 → 静かに消える。聖獣の弱い唸り声で始まる。
	fall(tr, T) {
		tr.sfx("encounter/wolf_growl", T.ring, { db: -18, speed: 0.55, pan: 0.15 });
		tr.put(choir(T.wane - T.ring + 0.4, 330, -23, 301, [1, 1.25, 1.5, 2]), T.ring, { db: -23, pan: 0.15, send: 0.5 });
		tr.put(bell(659, 2.0, 2.4, 303, [1, 2.0, 2.76, 3.42]), T.full - 0.05, { db: -18, pan: 0.15, send: 0.6 });
		tr.put(drone({ sec: T.gone - T.wane + 0.3, f0: 196, f1: 52, curve: 0.9, voices: [1, 1.06, 0.5, 1.41], cutoff: (_, u) => lerp(1500, 360, u), env: swell(0, 0.4, 0.95), seed: 305 }), T.wane, { db: -19, pan: 0.1, send: 0.3 });
		tr.put(shatter({ sec: T.last - T.wane + 0.2, count: 70, seed: 307, f0: 2000, f1: 6500 }), T.wane, { db: -24, pan: 0.1, send: 0.45 });
		tr.put(crackle({ sec: T.last - T.wane + 0.2, density: 22, seed: 309, env: swell(0, 0.6, 0.95) }), T.wane, { db: -28, pan: 0.1 });
		tr.sfx("encounter/golem_pebbles", T.wane + 0.3, { db: -24, speed: 1.4, pan: 0.2 });
		tr.sfx("encounter/sparkle", T.melt, { db: -22, speed: 0.8, send: 0.5, pan: 0.15 });
		tr.sfx("encounter/wolf_fade", T.melt, { db: -17, speed: 0.85, pan: 0.15, send: 0.3 });
		tr.put(bell(1760, 1.4, 4, 311, [1, 2.0, 3.01]), T.last, { db: -17, pan: 0.15, send: 0.7 });
		tr.put(subDrop({ sec: 1.0, f0: 64, f1: 30, decay: 3, seed: 313 }), T.last, { db: -16 });
		// 最後のかけらが光の剣になって床に刺さる（2026-11-13）
		tr.put(sweepNoise({ sec: T.stab - T.sword + 0.02, f0: 2400, f1: 600, q: 1.2, curve: 0.7, seed: 315, env: swell(0, 0.85, 1.0) }), T.sword, { db: -22, pan: 0.15 });
		tr.sfx("encounter/knight_plant", T.stab, { db: -12, speed: 1.0, align: "peak", pan: 0.15 });
		tr.put(bell(1319, 1.6, 3, 317, [1, 2.0, 2.76]), T.stab, { db: -19, pan: 0.15, send: 0.7 });
		tr.sfx("encounter/sparkle", T.stab + 0.15, { db: -24, speed: 1.15, send: 0.6, pan: 0.1 });
	},
	// 覚醒後の撃破（2026-11-13「もっと派手に」）: 苦しむ叫び → 光冠が燃え上がる → 欠けていく間の脈打つ低い打撃
	// → 最後のかけらで深紅の大爆発 → 煙の中から大剣が落ちて突き刺さる（重い金属音と低い鐘）
	fall_awakened(tr, T) {
		tr.sfx("encounter/dragon_cry", T.ring, { db: -12, speed: 0.82, align: "onset", pan: 0.15, send: 0.3 });
		tr.put(drone({ sec: T.burst - T.ring, f0: 110, f1: 46, curve: 0.9, voices: [1, 1.06, 0.5, 1.41, 0.71], cutoff: (_, u) => lerp(1200, 300, u), env: swell(0, 0.3, 0.97), seed: 401 }), T.ring, { db: -16, pan: 0.1, send: 0.3 });
		tr.put(bell(1760, 1.2, 6, 403, [1, 2.0, 3.01]), T.full - 0.05, { db: -17, pan: 0.15, send: 0.6 });
		tr.sfx("fire_burst", T.flare, { db: -12, speed: 0.6, lp: 1800, pan: 0.15 });
		tr.put(flame({ sec: 1.0, f: 340, q: 0.6, seed: 405, env: hitDecay(1.2, 0.02) }), T.flare, { db: -14, pan: 0.15, send: 0.25 });
		tr.put(subDrop({ sec: 0.6, f0: 80, f1: 32, decay: 5, click: 0.08, seed: 407 }), T.flare, { db: -12 });
		for (let k = 0; T.wane + k * 0.3 < T.last; k++) {
			tr.put(subDrop({ sec: 0.3, f0: 78, f1: 40, decay: 10, click: 0.05, seed: 411 + k }), T.wane + k * 0.3, { db: -19 + k * 0.6 });
		}
		tr.put(shatter({ sec: T.last - T.wane + 0.2, count: 110, seed: 431, f0: 1600, f1: 6000 }), T.wane, { db: -21, pan: 0.1, send: 0.45 });
		tr.put(crackle({ sec: T.last - T.wane + 0.2, density: 30, seed: 433, env: swell(0, 0.6, 0.95) }), T.wane, { db: -25, pan: 0.1 });
		tr.put(sweepNoise({ sec: T.burst - T.wane, f0: 300, f1: 1800, q: 1, curve: 1.6, seed: 435, env: swell(0, 0.9, 0.98) }), T.wane, { db: -21, pan: 0.1 });
		// 大爆発
		boomCore(tr, T.burst, -6, 437, 2.2);
		tr.sfx("encounter/dragon_detonation", T.burst, { db: -8, speed: 0.78, align: "peak", send: 0.45 });
		tr.sfx("encounter/final_hit", T.burst, { db: -11, speed: 0.85, align: "peak" });
		tr.put(shatter({ sec: 1.1, count: 100, seed: 439, f0: 1600, f1: 6500 }), T.burst + 0.02, { db: -19, send: 0.4 });
		tr.put(flame({ sec: 1.6, f: 380, q: 0.5, seed: 441, env: hitDecay(1.4, 0.02) }), T.burst + 0.02, { db: -13, send: 0.25 });
		// 大剣が落ちて突き刺さる
		tr.put(sweepNoise({ sec: T.stab - T.sword + 0.02, f0: 2800, f1: 260, q: 1.1, curve: 0.6, seed: 443, env: swell(0, 0.9, 1.0) }), T.sword, { db: -15, pan: 0.15 });
		tr.sfx("encounter/knight_plant", T.stab, { db: -9, speed: 0.74, align: "peak", pan: 0.15 });
		tr.put(subDrop({ sec: 0.8, f0: 70, f1: 30, decay: 4, click: 0.1, seed: 445 }), T.stab, { db: -11 });
		tr.put(bell(262, 2.6, 1.8, 447, [1, 2.0, 2.76, 3.42]), T.stab, { db: -16, pan: 0.15, send: 0.6 });
		tr.sfx("encounter/golem_pebbles", T.stab + 0.03, { db: -20, pan: 0.2 });
	},
};

// 支援（回復・強化）: 立ち姿から支援のポーズへ（短い唸り）→ 頭上の金環の澄んだ鐘 → 光が集まる → 放つ。
function support(tr, T, { awakened, heal }) {
	const pan = 0.15;
	tr.sfx("encounter/wolf_growl", T.pose, { db: awakened ? -19 : -22, speed: awakened ? 0.62 : 0.8, pan, to: 0.6, fout: 0.2 });
	tr.put(bell(awakened ? 988 : 1319, 1.0, 4, awakened ? 411 : 401, [1, 2.0, 2.76]), T.halo, { db: -21, pan, send: 0.6 });
	tr.put(choir(T.impact - T.halo + 0.3, awakened ? 247 : 330, -24, awakened ? 413 : 403, [1, 1.25, 1.5, 2]), T.halo, { db: -24, pan, send: 0.5 });
	tr.put(sweepNoise({ sec: T.impact - T.gather, f0: 400, f1: 2600, q: 1, curve: 1.6, seed: awakened ? 415 : 405, env: swell(0, 0.9, 0.98) }), T.gather, { db: -24, pan });
	if (awakened) tr.put(drone({ sec: T.end - T.halo, f0: 62, f1: 70, voices: [1, 1.06, 0.5, 1.41], cutoff: 600, env: swell(0, 0.3, 0.95), seed: 417 }), T.halo, { db: -22, send: 0.3 });
	if (heal) {
		tr.sfx("heal_hp", T.impact, { db: -12, speed: awakened ? 0.85 : 1.0, align: "onset", pan, send: 0.4 });
		tr.put(bell(awakened ? 392 : 523, 2.0, 2.2, awakened ? 419 : 407, [1, 2.0, 3.0, 4.0, 5.04]), T.impact, { db: -17, pan, send: 0.7 });
		tr.sfx("encounter/sparkle", T.impact + 0.12, { db: -19, speed: awakened ? 0.85 : 1.0, send: 0.5, pan });
		tr.sfx("encounter/sparkle", T.impact + 0.55, { db: -24, speed: 1.15, send: 0.5, pan: -0.1 });
	} else {
		tr.sfx("buff_atk", T.impact, { db: -12, speed: awakened ? 0.85 : 1.0, align: "onset", pan, send: 0.3 });
		tr.put(subDrop({ sec: 0.6, f0: 84, f1: 34, decay: 5, click: 0.08, seed: awakened ? 421 : 409 }), T.impact, { db: -13 });
		tr.put(flame({ sec: 1.0, f: awakened ? 360 : 460, q: 0.6, seed: awakened ? 423 : 411, env: hitDecay(1.3, 0.02) }), T.impact, { db: -16, pan, send: 0.2 });
		tr.put(bell(awakened ? 330 : 440, 1.6, 2.6, awakened ? 425 : 413, [1, 2.0, 2.76, 3.42]), T.impact, { db: -18, pan, send: 0.6 });
		if (awakened) tr.sfx("encounter/wolf_snarl", T.impact - 0.05, { db: -16, speed: 0.72, pan });
	}
}
for (const awakened of [false, true]) for (const heal of [true, false]) {
	lion[(awakened ? "post" : "pre") + "_support_" + (heal ? "heal" : "buff")] = (tr, T) => support(tr, T, { awakened, heal });
}

const NAMES = { pre_single: "single", pre_all: "all", awaken: "awakening", post_single: "awakened_single", post_all: "awakened_all",
	intro: "intro", fall: "defeat", fall_awakened: "defeat_awakened", pre_support_heal: "heal", pre_support_buff: "buff", post_support_heal: "awakened_heal", post_support_buff: "awakened_buff" };
const timingOf = (move) => (move.includes("_support_") ? "support" : move);
const only = process.argv.slice(2);
fs.mkdirSync(path.join(HERE, "out"), { recursive: true });
for (const [move, fn] of Object.entries(lion)) {
	if (only.length && !only.includes(move)) continue;
	const info = TIMING.lion[timingOf(move)];
	const tr = new Track(info);
	fn(tr, info.T);
	const { out } = tr.finish();
	wavWrite(path.join(HERE, "out", move + ".wav"), out);
	console.log(`${move} → ${NAMES[move]}.wav: ${(out[0].length / SR).toFixed(2)}秒`);
}
