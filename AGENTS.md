# CueX project workflow

The user has authorized automatic Git commits and pushes for CueX codebase updates.

- Before making any codebase changes, inspect the working tree, fetch the latest changes from GitHub, and integrate the current branch's upstream so work starts from up-to-date code. Other collaborators and their agents may have pushed changes since the last session. Preserve local edits and commits; never discard work to synchronize. If fetching or integration fails, resolve the problem before changing code, or explain the blocker to the user.
- After completing a requested codebase update, commit the relevant source, documentation, and project configuration changes with a descriptive message and push to the current branch's upstream. The default workflow is `main` tracking `origin/main`.
- Do not ask for commit or push confirmation again unless the user changes this preference or an action requires additional authorization.
- Include only changes belonging to the requested work. Preserve unrelated user edits.
- Respect `.gitignore`; personal Logic projects, setlists, generated app bundles, and build caches stay out of Git.
- Use normal pushes. Do not force-push or rewrite published history. If a push is rejected, inspect remote changes and integrate them without discarding work.
- Report the commit and push outcome in the final response. If authentication, network access, or conflicts prevent publishing, preserve the work and explain what remains.
- This is an end-of-task workflow, not a background file watcher. Do not auto-commit partially completed edits.
