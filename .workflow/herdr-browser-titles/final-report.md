# Final report

Status: focused verification passed; integration rebuild belongs to the parent session.

Evidence:

- `python3 -m unittest -v tests/test_herdr_title.py`: 16 passed.
- Fake Unix-socket snapshot/rename and fake HTTP request validation passed.
- Python compilation, workflow-schema verification, Nix evaluation, the compiled-hook derivation build, and diff whitespace checks passed.
- 100-run compiled-hook measurements: coordinator available median 0.986 ms, p95 1.228 ms, maximum 2.132 ms; coordinator unavailable median 1.033 ms, p95 2.043 ms, maximum 2.162 ms.
- No active Herdr command or real DashScope request was issued.
