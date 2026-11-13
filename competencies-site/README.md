# Competencies site

A Hugo site with one page per competency, grouped under Required and Advanced tabs.
It uses the NocturnalZone theme, copied into `themes/nocturnalzone-hugo-theme`.

## Run locally

```bash
cd competencies-site
hugo server -p 1313
```

Then open http://localhost:1313/.

## Publish

The workflow in `.github/workflows/pages.yml` builds the site and deploys it to
GitHub Pages on every push to `main` that changes this folder. The site is served at
https://miaphoebe.github.io/csc324/.
