#include "ipc.h"

#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

static pthread_mutex_t g_write_mutex = PTHREAD_MUTEX_INITIALIZER;

int ipc_connect(const char* socket_path) {
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) return -1;
  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path) - 1);
  if (connect(fd, (struct sockaddr*)&addr, sizeof(addr)) != 0) {
    close(fd);
    return -1;
  }
  return fd;
}

static bool write_all(int fd, const uint8_t* data, size_t len) {
  size_t off = 0;
  while (off < len) {
    ssize_t n = write(fd, data + off, len - off);
    if (n <= 0) return false;
    off += (size_t)n;
  }
  return true;
}

static bool read_all(int fd, uint8_t* data, size_t len) {
  size_t off = 0;
  while (off < len) {
    ssize_t n = read(fd, data + off, len - off);
    if (n <= 0) return false;
    off += (size_t)n;
  }
  return true;
}

bool ipc_send(int fd, uint8_t type, const uint8_t* payload, size_t len) {
  uint32_t frame_len = (uint32_t)(1 + len);
  uint8_t header[5];
  memcpy(header, &frame_len, 4);  // host is little-endian
  header[4] = type;
  pthread_mutex_lock(&g_write_mutex);
  bool ok = write_all(fd, header, 5) &&
            (len == 0 || write_all(fd, payload, len));
  pthread_mutex_unlock(&g_write_mutex);
  return ok;
}

int ipc_read(int fd, uint8_t** payload, size_t* len) {
  uint8_t header[5];
  if (!read_all(fd, header, 5)) return -1;
  uint32_t frame_len;
  memcpy(&frame_len, header, 4);
  if (frame_len < 1) return -1;
  size_t payload_len = frame_len - 1;
  uint8_t* buf = payload_len ? (uint8_t*)malloc(payload_len) : NULL;
  if (payload_len && !read_all(fd, buf, payload_len)) {
    free(buf);
    return -1;
  }
  *payload = buf;
  *len = payload_len;
  return header[4];
}
