// Job application forms that company career pages embed in a frame. Prefill runs in a frame
// only when the frame itself is one of these, over https, so an ad or widget from any other
// site can't reorder the card or record values under its own host.
const EXACT_HOSTS: ReadonlySet<string> = new Set([
  "boards.greenhouse.io",
  "boards.eu.greenhouse.io",
  "job-boards.greenhouse.io",
  "job-boards.eu.greenhouse.io",
  "jobs.lever.co",
  "jobs.eu.lever.co",
  "jobs.ashbyhq.com",
  "apply.workable.com",
  "jobs.smartrecruiters.com",
]);

// Each company gets its own subdomain here, such as acme.wd5.myworkdayjobs.com.
const DOMAIN_SUFFIXES: readonly string[] = ["myworkdayjobs.com"];

export function isAtsHost(hostname: string): boolean {
  return EXACT_HOSTS.has(hostname) || DOMAIN_SUFFIXES.some((domain) => hostname === domain || hostname.endsWith(`.${domain}`));
}

export function isAtsFrame(protocol: string, hostname: string): boolean {
  return protocol === "https:" && isAtsHost(hostname);
}
