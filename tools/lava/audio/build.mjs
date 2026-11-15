// 熔鉱炉の番人／噴界炉の巨神（lava）の効果音（2026-11-14〜16 ユーザーが確認動画で採用した音。試作 prototypes/four_bosses_2026-11-11/audio/build.mjs の lava をそのまま移した）。
// 時刻は timing.json（tools/lava/dump_lava_timing.gd が本番のエフェクトの T・ヒットストップから書き出す）。
// 使い方: godot --headless --path . --script res://tools/lava/dump_lava_timing.gd → node tools/lava/audio/build.mjs [技の名前 ...] → tools/lava/audio/out/<名前>.wav
// できた音は同じ名前で assets_bossmaker/audio/lava/ へ置く（置いた後に --import）。名前の対応は NAMES（技 → 音の名前）。
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
/** 技 → assets_bossmaker/audio/lava/ の音の名前 */
const NAMES = {"pre_single":"single","pre_all":"all","awaken":"awakening","post_single":"awakened_single","post_all":"awakened_all","intro":"intro","pre_support_heal":"heal","pre_support_buff":"buff","post_support_heal":"awakened_heal","post_support_buff":"awakened_buff","pre_defeat":"defeat","post_defeat":"defeat_awakened"};
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
		return te + shift;
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



// 溶岩（2026-11-13 溶岩の巨人の作り直し）: 噴き上がる溶岩柱・煮える溜まり・落ちてくる溶岩の塊
function geyser(tr, te, lvl, seed, pan = 0, len = 0.9) {
	tr.put(flame({ sec: len, f: 340, q: 0.55, seed, env: hitDecay(1.1, 0.02) }), te, { db: lvl, pan, send: 0.2 });
	tr.put(sweepNoise({ sec: 0.35, f0: 300, f1: 1800, q: 1, curve: 1.4, seed: seed + 1, env: hitDecay(1.0, 0.01) }), te, { db: lvl - 4, pan });
	tr.put(subDrop({ sec: 0.4, f0: 80, f1: 36, decay: 7, seed: seed + 2 }), te, { db: lvl - 2 });
}
function simmer(tr, te, sec, lvl, seed, pan = 0) {
	tr.put(crackle({ sec, density: 18, seed, env: swell(0, 0.2, 0.9) }), te, { db: lvl, pan });
	tr.put(flame({ sec, f: 180, q: 0.7, seed: seed + 1, env: swell(0, 0.3, 0.9), flutter: 0.8 }), te, { db: lvl - 2, pan });
}
function bombs(tr, te, n, step, life, lvl, seed) {
	for (let k = 0; k < n; k++) {
		tr.put(sweepNoise({ sec: life * 0.9, f0: 2600, f1: 500, q: 1.2, curve: 0.8, seed: seed + k, env: swell(0, 0.85, 1.0) }), te + k * step, { db: lvl - 6, pan: -0.5 + (k % 5) * 0.25 });
		tr.put(subDrop({ sec: 0.25, f0: 90, f1: 46, decay: 10, click: 0.06, seed: seed + 40 + k }), te + k * step + life, { db: lvl, pan: -0.5 + (k % 5) * 0.25 });
		if (k % 3 === 0) tr.sfx("encounter/golem_pebbles", te + k * step + life, { db: lvl - 4, speed: 1.3, pan: -0.5 + (k % 5) * 0.25 });
	}
}
const lava = {
	// ①（2026-11-14）: 拳の赤熱 → 跳び立ち（地を蹴る音・上へ抜ける風）→ 燃えながら落ちてくる → 叩きつけ（溶岩の柱・溜まり）→ また跳んで戻る
	pre_single(tr, T) {
		tr.sfx("hammer_swing", T.windup, { db: -18, speed: 0.7, pan: 0.2 });
		tr.put(crackle({ sec: T.leap - T.windup, density: 24, seed: 201, env: swell(0, 0.5, 0.95) }), T.windup, { db: -24, pan: 0.2 });
		tr.sfx("encounter/dragon_land", T.leap, { db: -14, speed: 1.2, align: "peak", pan: 0.15 });
		tr.put(sweepNoise({ sec: 0.25, f0: 400, f1: 2600, q: 1, curve: 1.2, seed: 202, env: hitDecay(1.0, 0.02) }), T.leap, { db: -17, pan: 0.15 });
		tr.put(sweepNoise({ sec: T.slam - T.fall + 0.02, f0: 2800, f1: 300, q: 1.1, curve: 0.6, seed: 204, env: swell(0, 0.9, 1.0) }), T.fall, { db: -14, pan: -0.1 });
		tr.put(flame({ sec: T.slam - T.fall + 0.05, f: 300, q: 0.6, seed: 206, env: swell(0, 0.8, 1.0), flutter: 0.6 }), T.fall, { db: -15, pan: -0.1 });
		tr.sfx("hammer_impact", T.slam, { db: -8, speed: 0.8, align: "peak", pan: -0.15 });
		tr.sfx("encounter/golem_slam", T.slam, { db: -10, speed: 0.95, align: "peak", pan: -0.15 });
		tr.put(subDrop({ sec: 0.9, f0: 70, f1: 28, decay: 3.6, seed: 203 }), T.slam, { db: -8 });
		geyser(tr, T.slam + 0.01, -11, 301, -0.15);
		tr.sfx("encounter/golem_pebbles", T.slam + 0.06, { db: -17, pan: -0.2 });
		simmer(tr, T.slam + 0.3, T.end - T.slam - 0.3, -24, 305, -0.15);
		tr.put(sweepNoise({ sec: 0.25, f0: 400, f1: 2600, q: 1, curve: 1.2, seed: 207, env: hitDecay(1.0, 0.02) }), T.hop, { db: -18, pan: -0.1 });
		tr.put(sweepNoise({ sec: T.land - T.drop, f0: 2400, f1: 400, q: 1.1, curve: 0.6, seed: 208, env: swell(0, 0.9, 1.0) }), T.drop, { db: -17, pan: 0.15 });
		tr.sfx("encounter/dragon_land", T.land, { db: -12, speed: 1.0, align: "peak", pan: 0.15 });
	},
	// ②（2026-11-14）: 炉が唸る → 腹から溶岩が昇る流れ → 上空で煮える玉 → 一人ずつ垂れて落ちる → 玉ごと落ちて大きく飛び散る
	pre_all(tr, T) {
		tr.put(flame({ sec: T.release - T.charge, f: 280, q: 0.6, seed: 211, env: swell(0, 0.8, 0.97), flutter: 0.5 }), T.charge, { db: -16, pan: 0.15, send: 0.15 });
		tr.sfx("encounter/golem_rumble", T.charge, { db: -18, speed: 0.9, pan: 0.15 });
		tr.sfx("fire_cast", T.release, { db: -12, speed: 0.6, pan: 0.1, send: 0.2 });
		tr.put(flame({ sec: T.gather_end - T.release, f: 240, q: 0.5, seed: 213, env: swell(0, 0.2, 0.92), flutter: 0.7 }), T.release, { db: -13, pan: -0.1, send: 0.2 });
		tr.put(sweepNoise({ sec: T.gather_end - T.release, f0: 200, f1: 900, q: 1, curve: 1.2, seed: 214, env: swell(0, 0.6, 0.95) }), T.release, { db: -21, pan: -0.2 });
		simmer(tr, T.release + 0.3, T.drop - T.release - 0.3, -19, 216, -0.3);
		T.drips.forEach((d, i) => {
			tr.put(sweepNoise({ sec: 0.16, f0: 1800, f1: 600, q: 1.2, curve: 0.8, seed: 221 + i, env: swell(0, 0.9, 1.0) }), d, { db: -21, pan: -0.4 + i * 0.2 });
			tr.sfx("encounter/slime_splat", d + 0.16, { db: -15, speed: 0.75, align: "peak", pan: -0.4 + i * 0.2 });
			tr.put(flame({ sec: 0.4, f: 420, q: 0.6, seed: 225 + i, env: hitDecay(1.2, 0.02) }), d + 0.16, { db: -18, pan: -0.4 + i * 0.2 });
		});
		tr.put(sweepNoise({ sec: T.impact - T.drop + 0.02, f0: 1600, f1: 120, q: 1, curve: 0.7, seed: 229, env: swell(0, 0.9, 1.0) }), T.drop, { db: -13, pan: -0.2 });
		boomCore(tr, T.impact, -6, 231, 2.0);
		tr.sfx("encounter/slime_splat", T.impact, { db: -9, speed: 0.5, align: "peak", pan: -0.2, send: 0.3 });
		tr.sfx("hammer_burst", T.impact, { db: -9, speed: 0.85, align: "peak", send: 0.3 });
		tr.sfx("encounter/dragon_detonation", T.impact, { db: -11, speed: 0.85, align: "peak", send: 0.4 });
		tr.put(flame({ sec: 1.6, f: 360, q: 0.5, seed: 233, env: hitDecay(1.2, 0.02) }), T.impact + 0.02, { db: -11, send: 0.25 });
		simmer(tr, T.impact + 0.3, T.end - T.impact - 0.3, -21, 235, -0.2);
		tr.sfx("encounter/golem_crumble", T.impact + 0.3, { db: -17, speed: 0.9 });
	},
	// ③（2026-11-14 作り直し2）: 地鳴り → 闇が落ちる（低い音・炉の唸り・目が灯る）→ 鼓動4回 → 火口が開く（崩れる岩・煮える溶岩）
	// → せり上がる（高まる唸り）→ 大噴火（柱が天へ）→ 覚醒後の姿（低い鐘・灰）
	awaken(tr, T) {
		tr.sfx("encounter/golem_rumble", 0.1, { db: -17, speed: 0.8, pan: 0.15 });
		tr.put(flame({ sec: T.dark, f: 240, q: 0.6, seed: 241, env: swell(0, 0.8, 0.97), flutter: 0.6 }), 0.1, { db: -20, pan: 0.15 });
		tr.sfx("encounter/crt_off", T.dark, { db: -16, speed: 0.55, pan: 0.1 });
		tr.put(subDrop({ sec: 1.2, f0: 66, f1: 28, decay: 2.4, seed: 243 }), T.dark, { db: -11 });
		tr.sfx("encounter/musha_eye", T.dark + 0.3, { db: -14, speed: 0.7, align: "onset", pan: 0.15, send: 0.3 });
		tr.put(drone({ sec: T.erupt - T.dark, f0: 44, f1: 66, voices: [1, 1.006, 0.5, 2.0], cutoff: (_, u) => lerp(300, 700, u), env: swell(0, 0.3, 0.98), seed: 245 }), T.dark, { db: -15, send: 0.15 });
		T.beats.forEach((b, i) => beat(tr, b, -12 + i * 1.2, 251 + i * 3));
		tr.sfx("encounter/golem_crack", T.caldera, { db: -12, speed: 0.75, align: "peak", pan: 0.15 });
		tr.sfx("encounter/golem_crumble", T.caldera + 0.1, { db: -15, speed: 0.9, pan: 0.15 });
		simmer(tr, T.caldera + 0.2, T.erupt - T.caldera - 0.2, -17, 261, 0.15);
		build(tr, T.rise, T.erupt, -12, 263, 40, 110);
		for (let i = 0; i < 6; i++) tr.put(flame({ sec: 0.5, f: 380, q: 0.6, seed: 271 + i, env: hitDecay(1.1, 0.03) }), T.rise + i * 0.08, { db: -21, pan: -0.4 + i * 0.16 });
		// 大噴火
		boomCore(tr, T.erupt, -5, 281, 2.8);
		geyser(tr, T.erupt, -7, 283, 0.1, 2.2);
		tr.sfx("encounter/dragon_detonation", T.erupt, { db: -7, speed: 0.62, align: "peak", send: 0.45 });
		tr.sfx("hammer_burst", T.erupt, { db: -9, speed: 0.8, align: "peak" });
		tr.put(flame({ sec: 2.0, f: 340, q: 0.5, seed: 287, env: hitDecay(1.1, 0.02) }), T.erupt + 0.02, { db: -9, send: 0.25 });
		bombs(tr, T.erupt + 0.15, 12, 0.07, 0.8, -20, 291);
		// 覚醒後の姿
		tr.put(bell(110, 3.0, 1.4, 311, [1, 2.0, 2.76, 3.42]), T.reveal, { db: -15, send: 0.6 });
		tr.sfx("fire_cast", T.reveal, { db: -14, speed: 0.55, pan: 0.15, send: 0.3 });
		simmer(tr, T.reveal + 0.3, T.end - T.reveal - 0.3, -21, 313, 0.1);
	},
	// ④（2026-11-14）: 足元の溶岩が拳へ集まる（流れる音・高まる唸り）→ 殴って溶岩の玉を撃ち出す（飛ぶ音）→ 着弾の大爆発
	post_single(tr, T) {
		tr.sfx("hammer_swing", T.windup, { db: -16, speed: 0.6, pan: 0.2 });
		tr.put(flame({ sec: T.punch - T.windup, f: 240, q: 0.6, seed: 301, env: swell(0, 0.8, 0.95), flutter: 0.7 }), T.windup, { db: -15, pan: 0.2 });
		tr.put(sweepNoise({ sec: T.punch - T.windup, f0: 200, f1: 1400, q: 1, curve: 1.5, seed: 303, env: swell(0, 0.9, 0.98) }), T.windup, { db: -19, pan: 0.2 });
		simmer(tr, T.windup, T.punch - T.windup, -20, 305, 0.2);
		tr.sfx("boss_move_heavy", T.punch - 0.04, { db: -14, speed: 0.8, pan: 0.1 });
		tr.sfx("hammer_impact", T.punch, { db: -10, speed: 0.8, align: "peak", pan: 0.0 });
		tr.put(sweepNoise({ sec: T.boom - T.punch + 0.02, f0: 1800, f1: 500, q: 1.1, curve: 0.8, seed: 307, env: swell(0, 0.6, 1.0) }), T.punch, { db: -14, pan: -0.15 });
		tr.put(flame({ sec: T.boom - T.punch + 0.05, f: 420, q: 0.5, seed: 309, env: swell(0, 0.5, 1.0) }), T.punch, { db: -15, pan: -0.15 });
		boomCore(tr, T.boom, -5, 311, 2.0);
		tr.sfx("fire_impact_heavy", T.boom, { db: -9, speed: 0.7, align: "peak", pan: -0.15 });
		tr.sfx("encounter/dragon_detonation", T.boom, { db: -8, speed: 0.9, align: "peak", pan: -0.15, send: 0.4 });
		tr.sfx("hammer_burst", T.boom, { db: -10, speed: 0.85, align: "peak", pan: -0.15 });
		geyser(tr, T.boom + 0.01, -11, 313, -0.15, 1.2);
		tr.put(flame({ sec: 1.4, f: 380, q: 0.5, seed: 317, env: hitDecay(1.2, 0.02) }), T.boom + 0.02, { db: -11, pan: -0.15, send: 0.25 });
		bombs(tr, T.boom + 0.1, 6, 0.05, 0.55, -21, 321);
		simmer(tr, T.boom + 0.3, T.end - T.boom - 0.3, -22, 331, -0.15);
	},
	// ⑤（2026-11-14 新しい技）: オーラが燃え上がる溜め → 炉を開く（熱の波が地を走る）→ 足元が赤く光り火口が開く → 一人ずつの炎
	// → 大噴火（柱が四人を突き抜ける）→ 火砕流（灰と炎の壁がなぎ払う低い轟き）→ 灰が降る
	post_all(tr, T) {
		tr.put(flame({ sec: T.open_furnace - T.charge, f: 260, q: 0.6, seed: 341, env: swell(0, 0.8, 0.97), flutter: 0.6 }), T.charge, { db: -13, pan: 0.15, send: 0.15 });
		build(tr, T.charge, T.open_furnace, -15, 343, 38, 88);
		tr.sfx("fire_cast", T.open_furnace, { db: -10, speed: 0.5, pan: 0.15, send: 0.2 });
		tr.put(sweepNoise({ sec: 0.4, f0: 200, f1: 1200, q: 1, curve: 1.2, seed: 345, env: hitDecay(1.0, 0.02) }), T.open_furnace, { db: -15, pan: 0.0 });
		tr.sfx("encounter/golem_rumble", T.glow, { db: -14, speed: 0.75, pan: -0.2 });
		tr.sfx("encounter/golem_crack", T.open, { db: -11, speed: 0.75, align: "peak", pan: -0.2 });
		tr.sfx("encounter/golem_crumble", T.open + 0.1, { db: -15, speed: 0.9, pan: -0.2 });
		simmer(tr, T.open + 0.2, T.end - T.open - 0.2, -19, 347, -0.2);
		T.jets.forEach((j, i) => geyser(tr, j, -14, 361 + i * 3, -0.5 + i * 0.25, 0.6));
		build(tr, T.jets[3], T.erupt, -14, 371, 50, 120);
		boomCore(tr, T.erupt, -4, 381, 2.8);
		geyser(tr, T.erupt, -6, 383, -0.2, 2.0);
		tr.sfx("encounter/dragon_detonation", T.erupt, { db: -6, speed: 0.6, align: "peak", send: 0.45 });
		tr.sfx("hammer_burst", T.erupt, { db: -8, speed: 0.7, align: "peak" });
		bombs(tr, T.erupt + 0.2, 10, 0.07, 0.75, -20, 391);
		// 火砕流: 低く長い轟き・風・砂の音
		tr.put(rumble({ sec: 1.8, cutoff: 110, seed: 401, env: (_, u) => smooth(0, 0.1, u) * fall(u, 1.1) }), T.surge, { db: -9 });
		tr.sfx("wind_burst", T.surge, { db: -10, speed: 0.45, send: 0.4 });
		tr.put(sweepNoise({ sec: 1.6, f0: 1400, f1: 200, q: 0.8, curve: 0.8, seed: 403, env: (_, u) => smooth(0, 0.08, u) * fall(u, 1.2) }), T.surge, { db: -13, send: 0.3 });
		tr.sfx("encounter/golem_pebbles", T.surge + 0.3, { db: -16, speed: 0.8 });
	},
	// 登場（2026-11-14）: 右上から唸りながら落ちてくる → 着地（地響き・飛沫）→ 煮え立ちながら震える（鼓動がだんだん速く）→ 一気に爆発 → 巨人が踏みしめる
	intro(tr, T) {
		tr.put(sweepNoise({ sec: T.land - T.fall0 + 0.02, f0: 2600, f1: 260, q: 1.0, curve: 0.6, seed: 601, env: swell(0, 0.95, 1.0) }), T.fall0, { db: -14, pan: 0.4, send: 0.2 });
		tr.put(flame({ sec: T.land - T.fall0 + 0.05, f: 260, q: 0.6, seed: 603, env: swell(0, 0.9, 1.0), flutter: 0.7 }), T.fall0, { db: -14, pan: 0.3 });
		tr.sfx("encounter/golem_slam", T.land, { db: -8, speed: 0.85, align: "peak" });
		tr.sfx("hammer_impact", T.land, { db: -10, speed: 0.7, align: "peak" });
		tr.put(subDrop({ sec: 1.0, f0: 72, f1: 26, decay: 3.2, seed: 605 }), T.land, { db: -8 });
		tr.sfx("encounter/slime_splat", T.land + 0.02, { db: -13, speed: 0.6, align: "peak", send: 0.2 });
		tr.sfx("encounter/golem_pebbles", T.land + 0.06, { db: -16 });
		simmer(tr, T.land + 0.2, T.boom - T.land - 0.2, -20, 607);
		tr.sfx("encounter/golem_rumble", T.tremble, { db: -16, speed: 0.85 });
		build(tr, T.tremble, T.boom, -15, 609, 40, 130);
		const n = 7;
		for (let i = 0; i < n; i++) {
			const u = i / n;
			const te = T.tremble + (T.boom - T.tremble) * (1 - Math.pow(1 - u, 1.6));
			beat(tr, te, -17 + 6 * u, 611 + i * 2);
		}
		boomCore(tr, T.boom, -5, 631, 2.2);
		tr.sfx("encounter/dragon_detonation", T.boom, { db: -9, speed: 0.9, align: "peak", send: 0.3 });
		tr.sfx("hammer_burst", T.boom, { db: -10, speed: 0.8, align: "peak", send: 0.3 });
		geyser(tr, T.boom + 0.02, -11, 633);
		bombs(tr, T.boom + 0.1, 10, 0.06, 0.75, -17, 641);
		tr.sfx("boss_move_heavy", T.stance - 0.05, { db: -14, speed: 0.75 });
		simmer(tr, T.boom + 0.6, T.end - T.boom - 0.6, -24, 661);
	},
	// 支援・回復: 溶岩が湧く（泡）→ 玉が昇って炉へ吸い込まれる → 炉が燃え上がる（癒し）・湯気
	pre_support_heal(tr, T) {
		tr.sfx("encounter/slime_bubble", T.flow, { db: -18, speed: 0.7, pan: 0.2 });
		simmer(tr, T.flow, T.back - T.flow, -21, 671, 0.2);
		tr.put(flame({ sec: T.impact - T.gather, f: 220, q: 0.6, seed: 673, env: swell(0, 0.9, 1.0), flutter: 0.5 }), T.gather, { db: -17, pan: 0.2 });
		for (let i = 0; i < 4; i++) tr.sfx("encounter/slime_drip", T.gather + i * 0.15, { db: -22, speed: 0.7 + i * 0.05, pan: 0.2 });
		tr.sfx("heal_hp", T.impact, { db: -12, speed: 0.85, pan: 0.2, send: 0.4 });
		tr.sfx("fire_cast", T.impact, { db: -16, speed: 0.7, pan: 0.2, send: 0.2 });
		tr.sfx("encounter/slime_fizz", T.impact + 0.15, { db: -20, speed: 0.9, pan: 0.2, send: 0.3 });
	},
	// 支援・強化: 炉が唸る → 煙突から火柱（2本）→ 強化の音
	pre_support_buff(tr, T) {
		tr.sfx("encounter/golem_rumble", T.pose, { db: -19, speed: 1.0, pan: 0.2 });
		build(tr, T.gather - 0.1, T.impact, -18, 681, 50, 140);
		geyser(tr, T.impact, -12, 683, 0.15, 0.8);
		geyser(tr, T.impact + 0.06, -14, 685, 0.3, 0.7);
		tr.sfx("buff_atk", T.impact, { db: -12, speed: 0.85, pan: 0.2, send: 0.3 });
		tr.sfx("fire_burst", T.impact + 0.02, { db: -15, speed: 0.8, pan: 0.2, send: 0.2 });
	},
	post_support_heal(tr, T) {
		lava.pre_support_heal(tr, T);
		tr.put(subDrop({ sec: 0.7, f0: 64, f1: 30, decay: 4, seed: 691 }), T.impact, { db: -15 });
		tr.sfx("wind_burst", T.impact, { db: -20, speed: 0.5, pan: 0.2, send: 0.3 });
	},
	post_support_buff(tr, T) {
		lava.pre_support_buff(tr, T);
		tr.put(subDrop({ sec: 0.9, f0: 70, f1: 28, decay: 3.6, seed: 693 }), T.impact, { db: -12 });
		tr.sfx("wind_burst", T.impact, { db: -16, speed: 0.45, pan: 0.2, send: 0.35 });
	},
	// 撃破（覚醒前）: 火が消えていく（湯気の音・沈む唸り）→ ひび → 崩れる（岩が転げ落ちる）→ 残り火が冷える
	pre_defeat(tr, T) {
		tr.put(drone({ sec: T.melt - T.cool + 0.3, f0: 110, f1: 40, curve: 0.8, voices: [1, 1.006, 0.5], cutoff: (_, u) => lerp(900, 200, u), env: swell(0, 0.2, 0.9), seed: 701 }), T.cool, { db: -18, pan: 0.15 });
		tr.sfx("encounter/slime_fizz", T.cool, { db: -16, speed: 0.6, pan: 0.15, send: 0.3 });
		tr.put(sweepNoise({ sec: T.melt - T.cool + 0.4, f0: 5200, f1: 2200, q: 1.0, curve: 1.0, seed: 703, env: swell(0, 0.2, 0.9) }), T.cool, { db: -24, pan: 0.15 });
		tr.sfx("encounter/golem_crack", T.crack, { db: -13, speed: 1.0, align: "peak", pan: 0.15 });
		tr.sfx("encounter/golem_crumble", T.melt, { db: -10, speed: 0.9, pan: 0.1, send: 0.2 });
		for (let i = 0; i < 6; i++) tr.sfx("encounter/golem_pebbles", T.melt + 0.15 + i * 0.18, { db: -18 + (i % 2) * 2, speed: 0.9 + (i % 3) * 0.1, pan: -0.1 + (i % 3) * 0.1 });
		tr.put(rumble({ sec: T.gone - T.melt, cutoff: 80, seed: 705, env: swell(0, 0.2, 0.9) }), T.melt, { db: -16 });
		tr.sfx("encounter/slime_fizz", T.gone + 0.2, { db: -22, speed: 0.5, pan: 0.1, send: 0.3 });
	},
	// 撃破（覚醒後）: 熱が暴れ出す（鼓動が速まる・噴き出し）→ 最後の大噴火 → 崩れる → 冷えていく
	post_defeat(tr, T) {
		build(tr, T.surge, T.erupt, -14, 711, 40, 140);
		tr.sfx("encounter/golem_rumble", T.surge, { db: -15, speed: 0.8 });
		for (let i = 0; i < 4; i++) geyser(tr, T.surge + 0.5 + i * 0.15, -18, 713 + i * 3, -0.4 + i * 0.27, 0.6);
		const n = 6;
		for (let i = 0; i < n; i++) {
			const u = i / n;
			beat(tr, T.surge + (T.erupt - T.surge) * (1 - Math.pow(1 - u, 1.7)), -17 + 6 * u, 731 + i * 2);
		}
		boomCore(tr, T.erupt, -4, 751, 2.4);
		tr.sfx("encounter/dragon_detonation", T.erupt, { db: -8, speed: 0.8, align: "peak", send: 0.3 });
		tr.sfx("hammer_burst", T.erupt, { db: -10, speed: 0.75, align: "peak", send: 0.3 });
		tr.put(flame({ sec: 1.6, f: 200, q: 0.5, seed: 753, env: hitDecay(0.9, 0.02), flutter: 0.4 }), T.erupt, { db: -9, send: 0.3 });
		bombs(tr, T.erupt + 0.15, 12, 0.07, 0.8, -17, 761);
		tr.sfx("encounter/golem_crumble", T.erupt + 0.6, { db: -12, speed: 0.85, send: 0.2 });
		for (let i = 0; i < 5; i++) tr.sfx("encounter/golem_pebbles", T.erupt + 0.8 + i * 0.2, { db: -19, speed: 0.9 + (i % 3) * 0.1, pan: -0.1 + (i % 3) * 0.1 });
		tr.sfx("encounter/slime_fizz", T.erupt + 1.6, { db: -18, speed: 0.5, send: 0.3 });
	},
};

// =============================== 振り子の給仕長 / 終刻の給仕長 ===============================

const only = process.argv.slice(2);
fs.mkdirSync(path.join(HERE, "out"), { recursive: true });
for (const [move, fn] of Object.entries(lava)) {
	if (only.length && !only.includes(move)) continue;
	// 支援の回復・強化は同じ時刻（pre_support / post_support）
	const info = TIMING[move.replace(/_(heal|buff)$/, "")];
	const tr = new Track(info);
	fn(tr, info.T);
	const { out } = tr.finish();
	wavWrite(path.join(HERE, "out", NAMES[move] + ".wav"), out);
	console.log(`lava/${move} → ${NAMES[move]}.wav: ${(out[0].length / SR).toFixed(2)}秒`);
}
