/**
 * @typedef {{ calls: dict<any[]> }} Spy
 */

/**
 * Returns a spy interface to inspect calls made to a mock proxy.
 *
 * @param {any} obj - The mock proxy object.
 * @returns {Spy} An object containing the recorded calls.
 */
export function spy(obj) {
	if (!obj || !obj.__utest__)
		die("spy(): argument is not a spyable object");
	// Module proxies store their registry name for a live lookup so spy() always
	// reflects the currently active layer's call dict.  Inner objects (e.g. the
	// connection object returned by ubus.connect()) store a local calls dict
	// directly — they are not in the registry and have no layer stack.
	if (obj.__utest__.name)
		return { calls: global.__utest_internal_instance.get_calls(obj.__utest__.name) };
	if (obj.__utest__.calls)
		return { calls: obj.__utest__.calls };
	die("spy(): argument is not a spyable object");
};
