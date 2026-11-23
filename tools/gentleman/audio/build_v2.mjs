// 異形紳士の作り直した大技の音（2026-11-20）: 覚醒「異形の目覚め」と覚醒後の全体「深紅の終幕」。
// 時刻は演出のスクリプトの T（src/bossmaker/visuals/gentleman/rbm_gentleman_fx_*.gd）を読む。演出の0秒＝音の0秒。
// 素材: 紳士の登場・勝利の音（encounter/gent_*）、銃声は紳士の単体攻撃の元の音（src/single_base.wav）から切り出す、
// ほかはゲームの効果音と合成（../../hero_boss/audio/dsp.mjs）。
// 出力: assets_bossmaker/audio/gentleman/awakening_v2.wav（覚醒。Codex が手を入れている awakening.wav には触れない）と
//       assets_bossmaker/audio/gentleman/awakened_all.wav（覚醒後の全体。前の版は Git の履歴にある）。
// 実行: node tools/gentleman/audio/build_v2.mjs [awaken] [post_all]
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
	SR, db, smooth, stereo, wavRead, wavWrite, resample, analyze, slice, fade, pan as panIt,
	filt, sweepNoise, subDrop, drone, crackle, rumble, shatter, reverb, limiter, rip, metalRing,
} from "../../hero_boss/audio/dsp.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "../../..");
const ASSET = path.join(ROOT, "assets_bossmaker/audio");

function timing(name) {
	const src = fs.readFileSync(path.join(ROOT, `src/bossmaker/visuals/gentleman/rbm_gentleman_fx_${name}.gd`), "utf8");
	const m = src.match(/const T := (\{[\s\S]*?\})\n/);
	return JSON.parse(m[1]);
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
	finish(sendGain = 0.45, room = 0.82, damp = 0.45) {
		const wet = reverb(this.wet, { room, damp, wet: sendGain, tail: 0.1 });
		const n = Math.ceil(this.sec * SR);
		const mix = stereo(this.sec);
		for (let c = 0; c < 2; c++) for (let i = 0; i < n; i++) mix[c][i] = this.dry[c][i] + wet[c][i];
		fade(mix, 0.002, 0.15);
		return limiter(mix, db(-1.6));
	}
}

const BOSS = 0.35; // 紳士は画面の右
const PARTY = -0.35;

// ---- 覚醒「紅の眼差し」（2026-11-23 作り直し。カメラの寄りと切り替えで見せる）----
function awaken() {
	const t = timing("awaken"), D = t.end;
	const tr = new Track(D);
	// 1 帽子のつばに手 → 世界が暗くなる
	tr.sfx("cover_move", t.bow, { db: -23, speed: 1.1, pan: BOSS, lp: 3000 });
	tr.put(sweepNoise({ sec: 0.45, f0: 1600, f1: 140, q: 0.8, curve: 0.8, seed: 1201, env: rise(0, 0.3, 0.9) }), t.bow + 0.1, { db: -23, send: 0.4 });
	// 2 顔の寄り: 低い唸り・心臓が二度・目が開く → 燃える（せり上がる）
	tr.put(drone({ sec: t.red - t.close, f0: 40, f1: 44, cutoff: 320, seed: 1203, env: rise(0, 0.3, 0.97), wob: 0.05 }), t.close, { db: -20, send: 0.3 });
	for (const [i, at] of [t.beat1, t.beat2].entries()) {
		tr.put(subDrop({ sec: 0.3, f0: 70, f1: 40, decay: 9, click: 0.4, seed: 1205 + i }), at, { db: -13 });
		tr.put(subDrop({ sec: 0.25, f0: 60, f1: 36, decay: 10, click: 0.3, seed: 1207 + i }), at + 0.13, { db: -17 });
	}
	tr.sfx("encounter/gent_eyes", t.eyes, { db: -16, pan: BOSS * 0.3, send: 0.5 });
	tr.put(sweepNoise({ sec: t.red - t.flare + 0.15, f0: 400, f1: 3600, q: 1.4, curve: 1.8, seed: 1209, env: rise(0, 0.95, 0.99) }), t.flare - 0.15, { db: -19, send: 0.4 });
	// 3 深紅の空: 低く深い一撃・コートが翻る風
	tr.put(subDrop({ sec: 1.2, f0: 76, f1: 26, decay: 3, click: 0.8, seed: 1211 }), t.red, { db: -9 });
	tr.sfx("encounter/gentleman_burst", t.red + 0.01, { db: -14, speed: 0.75, align: "peak", lp: 1200, send: 0.5 });
	tr.sfx("wind_burst", t.red + 0.02, { db: -17, speed: 0.85, align: "peak", pan: BOSS, send: 0.4 });
	tr.sfx("cover_move", t.red, { db: -19, speed: 0.8, pan: BOSS, lp: 2400 });
	// 4 胸の寄り: 二丁を抜く・銃口が順に閃く（高い金属の音と撃鉄）
	tr.sfx("cover_move", t.draw, { db: -21, speed: 1.2, pan: BOSS, lp: 3200 });
	tr.put(metalRing({ sec: 0.4, base: 3600, decay: 12, seed: 1213 }), t.glint1, { db: -20, pan: BOSS - 0.2, send: 0.45 });
	tr.put(metalRing({ sec: 0.4, base: 4100, decay: 12, seed: 1215 }), t.glint2, { db: -20, pan: BOSS + 0.2, send: 0.45 });
	tr.sfx("encounter/gent_cock", t.glint1 + 0.02, { db: -15, pan: BOSS - 0.15, send: 0.25 });
	tr.sfx("encounter/gent_cock", t.glint2 + 0.02, { db: -15, speed: 1.08, pan: BOSS + 0.15, send: 0.25 });
	tr.put(sweepNoise({ sec: t.awaken - t.spread, f0: 300, f1: 2400, q: 1.2, curve: 1.6, seed: 1217, env: rise(0, 0.95, 0.99) }), t.spread, { db: -21, send: 0.3 });
	// 5 覚醒: 深紅の墨の爆発・衝撃
	tr.sfx("encounter/gentleman_burst", t.awaken, { db: -8, align: "peak", pan: BOSS * 0.5, send: 0.45 });
	tr.sfx("boss_impact_mass", t.awaken + 0.01, { db: -11, speed: 0.8, align: "peak", pan: 0, send: 0.3 });
	tr.put(subDrop({ sec: 1.4, f0: 82, f1: 24, decay: 2.6, seed: 1219 }), t.awaken, { db: -9 });
	tr.put(rumble({ sec: 1.4, cutoff: 120, seed: 1221, env: hitDecay(1.0, 0.04) }), t.awaken + 0.02, { db: -15, send: 0.3 });
	tr.put(crackle({ sec: 0.5, density: 90, seed: 1223, env: hitDecay(1.4, 0.01) }), t.awaken + 0.03, { db: -21, send: 0.3 });
	tr.sfx("cover_move", t.lower, { db: -24, speed: 1.0, pan: BOSS, lp: 2800 });
	return tr;
}

// ---- 覚醒前の全体「跳弾」（2026-11-23 作り直し。前の版は影の射撃 all.wav）----
function all_v2() {
	const src = fs.readFileSync(path.join(ROOT, "src/bossmaker/visuals/gentleman/rbm_gentleman_fx_all.gd"), "utf8");
	const t = timing("all");
	const num = (name) => parseFloat(src.match(new RegExp(`const ${name} := ([\\d.]+)`))[1]);
	const FIRST = num("FIRST"), STEP = num("STEP"), COUNT = num("COUNT");
	// 五芒星の頂点に着く時刻（最初の頂点 FIRST から STEP ごと。COUNT 本目で最初の頂点へ戻り、次の一本で一人の胸に食い込んで止まる）と、
	// 星の線の真ん中（体を貫く頃）。rbm_gentleman_fx_all.gd の _seg_end と同じ。貫く時刻は並びで少し変わるので、線の真ん中に置く
	const bounces = [], passes = [];
	for (let k = 0; k <= COUNT + 1; k++) bounces.push(FIRST + STEP * k);
	for (let k = 1; k <= COUNT; k++) passes.push(FIRST + STEP * (k - 0.5));
	const tr = new Track(t.end);
	// 銃を抜く・構える・銃身の閃き
	tr.sfx("cover_move", t.draw, { db: -23, speed: 1.15, pan: BOSS, lp: 3000 });
	tr.sfx("encounter/gent_cock", t.aim + 0.05, { db: -17, pan: BOSS, send: 0.2 });
	tr.put(metalRing({ sec: 0.25, base: 3400, decay: 18, seed: 1401 }), t.glint, { db: -27, pan: BOSS, send: 0.4 });
	// 一発 → 時間がほとんど止まる（音が遠のき、低く伸びる）
	tr.gun(t.fire, { db: -8, pan: BOSS, send: 0.55 });
	tr.put(sweepNoise({ sec: t.click - t.fire, f0: 380, f1: 140, q: 0.9, curve: 0.7, seed: 1403, env: rise(0, 0.08, 0.97) }), t.fire + 0.05, { db: -21, send: 0.5 });
	tr.put(drone({ sec: t.click - t.fire, f0: 52, f1: 49, cutoff: 300, seed: 1405, env: rise(0, 0.1, 0.96), wob: 0.05 }), t.fire + 0.04, { db: -20, send: 0.3 });
	// 弾の出来事: 体を貫く（低い鈍い音と短い風）・跳ね返る（間延びした金属の音。左右に振る）
	for (const [i, at] of passes.entries()) {
		tr.put(subDrop({ sec: 0.2, f0: 160, f1: 80, decay: 14, click: 0.7, seed: 1410 + i }), at, { db: -20, pan: -0.3 });
		tr.put(sweepNoise({ sec: 0.2, f0: 900, f1: 300, q: 1.2, curve: 0.6, seed: 1420 + i, env: hitDecay(1.3, 0.05) }), at - 0.04, { db: -26, pan: -0.3, send: 0.4 });
	}
	for (const [i, at] of bounces.entries()) {
		const p = [-0.1, -0.6, 0.1, -0.5, -0.2, -0.1][i % 6];
		if (i < bounces.length - 1) {
			tr.put(metalRing({ sec: 0.6, base: 1700 + 170 * (i % 4), decay: 7, seed: 1430 + i }), at, { db: -21, pan: p, send: 0.55 });
			tr.put(crackle({ sec: 0.1, density: 80, seed: 1440 + i, env: hitDecay(1.4, 0.01) }), at, { db: -26, pan: p, send: 0.3 });
		} else {
			// 一人の胸に食い込んで止まる: 鈍く食い込む音と、低く残る響き
			tr.put(subDrop({ sec: 0.35, f0: 120, f1: 50, decay: 8, click: 1.0, seed: 1450 }), at, { db: -17, pan: p });
			tr.put(metalRing({ sec: 1.0, base: 900, decay: 3.5, seed: 1452 }), at, { db: -25, pan: p, send: 0.6 });
		}
	}
	// 帽子のつばに触れる（小さな音）→ 時間が戻る: 四人が同時に撃ち抜かれ、軌跡が砕ける
	tr.put(metalRing({ sec: 0.12, base: 4200, decay: 40, seed: 1451 }), t.click, { db: -22, pan: BOSS, send: 0.3 });
	for (let k = 0; k < 4; k++) tr.sfx("neutral_impact_light", t.impact + 0.012 * k, { db: -14, speed: 0.95 + 0.04 * k, align: "peak", pan: -0.45 + 0.1 * k, send: 0.3 });
	tr.sfx("boss_impact_mass", t.impact + 0.01, { db: -13, speed: 0.95, align: "peak", pan: -0.3, send: 0.3 });
	tr.put(subDrop({ sec: 0.9, f0: 90, f1: 32, decay: 4, seed: 1453 }), t.impact, { db: -11 });
	tr.put(shatter({ sec: 0.9, count: 90, seed: 1455, f0: 2600, f1: 9000, env: hitDecay(1.5, 0.004) }), t.impact + 0.01, { db: -17, pan: -0.3, send: 0.45 });
	tr.gun(t.impact - 0.005, { db: -16, speed: 0.8, pan: -0.3, send: 0.6 });
	return tr;
}

// ---- 覚醒後の全体「深紅の終幕」 ----
function post_all() {
	const t = timing("post_all"), D = t.end;
	const tr = new Track(D);
	// 帽子に手をやる → 幕が下りる（重い布が落ちる）・暗くなる唸り
	tr.sfx("cover_move", t.lift, { db: -21, speed: 0.8, pan: BOSS, lp: 2400 });
	tr.put(sweepNoise({ sec: 0.7, f0: 1400, f1: 180, q: 0.9, curve: 0.8, seed: 1301, env: rise(0, 0.4, 0.9) }), t.lift + 0.05, { db: -20, send: 0.3 });
	tr.put(subDrop({ sec: 0.5, f0: 60, f1: 38, decay: 6, seed: 1303 }), t.reveal - 0.05, { db: -18 });
	tr.put(drone({ sec: t.fire - t.lift, f0: 49, f1: 62, cutoff: 600, seed: 1305, env: rise(0, 0.9, 0.98), wob: 0.25 }), t.lift, { db: -18, send: 0.3 });
	// 両腕を広げる: 目が開く・裂け目が開く・舞台の光が落ちる
	tr.sfx("encounter/gent_eyes", t.reveal + 0.05, { db: -18, pan: PARTY, send: 0.4 });
	for (let i = 0; i < 6; i++) tr.put(rip({ sec: 0.26, seed: 1307 + i, f0: 800, f1: 2600 }), t.reveal + 0.2 + 0.08 * i, { db: -25, pan: PARTY + (i % 2 ? 0.25 : -0.25), send: 0.4 });
	tr.put(subDrop({ sec: 0.4, f0: 120, f1: 70, decay: 9, click: 1.0, seed: 1313 }), t.reveal + 0.12, { db: -21, pan: PARTY });
	// 二丁を広げて構える
	tr.sfx("encounter/gent_cock", t.raise, { db: -17, pan: BOSS, send: 0.2 });
	tr.sfx("encounter/gent_cock", t.raise + 0.14, { db: -19, speed: 1.08, pan: BOSS, send: 0.2 });
	// 左右交互の射撃（弾は裂け目へ入り、四人のまわりの裂け目から出て当たる）
	for (let i = 0; i < t.count; i++) {
		const st = t.shots + t.step * i;
		tr.gun(st, { db: -14, speed: 1.0 + 0.04 * (i % 3), pan: BOSS + (i % 2 ? 0.15 : -0.15), send: 0.3 });
		tr.put(sweepNoise({ sec: 0.12, f0: 3000, f1: 900, q: 1.2, curve: 0.6, seed: 1320 + i, env: hitDecay(1.4, 0.1) }), st + 0.02, { db: -26, pan: PARTY, send: 0.3 });
		tr.sfx("neutral_impact_light", st + 0.09, { db: -20, speed: 0.9 + 0.05 * (i % 3), align: "peak", pan: PARTY, send: 0.2 });
	}
	// 二丁を前にそろえて溜める（裂け目が脈打つ）
	tr.sfx("encounter/gent_cock", t.cross, { db: -16, speed: 0.92, pan: BOSS, send: 0.25 });
	tr.put(sweepNoise({ sec: t.fire - t.cross, f0: 260, f1: 2600, q: 1.3, curve: 1.6, seed: 1341, env: rise(0, 0.95, 0.99) }), t.cross, { db: -19, send: 0.3 });
	for (let k = 0; k < 3; k++) tr.put(subDrop({ sec: 0.25, f0: 70, f1: 48, decay: 9, seed: 1343 + k }), t.cross + 0.15 * k, { db: -20 });
	// 一斉射撃 → 深紅の墨の大爆発
	tr.gun(t.fire, { db: -10, speed: 0.92, pan: BOSS, send: 0.4 });
	tr.gun(t.fire + 0.012, { db: -12, speed: 0.86, pan: BOSS - 0.1, send: 0.4 });
	tr.sfx("encounter/gentleman_burst", t.impact, { db: -8, align: "peak", pan: PARTY, send: 0.45 });
	tr.sfx("boss_impact_mass", t.impact + 0.01, { db: -11, speed: 0.75, align: "peak", pan: PARTY, send: 0.3 });
	tr.put(subDrop({ sec: 1.6, f0: 78, f1: 24, decay: 2.3, seed: 1351 }), t.impact, { db: -9 });
	tr.put(rumble({ sec: 1.9, cutoff: 120, seed: 1353, env: hitDecay(1.0, 0.04) }), t.impact + 0.02, { db: -14, send: 0.3 });
	tr.put(shatter({ sec: 1.1, count: 80, seed: 1355, f0: 2000, f1: 7000, env: hitDecay(1.6, 0.02) }), t.impact + 0.03, { db: -22, pan: PARTY, send: 0.4 });
	tr.sfx("encounter/golem_crack", t.impact + 0.05, { db: -18, speed: 0.85, pan: PARTY, send: 0.3, lp: 3200 });
	// カーテンコール: 花びらが降る（きらめき）・お辞儀・幕が上がる
	tr.sfx("encounter/sparkle", t.impact + 0.5, { db: -26, speed: 0.8, pan: PARTY, send: 0.5 });
	tr.sfx("encounter/gent_bow", t.bow, { db: -17, pan: BOSS, send: 0.3 });
	tr.put(sweepNoise({ sec: 0.9, f0: 200, f1: 1300, q: 0.9, curve: 1.3, seed: 1361, env: rise(0, 0.5, 0.95) }), t.curtain_up, { db: -22, send: 0.3 });
	return tr;
}

const OUTS = { awaken: "awakening_v2.wav", post_all: "awakened_all.wav", all_v2: "all_v2.wav" };
const ALL = { awaken, post_all, all_v2 };
const only = process.argv.slice(2);
for (const [name, fn] of Object.entries(ALL)) {
	if (only.length && !only.includes(name)) continue;
	const { out, reducedSec } = fn().finish();
	wavWrite(path.join(ASSET, "gentleman", OUTS[name]), out);
	console.log(`${name}: ${(out[0].length / SR).toFixed(2)}秒, リミッターが働いた時間=${reducedSec.toFixed(2)}秒`);
}
