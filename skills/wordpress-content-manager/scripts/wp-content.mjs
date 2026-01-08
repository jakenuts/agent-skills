#!/usr/bin/env node
import fs from "fs";
import path from "path";
import { fileURLToPath, pathToFileURL } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function parseArgs(argv) {
  const flags = {};
  const positionals = [];
  let i = 0;
  while (i < argv.length) {
    const arg = argv[i];
    if (arg.startsWith("--")) {
      const key = arg.slice(2);
      const next = argv[i + 1];
      if (next && !next.startsWith("--")) {
        flags[key] = next;
        i += 2;
      } else {
        flags[key] = true;
        i += 1;
      }
    } else {
      positionals.push(arg);
      i += 1;
    }
  }
  return { flags, positionals };
}

function loadProfile(profileName) {
  const skillDir = path.resolve(__dirname, "..");
  const profilePath = path.join(skillDir, "profiles", `${profileName}.json`);
  if (!fs.existsSync(profilePath)) {
    throw new Error(`Profile not found: ${profilePath}`);
  }
  return JSON.parse(fs.readFileSync(profilePath, "utf8"));
}

function resolveCliPath(profile) {
  const envOverride = process.env.WP_CLI_PATH;
  if (envOverride) {
    return envOverride;
  }
  if (profile.cli_path) {
    return profile.cli_path;
  }
  throw new Error("WordPress CLI path not set. Use WP_CLI_PATH or profile cli_path.");
}

function applyProfileEnv(profile) {
  if (!process.env.WP_SITE_URL && profile.site_url) {
    process.env.WP_SITE_URL = profile.site_url;
  }
  if (!process.env.WP_API_URL && profile.api_url) {
    process.env.WP_API_URL = profile.api_url;
  }
}

function ensureAuthEnv() {
  if (!process.env.WP_USERNAME || !process.env.WP_APP_PASSWORD) {
    throw new Error("Missing WP_USERNAME or WP_APP_PASSWORD.");
  }
}

function parseListQuery(value) {
  if (!value) return undefined;
  return value
    .split(",")
    .map(v => v.trim())
    .filter(Boolean)
    .join(",");
}

function parseIdList(value) {
  if (!value) return undefined;
  return value
    .split(",")
    .map(v => v.trim())
    .filter(Boolean)
    .map(v => {
      const n = Number(v);
      return Number.isFinite(n) ? n : v;
    });
}

function parseNumber(value) {
  if (value === undefined) return undefined;
  const n = Number(value);
  return Number.isFinite(n) ? n : undefined;
}

async function getClient(cliPath) {
  const absCliPath = path.resolve(cliPath);
  if (!fs.existsSync(absCliPath)) {
    throw new Error(`WordPress CLI path not found: ${absCliPath}`);
  }
  const cliEntry = path.join(absCliPath, "wp-cli.js");
  if (!fs.existsSync(cliEntry)) {
    throw new Error(`WordPress CLI entry not found: ${cliEntry}`);
  }
  const nodeModules = path.join(absCliPath, "node_modules");
  if (!fs.existsSync(nodeModules)) {
    throw new Error("CLI dependencies are not installed. Run setup.sh or setup.ps1 first.");
  }

  process.chdir(absCliPath);
  applyProfileEnv(activeProfile);

  const moduleUrl = pathToFileURL(cliEntry);
  const mod = await import(moduleUrl.href);
  return new mod.WordPressClient();
}

function readContent(flags) {
  if (flags["content-file"]) {
    return fs.readFileSync(flags["content-file"], "utf8");
  }
  if (flags.content) {
    return flags.content;
  }
  return "";
}

function formatOutput(data, jsonOutput) {
  if (jsonOutput) {
    console.log(JSON.stringify(data, null, 2));
    return;
  }
  console.log(data);
}

const argv = process.argv.slice(2);
const { flags, positionals } = parseArgs(argv);
const profileName = flags.profile || process.env.WP_PROFILE || "example-blog";
const jsonOutput = Boolean(flags.json);

let activeProfile;
try {
  activeProfile = loadProfile(profileName);
} catch (error) {
  console.error(`Error: ${error.message}`);
  process.exit(2);
}

let client;
try {
  client = await getClient(resolveCliPath(activeProfile));
  ensureAuthEnv();
} catch (error) {
  console.error(`Error: ${error.message}`);
  process.exit(2);
}

const command = positionals[0];
const subcommand = positionals[1];

if (!command || command === "help" || command === "--help") {
  console.log(`
WordPress Content Manager

Usage:
  node wp-content.mjs site info [--json]
  node wp-content.mjs posts list [--status <status>] [--search <text>] [--categories 1,2] [--tags 3,4] [--after <date>] [--before <date>] [--page <n>] [--per_page <n>] [--json]
  node wp-content.mjs posts get <id> [--json]
  node wp-content.mjs posts create --title <title> [--content <html>] [--content-file <path>] [--status <status>] [--date <iso>] [--categories 1,2] [--tags 3,4]
  node wp-content.mjs posts update <id> [--title <title>] [--content <html>] [--content-file <path>] [--status <status>] [--date <iso>] [--categories 1,2] [--tags 3,4]
  node wp-content.mjs posts delete <id>
  node wp-content.mjs posts delete-many [filters] [--dry-run] [--confirm]

Profiles:
  --profile <name> or WP_PROFILE=<name>
`);
  process.exit(0);
}

if (command === "site" && subcommand === "info") {
  try {
    const info = await client.getSiteInfo();
    formatOutput(info, jsonOutput);
  } catch (error) {
    console.error(`Error: ${error.message}`);
    process.exit(1);
  }
  process.exit(0);
}

if (command === "posts") {
  if (subcommand === "list") {
    const params = {
      status: flags.status,
      search: flags.search,
      categories: parseListQuery(flags.categories),
      tags: parseListQuery(flags.tags),
      after: flags.after,
      before: flags.before,
      page: parseNumber(flags.page),
      per_page: parseNumber(flags.per_page),
      orderby: flags.orderby,
      order: flags.order
    };

    try {
      const posts = await client.listPosts(Object.fromEntries(Object.entries(params).filter(([, v]) => v)));
      if (jsonOutput) {
        formatOutput(posts, true);
      } else {
        posts.forEach(post => {
          console.log(`[${post.id}] ${post.title?.rendered || ""}`);
          console.log(`  Status: ${post.status} | Date: ${post.date}`);
          console.log(`  Link: ${post.link}`);
        });
      }
    } catch (error) {
      console.error(`Error: ${error.message}`);
      process.exit(1);
    }
    process.exit(0);
  }

  if (subcommand === "get") {
    const id = positionals[2];
    if (!id) {
      console.error("Error: Post ID required.");
      process.exit(2);
    }
    try {
      const post = await client.getPost(id);
      formatOutput(post, jsonOutput);
    } catch (error) {
      console.error(`Error: ${error.message}`);
      process.exit(1);
    }
    process.exit(0);
  }

  if (subcommand === "create") {
    const title = flags.title;
    if (!title) {
      console.error("Error: --title is required.");
      process.exit(2);
    }
    const content = readContent(flags);
    const data = {
      title,
      content,
      status: flags.status || "draft",
      date: flags.date,
      categories: parseIdList(flags.categories),
      tags: parseIdList(flags.tags)
    };

    try {
      const post = await client.createPost(Object.fromEntries(Object.entries(data).filter(([, v]) => v)));
      formatOutput(post, jsonOutput);
    } catch (error) {
      console.error(`Error: ${error.message}`);
      process.exit(1);
    }
    process.exit(0);
  }

  if (subcommand === "update") {
    const id = positionals[2];
    if (!id) {
      console.error("Error: Post ID required.");
      process.exit(2);
    }
    const content = readContent(flags);
    const data = {
      title: flags.title,
      content: flags.content || flags["content-file"] ? content : undefined,
      status: flags.status,
      date: flags.date,
      categories: parseIdList(flags.categories),
      tags: parseIdList(flags.tags)
    };

    try {
      const post = await client.updatePost(id, Object.fromEntries(Object.entries(data).filter(([, v]) => v)));
      formatOutput(post, jsonOutput);
    } catch (error) {
      console.error(`Error: ${error.message}`);
      process.exit(1);
    }
    process.exit(0);
  }

  if (subcommand === "delete") {
    const id = positionals[2];
    if (!id) {
      console.error("Error: Post ID required.");
      process.exit(2);
    }
    try {
      const result = await client.deletePost(id);
      formatOutput(result, jsonOutput);
    } catch (error) {
      console.error(`Error: ${error.message}`);
      process.exit(1);
    }
    process.exit(0);
  }

  if (subcommand === "delete-many") {
    const dryRun = !flags.confirm || Boolean(flags["dry-run"]);
    const params = {
      status: flags.status,
      search: flags.search,
      categories: parseListQuery(flags.categories),
      tags: parseListQuery(flags.tags),
      after: flags.after,
      before: flags.before,
      page: parseNumber(flags.page),
      per_page: parseNumber(flags.per_page) || 100
    };

    try {
      const posts = await client.listPosts(Object.fromEntries(Object.entries(params).filter(([, v]) => v)));
      const summary = posts.map(p => ({ id: p.id, title: p.title?.rendered || "", status: p.status }));
      if (dryRun) {
        formatOutput({ dry_run: true, count: summary.length, posts: summary }, jsonOutput);
        process.exit(0);
      }

      const results = [];
      for (const post of posts) {
        const res = await client.deletePost(post.id);
        results.push({ id: post.id, status: res?.status || "deleted" });
      }
      formatOutput({ deleted: results.length, results }, jsonOutput);
    } catch (error) {
      console.error(`Error: ${error.message}`);
      process.exit(1);
    }
    process.exit(0);
  }
}

console.error(`Error: Unknown command "${command} ${subcommand || ""}". Use "help" for usage.`);
process.exit(2);
