import { describe, it, assert } from 'utest';

describe("User Management", () => {
	describe("Registration", () => {
		it("creates a new user", () => {
			const user = { name: 'alice', email: 'alice@example.com' };
			assert.match('alice', user.name);
		});

		it("prevents duplicate emails", () => {
			const seen = { 'alice@example.com': true };
			assert.match(true, seen['alice@example.com']);
			assert.match(null, seen['bob@example.com']);
		});
	});

	describe("Permissions", () => {
		it("allows admins to delete users", () => {
			const perms = { admin: true, viewer: false };
			assert.match(true, perms.admin);
		});

		describe("Read-only users", () => {
			it("cannot modify data", () => {
				const perms = { admin: true, viewer: false };
				assert.match(false, perms.viewer);
			});
		});
	});
});
