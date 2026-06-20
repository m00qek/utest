import { describe, it, assert, mock } from 'utest';

// mock.inject_all() sets up multiple proxy layers in one call and tears them
// all down after the callback, regardless of whether it throws.  The callback
// receives an object whose keys are the proxy names.

describe('mock.inject_all()', () => {
	it('injects two proxies and exposes them as named deps', () => {
		mock.inject_all({
			uci:  { data: { 'network': { 'lan': { '.type': 'interface', 'ipaddr': '192.168.1.1' } } } },
			ubus: { data: { 'network.interface:dump': { interface: [{ interface: 'lan', up: true }] } } }
		}, (deps) => {
			const ip = deps.uci.cursor().get('network', 'lan', 'ipaddr');
			assert.match('192.168.1.1', ip);

			const dump = deps.ubus.connect().call('network.interface', 'dump', {});
			assert.match('lan', dump.interface[0].interface);
		});
	});

	it('injects three proxies at once', () => {
		mock.inject_all({
			uci:  { data: { 'system': { 'cfg': { '.type': 'system', 'hostname': 'myrouter' } } } },
			ubus: { data: { 'system:board': { model: 'Test Board' } } },
			fs:   { data: { '/etc/hostname': 'myrouter\n' } }
		}, (deps) => {
			assert.match('myrouter', deps.uci.cursor().get('system', 'cfg', 'hostname'));
			assert.match('Test Board', deps.ubus.connect().call('system', 'board', {}).model);
			assert.match('myrouter\n', deps.fs.readfile('/etc/hostname'));
		});
	});

	it('cleans up all proxy layers after the callback', () => {
		mock.inject_all({
			uci:  { data: { 'pkg': { 'sec': { '.type': 't', 'opt': 'val' } } } },
			ubus: { data: { 'svc:status': { running: true } } }
		}, (deps) => {
			assert.match('val', deps.uci.cursor().get('pkg', 'sec', 'opt'));
			assert.match(true, deps.ubus.connect().call('svc', 'status', {}).running);
		});

		// Both layers must be gone — a fresh inject sees only its own state.
		mock.inject_all({
			uci:  { data: {} },
			ubus: { data: {} }
		}, (deps) => {
			assert.match(null, deps.uci.cursor().get('pkg', 'sec', 'opt'));
			assert.match(null, deps.ubus.connect().call('svc', 'status', {}));
		});
	});

	it('cleans up all layers even when the callback throws', () => {
		assert.throws(() => {
			mock.inject_all({
				uci:  { data: { 'p': { 's': { '.type': 't', 'k': 'v' } } } },
				ubus: { data: {} }
			}, (deps) => {
				assert.match('v', deps.uci.cursor().get('p', 's', 'k'));
				die('intentional error');
			});
		}, /intentional error/);

		mock.inject_all({
			uci: { data: {} }
		}, (deps) => {
			assert.match(null, deps.uci.cursor().get('p', 's', 'k'), 'uci layer cleaned up despite throw');
		});
	});

	it('dies immediately when a proxy name is not configured', () => {
		assert.throws(() => {
			mock.inject_all({
				uci:     { data: {} },
				no_such: { data: {} }
			}, () => {});
		}, /mock\.inject_all.*no_such/);
	});
});

describe('mock.inject() unknown proxy', () => {
	it('inject() with an unknown proxy name dies with a clear error', () => {
		assert.throws(
			() => mock.inject('no_such_proxy', { data: {} }, () => {}),
			/no_such_proxy/
		);
	});
});
