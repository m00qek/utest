// Loaded via loadfile() — no import/export. Circular-reference protection is
// intentionally omitted because this is only used to compare JSON-derived data,
// which cannot contain cycles.
// format_path duplicates src/utest/util.uc: this file runs in program mode and
// cannot import ES modules. Keep both in sync if the logic ever changes.
function deep_equal(a, b) {
	if (a === b) return true;
	if (type(a) != type(b)) return false;
	if (type(a) == "array") {
		if (length(a) != length(b)) return false;
		for (let i = 0; i < length(a); i++) {
			if (!deep_equal(a[i], b[i])) return false;
		}
		return true;
	}
	if (type(a) == "object") {
		let ka = keys(a);
		let kb = keys(b);
		if (length(ka) != length(kb)) return false;
		for (let k in ka) {
			if (!exists(b, k) || !deep_equal(a[k], b[k])) return false;
		}
		return true;
	}
	return a == b;
}

function format_path(path) {
	let parts = [];
	for (let p in path) {
		if (p.id != 0) push(parts, p.name);
	}
	return join(" > ", parts);
}

return { deep_equal, format_path };
