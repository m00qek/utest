import { describe, it, assert, mock } from 'utest';

// A custom proxy that names a channel after reserved metadata (fns/strict/calls/
// proxy/channels) would corrupt that metadata; the engine must reject it.
describe('reserved channel names', () => {
	it('a proxy declaring a reserved channel name fails at inject', () => {
		assert.throws(() => mock.inject('widget', { data: {} }, () => {}),
		              /reserved channel name 'calls'/);
	});
});
