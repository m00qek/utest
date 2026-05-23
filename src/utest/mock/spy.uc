export function spy(obj) {
	if (!obj || !obj.__utest__ || !obj.__utest__.calls)
		die("spy(): argument is not a spyable object");
	return { calls: obj.__utest__.calls };
};
