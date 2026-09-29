#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawnSync } = require("child_process");

const args = process.argv.slice(2);
const command = args[0];
const isGlobal = args.includes("--global");
const isKiro = args.includes("--kiro");

const PLUGIN_DIR = path.join(__dirname, "..", "plugins", "luciq-skills");
const SKILLS_SRC = path.join(PLUGIN_DIR, "skills");
const MCP_SRC = path.join(PLUGIN_DIR, ".mcp.json");

function getTargetDirs() {
  const base = isGlobal
    ? path.join(os.homedir(), ".claude")
    : path.join(process.cwd(), ".claude");
  return {
    skills: path.join(base, "skills"),
    // Installers before 1.5.0 wrote mcpServers here. Claude Code never reads
    // MCP servers from settings.json, so that entry was a silent no-op.
    legacySettings: path.join(base, "settings.json"),
    // Project-scope MCP servers live in .mcp.json at the project root.
    mcpJson: path.join(process.cwd(), ".mcp.json"),
  };
}

function listSkillNames() {
  return fs
    .readdirSync(SKILLS_SRC)
    .filter((name) => fs.existsSync(path.join(SKILLS_SRC, name, "SKILL.md")))
    .sort();
}

function printNextSteps(prefix) {
  console.log("\nSkills installed:");
  for (const skill of listSkillNames()) console.log("  " + prefix + skill);
}

function getKiroDirs() {
  const base = isGlobal
    ? path.join(os.homedir(), ".kiro")
    : path.join(process.cwd(), ".kiro");
  return {
    steering: path.join(base, "steering"),
  };
}

// Copy a skill's SKILL.md into a Kiro steering file, injecting
// `inclusion: manual` so it loads only when referenced (#luciq-<name>).
function writeSteeringFile(skillName, srcSkillMd, steeringDir) {
  const raw = fs.readFileSync(srcSkillMd, "utf8");
  const out = raw.startsWith("---\n")
    ? raw.replace(/^---\n/, "---\ninclusion: manual\n")
    : "---\ninclusion: manual\n---\n\n" + raw;
  fs.mkdirSync(steeringDir, { recursive: true });
  fs.writeFileSync(path.join(steeringDir, skillName + ".md"), out);
}

function copyDir(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

function readJson(file) {
  if (!fs.existsSync(file)) return {};
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function luciqServer() {
  return JSON.parse(fs.readFileSync(MCP_SRC, "utf8")).mcpServers.luciq;
}

function manualAddCommand() {
  const { type, url } = luciqServer();
  return "claude mcp add --transport " + type + " --scope user luciq " + url;
}

function removeLegacyMcpEntry(settingsPath) {
  let settings;
  try {
    settings = readJson(settingsPath);
  } catch {
    return;
  }
  if (!settings.mcpServers || !settings.mcpServers.luciq) return;
  delete settings.mcpServers.luciq;
  if (Object.keys(settings.mcpServers).length === 0) delete settings.mcpServers;
  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n");
  console.log("  Removed stale MCP entry from " + settingsPath);
}

// Project scope: merge into <project>/.mcp.json, the file Claude Code reads.
function wireMcpProject(mcpJsonPath) {
  let config;
  try {
    config = readJson(mcpJsonPath);
  } catch {
    console.warn(
      "  Warning: could not parse " + mcpJsonPath + " — skipping MCP wiring.\n" +
        "  Add it yourself: " + manualAddCommand().replace(" --scope user", " --scope project")
    );
    return;
  }
  config.mcpServers = { ...(config.mcpServers || {}), luciq: luciqServer() };
  fs.writeFileSync(mcpJsonPath, JSON.stringify(config, null, 2) + "\n");
  console.log("  MCP server wired -> " + mcpJsonPath);
}

// User scope lives in ~/.claude.json, which is large and shared with every
// other setting — let the claude CLI edit it rather than writing it ourselves.
function wireMcpUser() {
  const { type, url } = luciqServer();
  const res = spawnSync(
    "claude",
    ["mcp", "add", "--transport", type, "--scope", "user", "luciq", url],
    { encoding: "utf8" }
  );
  const output = (res.stdout || "") + (res.stderr || "");
  if (res.error) {
    console.log("  MCP server not wired: the claude CLI was not found. Run:\n    " + manualAddCommand());
  } else if (res.status === 0) {
    console.log("  MCP server wired (user scope, via claude mcp add)");
  } else if (/already exists/i.test(output)) {
    console.log("  MCP server already configured (user scope)");
  } else {
    console.warn("  Warning: claude mcp add failed:\n    " + output.trim() + "\n  Run it yourself:\n    " + manualAddCommand());
  }
}

function unwireMcpProject(mcpJsonPath) {
  let config;
  try {
    config = readJson(mcpJsonPath);
  } catch {
    console.warn("  Warning: could not parse " + mcpJsonPath + " — remove the luciq entry manually.");
    return;
  }
  if (!config.mcpServers || !config.mcpServers.luciq) return;
  delete config.mcpServers.luciq;
  if (Object.keys(config.mcpServers).length === 0 && Object.keys(config).length === 1) {
    fs.rmSync(mcpJsonPath);
  } else {
    fs.writeFileSync(mcpJsonPath, JSON.stringify(config, null, 2) + "\n");
  }
  console.log("  MCP server entry removed from " + mcpJsonPath);
}

function unwireMcpUser() {
  const res = spawnSync("claude", ["mcp", "remove", "luciq", "--scope", "user"], { encoding: "utf8" });
  if (res.status === 0) console.log("  MCP server entry removed (user scope).");
  else console.log("  To remove the MCP server, run: claude mcp remove luciq --scope user");
}

function installKiro() {
  const { steering: steeringDest } = getKiroDirs();
  const scope = isGlobal ? "global (~/.kiro/)" : "local (.kiro/)";

  console.log("\nInstalling Luciq skills as Kiro steering [" + scope + "]...\n");

  const skillNames = fs
    .readdirSync(SKILLS_SRC)
    .filter((name) => fs.statSync(path.join(SKILLS_SRC, name)).isDirectory());

  for (const skill of skillNames) {
    const skillMd = path.join(SKILLS_SRC, skill, "SKILL.md");
    if (!fs.existsSync(skillMd)) continue;
    writeSteeringFile(skill, skillMd, steeringDest);
    console.log("  Installed: " + skill + " (#" + skill + ")");
  }

  printNextSteps("#");
  console.log(
    "\nSteering files use inclusion: manual — reference one in a Kiro session\n" +
      "to load it, e.g. #luciq-setup.\n" +
      "\nThe Luciq MCP server is set up separately — see the MCP setup guide:\n" +
      "  https://docs.luciq.ai/product-guides-and-integrations/product-guides/ai-features/luciq-mcp-server\n"
  );
}

function install() {
  if (isKiro) return installKiro();
  const { skills: skillsDest, legacySettings, mcpJson } = getTargetDirs();
  const scope = isGlobal ? "global (~/.claude/)" : "local (.claude/)";

  console.log("\nInstalling Luciq skills [" + scope + "]...\n");

  const skillNames = fs
    .readdirSync(SKILLS_SRC)
    .filter((name) => fs.statSync(path.join(SKILLS_SRC, name)).isDirectory());

  for (const skill of skillNames) {
    copyDir(path.join(SKILLS_SRC, skill), path.join(skillsDest, skill));
    console.log("  Installed: " + skill);
  }

  removeLegacyMcpEntry(legacySettings);
  if (isGlobal) wireMcpUser();
  else wireMcpProject(mcpJson);

  printNextSteps("/");
  console.log(
    "\nNext: restart Claude Code (or start a new session). A running session\n" +
      "does not see newly installed skills or MCP servers.\n" +
      (isGlobal
        ? "On first use, sign in to Luciq when your browser opens.\n"
        : "On first use, approve the luciq MCP server when prompted, then sign in.\n")
  );
}

function uninstallKiro() {
  const { steering: steeringDest } = getKiroDirs();
  const scope = isGlobal ? "global" : "local";

  console.log("\nUninstalling Luciq Kiro steering [" + scope + "]...\n");

  const skillNames = fs
    .readdirSync(SKILLS_SRC)
    .filter((name) => fs.statSync(path.join(SKILLS_SRC, name)).isDirectory());

  for (const skill of skillNames) {
    const dest = path.join(steeringDest, skill + ".md");
    if (fs.existsSync(dest)) {
      fs.rmSync(dest, { force: true });
      console.log("  Removed: " + skill + ".md");
    }
  }

  console.log("\nDone.\n");
}

function uninstall() {
  if (isKiro) return uninstallKiro();
  const { skills: skillsDest, legacySettings, mcpJson } = getTargetDirs();
  const scope = isGlobal ? "global" : "local";

  console.log("\nUninstalling Luciq skills [" + scope + "]...\n");

  const skillNames = fs
    .readdirSync(SKILLS_SRC)
    .filter((name) => fs.statSync(path.join(SKILLS_SRC, name)).isDirectory());

  for (const skill of skillNames) {
    const dest = path.join(skillsDest, skill);
    if (fs.existsSync(dest)) {
      fs.rmSync(dest, { recursive: true, force: true });
      console.log("  Removed: " + skill);
    }
  }

  removeLegacyMcpEntry(legacySettings);
  if (isGlobal) unwireMcpUser();
  else unwireMcpProject(mcpJson);

  console.log("\nDone.\n");
}

function printHelp() {
  console.log(
    "\nUsage:\n" +
      "  npx luciq-skills install                 Install into this project (.claude/skills/)\n" +
      "  npx luciq-skills install --global        Install globally (~/.claude/skills/)\n" +
      "  npx luciq-skills install --kiro          Install as Kiro steering (.kiro/steering/)\n" +
      "  npx luciq-skills install --kiro --global Install as Kiro steering (~/.kiro/steering/)\n" +
      "  npx luciq-skills uninstall               Remove from this project\n" +
      "  npx luciq-skills uninstall --global      Remove globally\n" +
      "  npx luciq-skills uninstall --kiro        Remove Kiro steering\n"
  );
}

switch (command) {
  case "install":
    install();
    break;
  case "uninstall":
    uninstall();
    break;
  default:
    printHelp();
    process.exit(command ? 1 : 0);
}
