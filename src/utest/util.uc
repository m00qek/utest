import * as math from 'math';
import * as fs from 'fs';

export const q = (s) => "'" + replace(s, "'", "'\\''") + "'";

// Parse a caught exception and return { is_assertion, message }.
// is_assertion is true only for values thrown by assert.fail() (utest-controlled
// failures); everything else is an ERROR (runtime crash or unexpected die).
export const parse_thrown = function(e) {
	if (type(e) == 'object' && e.type) {
		if (e.type == "Error") {
			let parsed = null;
			try { parsed = json(e.message); } catch(_) {}
			if (type(parsed) == 'object' && parsed.__utest__ && parsed.__utest__.kind == 'fail')
				return { is_assertion: true, message: parsed.__utest__.message };
			return { is_assertion: false, message: e.message };
		}
		return { is_assertion: false, message: e.message };
	}
	return { is_assertion: false, message: sprintf('%s', e) };
};

export const format_path = function(path) {
	let parts = [];
	for (let p in path) {
		if (p.id != 0) push(parts, p.name);
	}
	return join(" > ", parts);
};

export const shuffle = function(arr, seed) {
	let result = [ ...arr ];
	if (seed == null) {
		let t = clock();
		seed = t[0] * 1000000000 + t[1];
	}
	math.srand(seed);
	for (let i = length(result) - 1; i > 0; i--) {
		let j = math.rand() % (i + 1);
		let tmp = result[i];
		result[i] = result[j];
		result[j] = tmp;
	}
	return result;
};

export function mkdir_p(path) {
	let parts = split(path, "/");
	let cur = "";
	for (let part in parts) {
		if (!length(part)) { cur = "/"; continue; }
		cur = (cur == "/" ? "/" : cur + "/") + part;
		if (!fs.access(cur, "r") && !fs.mkdir(cur, 493))
			return false;
	}
	return true;
};
