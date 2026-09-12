// Persistent browser sessions are available on the Node/container deployment.
// Workers use the HTTP providers and return disabled for these optional channels.
export const chromium = { launchPersistentContext() { throw new Error("browser_session_unavailable_on_workers"); } };
