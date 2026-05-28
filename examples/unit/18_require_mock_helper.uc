// Simulates code under test that uses require() instead of import.
// require() is called lazily inside the function so mock.global.patch() intercepts per-call.
export function compute_abs(x) {
	return require('math').abs(x);
};
