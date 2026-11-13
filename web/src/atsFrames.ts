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

// Form builders that sites embed for their application forms, such as Modal's builder grant
// form on modal.com/builders, which is a Fillout form in a frame from embed.fillout.com.
// These run Prefill in the frame like an ATS does, but aren't assumed to be job applications.
const FORM_FRAME_HOSTS: ReadonlySet<string> = new Set(["embed.fillout.com", "forms.fillout.com"]);

// Each company gets its own subdomain here, such as acme.wd5.myworkdayjobs.com or
// us-careers-acme.icims.com (iCIMS shows its form in a frame from the same host).
const DOMAIN_SUFFIXES: readonly string[] = ["myworkdayjobs.com", "icims.com"];

export function isAtsHost(hostname: string): boolean {
  return EXACT_HOSTS.has(hostname) || DOMAIN_SUFFIXES.some((domain) => hostname === domain || hostname.endsWith(`.${domain}`));
}

export function isAtsFrame(protocol: string, hostname: string): boolean {
  return protocol === "https:" && (isAtsHost(hostname) || FORM_FRAME_HOSTS.has(hostname));
}
