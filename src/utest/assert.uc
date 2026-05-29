import { parse_thrown } from 'utest.util';
import { is_combinator, equals } from 'utest.combinators';

function fail(msg) {
	die(sprintf('%J', { __utest__: { kind: 'fail', message: msg } }));
}

function unwrap_error_msg(e) {
	return parse_thrown(e).message;
}

export const assert = {
	throws: function(fn, pattern, msg) {
		try {
			fn();
		} catch (e) {
			if (pattern) {
				const emsg = unwrap_error_msg(e);
				if (!match(emsg, pattern))
					fail(msg || sprintf("Exception '%s' did not match pattern %s", emsg, pattern));
			}
			return;
		}
		fail(msg || "Expected exception but none was thrown");
	},

	match: function(expected, actual, msg) {
		const r = (is_combinator(expected) ? expected : equals(expected)).match(actual);
		if (!r.ok) fail(msg ? (msg + "\n" + r.message) : r.message);
	}
};
