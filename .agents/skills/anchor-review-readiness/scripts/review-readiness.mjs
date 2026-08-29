#!/usr/bin/env node

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const skillDir = resolve(scriptDir, "..");
const repoRoot = resolve(skillDir, "../../..");
process.chdir(repoRoot);

const argv = process.argv.slice(2);
const has = (flag) => argv.includes(flag);
const value = (flag) => {
  const index = argv.indexOf(flag);
  return index >= 0 ? argv[index + 1] : undefined;
};

if (has("--help")) {
  console.log(`Usage: review-readiness.mjs [options]\n\n  --full                           Run non-disruptive native builds and visual catalog\n  --allow-disruptive-local-ui      Also drive local Mac/iPhone UI (isolated workers only)\n  --policy-checked YYYY-MM-DD      Record current Apple policy refresh\n  --archive /path/Anchor.xcarchive Inspect an exact release archive\n  --physical-iphone-observed       Current build launched on owner iPhone\n  --authenticated-data-observed   Fresh signed-in account has clean provenance\n  --simulator-name NAME            Override stable iPhone simulator\n  --developer-dir PATH             Override stable Xcode Developer directory`);
  process.exit(0);
}

const full = has("--full");
const allowDisruptiveLocalUI = has("--allow-disruptive-local-ui");
const policyChecked = value("--policy-checked");
const archivePath = value("--archive");
const developerDir = value("--developer-dir")
  ?? process.env.ANCHOR_REVIEW_DEVELOPER_DIR
  ?? "/Applications/Xcode-26.6.0.app/Contents/Developer";
const simulatorName = value("--simulator-name")
  ?? "Anchor Evidence Stable iPhone 20260828";
const stamp = new Date().toISOString().replaceAll(":", "-").replace(/\.\d{3}Z$/, "Z");
const outputDir = join(repoRoot, "build", "review-readiness", stamp);
mkdirSync(outputDir, { recursive: true });

const results = [];
const policies = [
  "https://developer.apple.com/app-store/review/guidelines/",
  "https://developer.apple.com/news/upcoming-requirements/",
  "https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/",
  "https://developer.apple.com/documentation/bundleresources/privacy_manifest_files"
];

function addResult(id, label, status, detail, logPath) {
  results.push({ id, label, status, detail, ...(logPath ? { logPath } : {}) });
  const glyph = status === "pass" ? "PASS" : status === "warn" ? "WARN" : status === "manual" ? "MANUAL" : "FAIL";
  console.log(`[${glyph}] ${label}${detail ? ` — ${detail}` : ""}`);
}

function run(id, label, command, args, { blocking = true, env = {} } = {}) {
  const started = Date.now();
  const child = spawnSync("rtk", [command, ...args], {
    cwd: repoRoot,
    env: { ...process.env, ...env },
    encoding: "utf8",
    maxBuffer: 128 * 1024 * 1024
  });
  const logPath = join(outputDir, `${id}.log`);
  const commandText = ["rtk", command, ...args].map((part) => JSON.stringify(part)).join(" ");
  writeFileSync(logPath, `$ ${commandText}\n\n${child.stdout ?? ""}${child.stderr ?? ""}`);
  const ok = child.status === 0;
  addResult(
    id,
    label,
    ok ? "pass" : blocking ? "fail" : "warn",
    `${ok ? "completed" : `exit ${child.status ?? "unknown"}`} in ${Math.round((Date.now() - started) / 1000)}s`,
    logPath
  );
  return ok;
}

function evidenceChecks() {
  const matrixPath = join(skillDir, "references", "feature-matrix.json");
  const matrix = JSON.parse(readFileSync(matrixPath, "utf8"));
  for (const feature of matrix.features) {
    const missing = feature.evidence.filter((item) => {
      try {
        return !readFileSync(join(repoRoot, item.file), "utf8").includes(item.contains);
      } catch {
        return true;
      }
    });
    addResult(
      `feature-${feature.id}`,
      feature.name,
      missing.length === 0 ? "pass" : "fail",
      missing.length === 0
        ? `${feature.evidence.length} declared evidence hook(s) present`
        : `missing: ${missing.map((item) => `${item.file} :: ${item.contains}`).join("; ")}`
    );
  }
}

function designReceiptCheck() {
  const project = readFileSync(join(repoRoot, "Apps", "project.yml"), "utf8");
  const build = project.match(/CURRENT_PROJECT_VERSION:\s*"([^"]+)"/)?.[1];
  try {
    const receipt = JSON.parse(readFileSync(join(repoRoot, ".fleet", "design-review.json"), "utf8"));
    const target = String(receipt.target ?? "");
    addResult(
      "design-receipt",
      "Design review receipt matches current build",
      build && target.includes(build) ? "pass" : "fail",
      `build ${build ?? "unknown"}; receipt target: ${target || "missing"}`
    );
  } catch (error) {
    addResult("design-receipt", "Design review receipt matches current build", "fail", String(error));
  }
}

function manualGates() {
  if (policyChecked && /^\d{4}-\d{2}-\d{2}$/.test(policyChecked)) {
    addResult("policy-current", "Current Apple policy sources refreshed", "pass", policyChecked);
  } else {
    addResult("policy-current", "Current Apple policy sources refreshed", "manual", "supply --policy-checked after opening all official sources");
  }
  addResult(
    "authenticated-data",
    "Fresh authenticated account has clean history provenance",
    has("--authenticated-data-observed") ? "pass" : "manual",
    has("--authenticated-data-observed") ? "owner-observed" : "Google completion and unexplained old history remain an explicit gate"
  );
  addResult(
    "physical-iphone",
    "Current build launches on the owner iPhone",
    has("--physical-iphone-observed") ? "pass" : "manual",
    has("--physical-iphone-observed") ? "owner-observed" : "physical launch evidence not supplied"
  );
  if (!archivePath) {
    addResult("exact-archive", "Exact review archive supplied and inspected", "manual", "no --archive supplied");
  }
}

run("diff-check", "Git patch is structurally clean", "git", ["diff", "--check"]);
run("privacy-manifest", "Privacy manifest is valid", "plutil", ["-lint", "Apps/Shared/PrivacyInfo.xcprivacy"]);
run("mac-entitlements", "Mac entitlements are valid plists", "plutil", ["-lint", "Apps/Mac/Anchor.entitlements", "Apps/Mac/Anchor.DirectDistribution.entitlements"]);
run("ios-entitlements", "iPhone and Watch entitlements are valid plists", "plutil", ["-lint", "Apps/iOS/Anchor.entitlements", "Apps/Watch/Anchor.entitlements"]);
evidenceChecks();
designReceiptCheck();
run("swift-test", "All Swift package tests pass", "swift", ["test"]);
run("model-diagnose", "On-device tagging diagnostic passes", ".build/debug/anchor-mcp", ["--diagnose"]);
run("xcodegen", "Generated Xcode project matches project.yml", "xcodegen", ["generate", "--spec", "Apps/project.yml", "--project", "Apps"]);
run("xcode-version", "Stable Xcode toolchain is available", "xcodebuild", ["-version"], { env: { DEVELOPER_DIR: developerDir } });

if (full) {
  const common = ["-y", "xcodebuildmcp@2.7.0"];
  run(
    "visual-catalog",
    "Every primary surface renders offscreen",
    "scripts/render-visual-catalog.sh",
    [join(outputDir, "visual-catalog")]
  );
  run(
    "mac-build",
    "macOS app compiles on stable Xcode",
    "env",
    [
      `DEVELOPER_DIR=${developerDir}`,
      "npx", ...common,
      "macos", "build",
      "--project-path", "Apps/Anchor.xcodeproj",
      "--scheme", "Anchor (macOS)",
      "--configuration", "DebugLocal",
      "--derived-data-path", join(outputDir, "DerivedData-Mac-Build"),
      "--output", "json"
    ]
  );
  run(
    "ios-build",
    "iPhone app compiles on stable Xcode",
    "env",
    [
      `DEVELOPER_DIR=${developerDir}`,
      "xcodebuild",
      "-project", "Apps/Anchor.xcodeproj",
      "-scheme", "Anchor (iOS)",
      "-configuration", "DebugLocal",
      "-destination", "generic/platform=iOS Simulator",
      "-derivedDataPath", join(outputDir, "DerivedData-iOS-Build"),
      "build"
    ]
  );
  run(
    "watch-build",
    "watchOS companion compiles on stable Xcode",
    "env",
    [
      `DEVELOPER_DIR=${developerDir}`,
      "xcodebuild",
      "-project", "Apps/Anchor.xcodeproj",
      "-scheme", "Anchor (watchOS)",
      "-configuration", "DebugLocal",
      "-destination", "generic/platform=watchOS Simulator",
      "-derivedDataPath", join(outputDir, "DerivedData-Watch"),
      "build"
    ],
    { blocking: false }
  );

  if (allowDisruptiveLocalUI) {
    run(
      "mac-ui",
      "Complete macOS UI suite passes",
      "env",
      [
        `DEVELOPER_DIR=${developerDir}`,
        "npx", ...common,
        "macos", "test",
        "--project-path", "Apps/Anchor.xcodeproj",
        "--scheme", "Anchor (macOS)",
        "--configuration", "DebugLocal",
        "--derived-data-path", join(outputDir, "DerivedData-Mac-UI"),
        "--output", "json"
      ]
    );
    run(
      "ios-ui",
      "Complete iPhone UI suite passes",
      "env",
      [
        `DEVELOPER_DIR=${developerDir}`,
        "npx", ...common,
        "simulator", "test",
        "--project-path", "Apps/Anchor.xcodeproj",
        "--scheme", "Anchor (iOS)",
        "--configuration", "DebugLocal",
        "--simulator-name", simulatorName,
        "--derived-data-path", join(outputDir, "DerivedData-iOS-UI"),
        "--output", "json"
      ]
    );
  } else {
    addResult("mac-ui", "Complete macOS UI suite passes", "manual", "run the isolated GitHub workflow; local UI remains intentionally disabled");
    addResult("ios-ui", "Complete iPhone UI suite passes", "manual", "run the isolated GitHub workflow; local UI remains intentionally disabled");
  }
} else {
  addResult("visual-catalog", "Every primary surface renders offscreen", "manual", "rerun with --full");
  addResult("mac-ui", "Complete macOS UI suite passes", "manual", "run the isolated GitHub workflow");
  addResult("ios-ui", "Complete iPhone UI suite passes", "manual", "run the isolated GitHub workflow");
}

if (archivePath) {
  run("archive-info", "Exact archive has readable metadata", "plutil", ["-p", join(archivePath, "Info.plist")]);
  run(
    "archive-entitlements",
    "Exact archive carries inspectable app entitlements",
    "codesign",
    ["-d", "--entitlements", ":-", join(archivePath, "Products/Applications/Anchor.app")]
  );
}

manualGates();

const blockers = results.filter((item) => item.status === "fail" || item.status === "manual");
const warnings = results.filter((item) => item.status === "warn");
const report = {
  schema: "anchor.review-readiness.v1",
  generatedAt: new Date().toISOString(),
  repository: repoRoot,
  scope: ["macOS", "iOS"],
  mode: full ? (allowDisruptiveLocalUI ? "full-isolated-ui" : "full-nondisruptive") : "quick",
  developerDir,
  simulatorName,
  policy: { checkedAt: policyChecked ?? null, sources: policies },
  status: blockers.length === 0 ? "READY" : "NOT_READY",
  counts: { pass: results.filter((item) => item.status === "pass").length, blockers: blockers.length, warnings: warnings.length },
  results
};

const jsonPath = join(outputDir, "report.json");
const markdownPath = join(outputDir, "report.md");
writeFileSync(jsonPath, `${JSON.stringify(report, null, 2)}\n`);
const lines = [
  "# Anchor review readiness",
  "",
  `Status: **${report.status.replace("_", " ")}**`,
  "",
  `Generated: ${report.generatedAt}`,
  `Mode: ${report.mode}`,
  `Passes: ${report.counts.pass}; blockers/manual gates: ${report.counts.blockers}; warnings: ${report.counts.warnings}`,
  "",
  "## Results",
  "",
  ...results.map((item) => `- **${item.status.toUpperCase()}** — ${item.label}: ${item.detail}${item.logPath ? ` ([log](${item.logPath}))` : ""}`),
  ""
];
writeFileSync(markdownPath, lines.join("\n"));
console.log(`\n${report.status.replace("_", " ")} — ${blockers.length} blocker/manual gate(s), ${warnings.length} warning(s)`);
console.log(`Report: ${markdownPath}`);
process.exit(blockers.length === 0 ? 0 : 2);
