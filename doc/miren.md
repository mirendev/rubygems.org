# Deploy your own RubyGems.org on Miren

Run your own copy of RubyGems.org on the team's cluster, give it a development
hostname, and deploy changes from your checkout without replacing anyone else's
app. This is a non-production environment, separate from public rubygems.org.

Commands in this guide were checked against Miren v0.17.1.

## First, get your own app running

You need access to the **RubyGems** organization and a checkout containing the
team's Miren setup changes. The destination is the **miren-rubygems** cluster,
where you will create your own named app, such as `rubygems-evan`.

The cluster and reference app are running. The development-domain setup below is
proposed, not applied. The Miren setup is on the
[`miren-deployment` branch of `mirendev/rubygems.org`](https://github.com/mirendev/rubygems.org/tree/miren-deployment),
not the upstream RubyGems.org default branch.

## 1. Connect your laptop to the cluster

Miren builds and runs your application on a remote **cluster**. You use its
command-line client from your laptop to deploy code and inspect the result. The
cluster is already set up; you only need to connect to it.

Install the client using [Miren's platform-specific instructions](https://miren.dev/get-started).
Use v0.17.1 or later. You do not need to install a server or Docker locally.

```sh
miren version
miren login
miren cluster add --cluster miren-rubygems --organization RubyGems
miren app status -C miren-rubygems -a rubygems
```

Login opens the account authorization flow. Your account needs access to the
RubyGems organization and cluster; ask an org admin if the cluster is missing or
access is denied. Every command here explicitly names the cluster to avoid
deploying elsewhere by accident.

In your existing RubyGems.org checkout, obtain the team's Miren setup changes
before deploying: `.miren/app.toml`, `.miren/deploy.toml`, `bin/miren-web`,
`config/environments/preview.rb`, and their supporting configuration changes.
The setup is not yet upstream; a fresh upstream checkout alone is insufficient.
Run deployment commands from the repository root on the branch you want to test.
Do not run `miren init` over the existing configuration.

## 2. Deploy your own copy of RubyGems.org

Choose a name and use it consistently. The examples use `evan` and create an app
called `rubygems-evan`; substitute your name. An **app** owns its running services
and database, so your deployment will not replace anyone else's.

Keep the existing `.miren/app.toml` as the recipe. It already defines the
Dockerfile build, Rails startup command, OpenSearch service, and PostgreSQL addon.
The `-a` flag overrides its default app name, while `-C` explicitly selects the
cluster.

Start with Miren's managed hostname so you can deploy before custom DNS is ready.
On the first deployment, generate a private Rails secret and pass it as a
sensitive value:

```sh
name=evan
app="rubygems-$name"
host="$app.cluster-2wh7n1wappef.miren.systems"

secret_file=$(mktemp)
chmod 600 "$secret_file"
openssl rand -hex 64 > "$secret_file"
miren deploy -C miren-rubygems -a "$app" \
  -e "APP_HOST=$host" -s "SECRET_KEY_BASE=@$secret_file"
rm -f "$secret_file"
```

Miren uploads your current checkout and builds it remotely; you do not need Docker
on your laptop. It creates your app's logical database on the cluster's shared
PostgreSQL 18 server and starts web and OpenSearch services. Rails loads the schema
automatically. Review local changes before deploying: upload rules, not Git commit
boundaries, determine which source files are included.

Your database starts empty, not as a copy of the reference app. Signups are disabled
and insecure development seeds are skipped; ask the maintainer to arrange approved
test accounts and data. Keep production credentials out of this environment.

```sh
miren app status -C miren-rubygems -a "$app"
curl -I "https://$host/"
```

Open `https://rubygems-evan.cluster-2wh7n1wappef.miren.systems`, substituting your
app name. Initial startup can take time while Rails prepares the database and
search index. If startup fails, inspect the web logs rather than repeatedly
deploying:

```sh
miren logs -C miren-rubygems -a "$app" --service web --last 15m
```

The deployment flow is your checkout → remote Dockerfile build → your named app
(web, search, and your database). PostgreSQL databases share a server, not app data.

## 3. Give your app its own development hostname

Recommend that the team's DNS owner point `*.dev.rubygems.org` at the cluster.
This lets developers choose separate hostnames such as `evan.dev.rubygems.org`
without changing DNS for every new app. An equivalent team-owned domain works too.

```text
# Proposed DNS record — for the DNS owner to add:
*.dev.rubygems.org. CNAME cluster-2wh7n1wappef.miren.systems.
```

Use the cluster hostname, not its API address or port 8443. Once your hostname
resolves to the cluster, create an exact **route** to your app. A route tells
Miren which app should receive requests for that hostname:

```sh
name=evan
app="rubygems-$name"
host="$name.dev.rubygems.org"
miren route set -C miren-rubygems "$host" "$app"
miren deploy -C miren-rubygems -a "$app" -e "APP_HOST=$host"
curl -I "https://$host/"
```

The deployment changes Rails' canonical hostname to match the route. `APP_HOST`
takes a hostname only, without `https://` or a path; Rails uses it for redirects,
generated links, and WebAuthn origins. The app reuses its stored Rails secret, so
do not generate another one.

Miren provisions HTTPS automatically. Allow time for DNS propagation and the
first certificate request; the DNS owner should confirm any CAA restrictions and
that HTTP/HTTPS traffic reaches Miren. Create a separate exact route for each app,
rather than sending every name to the reference app `rubygems`.

## 4. Deploy changes to your app

With your desired branch checked out, deploy again using the same app name and
hostname:

```sh
name=evan
app="rubygems-$name"
host="$name.dev.rubygems.org"
miren deploy -C miren-rubygems -a "$app" -e "APP_HOST=$host"
```

This replaces your app's **active version**—the code serving your normal URL. If
custom DNS is not ready, keep using the managed hostname from step 2 instead.
Always pass your app name: the unchanged `app.toml` still defaults to the reference
app `rubygems`.

Startup runs `db:prepare`, so database migrations affect your app's database.
Deploying older code does not undo those migrations. Each named app also runs its
own search and web services; coordinate capacity with the maintainer before
creating many apps on this shared cluster.

**You now have your own deployed RubyGems.org.** The workflow above is enough to
keep updating it. The next section is optional: use it when you want to test a
branch without replacing the version at your normal URL.

## 5. Add short-lived PR environments when you need them

An **ephemeral deployment** runs a branch alongside your app's active version, at
a separate URL. We will call your normal deployed app the **baseline**: each PR
environment starts from a snapshot of that app's database, then keeps its own
writes and migrations separate.

Before using PR hostnames, have the DNS owner ensure names below your app's
hostname also resolve. An explicit wildcard for your name makes that coverage
clear:

```text
*.evan.dev.rubygems.org. CNAME cluster-2wh7n1wappef.miren.systems.
```

Your existing route at `evan.dev.rubygems.org` handles its PR labels automatically.
You do not need a wildcard route or a separate route command for each PR.

Check out the branch you want to test and choose a label such as `pr-123`. Labels
should contain lowercase letters, digits, and hyphens, start and end with a letter
or digit, and be at most 63 characters. Labels are unique within your app: two
developers with separate apps can both use `pr-123`.

After the proposed custom domain is set up:

```sh
name=evan
app="rubygems-$name"
label=pr-123
host="$label.$name.dev.rubygems.org"
miren deploy -C miren-rubygems -a "$app" \
  --ephemeral "$label" --ttl 48h \
  -e "APP_HOST=$host"
curl -I "https://$host/"
```

Without custom DNS, use the managed domain instead:

```sh
name=evan
app="rubygems-$name"
label=pr-123
host="$label.$app.cluster-2wh7n1wappef.miren.systems"
miren deploy -C miren-rubygems -a "$app" \
  --ephemeral "$label" --ttl 48h \
  -e "APP_HOST=$host"
curl -I "https://$host/"
```

Choose one example. Miren uploads source from your current checkout, builds the
Dockerfile remotely, clones the baseline database, and creates the labeled version.
This includes local changes that the upload rules allow; review your working tree
before deploying. The first request may wait while Rails prepares the database
and populates the preview's search index.

`APP_HOST` is a hostname only—no scheme or path—and must match the URL you will
open. It controls canonical redirects, generated links, and WebAuthn origins. If
the CLI prints several possible URLs, use the hostname you supplied here.

Make a change and rerun the same command to update the preview. **Reusing a label
deletes and replaces its old version and database clone**; preview data is not
carried forward. Each deployment starts from a fresh baseline snapshot and resets
the TTL.

### Previews clean themselves up

`--ttl 48h` keeps the preview for 48 hours; omitting it uses 24 hours. After expiry,
requests return 404 and Miren cleans up the version and cloned database. Redeploy
the label to refresh its lifetime; there is no extend command.

There is a limit of 10 ephemeral versions per app. Creating an eleventh evicts the
one nearest expiry. Keep TTLs modest on this shared cluster.

### Optional: preview an already-built version without rebuilding

```sh
miren app versions -C miren-rubygems -a rubygems-evan
# Replace VERSION_ID with a version listed above.
miren deploy -C miren-rubygems -a rubygems-evan \
  --version VERSION_ID --ephemeral pr-123 --ttl 48h \
  -e APP_HOST=pr-123.evan.dev.rubygems.org
```

Use the managed hostname instead until custom DNS is ready. An existing build uses
its saved addon cloning policy, not edits in your local `app.toml`. Choose a build
made with PostgreSQL cloning enabled; do not reuse an older build that would share
the baseline database.

## Reference: what the existing configuration supplies

The configuration should remain the shared recipe, with branch-specific changes
layered on it. `.miren/deploy.toml` names the deployment target; the explicit `-C`
flags above make the destination unambiguous.

- `RAILS_ENV=preview` uses production-like behavior without production service
  credentials.
- The Dockerfile builds the app; `sh bin/miren-web` prepares PostgreSQL, waits for
  search, initializes a missing index, then starts Puma on port 3000.
- The baseline runs web and a private OpenSearch 2.13 service. Ephemeral versions
  run only web, using the baseline's search server and their own database-prefixed
  indexes.
- `include = ["config/rubygems.yml"]` ensures the needed configuration is uploaded
  despite ignore rules. Keep it.

```toml
[addons.miren-postgresql]
variant = "shared"
version = "18"
clone = true
clone_variant = "shared"
```

This means PostgreSQL 18, one shared server, and one isolated logical database/user
per preview. Let the addon provide `DATABASE_URL` and the `PG*` variables.
**Do not manually set them**: manual values take precedence and can accidentally
connect a preview to the baseline.

Each named app needs its own sensitive `SECRET_KEY_BASE` on first deployment
(step 2). Later deployments and PR previews reuse that app's stored value. Do not
copy secrets into the repository or reuse the reference app's secret.

## Limits and safety

### Gem metadata is cloned; package files are not

Gem uploads use container-local files, not production S3. Files can disappear when
a container is replaced, and database cloning does not copy them. A cloned gem can
appear in metadata or search while its download is unavailable. Upload your test
gem directly to your preview to test push, download, and installation; never point
those tests at public rubygems.org.

### Use test accounts, not production credentials

No production data or credentials were imported. Signups are disabled, and
development seed accounts with known passwords are not created. Ask the maintainer
for an approved test account and preview-scoped API key when testing authenticated
flows; do not enable public signup just to get access. A preview URL is not itself
an access-control boundary.

### Some production behavior is deliberately absent

Email delivery and scheduled jobs are disabled. Explicitly enqueued jobs run inline
after database transactions commit; there is no separate preview worker. Search
indexes are isolated but are not automatically deleted with the preview TTL. The
baseline, previews, PostgreSQL, and OpenSearch share cluster resources, so heavy
tests can affect teammates.

## Check and troubleshoot

```sh
miren app versions -C miren-rubygems -a rubygems-evan --ephemeral
miren app status -C miren-rubygems -a rubygems-evan
miren route -C miren-rubygems
miren logs -C miren-rubygems -a rubygems-evan --service web --last 15m
# Add --follow to stream new logs.
```

The versions list shows labels and expiration. App status describes the baseline;
app logs may include more than one version, so correlate the time and
version/sandbox identifiers when investigating a preview. Ephemeral deployments
do not appear in normal deployment history.

- **Cluster missing or access denied:** check your account's RubyGems org access
  and repeat step 1; do not create a replacement cluster.
- **DNS or HTTPS failure:** check both proposed records and propagation; confirm
  the baseline route and a live preview label. Try the managed-domain example
  with its matching `APP_HOST`. Do not bypass certificate verification as a fix.
- **Redirects to the baseline:** redeploy the preview with the correct `APP_HOST`.
- **404 after working earlier:** inspect expiration, label replacement, and the
  per-app preview limit.
- **First request slow or startup failure:** inspect web logs for database
  preparation, search readiness, and indexing. Repeated failure is not just a
  cold start.
- **Preview sees baseline writes:** stop testing writes and ask the maintainer to
  check for manually configured `DATABASE_URL`/`PG*` values or an older build
  without cloning. Do not print connection credentials into chat.

## References and scope

This guide was checked against `.miren/app.toml`, CLI v0.17.1 help, and Miren's
routing, TLS, and PR-environment documentation. Read-only checks on 27 October 2026
confirmed the reference app was active, with one web and one search sandbox, and
only its managed hostname plus default route configured. Custom DNS and route
commands in this guide were not executed.

The setup was previously exercised with gem push, search, download, installation,
and isolated preview writes after migration to shared PostgreSQL. Those tests
used the managed domain; custom-domain validation remains part of the DNS rollout.

- [Install the CLI](https://miren.dev/get-started)
- [Miren Cloud](https://miren.cloud)
- [Ephemeral environments](https://miren.md/pr-environments)
- [Routes and custom domains](https://miren.md/traffic-routing)
- [TLS](https://miren.md/tls)

This guide does not cover production rubygems.org deployment, durable gem storage,
importing production data, or setting up GitHub Actions. It describes manual
deployment from an existing checkout; no DNS, named apps, infrastructure, or app
configuration was changed while writing it.
