import { links, site } from "../site.config";

export const prerender = true;

export function GET() {
  const body = [
    `# ${site.name}`,
    `> ${site.summary}`,
    "",
    "## When to use this",
    "- Best fit: focus timing with distraction capture on Mac, iPhone, and Apple Watch",
    "- Best fit: understanding what actually interrupts your focus sessions over time",
    "- Not a fit: social productivity tracking or gamified focus apps",
    "- Not a fit: cloud-based distraction logging or team analytics",
    "",
    "## Primary",
    `- [Product overview](${links.home}index.md): Canonical Markdown summary of ${site.name}.`,
    `- [Privacy](${links.privacy}): Current privacy policy.`,
    `- [Support](${links.support}): Support and feedback.`,
    `- [TestFlight](${links.testflight}): Current beta availability.`,
    "",
    "## Machine surfaces",
    `- [Agent catalog](${site.url}/api/ai)`,
    `- [OpenAPI spec](${site.url}/openapi.json)`,
    `- [Sitemap](${site.url}/sitemap.xml)`,
    `- [This index](${site.url}/llms.txt)`,
    "",
    "## Product boundaries",
    ...site.boundaries.map((item) => `- ${item}`),
    ""
  ].join("\n");
  return new Response(body, { headers: { "content-type": "text/plain; charset=utf-8" } });
}
