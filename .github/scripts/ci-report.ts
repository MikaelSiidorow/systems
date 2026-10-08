// Builds the single CI report comment on a pull request. Each check writes a
// JSON section with report-section.sh; ci.yml's report job collects them.
// Imported from actions/github-script (Node 24 strips the types), which
// passes { github, context }.
import fs from "node:fs";
import path from "node:path";

type Status = "success" | "changes" | "failure" | "skipped";

interface Section {
  key: string;
  order: number;
  title: string;
  status: Status;
  summary: string;
  details: string;
}

interface Meta {
  sha: string;
  runUrl: string;
  results?: Record<string, string | undefined>;
}

// The parts of github-script's arguments this file uses.
interface Api {
  github: any;
  context: any;
}

const MARKER = "<!-- ci-report -->";
const ICONS: Record<Status, string> = {
  success: "✅",
  changes: "🔄",
  failure: "❌",
  skipped: "⏭️",
};
// Shown as "not affected" when their check did not run.
const EXPECTED: Omit<Section, "status" | "summary" | "details">[] = [
  { key: "workstations", order: 10, title: "Workstations" },
  { key: "k8s", order: 15, title: "k8s manifests" },
  { key: "nixos", order: 20, title: "k8s-server + Hestia" },
  { key: "openwrt", order: 30, title: "OpenWrt routers" },
  { key: "terraform", order: 40, title: "Terraform" },
  { key: "k8s-terraform", order: 50, title: "k8s Terraform" },
];
// Per-check comments from before this report existed.
const LEGACY = ["### NixOS Preview", "### Terraform Results", "### K8s Terraform Results"];
const MAX_DETAILS = 20000;

function readSections(dir: string): Section[] {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".json"))
    .map((f) => JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")));
}

function overall(sections: Section[]): Status {
  const statuses = sections.map((s) => s.status);
  if (statuses.includes("failure")) return "failure";
  if (statuses.includes("changes")) return "changes";
  return "success";
}

export function render(found: Section[], { sha, runUrl, results = {} }: Meta): string {
  const sections = [...found];
  for (const e of EXPECTED) {
    if (!sections.some((s) => s.key === e.key)) {
      sections.push({ ...e, status: "skipped", summary: "not affected", details: "" });
    }
  }
  // A called workflow can fail before any of its checks write a section.
  for (const [name, result] of Object.entries(results)) {
    if (
      (result === "failure" || result === "cancelled") &&
      !found.some((s) => s.status === "failure")
    ) {
      sections.push({
        key: name,
        order: 90,
        title: name,
        status: "failure",
        summary: `${result} before reporting`,
        details: "",
      });
    }
  }
  sections.sort((a, b) => a.order - b.order);

  const lines = [
    MARKER,
    `### ${ICONS[overall(sections)]} CI report · \`${sha.slice(0, 7)}\``,
    "",
    "| | Check | Summary |",
    "|---|---|---|",
    ...sections.map((s) => `| ${ICONS[s.status] ?? "❔"} | ${s.title} | ${s.summary} |`),
    "",
  ];
  for (const s of sections.filter((s) => s.details)) {
    let details = s.details;
    if (details.length > MAX_DETAILS) {
      // Close the code block with the fence it was opened with.
      const fence = details.match(/^`{3,}/m)?.[0] ?? "```";
      details = `${details.slice(0, MAX_DETAILS)}\n…\n${fence}\n\n*Truncated; see the run log for the rest.*`;
    }
    lines.push(
      `<details><summary>${ICONS[s.status] ?? "❔"} ${s.title}: ${s.summary}</summary>`,
      "",
      `<!-- ci:${s.key} -->`,
      details,
      `<!-- /ci:${s.key} -->`,
      "",
      "</details>",
      "",
    );
  }
  lines.push(`<sub>[Workflow run](${runUrl})</sub>`);
  return lines.join("\n");
}

export function running({ sha, runUrl }: Meta): string {
  return [
    MARKER,
    `### ⏳ CI report · \`${sha.slice(0, 7)}\``,
    "",
    `Checks are running. This comment is replaced with the results when they finish. [Workflow run](${runUrl})`,
  ].join("\n");
}

async function upsert({ github, context }: Api, body: string): Promise<void> {
  const { owner, repo } = context.repo;
  const issue_number = context.issue.number;
  const comments = await github.paginate(github.rest.issues.listComments, {
    owner,
    repo,
    issue_number,
    per_page: 100,
  });
  const ours = comments.filter((c: any) => c.user?.type === "Bot");
  const existing = ours.find((c: any) => c.body?.startsWith(MARKER));
  if (existing) {
    await github.rest.issues.updateComment({ owner, repo, comment_id: existing.id, body });
  } else {
    await github.rest.issues.createComment({ owner, repo, issue_number, body });
  }
  for (const c of ours.filter((c: any) => LEGACY.some((h) => c.body?.startsWith(h)))) {
    await github.rest.issues.deleteComment({ owner, repo, comment_id: c.id });
  }
}

function meta(context: any): Meta {
  return {
    sha: context.payload.pull_request.head.sha,
    runUrl: `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`,
  };
}

export function start(api: Api): Promise<void> {
  return upsert(api, running(meta(api.context)));
}

export function finish(
  api: Api,
  { dir, results }: { dir: string; results: Meta["results"] },
): Promise<void> {
  return upsert(api, render(readSections(dir), { ...meta(api.context), results }));
}
