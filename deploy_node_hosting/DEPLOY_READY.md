# Node Hosting Package

This folder is the deployable package for the root OrderDrop Node/Express web app.

## What Is Included

- `server.js` and `package.json`
- Root HTML pages used by the site
- Static assets in `css`, `js`, `images`, and `style`
- Backend code in `routes`, `middleware`, `services`, `utils`, and `config`
- Database setup files in `database`
- Empty `uploads/` directory placeholder

## Before Upload

1. Copy `.env.example` to `.env`
2. Fill in production database, JWT, Stripe, email, and domain values
3. Set `NODE_ENV=production`
4. Set `ALLOWED_ORIGINS` to your real domain

## On The Hosting Server

1. Upload this whole folder
2. Run `npm install`
3. Run `node setup-db.js` if this is a fresh database
4. Run `npm start`

## Start Command

Use:

```bash
npm start
```

This runs:

```bash
node server.js
```
