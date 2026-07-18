// Decoy: a sibling file coincidentally named after the module the companion
// config's lib_paths entry (greeting_lib/greeting.uc) provides. It must never
// be what `require('greeting')` resolves to in this directory's test — see
// 01_requireshadow_test.uc and bootstrap.uc. Loaded via require() in ucode
// program mode, not ES-module mode — export is unavailable.
return {
	greet: function() {
		return "DECOY (test directory)";
	}
};
