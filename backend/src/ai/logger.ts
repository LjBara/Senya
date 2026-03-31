export type RequestLogger = {
  info: (msg: string, data?: Record<string, unknown>) => void;
  warn: (msg: string, data?: Record<string, unknown>) => void;
  error: (msg: string, data?: Record<string, unknown>) => void;
};

export function createRequestLogger(requestId: string): RequestLogger {
  const p = `[ai ${requestId}]`;
  return {
    info: (msg, data) => console.log(p, msg, data ?? ''),
    warn: (msg, data) => console.warn(p, msg, data ?? ''),
    error: (msg, data) => console.error(p, msg, data ?? ''),
  };
}
