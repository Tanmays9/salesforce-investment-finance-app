import { execFileSync } from 'node:child_process';
import { copyFile, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const siteRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(siteRoot, '..');
const contentRoot = path.join(siteRoot, 'src', 'content', 'docs');
const manifestPath = path.join(siteRoot, '.synced-docs.json');

const sourcePaths = execFileSync(
  'git',
  ['ls-files', '-z', '--cached', '--', '*.md', '*.mdx', '*.markdown'],
  { cwd: repoRoot, encoding: 'utf8' },
)
  .split('\0')
  .filter(Boolean)
  .map((source) => source.replaceAll('\\', '/'))
  .filter((source) => !source.startsWith('docs-site/'))
  .filter((source) => !['AGENTS.MD', 'CLAUDE.MD', 'GEMINI.MD'].includes(path.posix.basename(source).toUpperCase()));

if (sourcePaths.length === 0) {
  throw new Error('No tracked Markdown files were found to publish.');
}

let previousTargets = [];
try {
  previousTargets = JSON.parse(await readFile(manifestPath, 'utf8'));
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}

for (const targetPath of previousTargets) {
  await rm(path.join(contentRoot, ...targetPath.split('/')), { force: true });
}

await mkdir(contentRoot, { recursive: true });
await copyFile(path.join(repoRoot, 'docs', 'architecture.svg'), path.join(contentRoot, 'architecture.svg'));

const destinations = new Set();
const writtenTargets = ['architecture.svg'];

for (const sourcePath of sourcePaths) {
  const originalPath = path.join(repoRoot, ...sourcePath.split('/'));
  const source = await readFile(originalPath, 'utf8');
  const targetPath = mapSourcePath(sourcePath);

  if (destinations.has(targetPath)) {
    throw new Error(`Multiple Markdown files map to ${targetPath}.`);
  }
  destinations.add(targetPath);

  const { content, frontmatter } = preparePage(source, sourcePath);
  const target = path.join(contentRoot, ...targetPath.split('/'));
  await mkdir(path.dirname(target), { recursive: true });
  await writeFile(target, `${frontmatter}\n${rewriteArchitectureLink(content)}`, 'utf8');
  writtenTargets.push(targetPath);
}

await writeFile(
  path.join(contentRoot, '404.md'),
  `---\ntitle: '404'\ntemplate: splash\neditUrl: false\npagefind: false\nsidebar:\n  hidden: true\nhero:\n  title: '404'\n  tagline: Page not found. Check the URL or try using the search bar.\n---\n`,
  'utf8',
);
writtenTargets.push('404.md');
await writeFile(manifestPath, JSON.stringify([...new Set(writtenTargets)], null, 2), 'utf8');

console.log(`Synced ${sourcePaths.length} tracked Markdown files into the Starlight docs site.`);

function mapSourcePath(sourcePath) {
  if (sourcePath.toLowerCase() === 'readme.md') return 'index.md';
  if (sourcePath.toLowerCase() === 'tools/portfolio/readme.md') return 'portfolio-operations.md';
  if (sourcePath.toLowerCase() === 'tools/investment-migration/readme.md') return 'investment-migration.md';
  const extension = path.posix.extname(sourcePath).toLowerCase();
  const directory = path.posix.dirname(sourcePath);
  const baseName = path.posix.basename(sourcePath);
  if (baseName.toLowerCase() === 'readme.md') {
    return path.posix.join(directory, `index${extension}`);
  }
  return sourcePath;
}

function preparePage(source, sourcePath) {
  const existingFrontmatter = source.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
  let metadata = existingFrontmatter?.[1] ?? '';
  let content = existingFrontmatter ? source.slice(existingFrontmatter[0].length) : source;
  const titleMatch = metadata.match(/^title:\s*(?:"([^"]+)"|'([^']+)'|(.+))\s*$/m);
  const firstHeading = content.match(/^\s*#\s+(.+?)\s*#*\s*$/m);
  const fallbackName = path.posix.basename(sourcePath).replace(/\.(md|mdx|markdown)$/i, '');
  const sourceTitle = (titleMatch?.[1] ?? titleMatch?.[2] ?? titleMatch?.[3] ?? firstHeading?.[1] ?? fallbackName).trim();
  const knownTitles = {
    'readme.md': 'Overview',
    'tools/portfolio/readme.md': 'Portfolio operations',
    'tools/investment-migration/readme.md': 'Investment migration',
  };
  const title = knownTitles[sourcePath.toLowerCase()] ?? sourceTitle;

  if (titleMatch && title !== sourceTitle) {
    metadata = metadata.replace(titleMatch[0], `title: ${JSON.stringify(title)}`);
  } else if (!titleMatch) {
    metadata = `title: ${JSON.stringify(title)}\n${metadata}`;
  }

  if (firstHeading && firstHeading[1].trim() === sourceTitle) {
    content = content.replace(firstHeading[0], '');
  }

  return {
    content: content.replace(/^\s+/, ''),
    frontmatter: `---\n${metadata.trimEnd()}\n---\n`,
  };
}

function rewriteArchitectureLink(content) {
  return content.replace(/\]\(docs\/architecture\.svg\)/g, '](./architecture.svg)');
}
