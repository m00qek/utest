import * as math from 'math';
import * as fs from 'fs';

export const q = (s) => "'" + replace(s, "'", "'\\''") + "'";

// Serialize a utest-controlled failure into the die() envelope that
// parse_thrown() below recognizes. Used by assert.fail() and the property
// engine so the wire shape lives in exactly one place.
export const fail_envelope = function(message) {
	return sprintf('%J', { __utest__: { kind: 'fail', message } });
};

// Parse a caught exception into { kind, message }.
//   kind    - the utest envelope kind ('fail' for assertion failures,
//             'property_overrun' / 'property_discard' for the property engine's
//             control-flow sentinels), or null for any non-utest throw (a
//             runtime crash or a plain die()).
//   message - the envelope's own message for a 'fail' kind; otherwise the raw
//             exception text.
// Only die()n values carry a utest envelope, and ucode tags those with
// type "Error", so the envelope is read only from that type; anything else is
// reported verbatim.  Callers classify: FAIL iff kind === 'fail', ERROR otherwise.
export const parse_thrown = function(e) {
	if (type(e) === 'object' && e.type === "Error") {
		let parsed = null;
		try { parsed = json(e.message); } catch(_) {}
		if (type(parsed) === 'object' && parsed.__utest__) {
			const kind = parsed.__utest__.kind;
			return { kind, message: kind === 'fail' ? parsed.__utest__.message : e.message };
		}
		return { kind: null, message: e.message };
	}
	if (type(e) === 'object' && e.type)
		return { kind: null, message: e.message };
	return { kind: null, message: sprintf('%s', e) };
};

export const format_path = function(path) {
	let parts = [];
	for (let p in path) {
		if (p.id !== 0) push(parts, p.name);
	}
	return join(" > ", parts);
};

export const shuffle = function(arr, seed) {
	let result = [ ...arr ];
	if (seed === null) {
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
	for (let i = 0; i < length(parts); i++) {
		let part = parts[i];
		if (!length(part)) {
			// A leading empty component means an absolute path ("/a"); any other
			// empty component is a redundant slash ("a//b") and must be skipped —
			// resetting to root here would send the rest of the path to "/".
			if (i === 0) cur = "/";
			continue;
		}
		cur = (cur === "" ? "" : (cur === "/" ? "/" : cur + "/")) + part;
		if (!fs.access(cur, "r") && !fs.mkdir(cur, 493))
			return false;
	}
	return true;
};
