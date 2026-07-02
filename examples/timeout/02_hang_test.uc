import { describe, it } from 'utest';

describe("Hanging suite", () => {
	it("never returns", () => { while (true) {} });
});
