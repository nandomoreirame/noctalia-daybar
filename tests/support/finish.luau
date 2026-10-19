--!strict
-- Trailing chunk for multi-file `luau` runs: print summary and exit non-zero on failure.
-- Luau CLI has no atexit; run-tests appends this file after all tests/*.test.luau.
local runner = require("./runner")
runner.finish()
