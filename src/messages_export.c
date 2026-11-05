// Messages Export for Claude: the only program that holds Full Disk Access for Messages.
// It opens the Messages and Contacts databases read-only and writes a reduced
// copy of each, holding only what the connector uses, to
// ~/Library/Application Support/messages-readonly/, which Claude reads through
// the connector. It cannot send: it never talks to Messages.app.
//
// Built and installed by install.sh at the top of this repository.

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <sqlite3.h>

// Only these tables and columns are copied. Everything else in the originals
// (deleted messages, attachment paths, addresses, birthdays, notes) stays behind.
static const char *MESSAGES_SQL =
    "CREATE TABLE message(ROWID INTEGER PRIMARY KEY, date INTEGER, is_from_me INTEGER,"
    "  handle_id INTEGER, text TEXT, attributedBody BLOB);"
    "INSERT INTO message SELECT ROWID, date, is_from_me, handle_id, text, attributedBody FROM src.message;"
    "CREATE TABLE chat(ROWID INTEGER PRIMARY KEY, display_name TEXT);"
    "INSERT INTO chat SELECT ROWID, display_name FROM src.chat;"
    "CREATE TABLE handle(ROWID INTEGER PRIMARY KEY, id TEXT);"
    "INSERT INTO handle SELECT ROWID, id FROM src.handle;"
    "CREATE TABLE chat_message_join(chat_id INTEGER, message_id INTEGER);"
    "INSERT INTO chat_message_join SELECT chat_id, message_id FROM src.chat_message_join;"
    "CREATE TABLE chat_handle_join(chat_id INTEGER, handle_id INTEGER);"
    "INSERT INTO chat_handle_join SELECT chat_id, handle_id FROM src.chat_handle_join;"
    "CREATE TABLE message_attachment_join(message_id INTEGER);"
    "INSERT INTO message_attachment_join SELECT message_id FROM src.message_attachment_join;"
    "CREATE INDEX cmj_chat ON chat_message_join(chat_id);"
    "CREATE INDEX cmj_msg ON chat_message_join(message_id);"
    "CREATE INDEX chj_chat ON chat_handle_join(chat_id);"
    "CREATE INDEX maj_msg ON message_attachment_join(message_id);"
    "CREATE INDEX msg_date ON message(date);";

static const char *CONTACTS_SQL =
    "CREATE TABLE ZABCDRECORD(Z_PK INTEGER PRIMARY KEY, ZFIRSTNAME TEXT, ZLASTNAME TEXT, ZORGANIZATION TEXT);"
    "INSERT INTO ZABCDRECORD SELECT Z_PK, ZFIRSTNAME, ZLASTNAME, ZORGANIZATION FROM src.ZABCDRECORD;"
    "CREATE TABLE ZABCDPHONENUMBER(ZOWNER INTEGER, ZFULLNUMBER TEXT);"
    "INSERT INTO ZABCDPHONENUMBER SELECT ZOWNER, ZFULLNUMBER FROM src.ZABCDPHONENUMBER;"
    "CREATE TABLE ZABCDEMAILADDRESS(ZOWNER INTEGER, ZADDRESS TEXT);"
    "INSERT INTO ZABCDEMAILADDRESS SELECT ZOWNER, ZADDRESS FROM src.ZABCDEMAILADDRESS;";

// Refuse a folder that is a symbolic link, not a folder, or not owned by us,
// so the app can never be steered into writing somewhere else.
static int safe_dir(const char *path) {
    struct stat st;
    if (mkdir(path, 0700) != 0 && errno != EEXIST) { perror(path); return 1; }
    if (lstat(path, &st) != 0) { perror(path); return 1; }
    if (!S_ISDIR(st.st_mode) || st.st_uid != getuid()) {
        fprintf(stderr, "%s is not a plain folder owned by you; refusing to write there.\n", path);
        return 1;
    }
    if ((st.st_mode & 0777) != 0700) chmod(path, 0700);
    return 0;
}

static int copy_db(const char *src, const char *dir, const char *name, const char *sql) {
    // A new, unguessable file in our own folder, created here, so no link is followed.
    char tmp[2048], dst[2048];
    snprintf(tmp, sizeof tmp, "%s/.%s.XXXXXX", dir, name);
    snprintf(dst, sizeof dst, "%s/%s", dir, name);
    int fd = mkstemp(tmp);
    if (fd < 0) { perror("mkstemp"); return 1; }
    fchmod(fd, 0600);
    close(fd);

    sqlite3 *db = NULL;
    char *err = NULL;
    int rc = sqlite3_open_v2(tmp, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_URI, NULL);
    if (rc == SQLITE_OK) {
        char *attach = sqlite3_mprintf("ATTACH 'file:%q?mode=ro' AS src;", src);
        sqlite3_busy_timeout(db, 5000);
        // One transaction, so the copy is a consistent snapshot of the original.
        rc = sqlite3_exec(db, attach, NULL, NULL, &err);
        sqlite3_free(attach);
        if (rc == SQLITE_OK) rc = sqlite3_exec(db, "BEGIN;", NULL, NULL, &err);
        if (rc == SQLITE_OK) rc = sqlite3_exec(db, sql, NULL, NULL, &err);
        if (rc == SQLITE_OK) rc = sqlite3_exec(db, "COMMIT; DETACH src;", NULL, NULL, &err);
    }
    if (rc != SQLITE_OK) fprintf(stderr, "copy %s: %s\n", src, err ? err : sqlite3_errmsg(db));
    sqlite3_free(err);
    sqlite3_close(db);

    if (rc != SQLITE_OK) { unlink(tmp); return 1; }
    // rename replaces the name itself; it never follows a link at dst.
    if (rename(tmp, dst) != 0) { perror("rename"); unlink(tmp); return 1; }
    return 0;
}

int main(void) {
    // Home comes from the account record, not the environment, so a changed
    // launch agent cannot point it at other files.
    struct passwd *pw = getpwuid(getuid());
    const char *home = pw ? pw->pw_dir : NULL;
    if (!home) return 2;
    umask(077);

    char outdir[1024], contacts_out[1024], src[2048], name[512];
    snprintf(outdir, sizeof outdir, "%s/Library/Application Support/messages-readonly", home);
    snprintf(contacts_out, sizeof contacts_out, "%s/contacts", outdir);
    if (safe_dir(outdir) || safe_dir(contacts_out)) return 1;

    int failures = 0;

    snprintf(src, sizeof src, "%s/Library/Messages/chat.db", home);
    failures += copy_db(src, outdir, "chat.db", MESSAGES_SQL);

    // Contacts: the main book plus one book per account under Sources/.
    snprintf(src, sizeof src, "%s/Library/Application Support/AddressBook/AddressBook-v22.abcddb", home);
    failures += copy_db(src, contacts_out, "main.abcddb", CONTACTS_SQL);

    char sources[1024];
    snprintf(sources, sizeof sources, "%s/Library/Application Support/AddressBook/Sources", home);
    DIR *d = opendir(sources);
    if (d) {
        struct dirent *e;
        while ((e = readdir(d))) {
            if (e->d_name[0] == '.') continue;
            snprintf(src, sizeof src, "%s/%s/AddressBook-v22.abcddb", sources, e->d_name);
            if (access(src, F_OK) != 0) continue;
            snprintf(name, sizeof name, "%s.abcddb", e->d_name);
            failures += copy_db(src, contacts_out, name, CONTACTS_SQL);
        }
        closedir(d);
    } else if (errno != ENOENT) {  // no contact accounts is normal
        fprintf(stderr, "opendir %s: %s\n", sources, strerror(errno));
        failures++;
    }

    return failures ? 1 : 0;
}
