#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define MAX_INPUT (24 * 1024)
#define MAX_FIELD 4096

static size_t bounded_length(const char *value, size_t maximum) {
    return value == NULL ? 0 : strnlen(value, maximum);
}

int main(void) {
    unsigned char input[MAX_INPUT + 1];
    size_t used = 0;
    while (used < sizeof(input)) {
        ssize_t count = read(STDIN_FILENO, input + used, sizeof(input) - used);
        if (count == 0) break;
        if (count < 0) {
            if (errno == EINTR) continue;
            return 0;
        }
        used += (size_t)count;
    }
    if (used == 0 || used > MAX_INPUT) return 0;

    const char *socket_path = getenv("HERDR_SOCKET_PATH");
    const char *pane_id = getenv("HERDR_PANE_ID");
    const char *tab_id = getenv("HERDR_TAB_ID");
    size_t socket_len = bounded_length(socket_path, MAX_FIELD);
    size_t pane_len = bounded_length(pane_id, 256);
    size_t tab_len = bounded_length(tab_id, 256);
    if (socket_len == 0 || pane_len == 0 || tab_len == 0) return 0;

    const char *runtime = getenv("XDG_RUNTIME_DIR");
    char fallback[64];
    if (runtime == NULL || runtime[0] != '/') {
        snprintf(fallback, sizeof(fallback), "/run/user/%lu", (unsigned long)getuid());
        runtime = fallback;
    }
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    int written = snprintf(address.sun_path, sizeof(address.sun_path), "%s/herdr-title/events.sock", runtime);
    if (written < 0 || (size_t)written >= sizeof(address.sun_path)) return 0;

    size_t total = 4 + 4 * sizeof(uint32_t) + socket_len + pane_len + tab_len + used;
    unsigned char *message = malloc(total);
    if (message == NULL) return 0;
    memcpy(message, "HT1\0", 4);
    uint32_t lengths[4] = {
        htonl((uint32_t)socket_len), htonl((uint32_t)pane_len),
        htonl((uint32_t)tab_len), htonl((uint32_t)used)
    };
    memcpy(message + 4, lengths, sizeof(lengths));
    size_t offset = 4 + sizeof(lengths);
    memcpy(message + offset, socket_path, socket_len); offset += socket_len;
    memcpy(message + offset, pane_id, pane_len); offset += pane_len;
    memcpy(message + offset, tab_id, tab_len); offset += tab_len;
    memcpy(message + offset, input, used);

    int client = socket(AF_UNIX, SOCK_DGRAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
    if (client >= 0) {
        (void)sendto(client, message, total, MSG_DONTWAIT,
                     (struct sockaddr *)&address, sizeof(address));
        close(client);
    }
    free(message);
    return 0;
}
