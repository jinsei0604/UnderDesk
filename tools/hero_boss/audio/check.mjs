// 音の確認: 無音の区間と、0.1秒ごとの音量の推移を出す。使い方: node check.mjs <wav>...
import { wavRead } from "./dsp.mjs";

for (const file of process.argv.slice(2)) {
	const { rate, buf } = wavRead(file);
	const win = Math.floor(rate * 0.05);
	const levels = [];
	for (let i = 0; i + win <= buf[0].length; i += win) {
		let e = 0;
		for (let j = 0; j < win; j++) e += buf[0][i + j] ** 2 + buf[1][i + j] ** 2;
		levels.push(10 * Math.log10(e / (2 * win) + 1e-12));
	}
	const quiet = -48;
	let longest = 0, cur = 0, curStart = 0, longestAt = 0, total = 0;
	levels.forEach((l, i) => {
		if (l < quiet) {
			if (cur === 0) curStart = i;
			cur++; total++;
			if (cur > longest) { longest = cur; longestAt = curStart; }
		} else cur = 0;
	});
	const bars = levels.filter((_, i) => i % 2 === 0).map((l) => " .:-=+*#%@"[Math.max(0, Math.min(9, Math.floor((l + 60) / 6)))]).join("");
	console.log(`${file.split(/[\\/]/).pop()}: 長さ${(buf[0].length / rate).toFixed(2)}秒 / ${quiet}dB未満の合計${(total * 0.05).toFixed(2)}秒 / 最長${(longest * 0.05).toFixed(2)}秒(${(longestAt * 0.05).toFixed(2)}秒〜)`);
	console.log("  " + bars);
}
