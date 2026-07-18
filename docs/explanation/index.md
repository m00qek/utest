# Explanation

Understanding-oriented material that explains the design decisions and concepts behind utest. These pages answer "why does it work this way?" rather than "how do I do X?".

---

## For test authors

| Page | What it covers |
| :--- | :--- |
| [About the mocking architecture](concepts.md) | Why utest separates shim, proxy, and mock engine — and how the layer model enables safe nested mocking |
| [About test isolation](test-isolation.md) | What the framework guarantees between tests and where that guarantee ends |
| [About inject() vs global.patch()](inject-vs-patch.md) | Why two mock mechanisms exist and when to use each |
| [About strict mode](strict-mode.md) | The philosophy behind failing on unmocked calls and the trade-offs involved |
| [About property-based testing](property-based-testing.md) | How the shrinking model works, and how randomness is managed |

---

## For contributors

| Page | What it covers |
| :--- | :--- |
| [About the worker/coordinator](worker-coordinator.md) | Why tests run in subprocesses and how the coordinator collects results |
| [About the reporter architecture](reporter-architecture.md) | Why the worker/coordinator reporter split exists and how the coordinator-side hook model works |
| [About the mock engine](mock-engine.md) | The registry, layer stack, and snapshot/restore design |
| [About shim generation](shim-generation.md) | Why shims exist and how manager.uc generates them at runtime |
