// 振り子の給仕長／終刻の給仕長（clock）の効果音（2026-11-16〜17 ユーザーが確認動画で採用した音。5技・登場・支援・撃破。試作 prototypes/four_bosses_2026-11-11/audio/build.mjs の clock をそのまま移した）。
// 時刻は timing.json（tools/clock/dump_clock_timing.gd が本番のエフェクトの T・ヒットストップから書き出す）。
// 使い方: godot --headless --path . --script res://tools/clock/dump_clock_timing.gd → node tools/clock/audio/build.mjs [技の名前 ...] → tools/clock/audio/out/<名前>.wav
// できた音は同じ名前で assets_bossmaker/audio/clock/ へ置く（置いた後に --import）。名前の対応は NAMES（技 → 音の名前）。
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
/** 技 → assets_bossmaker/audio/clock/ の音の名前 */
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


// =============================== 振り子の給仕長 / 終刻の給仕長 ===============================
const tick = (tr, te, lvl = -17, speed = 1, pan = 0.1) => tr.sfx("encounter/watch_tick", te, { db: lvl, speed, align: "onset", pan });
// 時が止まる: 高いところから一気に沈む風の音（その後は無音）
const stopFx = (tr, te, lvl = -14) => tr.put(sweepNoise({ sec: 0.32, f0: 3200, f1: 180, q: 1.1, curve: 0.5, seed: Math.floor(te * 997), env: hitDecay(1.2, 0.01) }), te, { db: lvl, send: 0.3 });
// 給仕長の支援（2026-11-16 試作）: 回復＝巻き戻し（逆再生の刻み → 澄んだ二つの鐘）、強化＝早送り（だんだん速くなる刻み → 歯車がかみ合う音）
function clockSupport(tr, T, heal, awakened) {
	tr.sfx("encounter/gent_bow", T.pose - 0.05, { db: -21, pan: 0.2 });
	let t = T.dial;
	let gap = heal ? 0.12 : 0.14;
	while (t < T.impact - 0.04) {
		if (heal) tr.sfx("encounter/watch_tick", t, { db: -19, rev: true, pan: 0.2 });
		else tick(tr, t, -19, 1.0 + (0.14 - gap) * 3.0, 0.2);
		t += gap;
		gap = Math.max(0.035, gap * (heal ? 0.9 : 0.85));
	}
	if (heal) {
		tr.sfx("rewind", T.dial, { db: -16, speed: 1.0, send: 0.3, pan: 0.2 });
		tr.put(bell(2200, 1.4, 5, 431), T.impact, { db: -16, pan: 0.2, send: 0.6 });
		tr.put(bell(1650, 1.4, 5, 432), T.impact + 0.04, { db: -19, pan: 0.2, send: 0.6 });
	} else {
		tr.sfx("encounter/gent_cock", T.impact, { db: -11, speed: 0.8, align: "peak", pan: 0.2 });
		tr.put(bell(880, 1.2, 5, 433, [1, 2, 3]), T.impact, { db: -17, pan: 0.2, send: 0.5 });
	}
	if (awakened) tr.put(drone({ sec: T.impact - T.dial, f0: 90, f1: 140, voices: [1, 1.5], cutoff: 900, env: swell(0, 0.8, 0.98), seed: 435 }), T.dial, { db: -20, send: 0.3 });
}
const clock = {
	// 2026-11-16 v3: 技の意味に合わせて音も作り直し（数より質。止まる前は刻む音、止まっている間は静寂、動き出した瞬間にまとめて鳴る）
	pre_single(tr, T) {
		tr.sfx("encounter/gent_bow", T.draw - 0.08, { db: -21, pan: 0.2 });
		tr.put(bell(2640, 0.45, 12, 301), T.dial, { db: -25, pan: -0.15, send: 0.4 });
		// 三つの刻み（だんだん強く低く）
		T.ticks.forEach((tk, i) => tick(tr, tk, -14 + i * 1.5, 1.0 - i * 0.08, -0.15));
		// 12時: 時が止まる → 静寂（凍った高い音だけ）
		stopFx(tr, T.stop, -12);
		tr.put(subDrop({ sec: 0.4, f0: 90, f1: 40, decay: 6, seed: 302 }), T.stop, { db: -18 });
		tr.sfx("encounter/sheathe", T.appear, { db: -20, speed: 1.3, pan: -0.1 });
		tr.sfx("samurai_iai_draw", T.thrust, { db: -18, speed: 1.6, align: "peak", pan: -0.15 });
		tr.put(drone({ sec: T.resume - T.thrust, f0: 1320, f1: 1320, voices: [1, 2.0], cutoff: 3000, env: swell(0, 0.3, 0.9), seed: 304 }), T.thrust, { db: -31, send: 0.4 });
		// 動き出した瞬間にまとめて届く
		tr.sfx("samurai_iai_draw", T.resume, { db: -9, speed: 1.2, align: "peak", pan: -0.15 });
		tr.sfx("neutral_impact_light", T.resume, { db: -8, align: "peak", pan: -0.15 });
		tr.sfx("ice_burst", T.resume, { db: -12, speed: 1.2, align: "peak", pan: -0.15, send: 0.3 });
		tr.put(shatter({ sec: 0.7, count: 50, seed: 305, f0: 2600, f1: 8000 }), T.resume, { db: -15, pan: -0.15, send: 0.3 });
		tr.put(subDrop({ sec: 0.6, f0: 80, f1: 32, decay: 4, seed: 306 }), T.resume, { db: -12 });
		tr.put(bell(1760, 1.0, 9, 307), T.resume, { db: -19, pan: -0.15, send: 0.5 });
		tr.put(sweepNoise({ sec: 0.2, f0: 1600, f1: 600, q: 1.2, curve: 0.7, seed: 308, env: hitDecay(1.3, 0.02) }), T.back, { db: -22 });
	},
	pre_all(tr, T) {
		tr.sfx("encounter/gent_bow", T.charge - 0.05, { db: -21, pan: 0.2 });
		tr.put(rumble({ sec: T.conduct - T.rise + 0.3, cutoff: 110, seed: 311, env: swell(0, 0.5, 0.95) }), T.rise, { db: -22 });
		// 歯車がかみ合う小さな刻み
		for (let k = 0; T.rise + k * 0.14 < T.conduct; k++) tick(tr, T.rise + k * 0.14, -22, 0.7, -0.3 + (k % 3) * 0.3);
		// 指揮の構え: 針が腕の角度へ跳ぶ
		tr.sfx("encounter/gent_cock", T.conduct, { db: -12, speed: 0.8, align: "peak", pan: 0.1 });
		// 4拍: 拍ごとに深い刻み・針が貫く
		T.beats.forEach((b, i) => {
			tick(tr, b - 0.02, -11, 0.75, -0.3 + i * 0.2);
			tr.sfx("samurai_iai_draw", b + 0.04, { db: -12, speed: 1.35 + i * 0.05, align: "peak", pan: -0.4 + i * 0.2 });
			tr.sfx("neutral_impact_light", b + 0.04, { db: -14, align: "peak", pan: -0.4 + i * 0.2 });
			tr.put(bell(1900 + i * 220, 0.5, 14, 315 + i), b + 0.04, { db: -21, pan: -0.4 + i * 0.2, send: 0.4 });
		});
		// 鐘: 12時で両針が重なり、砕ける
		tr.put(sweepNoise({ sec: 0.16, f0: 400, f1: 2400, q: 1, curve: 1.3, seed: 320, env: swell(0, 0.9, 0.99) }), T.chime - 0.16, { db: -18 });
		tr.sfx("encounter/gent_bell", T.chime, { db: -7, speed: 0.75, send: 0.5 });
		tr.sfx("ice_burst", T.chime, { db: -8, speed: 0.8, align: "peak", send: 0.4 });
		tr.put(shatter({ sec: 1.0, count: 110, seed: 321, f0: 2200, f1: 8000 }), T.chime, { db: -12, send: 0.35 });
		boomCore(tr, T.chime, -10, 322, 1.6);
		tr.put(bell(880, 1.8, 3, 325, [1, 1.5, 2, 3]), T.chime, { db: -16, send: 0.5 });
	},
	awaken(tr, T) {
		// 針が速くなる（秒針の音の間隔が縮む）→ 止まる
		let t = T.spin;
		let gap = 0.24;
		while (t < T.silence - 0.02) {
			tick(tr, t, -18, 1.0 + (0.24 - gap) * 2.0, 0.2);
			t += gap;
			gap = Math.max(0.03, gap * 0.86);
		}
		tr.sfx("encounter/gent_bow", T.distress, { db: -20, speed: 0.8, pan: 0.2 });
		stopFx(tr, T.silence, -12);
		// 静寂 → ひび → 仕組みがかみ合い、振り子が揺れ始める
		tr.sfx("ice_impact_light", T.crack, { db: -13, speed: 0.7, align: "peak", pan: 0.2 });
		tr.sfx("encounter/gent_cock", T.early, { db: -12, speed: 0.55, align: "peak", pan: 0.2 });
		tr.put(rumble({ sec: T.done - T.early, cutoff: 100, seed: 331, env: swell(0, 0.3, 0.98) }), T.early, { db: -20 });
		for (let k = 0; T.early + 0.275 + k * 0.55 < T.split; k++) tr.put(sweepNoise({ sec: 0.45, f0: 260, f1: 640, q: 1, curve: 1, seed: 335 + k, env: swell(0, 0.5, 0.9) }), T.early + 0.275 + k * 0.55, { db: -22, pan: (k % 2 ? 0.25 : -0.25) });
		// 分岐: 振り子が二つに割れる（二つの鐘がずれて鳴る）
		tr.sfx("ice_impact_light", T.split, { db: -11, speed: 0.9, align: "peak" });
		tr.put(bell(1320, 1.4, 4, 337), T.split, { db: -15, pan: -0.4, send: 0.5 });
		tr.put(bell(1247, 1.4, 4, 338), T.split + 0.02, { db: -15, pan: 0.4, send: 0.5 });
		// 過去（逆再生の刻み・左）と未来（速い刻み・右）
		tr.sfx("rewind", T.split + 0.05, { db: -14, speed: 0.8, send: 0.3, pan: -0.3 });
		let r = T.split + 0.1;
		let rg = 0.2;
		while (r < T.done - 0.05) {
			tr.sfx("encounter/watch_tick", r, { db: -20, speed: 1.0, rev: true, pan: -0.45 });
			tick(tr, r + rg * 0.5, -20, 1.15, 0.45);
			r += rg;
			rg = Math.max(0.04, rg * 0.9);
		}
		tr.put(drone({ sec: T.done - T.converge, f0: 80, f1: 170, curve: 1.3, voices: [1, 1.06, 0.5, 1.5], cutoff: (_, u) => lerp(300, 2000, u), env: swell(0, 0.85, 0.99), seed: 341 }), T.converge, { db: -13, send: 0.2 });
		// ぶつかって12時: 鐘の一打 → 砕ける
		tr.sfx("encounter/gent_bell", T.done, { db: -5, speed: 0.6, send: 0.5 });
		tr.put(bell(110, 3.4, 1.2, 343, [1, 2.01, 2.76, 3.42, 4.1]), T.done, { db: -10, send: 0.6 });
		boomCore(tr, T.done, -9, 344, 2.0);
		tr.sfx("ice_burst", T.done, { db: -9, speed: 0.7, align: "peak", send: 0.45 });
		tr.put(shatter({ sec: 1.4, count: 140, seed: 345, f0: 1800, f1: 8000 }), T.done, { db: -12, send: 0.4 });
	},
	post_single(tr, T) {
		// 狂った刻み（だんだん速く）→ 宣告（12時でぴたり）
		let t = T.dial;
		let gap = 0.12;
		while (t < T.sentence - 0.02) {
			tick(tr, t, -17, 0.95 + (0.12 - gap) * 3.0, -0.15);
			t += gap;
			gap = Math.max(0.03, gap * 0.85);
		}
		tr.sfx("encounter/gent_cock", T.sentence, { db: -10, speed: 0.7, align: "peak", pan: -0.15 });
		tr.put(bell(660, 1.0, 5, 350, [1, 2.4, 3.9]), T.sentence, { db: -16, pan: -0.15, send: 0.5 });
		stopFx(tr, T.stop, -12);
		// 止まった時の中で針を一本ずつ置く
		T.places.forEach((p, i) => {
			tr.sfx("encounter/sheathe", p, { db: -19, speed: 1.4, pan: -0.25 + i * 0.15 });
			tick(tr, p + 0.03, -17, 1.3, -0.25 + i * 0.15);
		});
		// 止めていた連撃が次々と届く（6回）
		for (let i = 0; i < 6; i++) {
			const h = T.resume + i * 0.05;
			tr.sfx("samurai_iai_draw", h, { db: -13 + (i === 5 ? 2 : 0), speed: 1.35 + (i % 3) * 0.08, align: "peak", pan: -0.35 + (i % 3) * 0.2 });
			tr.sfx("neutral_impact_light", h, { db: -16, speed: 1.0 + (i % 2) * 0.1, align: "peak", pan: -0.2 });
			if (i % 2 === 0) tr.put(bell(1900 + i * 140, 0.4, 16, 351 + i), h + 0.01, { db: -23, pan: -0.2, send: 0.4 });
		}
		// 執行: 振り子が振り下ろされる
		tr.put(sweepNoise({ sec: T.pendulum - T.resume - 0.04, f0: 200, f1: 1500, q: 1, curve: 1.4, seed: 355, env: swell(0, 0.92, 0.99) }), T.resume + 0.04, { db: -11, pan: 0.1 });
		tr.sfx("neutral_sword_swing", T.pendulum, { db: -9, speed: 0.65, align: "peak", pan: -0.2 });
		tr.sfx("boss_impact_mass", T.pendulum, { db: -8, align: "peak", pan: -0.2 });
		tr.sfx("ice_burst", T.pendulum, { db: -11, speed: 0.9, align: "peak", pan: -0.2, send: 0.3 });
		tr.put(shatter({ sec: 0.9, count: 70, seed: 356, f0: 2000, f1: 8000 }), T.pendulum, { db: -14, pan: -0.2, send: 0.3 });
		tr.put(subDrop({ sec: 0.8, f0: 70, f1: 28, decay: 3.5, seed: 357 }), T.pendulum, { db: -10 });
		tr.put(bell(1320, 1.2, 6, 358, [1, 2.76, 5.4]), T.pendulum, { db: -16, pan: -0.2, send: 0.5 });
	},
	post_all(tr, T) {
		tr.put(drone({ sec: T.stop - T.dark, f0: 55, f1: 62, voices: [1, 1.006, 0.5, 2.0], cutoff: 400, env: swell(0, 0.3, 0.97), seed: 361 }), T.dark, { db: -16, send: 0.2 });
		// 四人の時計の速い刻み（左右に散らす）
		for (let k = 0; T.dials + k * 0.09 < T.stop; k++) tick(tr, T.dials + k * 0.09, -19, 1.1, -0.45 + (k % 4) * 0.3);
		tr.put(crackle({ sec: T.stop - T.dials, density: 20, seed: 363, env: swell(0, 0.4, 0.95) }), T.dials, { db: -24 });
		tr.sfx("encounter/gent_bow", T.release - 0.08, { db: -19, pan: 0.2 });
		// 12時で止まる: 空の大時計の鐘と、時が止まる音 → 静寂
		tr.sfx("encounter/gent_bell", T.stop, { db: -9, speed: 0.5, send: 0.6 });
		stopFx(tr, T.stop, -10);
		// 止まった時の中で砕ける（くぐもった音）
		T.breaks.forEach((b, i) => {
			tr.sfx("ice_impact_light", b, { db: -14, speed: 0.65 + i * 0.05, lp: 1500, align: "peak", pan: -0.4 + i * 0.25 });
			tr.put(filt(shatter({ sec: 0.4, count: 24, seed: 371 + i, f0: 1600, f1: 4000 }), "lp", 1800, 0.7), b, { db: -20, pan: -0.4 + i * 0.25 });
		});
		// 動き出す: かけらが持ち主へ飛び込む
		tr.sfx("rewind", T.resume - 0.25, { db: -16, speed: 1.3, rev: true });
		for (let i = 0; i < 4; i++) {
			tr.sfx("samurai_iai_draw", T.resume + 0.12 + i * 0.01, { db: -13, speed: 1.4 + i * 0.05, align: "peak", pan: -0.4 + i * 0.25 });
		}
		tr.sfx("neutral_impact_light", T.resume + 0.12, { db: -12, align: "peak", pan: -0.2 });
		// 最後の一撃: 空の大時計が砕ける
		boomCore(tr, T.burst, -6, 381, 2.2);
		tr.sfx("ice_burst", T.burst, { db: -8, speed: 0.7, align: "peak", send: 0.45 });
		tr.put(shatter({ sec: 1.4, count: 140, seed: 383, f0: 1800, f1: 8000 }), T.burst, { db: -11, send: 0.4 });
		tr.sfx("encounter/dragon_detonation", T.burst, { db: -11, speed: 1.2, align: "peak", send: 0.4 });
		tr.sfx("encounter/gent_bell", T.burst + 0.05, { db: -12, speed: 0.7, send: 0.5 });
	},
	// --- 登場・支援・撃破（2026-11-16 試作。確認待ち） ---
	intro(tr, T) {
		tr.put(drone({ sec: T.stop, f0: 55, f1: 58, voices: [1, 1.004, 2.0], cutoff: 380, env: swell(0, 0.4, 0.97), seed: 401 }), 0.0, { db: -20, send: 0.2 });
		// 降りてくる懐中時計の鎖・刻む音
		tr.put(sweepNoise({ sec: 0.5, f0: 2600, f1: 900, q: 1.2, curve: 0.8, seed: 403, env: swell(0, 0.4, 0.9) }), T.drop, { db: -24, pan: 0.2 });
		T.ticks.forEach((tk, i) => tick(tr, tk, -13 + i, 1.0 - i * 0.07, 0.15));
		// 12時: ひびが走る → 砕ける（ここはまだ時が動いている＝はっきりした音）
		tick(tr, T.twelve, -10, 0.7, 0.15);
		tr.sfx("ice_impact_light", T.twelve + 0.02, { db: -13, speed: 0.8, align: "peak", pan: 0.15 });
		tr.sfx("ice_burst", T.burst, { db: -11, speed: 1.1, align: "peak", pan: 0.15, send: 0.3 });
		tr.put(shatter({ sec: 0.3, count: 40, seed: 405, f0: 2200, f1: 8000 }), T.burst, { db: -14, pan: 0.15 });
		// 飛び散る途中で時が止まる: 音がすっと吸い込まれて静寂（高い凍った音だけ）
		stopFx(tr, T.stop, -10);
		tr.put(drone({ sec: T.resume - T.stop, f0: 1760, f1: 1760, voices: [1, 1.5], cutoff: 3200, env: swell(0, 0.3, 0.9), seed: 406 }), T.stop + 0.1, { db: -31, send: 0.5 });
		tr.put(bell(2640, 0.8, 8, 404), T.bow, { db: -26, pan: 0.15, send: 0.6 });
		// 動き出す: かけらが散り、鐘
		tr.sfx("ice_burst", T.resume, { db: -12, speed: 1.0, align: "peak", pan: 0.15, send: 0.3 });
		tr.put(shatter({ sec: 0.9, count: 60, seed: 407, f0: 2200, f1: 8000 }), T.resume, { db: -15, pan: 0.15, send: 0.3 });
		tr.sfx("encounter/gent_bell", T.resume + 0.05, { db: -11, speed: 0.8, send: 0.5 });
		tr.sfx("encounter/gent_bow", T.rise - 0.05, { db: -20, pan: 0.2 });
	},
	pre_support_heal(tr, T) { clockSupport(tr, T, true, false); },
	pre_support_buff(tr, T) { clockSupport(tr, T, false, false); },
	post_support_heal(tr, T) { clockSupport(tr, T, true, true); },
	post_support_buff(tr, T) { clockSupport(tr, T, false, true); },
	pre_defeat(tr, T) {
		// 針がだんだん遅くなり、12時でかちりと止まる → ひび → ガラスがこぼれる → 小さな時計の音
		let t = 0.05;
		let gap = 0.08;
		while (t < T.stop - 0.05) {
			tick(tr, t, -18, 1.0 - (gap - 0.08) * 1.5, 0.2);
			t += gap;
			gap *= 1.22;
		}
		tick(tr, T.stop, -11, 0.6, 0.2);
		tr.put(subDrop({ sec: 0.5, f0: 70, f1: 34, decay: 5, seed: 411 }), T.stop, { db: -18 });
		tr.sfx("ice_impact_light", T.crack, { db: -14, speed: 0.8, align: "peak", pan: 0.2 });
		tr.put(shatter({ sec: T.gone - T.melt + 0.6, count: 80, seed: 413, f0: 1800, f1: 7000 }), T.melt, { db: -17, pan: 0.2, send: 0.35 });
		tr.put(bell(1760, 1.6, 4, 415), T.remain + 0.2, { db: -24, pan: 0.2, send: 0.6 });
		tick(tr, T.remain + 0.9, -24, 1.2, 0.2);
	},
	post_defeat(tr, T) {
		tr.put(drone({ sec: T.twelve - T.surge, f0: 70, f1: 150, curve: 1.3, voices: [1, 1.06, 0.5, 1.5], cutoff: (_, u) => lerp(300, 1800, u), env: swell(0, 0.85, 0.99), seed: 421 }), T.surge, { db: -15, send: 0.2 });
		tr.sfx("rewind", T.sky + 0.1, { db: -16, speed: 0.9, pan: -0.3, send: 0.3 });
		let r = T.sky + 0.2;
		let rg = 0.2;
		while (r < T.twelve - 0.05) {
			// 針が逆回転（巻き戻る）: 刻みは全部逆再生
			tr.sfx("encounter/watch_tick", r, { db: -19, rev: true, pan: -0.2 });
			tr.sfx("encounter/watch_tick", r + rg * 0.5, { db: -21, rev: true, speed: 1.1, pan: 0.2 });
			r += rg;
			rg = Math.max(0.04, rg * 0.88);
		}
		tr.sfx("encounter/gent_bell", T.twelve, { db: -6, speed: 0.55, send: 0.55 });
		boomCore(tr, T.twelve, -9, 423, 2.0);
		tr.sfx("ice_burst", T.twelve, { db: -9, speed: 0.75, align: "peak", send: 0.45 });
		tr.put(shatter({ sec: 1.6, count: 150, seed: 425, f0: 1800, f1: 8000 }), T.twelve, { db: -12, send: 0.4 });
		tr.put(bell(1320, 2.0, 3, 427), T.remain + 0.3, { db: -24, pan: 0.2, send: 0.6 });
	},
};


const only = process.argv.slice(2);
fs.mkdirSync(path.join(HERE, "out"), { recursive: true });
for (const [move, fn] of Object.entries(clock)) {
	if (only.length && !only.includes(move)) continue;
	// 支援の回復・強化は同じ時刻（pre_support / post_support）
	const info = TIMING[move.replace(/_(heal|buff)$/, "")];
	const tr = new Track(info);
	fn(tr, info.T);
	const { out } = tr.finish();
	wavWrite(path.join(HERE, "out", NAMES[move] + ".wav"), out);
	console.log(`clock/${move} → ${NAMES[move]}.wav: ${(out[0].length / SR).toFixed(2)}秒`);
}
