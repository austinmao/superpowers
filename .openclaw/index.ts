// @ts-nocheck

const fs = require("node:fs");
const path = require("node:path");

const SUPERPOWERS_GUIDANCE = `## Superpowers

You have access to the Superpowers skill framework. Superpowers provides a set of
structured workflow skills that guide how you approach software development tasks.

Before responding to a software development request, check whether a Superpowers skill
applies to the current task. If a Superpowers skill clearly fits, invoke it before
proceeding.

Key skills available:
- \`using-superpowers\` — Load this first; it explains how the rest of the pack works
- \`brainstorming\` — Before committing to an approach
- \`writing-plans\` — Before beginning implementation
- \`test-driven-development\` — For feature development
- \`systematic-debugging\` — For debugging sessions
- \`dispatching-parallel-agents\` — When parallelism would speed up the task
- \`verification-before-completion\` — Before declaring work complete

When Superpowers instructions reference generic tools, use the closest native OpenClaw tool or workflow.`;

function resolveConfig(api) {
  const raw = api?.pluginConfig || {};
  return {
    injectGuidance: raw.injectGuidance !== false,
  };
}

function resolvePluginRoot(api) {
  if (api?.source && typeof api.source === "string") {
    return path.resolve(path.dirname(api.source), "..");
  }
  return path.resolve(__dirname, "..");
}

function resolveSkillsDir(api) {
  return path.join(resolvePluginRoot(api), "skills");
}

function ensureSkillsDir(api, skillsDir, warned) {
  try {
    const stat = fs.statSync(skillsDir);
    if (stat.isDirectory()) return true;
  } catch {
    // handled below
  }

  if (!warned.value) {
    warned.value = true;
    api.logger?.warn?.(`[superpowers-openclaw] skills directory not found: ${skillsDir}`);
  }
  return false;
}

module.exports = {
  id: "superpowers-openclaw",
  name: "Superpowers for OpenClaw",
  description:
    "Expose the Superpowers skill pack through plugin-declared skill paths and optional prompt guidance.",

  register(api) {
    const warnedMissingSkills = { value: false };

    api.on("before_prompt_build", async () => {
      const { injectGuidance } = resolveConfig(api);
      if (!injectGuidance) {
        return;
      }

      const skillsDir = resolveSkillsDir(api);
      if (!ensureSkillsDir(api, skillsDir, warnedMissingSkills)) {
        return;
      }

      return { prependSystemContext: SUPERPOWERS_GUIDANCE };
    });
  },
};
