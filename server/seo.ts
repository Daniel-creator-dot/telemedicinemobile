import fs from 'fs';
import path from 'path';

/**
 * Public crawl origin for Healynks.
 *
 * Switch this to https://healynks.app once curl shows that host returns
 * Healynks HTML (HTTP 200, title or body contains Healynks). That check
 * passed on 2026-10-04, including https://healynks.app/login, and
 * https://www.healynks.app/ redirects to the apex — so this is the canonical
 * origin. If DNS later stops serving the app, set it back to
 * https://telemedicine-server-l2bj.onrender.com so crawlers are not sent to
 * a dead host. Keep the same origin in web/index.html, web/robots.txt, and
 * web/sitemap.xml (those files mirror this constant for static hosting).
 */
export const HEALYNK_CANONICAL_ORIGIN = 'https://healynks.app';

const THEME_COLOR = '#1D6BFF';
const SITEMAP_LASTMOD = '2026-10-04';
const OG_IMAGE_PATH = '/icons/Icon-512.png';

const HOME_TITLE = 'Healynks — doctors, nurses, and video consults in Ghana';
const HOME_DESCRIPTION =
  'Healynks is telemedicine for Ghana. Book a doctor or nurse, join a video consult, and receive prescriptions from your phone.';

export interface PublicPageSeo {
  /** Path beginning with /, or `/` for the home page. */
  path: string;
  title: string;
  description: string;
  robots: string;
  changefreq: string;
  priority: string;
  /** Indexable pages get a WebPage node. Home also gets Organization and WebSite. */
  webPage: boolean;
  indexable: boolean;
  noscriptHeading: string;
}

const PUBLIC_PAGES: PublicPageSeo[] = [
  {
    path: '/',
    title: HOME_TITLE,
    description: HOME_DESCRIPTION,
    robots: 'index,follow',
    changefreq: 'weekly',
    priority: '1.0',
    webPage: true,
    indexable: true,
    noscriptHeading: 'Healynks',
  },
  {
    path: '/login',
    title: 'Log in to Healynks',
    description:
      'Sign in to Healynks to book a doctor or nurse, join your video consult, and view prescriptions.',
    robots: 'index,follow',
    changefreq: 'monthly',
    priority: '0.8',
    webPage: true,
    indexable: true,
    noscriptHeading: 'Log in to Healynks',
  },
  {
    path: '/signup',
    title: 'Create a Healynks account',
    description:
      'Create a Healynks patient account to book doctors and nurses in Ghana, start a video consult, and receive prescriptions.',
    robots: 'index,follow',
    changefreq: 'monthly',
    priority: '0.7',
    webPage: true,
    indexable: true,
    noscriptHeading: 'Create a Healynks account',
  },
  {
    path: '/join',
    title: 'Join Healynks as a doctor, nurse, or nurse agency',
    description:
      'Doctors, nurses, and nurse agencies in Ghana can join Healynks to see patients on video and issue prescriptions.',
    robots: 'index,follow',
    changefreq: 'monthly',
    priority: '0.7',
    webPage: true,
    indexable: true,
    noscriptHeading: 'Join Healynks as a doctor, nurse, or nurse agency',
  },
];

const PRIVATE_SHELL: PublicPageSeo = {
  path: '/',
  title: 'Healynks',
  description: HOME_DESCRIPTION,
  robots: 'noindex,follow',
  changefreq: 'yearly',
  priority: '0.1',
  webPage: false,
  indexable: false,
  noscriptHeading: 'Healynks',
};

export function normalizePublicPath(requestPath: string): string {
  const pathOnly = (requestPath || '/').split('?')[0].split('#')[0];
  if (pathOnly === '' || pathOnly === '/') return '/';
  const trimmed = pathOnly.replace(/\/+$/, '');
  return trimmed === '' ? '/' : trimmed;
}

export function pageForPath(requestPath: string): PublicPageSeo {
  const path = normalizePublicPath(requestPath);
  return PUBLIC_PAGES.find((page) => page.path === path) ?? PRIVATE_SHELL;
}

export function canonicalUrlFor(page: PublicPageSeo): string {
  if (!page.indexable) return `${HEALYNK_CANONICAL_ORIGIN}/`;
  if (page.path === '/') return `${HEALYNK_CANONICAL_ORIGIN}/`;
  return `${HEALYNK_CANONICAL_ORIGIN}${page.path}`;
}

function ogImageUrl(): string {
  return `${HEALYNK_CANONICAL_ORIGIN}${OG_IMAGE_PATH}`;
}

function attr(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function jsonLdFor(page: PublicPageSeo): string {
  const origin = HEALYNK_CANONICAL_ORIGIN;
  const pageUrl = canonicalUrlFor(page);
  const organization = {
    '@type': 'Organization',
    '@id': `${origin}/#organization`,
    name: 'Healynks',
    url: `${origin}/`,
    logo: ogImageUrl(),
    description: HOME_DESCRIPTION,
    areaServed: { '@type': 'Country', name: 'Ghana' },
  };
  const website = {
    '@type': 'WebSite',
    '@id': `${origin}/#website`,
    name: 'Healynks',
    url: `${origin}/`,
    description: HOME_DESCRIPTION,
    inLanguage: 'en',
    publisher: { '@id': `${origin}/#organization` },
  };
  const graph: object[] = [organization, website];
  if (page.webPage) {
    graph.push({
      '@type': 'WebPage',
      '@id': `${pageUrl}#webpage`,
      url: pageUrl,
      name: page.title,
      description: page.description,
      inLanguage: 'en',
      isPartOf: { '@id': `${origin}/#website` },
      about: { '@id': `${origin}/#organization` },
    });
  }
  return JSON.stringify({ '@context': 'https://schema.org', '@graph': graph }).replace(/</g, '\\u003c');
}

/** Head tags for one route. The Flutter bootstrap script stays outside this block. */
export function seoHeadInner(page: PublicPageSeo): string {
  const url = canonicalUrlFor(page);
  const image = ogImageUrl();
  const lines = [
    `<title>${attr(page.title)}</title>`,
    `<meta name="description" content="${attr(page.description)}">`,
    `<meta name="robots" content="${page.robots}">`,
    `<meta name="theme-color" content="${THEME_COLOR}">`,
    `<link rel="canonical" href="${attr(url)}">`,
    `<meta property="og:title" content="${attr(page.title)}">`,
    `<meta property="og:description" content="${attr(page.description)}">`,
    `<meta property="og:url" content="${attr(url)}">`,
    `<meta property="og:type" content="website">`,
    `<meta property="og:image" content="${attr(image)}">`,
    `<meta property="og:site_name" content="Healynks">`,
    `<meta property="og:locale" content="en_GH">`,
    `<meta name="twitter:card" content="summary_large_image">`,
    `<meta name="twitter:title" content="${attr(page.title)}">`,
    `<meta name="twitter:description" content="${attr(page.description)}">`,
    `<meta name="twitter:image" content="${attr(image)}">`,
    `<script type="application/ld+json" id="healynks-jsonld">${jsonLdFor(page)}</script>`,
  ];
  return lines.map((line) => `  ${line}`).join('\n');
}

export function noscriptBlock(page: PublicPageSeo): string {
  const origin = HEALYNK_CANONICAL_ORIGIN;
  return [
    '<noscript>',
    `  <h1>${attr(page.noscriptHeading)}</h1>`,
    `  <p>${attr(page.description)}</p>`,
    `  <p><a href="${origin}/login">Log in</a> · <a href="${origin}/signup">Create a patient account</a> · <a href="${origin}/join">Join as a doctor, nurse, or nurse agency</a></p>`,
    '</noscript>',
  ].join('\n');
}

const SEO_BLOCK = /<!-- healynks-seo:start -->[\s\S]*?<!-- healynks-seo:end -->/;
const NOSCRIPT_BLOCK = /<!-- healynks-noscript:start -->[\s\S]*?<!-- healynks-noscript:end -->/;

/**
 * Rewrite title, description, canonical, Open Graph, and JSON-LD for a public
 * route. Leaves flutter_bootstrap.js untouched.
 */
export function applyRouteSeo(html: string, requestPath: string): string {
  const page = pageForPath(requestPath);
  const seoWrapped = `<!-- healynks-seo:start -->\n${seoHeadInner(page)}\n  <!-- healynks-seo:end -->`;
  const noscriptWrapped = `<!-- healynks-noscript:start -->\n  ${noscriptBlock(page)}\n  <!-- healynks-noscript:end -->`;

  let next = html;
  if (SEO_BLOCK.test(next)) {
    next = next.replace(SEO_BLOCK, seoWrapped);
  } else {
    next = next.replace(/<title>[^<]*<\/title>\s*/i, '');
    next = next.replace(/<meta\s+name=["']description["'][^>]*>\s*/i, '');
    next = next.replace('</head>', `${seoWrapped}\n</head>`);
  }

  if (NOSCRIPT_BLOCK.test(next)) {
    next = next.replace(NOSCRIPT_BLOCK, noscriptWrapped);
  }

  if (!/<html\b[^>]*\blang\s*=/i.test(next)) {
    next = next.replace(/<html\b/i, '<html lang="en"');
  }
  return next;
}

export function robotsTxt(): string {
  const lines = [
    '# Healynks public site. Canonical origin is HEALYNK_CANONICAL_ORIGIN in server/seo.ts.',
    '# Switch that constant (and web/index.html, web/robots.txt, web/sitemap.xml) to',
    '# https://healynks.app once the domain returns Healynks HTML. If it stops,',
    '# point them at https://telemedicine-server-l2bj.onrender.com instead.',
    'User-agent: *',
    'Allow: /',
    'Allow: /login',
    'Allow: /signup',
    'Allow: /join',
    'Disallow: /api/',
    'Disallow: /health',
    'Disallow: /paystack/',
    'Disallow: /patient',
    'Disallow: /doctor',
    'Disallow: /admin',
    'Disallow: /nurse',
    'Disallow: /ops',
    'Disallow: /lab-technician',
    'Disallow: /pharmacy',
    'Disallow: /imaging',
    'Disallow: /corporate',
    'Disallow: /insurance',
    'Disallow: /finance',
    'Disallow: /hospital',
    '',
    `Sitemap: ${HEALYNK_CANONICAL_ORIGIN}/sitemap.xml`,
    '',
  ];
  return lines.join('\n');
}

export function sitemapXml(): string {
  const urls = PUBLIC_PAGES.map((page) => {
    const loc = canonicalUrlFor(page);
    return [
      '  <url>',
      `    <loc>${loc}</loc>`,
      `    <lastmod>${SITEMAP_LASTMOD}</lastmod>`,
      `    <changefreq>${page.changefreq}</changefreq>`,
      `    <priority>${page.priority}</priority>`,
      '  </url>',
    ].join('\n');
  }).join('\n');
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    urls,
    '</urlset>',
    '',
  ].join('\n');
}

/** Write the static copies Flutter and the web build serve. */
export function writeStaticSeoFiles(webDir: string): void {
  fs.writeFileSync(path.join(webDir, 'robots.txt'), robotsTxt());
  fs.writeFileSync(path.join(webDir, 'sitemap.xml'), sitemapXml());
}
