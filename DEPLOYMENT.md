# 🚀 Deployment Guide

Complete guide for deploying the Trader Joe LB Dashboard to various platforms.

## Table of Contents
- [Pre-Deployment Checklist](#pre-deployment-checklist)
- [Vercel Deployment](#vercel-deployment)
- [Netlify Deployment](#netlify-deployment)
- [GitHub Pages](#github-pages)
- [AWS S3 + CloudFront](#aws-s3--cloudfront)
- [Docker Deployment](#docker-deployment)
- [Custom Server](#custom-server)
- [Environment Variables](#environment-variables)
- [Post-Deployment](#post-deployment)

## Pre-Deployment Checklist

Before deploying, ensure:

- [ ] All environment variables are configured
- [ ] Contract addresses are updated for target network
- [ ] API keys are set (if using external APIs)
- [ ] Remove or update testnet-specific features for mainnet
- [ ] Test build locally: `npm run build && npm run preview`
- [ ] Check bundle size: Should be < 500KB gzipped
- [ ] Verify all links and URLs are correct
- [ ] Test on multiple browsers (Chrome, Firefox, Safari)
- [ ] Mobile responsiveness verified
- [ ] Performance audit completed (Lighthouse score > 90)

## Vercel Deployment

### Quick Deploy (Recommended)

1. **Install Vercel CLI**
```bash
npm i -g vercel
```

2. **Login to Vercel**
```bash
vercel login
```

3. **Deploy**
```bash
# First deployment
vercel

# Production deployment
vercel --prod
```

### GitHub Integration

1. **Push to GitHub**
```bash
git add .
git commit -m "Ready for deployment"
git push origin main
```

2. **Import to Vercel**
- Go to https://vercel.com/new
- Import your GitHub repository
- Configure project:
  - Framework Preset: Vite
  - Root Directory: ./
  - Build Command: `npm run build`
  - Output Directory: `dist`

3. **Add Environment Variables**
- Go to Project Settings → Environment Variables
- Add all variables from `.env.example`
- Click "Deploy"

### Custom Domain

1. Go to Project Settings → Domains
2. Add your custom domain
3. Update DNS records as instructed
4. Wait for SSL certificate (automatic)

**Vercel Configuration** (`vercel.json`):
```json
{
  "buildCommand": "npm run build",
  "outputDirectory": "dist",
  "framework": "vite",
  "rewrites": [
    { "source": "/(.*)", "destination": "/index.html" }
  ],
  "headers": [
    {
      "source": "/assets/(.*)",
      "headers": [
        {
          "key": "Cache-Control",
          "value": "public, max-age=31536000, immutable"
        }
      ]
    }
  ]
}
```

## Netlify Deployment

### Quick Deploy

1. **Install Netlify CLI**
```bash
npm i -g netlify-cli
```

2. **Login**
```bash
netlify login
```

3. **Build and Deploy**
```bash
npm run build
netlify deploy --prod --dir=dist
```

### Drag & Drop Deploy

1. Build locally: `npm run build`
2. Go to https://app.netlify.com/drop
3. Drag the `dist` folder
4. Done! 🎉

### GitHub Integration

1. **Push to GitHub**
```bash
git push origin main
```

2. **Connect to Netlify**
- Go to https://app.netlify.com
- Click "New site from Git"
- Choose your repository
- Configure build:
  - Build command: `npm run build`
  - Publish directory: `dist`

3. **Environment Variables**
- Go to Site settings → Build & deploy → Environment
- Add variables from `.env.example`

**Netlify Configuration** (`netlify.toml`):
```toml
[build]
  command = "npm run build"
  publish = "dist"

[[redirects]]
  from = "/*"
  to = "/index.html"
  status = 200

[[headers]]
  for = "/assets/*"
  [headers.values]
    Cache-Control = "public, max-age=31536000, immutable"

[[headers]]
  for = "/*.js"
  [headers.values]
    Cache-Control = "public, max-age=31536000, immutable"
```

## GitHub Pages

### Using gh-pages Package

1. **Install gh-pages**
```bash
npm install --save-dev gh-pages
```

2. **Update package.json**
```json
{
  "homepage": "https://yourusername.github.io/your-repo-name",
  "scripts": {
    "predeploy": "npm run build",
    "deploy": "gh-pages -d dist"
  }
}
```

3. **Update vite.config.ts**
```typescript
export default defineConfig({
  base: '/your-repo-name/', // Add this
  plugins: [react()],
  // ... rest of config
})
```

4. **Deploy**
```bash
npm run deploy
```

5. **Enable GitHub Pages**
- Go to repository Settings → Pages
- Source: Deploy from a branch
- Branch: gh-pages → / (root)
- Save

### Using GitHub Actions

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches: [main]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'

      - name: Install dependencies
        run: npm ci

      - name: Build
        run: npm run build
        env:
          VITE_WALLETCONNECT_PROJECT_ID: ${{ secrets.VITE_WALLETCONNECT_PROJECT_ID }}

      - name: Deploy
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./dist
```

## AWS S3 + CloudFront

### Setup S3 Bucket

1. **Create S3 Bucket**
```bash
aws s3 mb s3://your-dashboard-bucket
```

2. **Enable Static Website Hosting**
```bash
aws s3 website s3://your-dashboard-bucket \
  --index-document index.html \
  --error-document index.html
```

3. **Set Bucket Policy**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::your-dashboard-bucket/*"
    }
  ]
}
```

### Deploy to S3

```bash
# Build
npm run build

# Upload to S3
aws s3 sync dist/ s3://your-dashboard-bucket \
  --delete \
  --cache-control "public, max-age=31536000"

# Upload index.html separately (no cache)
aws s3 cp dist/index.html s3://your-dashboard-bucket/index.html \
  --cache-control "no-cache"
```

### Setup CloudFront

1. **Create Distribution**
```bash
aws cloudfront create-distribution \
  --origin-domain-name your-dashboard-bucket.s3.amazonaws.com \
  --default-root-object index.html
```

2. **Configure Error Pages**
- 403 → /index.html (for SPA routing)
- 404 → /index.html (for SPA routing)

3. **Invalidate Cache**
```bash
aws cloudfront create-invalidation \
  --distribution-id YOUR_DISTRIBUTION_ID \
  --paths "/*"
```

## Docker Deployment

### Dockerfile

```dockerfile
# Build stage
FROM node:18-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# Production stage
FROM nginx:alpine

COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

### nginx.conf

```nginx
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
}
```

### Build and Run

```bash
# Build image
docker build -t trader-joe-dashboard .

# Run container
docker run -d -p 80:80 trader-joe-dashboard

# With environment variables
docker run -d -p 80:80 \
  -e VITE_CHAIN_ID=84532 \
  -e VITE_WALLETCONNECT_PROJECT_ID=your_project_id \
  trader-joe-dashboard
```

### Docker Compose

```yaml
version: '3.8'

services:
  dashboard:
    build: .
    ports:
      - "80:80"
    environment:
      - VITE_CHAIN_ID=84532
      - VITE_RPC_URL=https://sepolia.base.org
      - VITE_WALLETCONNECT_PROJECT_ID=${WALLETCONNECT_PROJECT_ID}
    restart: unless-stopped
```

## Custom Server (Node.js)

### Express Server

```javascript
// server.js
const express = require('express');
const path = require('path');
const app = express();

app.use(express.static(path.join(__dirname, 'dist')));

app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'dist', 'index.html'));
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
```

### Deploy

```bash
# Build
npm run build

# Install production dependencies
npm install express

# Start server
node server.js
```

## Environment Variables

### Development (.env.local)
```bash
VITE_CHAIN_ID=84532
VITE_RPC_URL=https://sepolia.base.org
VITE_TESTNET_MODE=true
VITE_WALLETCONNECT_PROJECT_ID=your_dev_project_id
```

### Production (.env.production)
```bash
VITE_CHAIN_ID=8453
VITE_RPC_URL=https://mainnet.base.org
VITE_TESTNET_MODE=false
VITE_WALLETCONNECT_PROJECT_ID=your_prod_project_id
# Add all contract addresses
VITE_LB_FACTORY_ADDRESS=0x...
VITE_LB_ROUTER_ADDRESS=0x...
```

### Platform-Specific

**Vercel**: Add in Project Settings → Environment Variables

**Netlify**: Add in Site settings → Build & deploy → Environment

**GitHub Pages**: Add in repository Settings → Secrets and variables → Actions

**Docker**: Pass via `-e` flag or docker-compose.yml

## Post-Deployment

### Verify Deployment

- [ ] Dashboard loads without errors
- [ ] Wallet connection works
- [ ] All pages/tabs accessible
- [ ] Charts render correctly
- [ ] External links work
- [ ] Mobile view is responsive
- [ ] SSL certificate is valid (https://)
- [ ] Console has no errors

### Performance Checks

1. **Run Lighthouse**
```bash
# Install
npm install -g @lhci/cli

# Run audit
lhci autorun --collect.url=https://your-domain.com
```

Target scores:
- Performance: > 90
- Accessibility: > 95
- Best Practices: > 90
- SEO: > 90

2. **Check Bundle Size**
```bash
npm run build

# Should see:
# dist/assets/index-[hash].js  ~150-200 KB gzipped
# dist/assets/index-[hash].css ~20-30 KB gzipped
```

### Monitoring

1. **Setup Error Tracking** (Sentry)
```bash
npm install @sentry/react
```

2. **Analytics** (Plausible/Google Analytics)
```html
<!-- Add to index.html -->
<script defer data-domain="yourdomain.com" src="https://plausible.io/js/script.js"></script>
```

3. **Uptime Monitoring**
- UptimeRobot (free)
- Pingdom
- StatusCake

### Security Headers

Add to your hosting platform:

```
Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: geolocation=(), microphone=(), camera=()
```

## Rollback Procedure

### Vercel
```bash
# List deployments
vercel ls

# Promote previous deployment
vercel promote [deployment-url]
```

### Netlify
- Go to Deploys tab
- Click on previous successful deploy
- Click "Publish deploy"

### GitHub Pages
```bash
# Revert commit
git revert HEAD
git push origin main
```

## Troubleshooting

### Build Fails
- Check Node.js version (needs 18+)
- Clear node_modules: `rm -rf node_modules && npm install`
- Check for TypeScript errors
- Verify all imports are correct

### Blank Page After Deploy
- Check browser console for errors
- Verify base path in vite.config.ts
- Ensure SPA routing is configured
- Check environment variables

### Wallet Won't Connect
- Verify WalletConnect project ID
- Check CORS settings
- Ensure HTTPS is enabled
- Test with different wallet

## Best Practices

1. **Use CI/CD**: Automate deployments with GitHub Actions
2. **Environment Separation**: Different configs for dev/staging/prod
3. **Monitoring**: Set up error tracking and analytics
4. **Backups**: Keep deployment artifacts for rollback
5. **Documentation**: Document your deployment process
6. **Testing**: Test on staging before prod deployment
7. **Secrets**: Never commit API keys or private keys
8. **Cache Busting**: Vite handles this automatically
9. **Compression**: Enable gzip/brotli on server
10. **SSL**: Always use HTTPS in production

---

**Need Help?**

- Vercel Docs: https://vercel.com/docs
- Netlify Docs: https://docs.netlify.com
- GitHub Pages: https://pages.github.com
- AWS S3: https://docs.aws.amazon.com/s3

Happy Deploying! 🚀
