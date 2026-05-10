#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const os = require("os");

const args = process.argv.slice(2);
const command = args[0];
const isGlobal = args.includes("--global");

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

function wireMcp(settingsPath) {
  const mcpConfig = JSON.parse(fs.readFileSync(MCP_SRC, "utf8"));
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

function install() {
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

function uninstall() {
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
      "  npx luciq-skills install             Install into this project (.claude/skills/)\n" +
      "  npx luciq-skills install --global    Install globally (~/.claude/skills/)\n" +
      "  npx luciq-skills uninstall           Remove from this project\n" +
      "  npx luciq-skills uninstall --global  Remove globally\n"
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
