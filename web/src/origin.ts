// Plain http only on this device itself, where no network attacker sits in between.
const LOOPBACK: ReadonlySet<string> = new Set([
  "localhost",
  "127.0.0.1",
  "[::1]",
]);

export function isTrustedPage(protocol: string, hostname: string): boolean {
  return (
    protocol === "https:" || (protocol === "http:" && LOOPBACK.has(hostname))
  );
}
