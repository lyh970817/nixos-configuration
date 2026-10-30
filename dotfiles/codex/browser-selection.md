Use Chromium for unspecified browser requests and clean browsing. "My browser"
or "my personal browser" means Brave with the user's existing signed-in profile.
An explicitly named browser or attached browser tab takes precedence. Keep using
that browser for the task; ask before switching to the other browser.

Select the browser by family (chrome for Chromium, brave for Brave), rather than
the first available extension or the runtime default. CLI and desktop share each
browser's normal profile; they do not need copies of its credentials.

Use the browser-control skill advertised by the current session for the chosen
browser, and follow that skill's setup and troubleshooting instructions. If the
skill is absent, inspect the installed client's enabled plugin configuration
and runtime, then check discovery again before concluding browser control is
unavailable. Do not load a disabled skill from an old plugin cache.
