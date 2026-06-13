/**
 * @typedef {Object} Spy
 * @property {Object<string, Array<any>>} calls - The recorded calls map.
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
