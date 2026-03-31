# Migrating from hassio-addons/addon-grocy

This guide helps you migrate from the original
[hassio-addons/addon-grocy](https://github.com/hassio-addons/addon-grocy)
add-on to the actively maintained
[lazytarget-homeassistant-apps/grocy](https://github.com/lazytarget-homeassistant-apps/grocy)
fork.

## Why is manual migration needed?

Home Assistant Supervisor identifies add-ons by their **slug**, which is
derived from the repository URL. Because this fork uses a different repository,
it gets a different slug — meaning Home Assistant treats it as a completely
separate add-on. Your database, configuration, and uploaded files from the
original Grocy add-on will **not** carry over automatically.

## What needs to be migrated

| Data | Location (inside container) | Importance |
|---|---|---|
| Grocy database | `/data/grocy/grocy.db` | **Critical** — all your products, stock, recipes, chores, etc. |
| Uploaded files | `/data/grocy/storage/` | Important — product images, file attachments |
| View cache | `/data/grocy/viewcache/` | Not needed — regenerated automatically |
| Grocy PHP config | `/data/grocy/config.php` | Not needed — generated from add-on options on each start |

**Add-on settings** (culture, currency, features, tweaks, etc.) are stored by
Home Assistant Supervisor, not inside Grocy's data directory. You will need to
**manually reconfigure** these in the new add-on's Configuration tab.

## Before you begin

1. **Write down your current add-on settings.** Go to **Settings → Add-ons →
   Grocy → Configuration** and note or screenshot all your option values
   (culture, currency, features, tweaks, etc.).
2. **Install the new add-on** from this repository but **do not start it yet**
   (or start it once and then stop it — this creates the data directory).
3. **Stop the original Grocy add-on** to prevent database writes during
   migration.

## Understanding the data paths

On Home Assistant OS, add-on persistent data is stored on the host at:

```
/mnt/data/supervisor/addons/data/<slug>/
```

- **Original add-on slug:** `a0d7b954_grocy`
  (from the `hassio-addons` community repository)
- **New add-on slug:** `<new_hash>_grocy`
  (from the `lazytarget-homeassistant-apps` repository)

The Grocy data directory sits at `grocy/` within the add-on's data path:

```
/mnt/data/supervisor/addons/data/a0d7b954_grocy/grocy/grocy.db    ← old
/mnt/data/supervisor/addons/data/<new_hash>_grocy/grocy/grocy.db   ← new
```

### How to find the new add-on's slug

You can find the exact slug by running this from the **Advanced SSH & Web
Terminal** add-on (or any host-level shell):

```bash
ha addons list | grep -i grocy
```

This will show both the old and new add-on slugs. Alternatively, open the
add-on in the Home Assistant UI and check the URL in your browser — it contains
the slug.

---

## Method 1: Via rooted SSH (recommended)

**Best for:** Users who already have SSH access to the host.

### Requirements

- The **[Advanced SSH & Web Terminal](https://github.com/hassio-addons/addon-ssh)**
  add-on installed with **Protection Mode disabled** (this grants host-level
  access).

### Steps

1. **Stop** both the old and new Grocy add-ons.

2. Open the **Advanced SSH & Web Terminal** web UI (or SSH in).

3. Identify the slugs:

   ```bash
   ls /mnt/data/supervisor/addons/data/ | grep grocy
   ```

   You should see two directories, e.g.:
   ```
   a0d7b954_grocy
   xxxxxxxx_grocy
   ```

4. **Ensure the new add-on's data directory exists** (start and stop the new
   add-on once if it doesn't).

5. **Copy the database and storage** from old to new:

   ```bash
   OLD_SLUG="a0d7b954_grocy"
   NEW_SLUG="xxxxxxxx_grocy"   # replace with your actual new slug

   OLD_DATA="/mnt/data/supervisor/addons/data/${OLD_SLUG}/grocy"
   NEW_DATA="/mnt/data/supervisor/addons/data/${NEW_SLUG}/grocy"

   # Back up the new (empty) data directory just in case
   cp -a "${NEW_DATA}" "${NEW_DATA}.bak"

   # Copy the database
   cp "${OLD_DATA}/grocy.db" "${NEW_DATA}/grocy.db"

   # Copy uploaded files / storage (if it exists)
   if [ -d "${OLD_DATA}/storage" ]; then
       cp -a "${OLD_DATA}/storage" "${NEW_DATA}/storage"
   fi
   ```

6. **Apply your add-on settings** to the new add-on's Configuration tab
   (culture, currency, features, tweaks, etc.).

7. **Start** the new Grocy add-on and verify your data is intact.

8. *(Optional)* Once you're satisfied, uninstall the old add-on.

---

## Method 2: Via Home Assistant backup (no SSH required)

**Best for:** Users without host-level SSH access. More involved, but works on
any Home Assistant installation.

### Overview

Home Assistant backups are `.tar` archives that contain add-on data. The idea
is to create a backup of the old add-on, extract the Grocy database from it,
then place it into a new backup that includes the new add-on.

### Steps

#### Part A — Extract data from the old add-on's backup

1. Go to **Settings → System → Backups** and create a **partial backup** that
   includes only the original **Grocy** add-on. Give it a recognizable name
   (e.g., `grocy-migration`).

2. **Download** the backup `.tar` file to your computer.

3. Extract the outer tar archive:

   ```bash
   mkdir grocy-migration && cd grocy-migration
   tar xf /path/to/grocy-migration.tar
   ```

4. Inside you'll find a file like `a0d7b954_grocy.tar.gz` — this contains the
   add-on's data. Extract it:

   ```bash
   mkdir old-addon-data
   tar xzf a0d7b954_grocy.tar.gz -C old-addon-data
   ```

5. The Grocy database is at `old-addon-data/data/grocy/grocy.db`.
   Uploaded files (if any) are at `old-addon-data/data/grocy/storage/`.

#### Part B — Inject data into the new add-on's backup

6. In Home Assistant, **start the new Grocy add-on once** (to initialize its
   data directory), then **stop it**.

7. Create a **partial backup** of the **new** Grocy add-on and download it.

8. Extract the new backup:

   ```bash
   mkdir new-backup && cd new-backup
   tar xf /path/to/new-grocy-backup.tar
   ```

9. Extract the new add-on's data archive (the filename will contain the new
   slug):

   ```bash
   NEW_ADDON_ARCHIVE=$(ls *_grocy.tar.gz)
   mkdir new-addon-data
   tar xzf "${NEW_ADDON_ARCHIVE}" -C new-addon-data
   ```

10. **Replace** the database and copy storage:

    ```bash
    # Copy database
    cp ../grocy-migration/old-addon-data/data/grocy/grocy.db \
       new-addon-data/data/grocy/grocy.db

    # Copy storage directory if it exists
    if [ -d ../grocy-migration/old-addon-data/data/grocy/storage ]; then
        cp -a ../grocy-migration/old-addon-data/data/grocy/storage \
           new-addon-data/data/grocy/storage
    fi
    ```

11. **Repackage** the add-on data archive:

    ```bash
    cd new-addon-data
    tar czf "../${NEW_ADDON_ARCHIVE}" .
    cd ..
    ```

12. **Repackage** the full backup:

    ```bash
    tar cf /path/to/modified-grocy-backup.tar ./*
    ```

13. **Upload** the modified backup in Home Assistant:
    Go to **Settings → System → Backups → ⋮ → Upload backup**, select the
    modified `.tar` file.

14. **Restore** only the new Grocy add-on from this backup.

15. **Apply your add-on settings** in the new add-on's Configuration tab and
    start it.

---

## Method 3: Using the migration helper script

To simplify Method 2, a helper script is provided that automates the backup
manipulation.

### Requirements

- A computer with **bash** and standard tools (`tar`, `cp`)
- Downloaded backups of both the old and new Grocy add-ons (see Method 2,
  steps 1–2 and 6–7)

### Usage

```bash
./scripts/migrate-grocy-backup.sh \
    --old-backup /path/to/old-grocy-backup.tar \
    --new-backup /path/to/new-grocy-backup.tar \
    --output /path/to/migrated-backup.tar
```

The script will:

1. Extract the Grocy database and storage from the old backup
2. Inject them into the new backup
3. Produce a ready-to-upload `.tar` file

Then upload and restore the output file in Home Assistant (see Method 2,
steps 13–15).

> **Note:** The migration script is located at
> [`scripts/migrate-grocy-backup.sh`](scripts/migrate-grocy-backup.sh).

---

## Post-migration checklist

- [ ] Open the new Grocy add-on web UI and verify your products, stock levels,
      recipes, and chores are present.
- [ ] Check that product images and file attachments loaded correctly.
- [ ] Reconfigure add-on settings (culture, currency, features, tweaks) if not
      done already.
- [ ] Test creating/editing a product to confirm the database is writable.
- [ ] Once satisfied, uninstall the old Grocy add-on and remove the old
      repository (if no longer needed).

## Troubleshooting

### "Database is locked" or permission errors

Make sure the old add-on is **stopped** before copying the database. If the new
add-on fails to start, check the logs — the database file may need its
ownership reset. Via SSH:

```bash
# Find the correct slug first
NEW_SLUG="xxxxxxxx_grocy"
chown -R root:root "/mnt/data/supervisor/addons/data/${NEW_SLUG}/grocy"
```

### Empty Grocy after starting the new add-on

The new add-on only copies a fresh data template if `/data/grocy` doesn't
exist. If you started the new add-on before copying your database, the empty
database was already created. **Stop** the add-on, replace the database file
(see your chosen method above), and start again.

### Add-on settings not applied

The add-on settings (culture, currency, features, tweaks, etc.) are **not**
part of the Grocy database — they are managed by Home Assistant and written to
Grocy's `config.php` on every start. You must reconfigure them in the new
add-on's **Configuration** tab.
