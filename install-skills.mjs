#!/usr/bin/env node
// 用 Node.js 安装 / 清理 skills
//   用法:
//     node install-skills.mjs            # 默认 install
//     node install-skills.mjs install    # 复制 skills/ 到 INSTALL_DIRS（复制前清理同名目录）
//     node install-skills.mjs cleanup    # 删除安装目录里已过期的 skill
//     node install-skills.mjs help

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const SKILLS_SRC = path.join(ROOT, 'skills');

const INSTALL_DIRS = [
  '~/.agents/skills',
  '~/.codebuddy/skills',
  '~/.workbuddy/skills',
  '~/.dsh/skills',
];

// 手动配置的旧 skill 名称：即使源里还有，也强制清理（留空则仅按源清单自动清理）
const STALE_SKILLS = [];

function expand(p) {
  return p.startsWith('~') ? path.join(os.homedir(), p.slice(1)) : p;
}

function listSkillDirs(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((e) => e.isDirectory())
    .map((e) => e.name);
}

function install() {
  const sources = listSkillDirs(SKILLS_SRC);
  if (sources.length === 0) {
    console.error(`未找到任何 skill：${SKILLS_SRC}`);
    process.exit(1);
  }

  for (const raw of INSTALL_DIRS) {
    const dir = expand(raw);
    fs.mkdirSync(dir, { recursive: true });

    for (const name of sources) {
      const src = path.join(SKILLS_SRC, name);
      const dest = path.join(dir, name);

      // 复制前先清理现有的同名目录
      fs.rmSync(dest, { recursive: true, force: true });
      fs.cpSync(src, dest, { recursive: true });
      console.log(`安装 ${name} -> ${dir}`);
    }
  }
  console.log('安装完成！');
}

function cleanup() {
  const canonical = new Set(listSkillDirs(SKILLS_SRC));

  let removed = 0;
  for (const raw of INSTALL_DIRS) {
    const dir = expand(raw);
    for (const name of listSkillDirs(dir)) {
      const stale = !canonical.has(name) || STALE_SKILLS.includes(name);
      if (!stale) continue;

      fs.rmSync(path.join(dir, name), { recursive: true, force: true });
      console.log(`清理 ${name} <- ${dir}`);
      removed++;
    }
  }
  console.log(removed ? `清理完成，共删除 ${removed} 个 skill` : '没有需要清理的 skill');
}

const cmd = process.argv[2] ?? 'install';
switch (cmd) {
  case 'install':
    install();
    break;
  case 'cleanup':
    cleanup();
    break;
  case 'help':
  default:
    console.log(
      [
        '用法: node install-skills.mjs [install|cleanup|help]',
        '  install  复制 skills/ 到 INSTALL_DIRS（默认）',
        '  cleanup  删除安装目录里已过期的 skill',
      ].join('\n')
    );
}
