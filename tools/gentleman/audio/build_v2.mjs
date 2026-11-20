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
	filt, sweepNoise, subDrop, drone, crackle, rumble, shatter, reverb, limiter, rip,
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

// ---- 覚醒「異形の目覚め」 ----
function awaken() {
	const t = timing("awaken"), D = t.end;
	const tr = new Track(D);
	// 帽子に手をやる・深くお辞儀
	tr.sfx("cover_move", t.lift, { db: -22, speed: 0.85, pan: BOSS, lp: 2600 });
	tr.sfx("encounter/gent_bow", t.bow, { db: -18, pan: BOSS, send: 0.3 });
	// お辞儀の間: 闇が満ちる低い唸り・石畳が割れる・目が開く・鐘
	tr.put(drone({ sec: t.reveal - t.bow_mid, f0: 46, f1: 58, cutoff: 520, seed: 1201, env: rise(0, 0.85, 0.97), wob: 0.2 }), t.bow_mid, { db: -16, send: 0.3 });
	tr.put(crackle({ sec: t.reveal - t.bow_deep, density: 16, seed: 1203, env: rise(0.1, 0.9, 0.98) }), t.bow_deep, { db: -25, pan: BOSS, send: 0.3 });
	tr.sfx("encounter/golem_crack", t.bow_deep, { db: -21, speed: 0.8, pan: BOSS, send: 0.3, lp: 3000 });
	tr.sfx("encounter/gent_eyes", t.bow_deep + 0.15, { db: -19, pan: 0, send: 0.4 });
	tr.sfx("encounter/gent_bell", t.bow_deep + 0.3, { db: -15, pan: 0, send: 0.5, to: 2.2, fout: 0.6 });
	tr.put(sweepNoise({ sec: t.reveal - t.rise + 0.25, f0: 220, f1: 1800, q: 1.1, curve: 1.6, seed: 1205, env: rise(0, 0.9, 0.98) }), t.rise - 0.2, { db: -22, pan: BOSS, send: 0.3 });
	// 正体: 闇の柱が噴き上がる
	tr.sfx("encounter/gentleman_burst", t.reveal, { db: -11, align: "peak", pan: BOSS, send: 0.4 });
	tr.put(subDrop({ sec: 1.2, f0: 72, f1: 28, decay: 3, seed: 1207 }), t.reveal, { db: -11 });
	tr.put(rumble({ sec: 1.6, cutoff: 110, seed: 1209, env: hitDecay(1.0, 0.05) }), t.reveal + 0.02, { db: -16, send: 0.3 });
	tr.sfx("wind_burst", t.reveal + 0.03, { db: -17, speed: 0.75, align: "peak", pan: BOSS, send: 0.35 });
	for (let i = 0; i < 4; i++) tr.put(rip({ sec: 0.28, seed: 1211 + i, f0: 700, f1: 2400 }), t.reveal + 0.06 * i + 0.05, { db: -26, pan: BOSS + (i % 2 ? 0.2 : -0.2), send: 0.4 });
	// 墨の帯が巡る風と、背後の闇の唸り
	tr.sfx("encounter/musha_wind", t.reveal + 0.15, { db: -21, pan: BOSS, send: 0.3, to: t.hat - t.reveal, fout: 0.3 });
	tr.put(drone({ sec: t.awaken - t.reveal, f0: 55, f1: 74, cutoff: 700, seed: 1215, env: rise(0, 0.8, 0.96), wob: 0.35 }), t.reveal, { db: -18, send: 0.3 });
	// 帽子をかぶり直す: 全部が体へ吸い込まれる（上がっていく音）
	tr.sfx("cover_move", t.hat, { db: -22, speed: 1.1, pan: BOSS, lp: 2800 });
	tr.put(sweepNoise({ sec: t.awaken - t.hat, f0: 2600, f1: 380, q: 1.4, curve: 0.7, seed: 1217, env: rise(0, 0.95, 0.99) }), t.hat, { db: -20, pan: BOSS, send: 0.3 });
	tr.sfx("encounter/gent_cock", t.awaken - 0.14, { db: -17, pan: BOSS, send: 0.2 });
	// 覚醒: 深紅の墨の爆発・二重の衝撃・鐘
	tr.sfx("encounter/gentleman_burst", t.awaken, { db: -9, align: "peak", pan: BOSS, send: 0.45 });
	tr.sfx("boss_impact_mass", t.awaken + 0.01, { db: -12, speed: 0.8, align: "peak", pan: BOSS, send: 0.3 });
	tr.put(subDrop({ sec: 1.5, f0: 80, f1: 24, decay: 2.4, seed: 1219 }), t.awaken, { db: -9 });
	tr.put(rumble({ sec: 1.8, cutoff: 120, seed: 1221, env: hitDecay(1.0, 0.04) }), t.awaken + 0.02, { db: -14, send: 0.3 });
	tr.put(shatter({ sec: 1.0, count: 70, seed: 1223, f0: 2200, f1: 7000, env: hitDecay(1.6, 0.02) }), t.awaken + 0.03, { db: -23, pan: BOSS, send: 0.4 });
	tr.sfx("encounter/gent_bell", t.awaken + 0.08, { db: -16, pan: 0, send: 0.5, fout: 0.8 });
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

const OUTS = { awaken: "awakening_v2.wav", post_all: "awakened_all.wav" };
const ALL = { awaken, post_all };
const only = process.argv.slice(2);
for (const [name, fn] of Object.entries(ALL)) {
	if (only.length && !only.includes(name)) continue;
	const { out, reducedSec } = fn().finish();
	wavWrite(path.join(ASSET, "gentleman", OUTS[name]), out);
	console.log(`${name}: ${(out[0].length / SR).toFixed(2)}秒, リミッターが働いた時間=${reducedSec.toFixed(2)}秒`);
}
