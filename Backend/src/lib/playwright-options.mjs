export function playwrightLaunchOptions(env = process.env) {
  const options = {};
  const executablePath = String(env.PLAYWRIGHT_EXECUTABLE_PATH || "").trim();
  const channel = String(env.PLAYWRIGHT_CHANNEL || "").trim();
  if (executablePath) options.executablePath = executablePath;
  else if (channel) options.channel = channel;
  return options;
}
