// 味方の覚醒の発動の音（2026-11-19 第2版）。1人1本（演出の0秒＝音の0秒）。
// 時刻は src/bossmaker/visuals/ally_awakening/rbm_<味方>_awakening_fx.gd の T から読むので、演出の時刻を直せば音も一緒に動く。
// 使い方: node tools/ally_awakening/audio/build.mjs [hero ...] → tools/ally_awakening/audio/out/<味方>.wav
// できた音は assets_bossmaker/audio/ally_awakening/<味方>.wav へ置く（置いた後に --import）。
// 素材: 既存のゲームの効果音（assets_bossmaker/audio/*.wav）と、ヒーローの音の部品（tools/hero_boss/audio/dsp.mjs）。乱数は種つきで、毎回同じ音になる。
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
	SR, db, smooth, lerp, stereo, wavRead, wavWrite, resample, analyze, slice, fade, pan as panIt,
	filt, sweepNoise, subDrop, drone, metalRing, crackle, flame, rumble, electric, shatter, reverb, limiter,
} from "../../hero_boss/audio/dsp.mjs";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, "../../..");
const ASSET = path.join(ROOT, "assets_bossmaker/audio");
const OUT = path.join(HERE, "out");
fs.mkdirSync(OUT, { recursive: true });

function timing(id) {
	const src = fs.readFileSync(path.join(ROOT, `src/bossmaker/visuals/ally_awakening/rbm_${id}_awakening_fx.gd`), "utf8");
	const m = src.match(/const T := (\{[^\n]*\})/);
	return JSON.parse(m[1]);
}

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
	finish(sendGain = 0.4, room = 0.78, damp = 0.5) {
		const wet = reverb(this.wet, { room, damp, wet: sendGain, tail: 0.1 });
		const n = Math.ceil(this.sec * SR);
		const mix = stereo(this.sec);
		for (let c = 0; c < 2; c++) for (let i = 0; i < n; i++) mix[c][i] = this.dry[c][i] + wet[c][i];
		fade(mix, 0.002, 0.12);
		return limiter(mix, db(-1.6));
	}
}

const fall = (u, p = 1.5) => Math.pow(1 - u, p);
const hitDecay = (p = 1.5, attack = 0.03) => (_, u) => smooth(0, attack, u) * fall(u, p);
const rise = (a = 0, b = 0.85, c = 0.95) => (_, u) => smooth(a, b, u) * (1 - smooth(c, 1, u));

// ---- 勇者「炎の誓い」 ----
function hero() {
	const t = timing("hero"), R = t.release, D = t.end;
	const tr = new Track(D);
	const pan = -0.35;
	// 片膝をつく（鎧と布の音）・剣を掲げる
	tr.sfx("cover_move", t.kneel, { db: -21, speed: 0.8, pan, lp: 2600 });
	tr.sfx("neutral_sword_swing", t.kneel + 0.05, { db: -24, speed: 0.8, pan, lp: 3200 });
	// ためる: 足元の火が育ち、火の粉が剣先へ吸い込まれる（上がっていく炎の唸り）
	tr.put(flame({ sec: R - t.kneel, f: 320, q: 0.6, seed: 901, flutter: 0.5, env: rise(0, 0.95, 0.98) }), t.kneel, { db: -19, pan, send: 0.15 });
	tr.put(crackle({ sec: R - t.kneel, density: 18, seed: 903, env: rise(0, 0.9, 0.98) }), t.kneel + 0.1, { db: -25, pan, send: 0.2 });
	tr.put(sweepNoise({ sec: R - t.kneel, f0: 260, f1: 2200, q: 1.2, curve: 1.8, seed: 905, env: rise(0.1, 0.95, 0.99) }), t.kneel, { db: -24, pan });
	// 誓い: 剣を立てると刃に炎が灯る（澄んだ刃の響き＋火がつく音）
	tr.put(metalRing({ sec: 0.9, base: 1900, decay: 5, seed: 907 }), t.oath, { db: -21, pan, send: 0.4 });
	tr.sfx("fire_cast", t.oath + 0.02, { db: -18, speed: 1.1, align: "onset", pan, send: 0.2 });
	// 一瞬の溜め（吸い込む）
	tr.put(sweepNoise({ sec: 0.3, f0: 2400, f1: 400, q: 1, curve: 0.8, seed: 909, env: rise(0, 0.9, 0.98) }), R - 0.3, { db: -24, pan });
	// 解放: 炎が噴き上がる（重い炸裂・炎・低音）・床を炎の輪が走る・火の粉
	tr.sfx("fire_burst", R, { db: -9, speed: 0.95, align: "peak", pan, send: 0.35 });
	tr.sfx("fire_impact_heavy", R, { db: -12, speed: 0.9, align: "peak", pan, send: 0.25 });
	tr.put(subDrop({ sec: 1.2, f0: 82, f1: 30, decay: 3, seed: 911 }), R, { db: -11 });
	tr.put(flame({ sec: 1.4, f: 420, q: 0.5, seed: 913, env: hitDecay(1.3, 0.02), flutter: 0.5 }), R + 0.02, { db: -15, pan, send: 0.3 });
	tr.put(crackle({ sec: 1.5, density: 30, seed: 915, env: hitDecay(1.2, 0.03) }), R + 0.04, { db: -23, pan, send: 0.3 });
	tr.put(sweepNoise({ sec: 0.6, f0: 900, f1: 220, q: 0.9, curve: 0.8, seed: 917, env: hitDecay(1.4, 0.05) }), R + 0.02, { db: -22, pan: 0 });
	return tr;
}

// ---- 老執事「凍てつく刻」 ----
function butler() {
	const t = timing("butler"), R = t.release, D = t.end;
	const tr = new Track(D);
	const pan = -0.3;
	// 胸に手を当てる（布の音）・冷たい息
	tr.sfx("cover_move", t.compose, { db: -23, speed: 0.95, pan, lp: 2600 });
	tr.put(sweepNoise({ sec: t.raise - t.compose + 0.3, f0: 1800, f1: 3200, q: 2, curve: 1, seed: 931, env: rise(0, 0.7, 0.95) }), t.compose, { db: -31, pan, send: 0.3 });
	// 懐中時計を掲げる: 時を刻む音（だんだん大きく）・霜が広がる細かな音・冷気が集まる
	tr.sfx("cover_move", t.raise, { db: -23, speed: 1.1, pan, lp: 2600 });
	// 床の文字盤の秒針が刻む（胸に手を当てた時から。演出の TICK=0.25 と同じ）
	for (let k = 0, at = t.compose; at < t.rush - 0.02; k++, at += 0.25) tr.sfx("encounter/watch_tick", at, { db: -27 + Math.min(k, 5) * 1.0, speed: 1.0, pan, send: 0.2 });
	// 針がすべて12時へ走る（速い刻み → 12時で止まる）
	for (let at = t.rush; at < R - 0.03; at += 0.05) tr.sfx("encounter/watch_tick", at, { db: -27, speed: 1.35, pan, send: 0.15 });
	tr.sfx("ice_cast", t.compose + 0.1, { db: -21, speed: 0.9, align: "onset", pan, send: 0.3 });
	tr.put(crackle({ sec: R - t.compose, density: 26, seed: 933, env: rise(0, 0.9, 0.98) }), t.compose, { db: -28, pan, send: 0.3 });
	tr.put(sweepNoise({ sec: R - t.raise, f0: 600, f1: 4200, q: 1.5, curve: 1.6, seed: 935, env: rise(0.1, 0.95, 0.99) }), t.raise, { db: -25, pan });
	// 解放: 時計が鳴る（澄んだ鐘）・冷気が弾ける・霜の輪・きらめき
	tr.put(metalRing({ sec: 1.6, base: 1320, partials: [1, 2.0, 2.76, 3.42, 4.1], decay: 3, seed: 937 }), R, { db: -17, pan, send: 0.5 });
	tr.sfx("ice_burst", R, { db: -10, speed: 0.9, align: "peak", pan, send: 0.35 });
	tr.sfx("ice_impact_heavy", R + 0.02, { db: -13, speed: 0.95, align: "peak", pan, send: 0.3 });
	tr.put(subDrop({ sec: 0.8, f0: 90, f1: 40, decay: 4, seed: 939 }), R, { db: -15 });
	tr.put(shatter({ sec: 1.2, count: 70, seed: 941, f0: 3000, f1: 9000 }), R + 0.03, { db: -22, pan, send: 0.4 });
	tr.put(sweepNoise({ sec: 1.0, f0: 2600, f1: 500, q: 0.8, curve: 0.8, seed: 943, env: hitDecay(1.2, 0.05) }), R + 0.02, { db: -23, pan: 0 });
	tr.sfx("encounter/sparkle", R + 0.35, { db: -24, speed: 0.9, send: 0.5, pan });
	tr.sfx("cover_move", t.settle, { db: -26, speed: 1.0, pan, lp: 2600 });
	return tr;
}

// ---- 少女「天雷の祈り」 ----
function healer() {
	const t = timing("healer"), R = t.release, D = t.end;
	const tr = new Track(D);
	const pan = -0.3;
	// 目を閉じて杖を胸に抱く（布の音）・足元を静電気が這う（小さなパチパチ、だんだん増える）
	tr.sfx("cover_move", t.pray, { db: -24, speed: 1.1, pan, lp: 2800 });
	tr.put(electric({ sec: R - t.pray, density: 16, seed: 951, env: rise(0, 0.9, 0.98) }), t.pray + 0.05, { db: -27, pan, send: 0.25 });
	tr.put(sweepNoise({ sec: t.raise - t.pray + 0.2, f0: 1400, f1: 2600, q: 2, curve: 1, seed: 953, env: rise(0, 0.7, 0.95) }), t.pray, { db: -32, pan, send: 0.3 });
	// 杖を天へ掲げる: 稲妻が宝石へ吸い込まれる（放電が増える）・遠くで雷が鳴り始める・上がっていく唸り
	tr.sfx("cover_move", t.raise, { db: -23, speed: 1.2, pan, lp: 2800 });
	tr.sfx("lightning_cast", t.raise + 0.02, { db: -19, speed: 1.0, align: "onset", pan, send: 0.3 });
	tr.put(electric({ sec: R - t.raise, density: 46, seed: 955, env: rise(0, 0.95, 0.99) }), t.raise, { db: -22, pan, send: 0.2 });
	tr.put(rumble({ sec: R - t.raise + 0.1, cutoff: 120, seed: 957, env: rise(0, 0.95, 0.99) }), t.raise, { db: -20 });
	tr.put(sweepNoise({ sec: R - t.raise, f0: 500, f1: 3800, q: 1.4, curve: 1.7, seed: 959, env: rise(0.1, 0.95, 0.99) }), t.raise, { db: -25, pan });
	// 一瞬の溜め（空から前触れの放電が降りてくる）
	tr.put(sweepNoise({ sec: 0.35, f0: 3800, f1: 900, q: 1, curve: 0.8, seed: 961, env: rise(0, 0.9, 0.98) }), R - 0.35, { db: -25, pan: 0 });
	// 解放: 雷が杖に落ちる（裂ける音・重い着弾・低音）・瞬く放電・床を走る稲妻・遠くへ転がる雷鳴
	tr.sfx("lightning_burst", R, { db: -9, speed: 0.95, align: "peak", pan, send: 0.35 });
	tr.sfx("lightning_impact_heavy", R, { db: -12, speed: 0.9, align: "peak", pan, send: 0.3 });
	tr.put(subDrop({ sec: 1.0, f0: 85, f1: 32, decay: 3.5, seed: 963 }), R, { db: -12 });
	tr.put(electric({ sec: 0.9, density: 90, seed: 965, env: hitDecay(1.4, 0.01) }), R + 0.01, { db: -18, pan, send: 0.3 });
	tr.put(crackle({ sec: 1.0, density: 34, seed: 967, env: hitDecay(1.2, 0.03) }), R + 0.05, { db: -24, pan, send: 0.3 });
	tr.put(rumble({ sec: 1.6, cutoff: 140, seed: 969, env: hitDecay(1.1, 0.08) }), R + 0.06, { db: -17, send: 0.4 });
	// 両腕を広げる: 体に放電が残る（小さなパチパチ）・きらめき
	tr.sfx("lightning_move", t.cast, { db: -22, speed: 1.0, align: "onset", pan, send: 0.3 });
	tr.put(electric({ sec: t.settle - t.cast, density: 20, seed: 971, env: rise(0, 0.1, 0.7) }), t.cast, { db: -27, pan, send: 0.3 });
	tr.sfx("encounter/sparkle", t.cast + 0.05, { db: -25, speed: 1.05, send: 0.5, pan });
	tr.sfx("cover_move", t.settle, { db: -26, speed: 1.0, pan, lp: 2600 });
	return tr;
}

// ---- 侍「墨風・一閃」（機械武者の墨の音: 構え・墨の風・斬撃・墨のしぶき・納刀） ----
function samurai() {
	const t = timing("samurai"), R = t.release, D = t.end;
	const tr = new Track(D);
	const pan = -0.35;
	// 風が立つ（目を閉じて立ったまま。風で布が揺れる音・武者の構えの風の音）
	tr.sfx("cover_move", t.crouch, { db: -22, speed: 0.9, pan, lp: 2600 });
	tr.sfx("encounter/musha_stance", t.crouch + 0.05, { db: -20, speed: 1.0, align: "onset", pan, send: 0.25 });
	// 墨の筆の風が体を巻く（だんだん遅く → 止まる）
	tr.sfx("encounter/musha_wind", t.crouch + 0.1, { db: -21, speed: 1.0, pan, send: 0.3, to: t.still - t.crouch + 0.2, fout: 0.25 });
	tr.put(sweepNoise({ sec: t.still - t.crouch, f0: 900, f1: 380, q: 1.6, curve: 0.8, seed: 981, env: rise(0, 0.3, 0.75) }), t.crouch, { db: -26, pan, send: 0.3 });
	// 止まる: 静けさの中に鼓動が2回、鯉口を切る小さな音
	tr.put(subDrop({ sec: 0.25, f0: 70, f1: 45, decay: 9, seed: 983 }), t.still + 0.08, { db: -24 });
	tr.put(subDrop({ sec: 0.25, f0: 70, f1: 45, decay: 9, seed: 985 }), t.still + 0.3, { db: -23 });
	tr.put(metalRing({ sec: 0.35, base: 2600, decay: 12, seed: 987 }), R - 0.1, { db: -27, pan, send: 0.3 });
	// 抜刀: 居合の音・武者の斬撃・墨が弾ける・墨のしぶき
	tr.sfx("samurai_iai_draw", R, { db: -11, speed: 1.0, align: "peak", pan, send: 0.3 });
	tr.sfx("encounter/musha_slash", R + 0.01, { db: -13, speed: 1.0, align: "peak", pan: 0.1, send: 0.3 });
	tr.sfx("encounter/musha_ink_burst", R + 0.03, { db: -15, speed: 1.0, align: "onset", pan: 0.1, send: 0.3 });
	tr.sfx("encounter/musha_splatter", R + 0.08, { db: -19, speed: 1.0, align: "onset", pan: 0.2, send: 0.3 });
	tr.put(subDrop({ sec: 0.7, f0: 80, f1: 36, decay: 5, seed: 989 }), R, { db: -15 });
	tr.sfx("wind_burst", R + 0.02, { db: -18, speed: 1.0, align: "peak", pan: 0.2, send: 0.35 });
	// 納刀
	tr.sfx("encounter/sheathe", t.sheathe, { db: -18, speed: 1.0, align: "onset", pan, send: 0.3 });
	return tr;
}

// ---- ハンマー使い「熔鉱・地裂」（熔鉱炉の番人の溶岩: 炉の唸り・溶岩が噴き上がる・冷える） ----
function tank() {
	const t = timing("tank"), R = t.release, D = t.end;
	const tr = new Track(D);
	const pan = -0.3;
	// ハンマーを肩に担ぐ（布・金属の重さ）→ 頭が赤く焼ける（炉の唸り・パチパチ）・床のひびが脈打つ（低い鼓動）
	tr.sfx("cover_move", t.heft, { db: -21, speed: 0.8, pan, lp: 2400 });
	tr.sfx("hammer_swing", t.heft + 0.02, { db: -25, speed: 0.75, pan, lp: 2600 });
	tr.put(flame({ sec: R - t.heft, f: 260, q: 0.6, seed: 991, flutter: 0.4, env: rise(0, 0.95, 0.99) }), t.heft + 0.1, { db: -20, pan, send: 0.2 });
	tr.put(crackle({ sec: R - t.heft, density: 14, seed: 993, env: rise(0, 0.9, 0.98) }), t.heft + 0.15, { db: -26, pan, send: 0.2 });
	for (let at = t.heft + 0.2; at < t.raise; at += 2 * Math.PI / 7) tr.put(subDrop({ sec: 0.3, f0: 62, f1: 40, decay: 8, seed: 995 + Math.round(at * 10) }), at, { db: -22 });
	// 頭上に振りかぶる（風を切る）・一瞬の溜め
	tr.sfx("hammer_swing", t.raise, { db: -20, speed: 0.85, align: "onset", pan, send: 0.2 });
	tr.put(sweepNoise({ sec: R - t.raise, f0: 300, f1: 1800, q: 1.2, curve: 1.6, seed: 997, env: rise(0, 0.9, 0.98) }), t.raise, { db: -24, pan });
	// 叩きつけ: 重い一撃・地面が割れる・溶岩が噴き上がる（炎の噴出・低音）・岩と飛沫・転がる地鳴り
	tr.sfx("hammer_impact", R, { db: -9, speed: 0.85, align: "peak", pan, send: 0.3 });
	tr.sfx("encounter/golem_slam", R + 0.01, { db: -12, speed: 0.9, align: "peak", pan, send: 0.3 });
	tr.put(subDrop({ sec: 1.3, f0: 70, f1: 26, decay: 2.6, seed: 999 }), R, { db: -10 });
	tr.sfx("fire_burst", R + 0.04, { db: -14, speed: 0.8, align: "peak", pan: 0, send: 0.3 });
	tr.put(flame({ sec: 1.3, f: 360, q: 0.5, seed: 1001, env: hitDecay(1.2, 0.03), flutter: 0.6 }), R + 0.04, { db: -15, pan: 0, send: 0.3 });
	tr.put(rumble({ sec: 1.8, cutoff: 120, seed: 1003, env: hitDecay(1.0, 0.05) }), R + 0.02, { db: -15, send: 0.3 });
	tr.put(crackle({ sec: 1.6, density: 26, seed: 1005, env: hitDecay(1.0, 0.05) }), R + 0.08, { db: -22, pan: 0, send: 0.3 });
	// 溶岩が冷えて固まる（ジュッという音・小さなパチパチ）・構え直す
	tr.put(sweepNoise({ sec: 0.9, f0: 4200, f1: 2200, q: 0.8, curve: 1, seed: 1007, env: hitDecay(1.4, 0.15) }), R + 0.7, { db: -27, pan: 0, send: 0.3 });
	tr.sfx("cover_move", t.recover, { db: -24, speed: 0.85, pan, lp: 2400 });
	return tr;
}

const ALL = { hero, butler, healer, samurai, tank };
const only = process.argv.slice(2);
for (const [name, fn] of Object.entries(ALL)) {
	if (only.length && !only.includes(name)) continue;
	const { out, reducedSec } = fn().finish();
	wavWrite(path.join(OUT, name + ".wav"), out);
	console.log(`${name}: ${(out[0].length / SR).toFixed(2)}秒, リミッターが働いた時間=${reducedSec.toFixed(2)}秒`);
}
