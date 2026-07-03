// A deliberately-misconfigured custom proxy: it declares a channel named after a
// reserved metadata key ('calls'), which the engine must reject rather than let
// it silently clobber call-recording state.
return {
	channels: ['calls'],
	create: function(name, real, ctx) { return ctx.base(); }
};
