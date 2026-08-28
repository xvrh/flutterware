// TEMPORARY. See crash_report.cc.
#ifndef RUNNER_CRASH_REPORT_H_
#define RUNNER_CRASH_REPORT_H_

#include <cstdint>

struct FwCrashNote {
  unsigned long frames;
  uint32_t width;
  uint32_t height;
  uint32_t gl_name;
  int slot;
};

// Records what the texture plugin last handed the engine, for the report.
void fw_crash_note(uint32_t width, uint32_t height, uint32_t gl_name, int slot);

// Installs the handlers when FW_CRASH_REPORT is set to something truthy.
void fw_crash_report_install();

#endif  // RUNNER_CRASH_REPORT_H_
