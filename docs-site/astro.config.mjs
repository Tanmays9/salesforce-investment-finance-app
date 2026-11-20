import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://tanmays9.github.io',
  base: '/salesforce-investment-finance-app',
  output: 'static',
  integrations: [
    starlight({
      title: 'Salesforce Investment Portfolio Manager',
      description:
        'Project documentation for the Salesforce Investment Portfolio Manager.',
      favicon: '/favicon.svg',
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/Tanmays9/salesforce-investment-finance-app',
        },
      ],
    }),
  ],
});
