/home/applepie/server/
│
├── infrastructure/
│   │
│   ├── gateway/
│   │   ├── docker-compose.yml        ← nginx, cloudflared
│   │   ├── .env                      ← CLOUDFLARE_TUNNEL_TOKEN
│   │   ├── nginx/
│   │   │   ├── nginx.conf
│   │   │   └── conf.d/
│   │   │       ├── portfolio.conf
│   │   │       ├── blog.conf
│   │   │       ├── app.conf
│   │   │       └── registry.conf
│   │   ├── upstreams/
│   │   │   ├── api_active.conf
│   │   │   ├── web_active.conf
│   │   │   ├── portfolio_active.conf
│   │   │   └── blog_active.conf
│   │   └── cloudflared/
│   │       └── config.yml
│   │
│   └── registry/
│       ├── docker-compose.yml
│       └── data/
│
├── apps/
│   │
│   ├── static/
│   │   ├── portfolio/
│   │   │   └── public/
│   │   │       ├── index.html
│   │   │       ├── about.html
│   │   │       ├── projects.html
│   │   │       ├── contact.html
│   │   │       ├── style.css
│   │   │       └── script.js
│   │   │
│   │   └── blog/
│   │       └── public/
│   │           ├── index.html
│   │           ├── style.css
│   │           └── script.js
│   │
│   └── dynamic/
│       └── app/
│           ├── api/
│           │   ├── docker-compose.yml
│           │   └── .env
│           └── web/
│               ├── docker-compose.yml
│               └── .env
│
├── releases/
│   │
│   ├── static/
│   │   ├── portfolio/
│   │   │   └── current_version
│   │   └── blog/
│   │       └── current_version
│   │
│   └── dynamic/
│       └── app/
│           ├── api/
│           │   ├── current_slot
│           │   ├── current_version
│           │   ├── blue.env
│           │   └── green.env
│           └── web/
│               ├── current_slot
│               ├── current_version
│               ├── blue.env
│               └── green.env
│
├── data/
│   ├── postgres/
│   ├── uploads/
│   │   └── app/
│   │       ├── images/
│   │       └── avatars/
│   └── backups/
│
├── logs/
│   └── nginx/
│       ├── access.log
│       └── error.log
│
└── docker/
    └── daemon.json