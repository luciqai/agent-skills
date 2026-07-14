#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const os = require("os");

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
    settings: path.join(base, "settings.json"),
  };
}

function getKiroDirs() {
  const base = isGlobal
    ? path.join(os.homedir(), ".kiro")
    : path.join(process.cwd(), ".kiro");
  return {
    steering: path.join(base, "steering"),
    mcp: path.join(base, "settings", "mcp.json"),
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

function wireMcp(settingsPath, kiro) {
  const mcpConfig = JSON.parse(fs.readFileSync(MCP_SRC, "utf8"));
  // Kiro's mcp.json schema has no `type` field — a remote server is
  // identified by its `url`. Strip it so Kiro accepts the entry.
  if (kiro) {
    for (const server of Object.values(mcpConfig.mcpServers)) {
      delete server.type;
    }
  }
  let settings = {};
  if (fs.existsSync(settingsPath)) {
    try {
      settings = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
    } catch {
      console.warn(
        "  Warning: could not parse " + settingsPath + " — skipping MCP wiring."
      );
      return;
    }
  }

  settings.mcpServers = {
    ...(settings.mcpServers || {}),
    ...mcpConfig.mcpServers,
  };
  fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
  fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n");
  console.log("  MCP server wired -> " + settingsPath);
}

function installKiro() {
  const { steering: steeringDest, mcp: mcpPath } = getKiroDirs();
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

  wireMcp(mcpPath, true);

  console.log(
    "\nDone. Steering files use inclusion: manual — reference them in a\n" +
      "Kiro session to load one:\n" +
      "  #luciq-setup    — integrate the Luciq SDK\n" +
      "  #luciq-debug    — investigate crashes and production signals\n" +
      "  #luciq-migrate  — migrate from Instabug or upgrade SDK versions\n"
  );
}

function install() {
  if (isKiro) return installKiro();
  const { skills: skillsDest, settings: settingsPath } = getTargetDirs();
  const scope = isGlobal ? "global (~/.claude/)" : "local (.claude/)";

  console.log("\nInstalling Luciq skills [" + scope + "]...\n");

  const skillNames = fs
    .readdirSync(SKILLS_SRC)
    .filter((name) => fs.statSync(path.join(SKILLS_SRC, name)).isDirectory());

  for (const skill of skillNames) {
    copyDir(path.join(SKILLS_SRC, skill), path.join(skillsDest, skill));
    console.log("  Installed: " + skill);
  }

  wireMcp(settingsPath);

  console.log(
    "\nDone. Skills available:\n" +
      "  /luciq-setup    — integrate the Luciq SDK\n" +
      "  /luciq-debug    — investigate crashes and production signals\n" +
      "  /luciq-migrate  — migrate from Instabug or upgrade SDK versions\n"
  );
}

function removeMcpEntry(mcpPath, fileLabel) {
  if (!fs.existsSync(mcpPath)) return;
  try {
    const settings = JSON.parse(fs.readFileSync(mcpPath, "utf8"));
    if (settings.mcpServers && settings.mcpServers.luciq) {
      delete settings.mcpServers.luciq;
      fs.writeFileSync(mcpPath, JSON.stringify(settings, null, 2) + "\n");
      console.log("  MCP server entry removed.");
    }
  } catch {
    console.warn(
      "  Warning: could not update " + fileLabel + " — remove MCP entry manually."
    );
  }
}

function uninstallKiro() {
  const { steering: steeringDest, mcp: mcpPath } = getKiroDirs();
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

  removeMcpEntry(mcpPath, "mcp.json");
  console.log("\nDone.\n");
}

function uninstall() {
  if (isKiro) return uninstallKiro();
  const { skills: skillsDest, settings: settingsPath } = getTargetDirs();
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

  if (fs.existsSync(settingsPath)) {
    try {
      const settings = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
      if (settings.mcpServers && settings.mcpServers.luciq) {
        delete settings.mcpServers.luciq;
        fs.writeFileSync(
          settingsPath,
          JSON.stringify(settings, null, 2) + "\n"
        );
        console.log("  MCP server entry removed.");
      }
    } catch {
      console.warn(
        "  Warning: could not update settings.json — remove MCP entry manually."
      );
    }
  }

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
