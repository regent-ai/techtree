type LogLevel = "info" | "warn" | "error";

const write = (level: LogLevel, message: string, meta?: unknown): void => {
  const payload = meta ? ` ${JSON.stringify(meta)}` : "";
  const line = `[xmtp-worker] ${level.toUpperCase()} ${message}${payload}`;
  if (level === "error") {
    console.error(line);
    return;
  }
  console.log(line);
};

export const logger = {
  info: (message: string, meta?: unknown) => write("info", message, meta),
  warn: (message: string, meta?: unknown) => write("warn", message, meta),
  error: (message: string, meta?: unknown) => write("error", message, meta),
};
