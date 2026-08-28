#include "crash_report.h"
#include "my_application.h"

int main(int argc, char** argv) {
  fw_crash_report_install();
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
