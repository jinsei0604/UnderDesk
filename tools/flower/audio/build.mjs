// 白磁のカラー／喪華のカラー女王（flower）の効果音（2026-11-14〜16 ユーザーが確認動画で採用した音。試作 prototypes/four_bosses_2026-11-11/audio/build.mjs の flower をそのまま移した）。
// 時刻は timing.json（tools/flower/dump_flower_timing.gd が本番のエフェクトの T・ヒットストップから書き出す）。
// 使い方: godot --headless --path . --script res://tools/flower/dump_flower_timing.gd → node tools/flower/audio/build.mjs [技の名前 ...] → tools/flower/audio/out/<名前>.wav
// できた音は同じ名前で assets_bossmaker/audio/flower/ へ置く（置いた後に --import）。名前の対応は NAMES（技 → 音の名前）。
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
/** 技 → assets_bossmaker/audio/flower/ の音の名前 */
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


// =============================== 白磁のカラー / 喪華のカラー女王 ===============================
const flower = {
	pre_single(tr, T) {
		tr.sfx("wind_cast", T.windup, { db: -22, speed: 1.1, pan: 0.2 });
		tr.put(bell(2350, 0.8, 9, 111), T.windup + 0.1, { db: -27, pan: 0.2, send: 0.5 });
		tr.sfx("samurai_iai_draw", T.thrust, { db: -11, speed: 1.2, align: "peak", pan: 0.0 });
		tr.put(rip({ sec: 0.18, seed: 113, f0: 900, f1: 2600 }), T.thrust + 0.01, { db: -18, pan: -0.1 });
		tr.sfx("neutral_impact_light", T.contact, { db: -9, align: "peak", pan: -0.15 });
		tr.sfx("wind_burst", T.contact, { db: -18, speed: 1.25, pan: -0.15, send: 0.3 });
		tr.sfx("encounter/sparkle", T.contact + 0.05, { db: -23, speed: 1.1, pan: -0.2, send: 0.4 });
	},
	// ②（2026-11-13 改）: 足元に白磁の大輪が開く → お辞儀 → 花びらの嵐 → 崩れて放たれる
	pre_all(tr, T) {
		tr.sfx("heal_sp", T.charge, { db: -20, speed: 0.8, pan: 0.2, send: 0.4 });
		tr.put(choir(T.open - T.charge, 330, -24, 121, [1, 1.25, 1.5, 2]), T.charge, { db: -24, pan: 0.2, send: 0.5 });
		for (let i = 0; i < 5; i++) tr.put(bell(1760 + i * 220, 0.6, 7, 191 + i, [1, 2.0, 2.76]), T.charge + i * 0.12 + 0.2, { db: -28, pan: 0.15, send: 0.5 });
		tr.put(sweepNoise({ sec: T.open - T.release + 0.1, f0: 300, f1: 2000, q: 1.1, curve: 1.2, seed: 123, env: swell(0, 0.7, 0.95) }), T.release, { db: -18, pan: -0.2, send: 0.3 });
		tr.sfx("wind_cast", T.release, { db: -18, speed: 0.7, pan: -0.2, send: 0.3 });
		tr.put(bell(660, 2.2, 2.4, 125, [1, 1.25, 1.5, 2, 2.5]), T.open - 0.1, { db: -17, pan: -0.2, send: 0.6 });
		tr.sfx("encounter/gent_bow", T.bow, { db: -16, speed: 1.1, pan: 0.2, send: 0.3 });
		tr.sfx("encounter/sparkle", T.bow + 0.05, { db: -21, speed: 1.2, pan: 0.2, send: 0.5 });
		T.storm.forEach((st, i) => tr.sfx("neutral_impact_light", st, { db: -19, speed: 1.0 + i * 0.05, align: "peak", pan: -0.3 + i * 0.15 }));
		tr.sfx("wind_move", T.storm[0] - 0.1, { db: -17, speed: 1.0, pan: -0.2, send: 0.3 });
		tr.sfx("wind_burst", T.burst, { db: -10, speed: 0.8, send: 0.35 });
		tr.sfx("heal_hp", T.burst, { db: -14, speed: 1.0, send: 0.5 });
		tr.put(subDrop({ sec: 0.8, f0: 70, f1: 34, decay: 4, seed: 127 }), T.burst, { db: -13 });
		tr.put(shatter({ sec: 1.0, count: 70, seed: 129, f0: 3000, f1: 9000 }), T.burst + 0.02, { db: -24, send: 0.4 });
	},
	// ③（2026-11-13 作り直し）: うなだれ → 根・地鳴り → 幹がきしみながら伸びる → 枝 → 花が次々と咲く（鈴）→ 満開の和音
	// → 一気に枯れる（乾いた音・沈む低音）→ ひび（5回）と鼓動 → 砕ける（木の破片・花びらの嵐）→ 覚醒後の姿（低い鐘）
	awaken(tr, T) {
		tr.put(choir(T.trunk + 0.4, 523, -26, 131, [1, 1.5, 2]), 0, { db: -26, pan: 0.2, send: 0.5 });
		tr.sfx("encounter/ghost_whisper", T.distress, { db: -17, speed: 0.8, pan: 0.2, send: 0.3 });
		tr.sfx("encounter/golem_crack", T.roots, { db: -15, speed: 1.1, align: "peak", pan: 0.2 });
		tr.put(rumble({ sec: T.trunk_end - T.roots + 0.2, cutoff: 90, seed: 201, env: swell(0, 0.4, 0.95) }), T.roots, { db: -15 });
		tr.sfx("encounter/golem_pebbles", T.roots + 0.05, { db: -22, speed: 1.2, pan: 0.2 });
		tr.put(drone({ sec: T.trunk_end - T.trunk, f0: 60, f1: 90, curve: 1.2, voices: [1, 1.04, 0.5, 1.5], cutoff: (_, u) => lerp(300, 900, u), env: swell(0, 0.6, 0.95), seed: 203 }), T.trunk, { db: -17, pan: 0.15, send: 0.2 });
		tr.put(crackle({ sec: T.branch_end - T.trunk, density: 14, seed: 205, env: swell(0, 0.5, 0.9) }), T.trunk, { db: -22, pan: 0.15 });
		tr.sfx("boss_move_heavy", T.trunk + 0.2, { db: -18, speed: 0.6, pan: 0.15 });
		for (let i = 0; i < 4; i++) tr.put(crackle({ sec: 0.18, density: 60, seed: 211 + i, env: hitDecay(1.2, 0.01) }), T.branch + i * 0.2, { db: -20, pan: -0.1 + i * 0.12 });
		for (let i = 0; i < 9; i++) tr.put(bell(1320 + (i % 4) * 165, 0.9, 5, 221 + i, [1, 2.0, 2.76]), T.bloom + i * 0.08, { db: -25 + (i % 3), pan: -0.3 + (i % 5) * 0.15, send: 0.6 });
		tr.put(choir(T.wither - T.bloom_end + 0.3, 392, -21, 233, [1, 1.25, 1.5, 2]), T.bloom_end - 0.3, { db: -21, pan: 0.1, send: 0.6 });
		tr.sfx("encounter/sparkle", T.bloom_end - 0.1, { db: -19, speed: 0.9, send: 0.5, pan: 0.1 });
		// 一気に枯れる
		tr.put(reverse(sweepNoise({ sec: 0.7, f0: 300, f1: 3000, q: 1, curve: 0.8, seed: 235, env: hitDecay(1.0, 0.02) })), T.wither - 0.2, { db: -17, pan: 0.1, send: 0.3 });
		tr.put(crackle({ sec: T.wither_end - T.wither + 0.2, density: 40, seed: 237, env: swell(0, 0.3, 0.9) }), T.wither, { db: -19, pan: 0.1 });
		tr.sfx("wind_move", T.wither, { db: -17, speed: 0.6, pan: 0.1, send: 0.3 });
		tr.put(drone({ sec: T.burst - T.wither, f0: 98, f1: 52, curve: 0.9, voices: [1, 1.19, 0.5, 1.41], cutoff: (_, u) => lerp(1200, 300, u), env: swell(0, 0.3, 0.97), seed: 239 }), T.wither, { db: -17, send: 0.3 });
		// ひびと鼓動
		for (let i = 0; i < 5; i++) tr.sfx("ice_impact_light", T.crack + i * 0.09, { db: -18 + i * 0.5, speed: 1.3 - i * 0.08, align: "peak", pan: 0.15 });
		for (let k = 0; T.crack + 0.1 + k * 0.17 < T.burst; k++) beat(tr, T.crack + 0.1 + k * 0.17, -17 + k * 1.2, 241 + k * 2);
		build(tr, T.crack, T.burst, -16, 251, 52, 120);
		// 砕ける → 覚醒後の姿
		tr.sfx("wind_burst", T.burst, { db: -7, speed: 0.5, send: 0.4 });
		boomCore(tr, T.burst, -8, 253, 2.0);
		tr.sfx("encounter/golem_crumble", T.burst, { db: -12, speed: 1.1, align: "peak", pan: 0.15 });
		tr.put(shatter({ sec: 1.2, count: 90, seed: 255, f0: 1600, f1: 6000 }), T.burst + 0.02, { db: -20, send: 0.4 });
		tr.sfx("encounter/ghost_shriek", T.burst + 0.02, { db: -16, speed: 0.6, pan: 0.15, send: 0.4 });
		tr.put(bell(262, 2.8, 1.6, 257, [1, 1.19, 1.5, 2.0, 2.38]), T.done, { db: -13, send: 0.6 });
		tr.sfx("encounter/gent_vanish", T.done + 0.05, { db: -17, speed: 0.8, send: 0.3 });
		tr.put(choir(1.6, 196, -18, 259, [1, 1.19, 1.5, 2]), T.done + 0.1, { db: -19, send: 0.6 });
	},
	// ④（2026-11-13 作り直し）: 両手に蔦が絡む → 両手で払う（2本の裂く音）・地面から2本 → 巻き付き → 締め上げ → 喪華が咲いて弾ける
	post_single(tr, T) {
		tr.sfx("encounter/slime_stretch", T.windup, { db: -18, speed: 0.7, pan: 0.2 });
		tr.sfx("encounter/ghost_whisper", T.windup + 0.1, { db: -22, speed: 0.9, pan: 0.2 });
		tr.put(sweepNoise({ sec: T.lash - T.windup, f0: 300, f1: 1600, q: 1, curve: 1.5, seed: 159, env: swell(0, 0.85, 0.97) }), T.windup, { db: -22, pan: 0.2 });
		tr.sfx("samurai_iai_draw", T.lash, { db: -11, speed: 0.9, align: "peak", pan: -0.1 });
		tr.sfx("samurai_iai_draw", T.lash + 0.03, { db: -13, speed: 0.78, align: "peak", pan: 0.15 });
		tr.put(rip({ sec: 0.22, seed: 161, f0: 700, f1: 2400 }), T.lash + 0.02, { db: -15, pan: -0.1 });
		tr.put(rip({ sec: 0.24, seed: 163, f0: 500, f1: 1800 }), T.lash + 0.06, { db: -16, pan: 0.1 });
		tr.sfx("encounter/golem_crack", T.lash + 0.06, { db: -18, speed: 1.3, align: "peak", pan: -0.3 });
		tr.sfx("guard_hit", T.wrap, { db: -13, speed: 0.8, align: "peak", pan: -0.2 });
		tr.sfx("encounter/slime_stretch", T.wrap + 0.05, { db: -17, speed: 0.55, pan: -0.2 });
		tr.put(crackle({ sec: T.squeeze - T.wrap, density: 30, seed: 165, env: swell(0, 0.8, 0.95) }), T.wrap, { db: -21, pan: -0.2 });
		tr.sfx("encounter/slime_splat", T.squeeze, { db: -12, speed: 0.7, align: "peak", pan: -0.2 });
		tr.sfx("wind_burst", T.squeeze, { db: -11, speed: 0.8, pan: -0.2, send: 0.3 });
		boomCore(tr, T.squeeze, -11, 167, 1.2);
		tr.put(bell(440, 1.6, 2.6, 169, [1, 1.19, 1.5, 2.0]), T.squeeze, { db: -18, pan: -0.2, send: 0.5 });
		tr.put(shatter({ sec: 0.8, count: 50, seed: 171, f0: 2000, f1: 7000 }), T.squeeze + 0.02, { db: -22, pan: -0.2, send: 0.4 });
	},
	// ⑤（2026-11-13 質を上げた版）: 沈む → 背に喪華が開く → 蔦が立ち上がって巻き付く → 蕾 → 花びらの波 → 順に開花（鈴・光の柱）→ 一斉に弾ける
	post_all(tr, T) {
		tr.put(drone({ sec: T.burst - T.dark, f0: 82, f1: 98, voices: [1, 1.19, 0.5, 1.41], cutoff: 900, env: swell(0, 0.3, 0.97), seed: 171 }), T.dark, { db: -18, send: 0.3 });
		tr.put(choir(T.wave - T.halo, 196, -22, 172, [1, 1.19, 1.5, 2]), T.halo, { db: -22, pan: 0.2, send: 0.6 });
		tr.put(bell(294, 2.0, 2.2, 174, [1, 1.19, 1.5, 2.0, 2.38]), T.halo + 0.2, { db: -19, pan: 0.2, send: 0.6 });
		tr.put(sweepNoise({ sec: T.wave - T.charge, f0: 600, f1: 1600, q: 2.0, curve: 1, seed: 173, env: swell(0, 0.3, 0.95) }), T.charge, { db: -23, pan: 0.1, send: 0.4 });
		for (let i = 0; i < 4; i++) tr.sfx("encounter/slime_stretch", T.vines + i * 0.08, { db: -17, speed: 0.6 + i * 0.05, pan: -0.4 + i * 0.2 });
		tr.put(rumble({ sec: 0.8, cutoff: 80, seed: 175, env: swell(0, 0.4, 0.9) }), T.vines, { db: -17 });
		tr.put(sweepNoise({ sec: T.bloom - T.buds, f0: 200, f1: 800, q: 1, curve: 1.6, seed: 177, env: swell(0, 0.8, 0.97) }), T.buds, { db: -19, send: 0.2 });
		tr.sfx("wind_move", T.wave, { db: -13, speed: 0.75, pan: 0.0, send: 0.35 });
		tr.put(sweepNoise({ sec: 0.5, f0: 2600, f1: 500, q: 1, curve: 0.7, seed: 178, env: hitDecay(1.1, 0.02) }), T.wave, { db: -17, pan: -0.2, send: 0.3 });
		for (let i = 0; i < 4; i++) {
			tr.put(bell(880 + i * 110, 1.2, 4, 180 + i, [1, 2.0, 2.76]), T.bloom + i * 0.06, { db: -21, pan: -0.4 + i * 0.2, send: 0.6 });
			tr.put(beam({ sec: 0.4, f0: 1400, f1: 400, seed: 186 + i }), T.bloom + i * 0.06, { db: -24, pan: -0.4 + i * 0.2, send: 0.3 });
		}
		tr.sfx("wind_burst", T.bloom, { db: -13, speed: 0.8, send: 0.35 });
		tr.sfx("encounter/sparkle", T.bloom + 0.05, { db: -20, speed: 0.8, send: 0.5 });
		tr.sfx("wind_burst", T.burst, { db: -6, speed: 0.5, send: 0.4 });
		boomCore(tr, T.burst, -7, 181, 2.2);
		tr.sfx("encounter/ghost_shriek", T.burst, { db: -17, speed: 0.5, send: 0.4 });
		tr.put(shatter({ sec: 1.3, count: 90, seed: 183, f0: 2000, f1: 7000 }), T.burst + 0.02, { db: -20, send: 0.4 });
		tr.put(choir(1.8, 196, -16, 185, [1, 1.19, 1.5, 2]), T.burst, { db: -17, send: 0.6 });
	},
	// 登場（2026-11-14）: 風が立ち、花びらのざわめきがだんだん大きく → 覆い隠す所で和音が満ちる → 一陣の風（吹き抜け）で晴れる → 鐘とお辞儀 → 顔を上げる
	intro(tr, T) {
		tr.put(sweepNoise({ sec: T.cover + 0.5, f0: 300, f1: 2400, q: 0.8, curve: 1.6, seed: 501, env: (_, u) => smooth(0, 1, u) * smooth(0, 1, u) }), 0, { db: -17, pan: 0.1, send: 0.3 });
		tr.sfx("wind_move", 0.4, { db: -24, speed: 0.7, pan: 0.3 });
		tr.sfx("wind_cast", 1.2, { db: -19, speed: 0.75, pan: 0.2, send: 0.3 });
		tr.put(crackle({ sec: T.clear - 0.6, density: 30, seed: 503, env: (_, u) => smooth(0.1, 0.9, u) * (1 - smooth(0.97, 1, u)) }), 0.6, { db: -24, pan: -0.1 });
		tr.put(choir(T.clear - 1.2, 392, -21, 505, [1, 1.25, 1.5, 2]), 1.2, { db: -21, send: 0.6 });
		tr.sfx("wind_burst", T.clear - 0.08, { db: -11, speed: 0.75, pan: -0.3, send: 0.35 });
		tr.put(sweepNoise({ sec: 0.8, f0: 2600, f1: 300, q: 0.9, curve: 0.7, seed: 507, env: hitDecay(1.1, 0.04) }), T.clear, { db: -15, pan: -0.4 });
		tr.put(bell(660, 2.4, 2.2, 509, [1, 1.25, 1.5, 2, 2.5]), T.clear + 0.15, { db: -17, pan: 0.2, send: 0.6 });
		tr.sfx("encounter/sparkle", T.clear_end - 0.1, { db: -21, speed: 0.9, pan: 0.2, send: 0.5 });
		tr.sfx("encounter/gent_bow", T.rise - 0.05, { db: -17, speed: 1.15, pan: 0.2, send: 0.3 });
		tr.put(bell(990, 1.2, 4, 511, [1, 2.0, 2.76]), T.rise + 0.05, { db: -25, pan: 0.2, send: 0.5 });
	},
	// 支援・回復: 足元に花が咲く（鈴）→ 光が降りる（和音）→ 癒しの音
	pre_support_heal(tr, T) {
		tr.sfx("heal_sp", T.bloom, { db: -21, speed: 0.85, pan: 0.2, send: 0.4 });
		for (let i = 0; i < 4; i++) tr.put(bell(1320 + i * 220, 0.7, 6, 521 + i, [1, 2.0, 2.76]), T.bloom + 0.05 + i * 0.09, { db: -27, pan: 0.2, send: 0.5 });
		tr.put(choir(T.back - T.gather, 523, -22, 525, [1, 1.25, 1.5, 2]), T.gather, { db: -22, pan: 0.2, send: 0.6 });
		tr.sfx("heal_hp", T.impact, { db: -12, speed: 1.0, pan: 0.2, send: 0.4 });
		tr.sfx("encounter/sparkle", T.impact + 0.05, { db: -20, speed: 1.1, pan: 0.2, send: 0.5 });
	},
	// 支援・強化: 花の輪が回る（鈴が速まる）→ 一斉に弾ける（風・強化の音）
	pre_support_buff(tr, T) {
		tr.sfx("wind_cast", T.bloom, { db: -20, speed: 1.0, pan: 0.2, send: 0.3 });
		for (let i = 0; i < 6; i++) tr.put(bell(1760 + (i % 3) * 220, 0.5, 8, 531 + i, [1, 2.0, 2.76]), T.bloom + i * (0.16 - i * 0.012), { db: -27, pan: 0.1 + (i % 3) * 0.1, send: 0.5 });
		tr.put(sweepNoise({ sec: T.impact - T.gather, f0: 400, f1: 2400, q: 1.0, curve: 1.3, seed: 537, env: swell(0, 0.9, 1.0) }), T.gather, { db: -20, pan: 0.2 });
		tr.sfx("buff_atk", T.impact, { db: -12, speed: 1.0, pan: 0.2, send: 0.3 });
		tr.sfx("wind_burst", T.impact, { db: -15, speed: 1.1, pan: 0.2, send: 0.3 });
		tr.put(shatter({ sec: 0.7, count: 40, seed: 539, f0: 3000, f1: 8000 }), T.impact + 0.02, { db: -26, pan: 0.2, send: 0.4 });
	},
	// 覚醒後の支援（喪華）: 低い鐘・ささやき・暗い和音
	post_support_heal(tr, T) {
		tr.sfx("encounter/ghost_whisper", T.pose, { db: -21, speed: 0.9, pan: 0.2, send: 0.3 });
		for (let i = 0; i < 4; i++) tr.put(bell(880 + i * 110, 0.8, 5, 541 + i, [1, 2.0, 2.76]), T.bloom + 0.05 + i * 0.1, { db: -26, pan: 0.2, send: 0.5 });
		tr.put(choir(T.back - T.gather, 262, -21, 545, [1, 1.19, 1.5, 2]), T.gather, { db: -21, pan: 0.2, send: 0.6 });
		tr.sfx("heal_hp", T.impact, { db: -12, speed: 0.85, pan: 0.2, send: 0.4 });
		tr.put(subDrop({ sec: 0.6, f0: 70, f1: 40, decay: 5, seed: 547 }), T.impact, { db: -18 });
	},
	post_support_buff(tr, T) {
		tr.sfx("encounter/ghost_whisper", T.pose, { db: -20, speed: 0.8, pan: 0.2, send: 0.3 });
		for (let i = 0; i < 6; i++) tr.put(bell(990 + (i % 3) * 165, 0.6, 7, 551 + i, [1, 2.0, 2.76]), T.bloom + i * (0.16 - i * 0.012), { db: -27, pan: 0.1 + (i % 3) * 0.1, send: 0.5 });
		tr.put(drone({ sec: T.impact - T.gather + 0.2, f0: 60, f1: 120, curve: 1.3, voices: [1, 1.006, 0.5, 1.498], cutoff: (_, u) => lerp(300, 1400, u), env: swell(0, 0.9, 0.97), seed: 557 }), T.gather, { db: -18, pan: 0.15 });
		tr.sfx("buff_atk", T.impact, { db: -11, speed: 0.85, pan: 0.2, send: 0.3 });
		tr.sfx("wind_burst", T.impact, { db: -14, speed: 0.8, pan: 0.2, send: 0.35 });
		tr.put(subDrop({ sec: 0.8, f0: 76, f1: 34, decay: 4, seed: 559 }), T.impact, { db: -14 });
	},
	// 撃破（覚醒前）: 乾いた音で褪せる → 風で花びらが吹かれていく → 一輪の花（澄んだ鐘）
	pre_defeat(tr, T) {
		tr.put(crackle({ sec: T.melt - T.wither + 0.3, density: 12, seed: 561, env: swell(0, 0.4, 0.9) }), T.wither, { db: -24, pan: 0.2 });
		tr.put(drone({ sec: T.gone - T.wither, f0: 330, f1: 196, curve: 0.8, voices: [1, 1.5, 2], cutoff: 1400, env: swell(0, 0.3, 0.9), seed: 563 }), T.wither, { db: -24, pan: 0.2, send: 0.5 });
		tr.sfx("wind_move", T.melt - 0.1, { db: -16, speed: 0.8, pan: -0.2, send: 0.3 });
		tr.put(sweepNoise({ sec: T.gone - T.melt + 0.6, f0: 2200, f1: 500, q: 0.9, curve: 0.8, seed: 565, env: swell(0, 0.3, 0.95) }), T.melt, { db: -19, pan: -0.4, send: 0.3 });
		tr.sfx("encounter/sparkle", T.gone - 0.3, { db: -24, speed: 0.8, pan: -0.3, send: 0.5 });
		tr.put(bell(1046, 2.6, 2.2, 567, [1, 2.0, 2.76, 3.42]), T.remain + 0.2, { db: -19, pan: 0.2, send: 0.7 });
	},
	// 撃破（覚醒後）: 花びらの渦が強まる → 大輪が開く（低い鐘）→ 一気に枯れる → 弾ける（風・砕け・低音）→ ほどける → 喪華の鐘
	post_defeat(tr, T) {
		tr.put(sweepNoise({ sec: T.burst - T.storm, f0: 300, f1: 2400, q: 0.9, curve: 1.5, seed: 571, env: swell(0, 0.95, 1.0) }), T.storm, { db: -16, pan: 0.2, send: 0.3 });
		tr.sfx("encounter/ghost_whisper", T.storm, { db: -18, speed: 0.75, pan: 0.2, send: 0.4 });
		tr.put(bell(330, 2.4, 2.0, 573, [1, 1.19, 1.5, 2]), T.bloom, { db: -16, pan: 0.2, send: 0.6 });
		tr.put(crackle({ sec: T.burst - T.wither, density: 40, seed: 575, env: swell(0, 0.8, 1.0) }), T.wither, { db: -19, pan: 0.2 });
		tr.put(subDrop({ sec: T.burst - T.wither, f0: 110, f1: 50, decay: 0.5, seed: 577 }), T.wither, { db: -20 });
		boomCore(tr, T.burst, -9, 579, 1.6);
		tr.sfx("wind_burst", T.burst, { db: -9, speed: 0.7, send: 0.4 });
		tr.sfx("encounter/ghost_shriek", T.burst, { db: -18, speed: 0.55, send: 0.4 });
		tr.put(shatter({ sec: 1.2, count: 80, seed: 581, f0: 2000, f1: 7000 }), T.burst + 0.02, { db: -20, send: 0.4 });
		tr.put(sweepNoise({ sec: T.gone - T.burst + 0.6, f0: 1800, f1: 300, q: 0.9, curve: 0.8, seed: 583, env: swell(0, 0.2, 0.95) }), T.burst + 0.2, { db: -19, pan: -0.4, send: 0.3 });
		tr.put(bell(523, 2.6, 2.0, 585, [1, 1.19, 1.5, 2]), T.remain + 0.2, { db: -19, pan: 0.2, send: 0.7 });
	},
};


const only = process.argv.slice(2);
fs.mkdirSync(path.join(HERE, "out"), { recursive: true });
for (const [move, fn] of Object.entries(flower)) {
	if (only.length && !only.includes(move)) continue;
	// 支援の回復・強化は同じ時刻（pre_support / post_support）
	const info = TIMING[move.replace(/_(heal|buff)$/, "")];
	const tr = new Track(info);
	fn(tr, info.T);
	const { out } = tr.finish();
	wavWrite(path.join(HERE, "out", NAMES[move] + ".wav"), out);
	console.log(`flower/${move} → ${NAMES[move]}.wav: ${(out[0].length / SR).toFixed(2)}秒`);
}
