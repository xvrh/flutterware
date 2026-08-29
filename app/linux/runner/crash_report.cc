// TEMPORARY debugging scaffolding for the Linux panel-resize segfault.
//
// Not shipped: gated on FW_CRASH_REPORT=1 and to be deleted once the fault is
// understood. It exists because Flutter publishes no symbols for
// `linux-x64`, so a backtrace of addresses is all there is — this turns those
// addresses into `<module>+<offset>` (which `objdump -d --start-address` can
// then be pointed at) and prints the register file, which is usually what says
// whether a pointer was null, freed, or garbage.

#include "crash_report.h"

#include <dlfcn.h>
#include <execinfo.h>
#include <link.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ucontext.h>
#include <unistd.h>

namespace {

// The last thing the texture plugin did, so the report says which frame the
// engine was on and at what size. Written from populate, read from a signal
// handler — plain volatile rather than a lock, because a handler must not take
// one and a torn read here is still a hint.
volatile FwCrashNote g_note = {0, 0, 0, 0, 0};

struct ModuleRange {
  const char* name;
  uintptr_t base;
};

int collect_module(struct dl_phdr_info* info, size_t, void* data) {
  auto* out = static_cast<FILE*>(data);
  if (info->dlpi_name != nullptr && info->dlpi_name[0] != '\0') {
    fprintf(out, "  map %016lx  %s\n",
            static_cast<unsigned long>(info->dlpi_addr), info->dlpi_name);
  }
  return 0;
}

void describe_frame(FILE* out, int index, void* pc) {
  Dl_info info;
  if (dladdr(pc, &info) != 0 && info.dli_fname != nullptr) {
    auto base = reinterpret_cast<uintptr_t>(info.dli_fbase);
    auto addr = reinterpret_cast<uintptr_t>(pc);
    const char* slash = strrchr(info.dli_fname, '/');
    fprintf(out, "  #%-2d %016lx  %s+0x%lx", index,
            static_cast<unsigned long>(addr), slash ? slash + 1 : info.dli_fname,
            static_cast<unsigned long>(addr - base));
    if (info.dli_sname != nullptr) {
      auto sym = reinterpret_cast<uintptr_t>(info.dli_saddr);
      fprintf(out, "  (%s+0x%lx)", info.dli_sname,
              static_cast<unsigned long>(addr - sym));
    }
    fputc('\n', out);
  } else {
    fprintf(out, "  #%-2d %016lx  ?\n", index,
            static_cast<unsigned long>(reinterpret_cast<uintptr_t>(pc)));
  }
}

void handler(int signo, siginfo_t* info, void* context) {
  static volatile sig_atomic_t entered = 0;
  if (entered) _exit(134);
  entered = 1;

  FILE* out = stderr;
  char thread_name[32] = "?";
  pthread_getname_np(pthread_self(), thread_name, sizeof(thread_name));

  fprintf(out, "\n=== FW CRASH REPORT ===\n");
  fprintf(out, "signal %d code %d addr %016lx thread \"%s\" tid %d\n", signo,
          info->si_code,
          static_cast<unsigned long>(reinterpret_cast<uintptr_t>(
              info->si_addr)),
          thread_name, static_cast<int>(gettid()));
  fprintf(out,
          "last populate: n=%lu name=%u size=%ux%u slot=%d\n",
          static_cast<unsigned long>(g_note.frames), g_note.gl_name,
          g_note.width, g_note.height, g_note.slot);

  auto* uc = static_cast<ucontext_t*>(context);
  const greg_t* r = uc->uc_mcontext.gregs;
  static const char* names[] = {"R8",  "R9",  "R10", "R11", "R12", "R13",
                                "R14", "R15", "RDI", "RSI", "RBP", "RBX",
                                "RDX", "RAX", "RCX", "RSP", "RIP"};
  static const int idx[] = {REG_R8,  REG_R9,  REG_R10, REG_R11, REG_R12,
                            REG_R13, REG_R14, REG_R15, REG_RDI, REG_RSI,
                            REG_RBP, REG_RBX, REG_RDX, REG_RAX, REG_RCX,
                            REG_RSP, REG_RIP};
  for (size_t i = 0; i < sizeof(idx) / sizeof(idx[0]); i++) {
    fprintf(out, "  %-3s %016lx%s", names[i],
            static_cast<unsigned long>(r[idx[i]]), (i % 4 == 3) ? "\n" : "");
  }
  fputc('\n', out);

  fprintf(out, "modules:\n");
  dl_iterate_phdr(collect_module, out);

  void* frames[64];
  int count = backtrace(frames, 64);
  fprintf(out, "backtrace (%d frames):\n", count);
  // Frame 0 is this handler; frame 2 is usually the faulting pc. Print the
  // signal context's RIP first so the faulting instruction is unambiguous.
  describe_frame(out, -1, reinterpret_cast<void*>(r[REG_RIP]));
  for (int i = 0; i < count; i++) describe_frame(out, i, frames[i]);
  fprintf(out, "=== END FW CRASH REPORT ===\n");
  fflush(out);
  _exit(139);
}

}  // namespace

void fw_crash_note(uint32_t width,
                   uint32_t height,
                   uint32_t gl_name,
                   int slot) {
  g_note.width = width;
  g_note.height = height;
  g_note.gl_name = gl_name;
  g_note.slot = slot;
  g_note.frames++;
}

void fw_crash_report_install() {
  const char* on = getenv("FW_CRASH_REPORT");
  if (on == nullptr || on[0] == '\0' || on[0] == '0') return;

  // SIGSTKSZ is not a compile-time constant on current glibc.
  static char stack[256 * 1024];
  stack_t ss = {};
  ss.ss_sp = stack;
  ss.ss_size = sizeof(stack);
  sigaltstack(&ss, nullptr);

  struct sigaction sa = {};
  sa.sa_sigaction = handler;
  sa.sa_flags = SA_SIGINFO | SA_ONSTACK;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGSEGV, &sa, nullptr);
  sigaction(SIGBUS, &sa, nullptr);
  sigaction(SIGILL, &sa, nullptr);
  sigaction(SIGFPE, &sa, nullptr);
  sigaction(SIGABRT, &sa, nullptr);
  fprintf(stderr, "[fw] crash reporter installed\n");
}
