cmake_minimum_required(VERSION 3.15)
project(flutterware_embedder_host C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

if(NOT FLUTTER_FRAMEWORK_DIR)
  message(FATAL_ERROR
    "Pass -DFLUTTER_FRAMEWORK_DIR=<dir containing FlutterEmbedder.framework>")
endif()

add_executable(host host.c surface.c ipc.c input.c)
target_include_directories(host PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_options(host PRIVATE "-F${FLUTTER_FRAMEWORK_DIR}")
target_link_libraries(host PRIVATE
  "-framework FlutterEmbedder"
  "-framework IOSurface"
  "-framework CoreFoundation")
set_target_properties(host PROPERTIES
  BUILD_WITH_INSTALL_RPATH TRUE
  INSTALL_RPATH "${FLUTTER_FRAMEWORK_DIR}")
