/**
 * @typedef {{calls: Object<string, Array<any>>}} Spy
 */

/**
 * Returns a spy interface to inspect calls made to a mock proxy.
 * 
 * @param {Object} obj - The mock proxy object.
 * @returns {Spy} An object containing the recorded calls.
 */
export function spy(obj) {
	if (!obj || !obj.__utest__ || !obj.__utest__.calls)
		die("spy(): argument is not a spyable object");
	return { calls: obj.__utest__.calls };
};
