// Loaded via require() in ucode program mode — see proxy_base.uc for why `return` is used here.
return {
	api: ['init', 'timer', 'run', 'end'],
	// The timer queue lives in its own channel, not the 'data' channel, so a user
	// who mocks a data key (even one literally named '__pending__') can never
	// collide with the mock's internal timer bookkeeping.
	channels: ['timers'],
	create: function(name, real, ctx) {
		let proxy = ctx.base();

		proxy.init = function() {
			ctx.record_call('init', []);
			let f = ctx.get_behavior('init');
			if (f) return f();
		};

		// The timer queue is transient per-scope state: read and clear it in the
		// current scope only (get_local, no fall-through) so timers registered in
		// an outer/global scope are neither copied into a nested layer nor left
		// behind — a falling-through read would consume them here yet clear only
		// this scope, re-firing them after the layer pops.
		//
		// timer() returns a handle matching the real uloop.timer resource
		// (set/remaining/cancel), so a SUT that stores its timer and later
		// reschedules or cancels it works under the mock instead of tripping over a
		// null return. The handle is stored in the queue *by reference* (channel
		// get/set do not clone), so cancel()/set() mutating it are visible to run().
		proxy.timer = function(ms, cb) {
			ctx.record_call('timer', [ms, cb]);
			let f = ctx.get_behavior('timer');
			if (f) return f(ms, cb);
			// The mock has no clock to advance, so `remaining` is simply the armed
			// deadline; cancel() marks the handle dead (remaining -1, skipped by run)
			// and set() re-arms it with a new deadline. Both return the handle so a
			// SUT can chain, matching the real resource.
			let handle = { ms, cb, cancelled: false };
			handle.remaining = () => handle.cancelled ? -1 : handle.ms;
			handle.cancel    = () => { handle.cancelled = true; return handle; };
			handle.set       = (new_ms) => { handle.ms = new_ms; handle.cancelled = false; return handle; };
			const pending = ctx.get_local('timers', 'queue');
			ctx.set('timers', 'queue', [...(type(pending) === 'array' ? pending : []), handle]);
			return handle;
		};

		proxy.run = function() {
			ctx.record_call('run', []);
			let f = ctx.get_behavior('run');
			if (f) return f();
			let pending = ctx.get_local('timers', 'queue') || [];
			ctx.set('timers', 'queue', []);
			// A handle cancelled before run() must not fire; read each handle's
			// CURRENT ms so a set() issued before run() reschedules it correctly.
			let live = filter(pending, (t) => !t.cancelled);
			// Real uloop fires timers in deadline order, not registration order, so a
			// deadline-dependent SUT that passes under a naive FIFO mock would fail on
			// target. Sort by ms, breaking ties on the original registration index
			// (ucode's sort is not guaranteed stable) to preserve the real
			// "equal-deadline timers fire in the order armed" behavior. This is a
			// single pass: timers armed (or re-armed via set()) by a callback need
			// another run() (documented).
			let ordered = map(live, (t, i) => ({ t, i }));
			sort(ordered, (a, b) => (a.t.ms - b.t.ms) || (a.i - b.i));
			for (let e in ordered) e.t.cb();
		};

		proxy.end = function() {
			ctx.record_call('end', []);
			let f = ctx.get_behavior('end');
			if (f) return f();
		};

		return proxy;
	}
};
