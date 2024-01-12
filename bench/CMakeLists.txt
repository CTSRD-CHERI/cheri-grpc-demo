cmake_minimum_required(VERSION 3.24)

project(cheri-c18n-policy C CXX)

set(CMAKE_CXX_STANDARD 17)

# Policy spec
add_library(qps_policy SHARED "qps/policy.c")
set_target_properties(qps_policy PROPERTIES NO_SONAME TRUE)
target_link_options(qps_policy PRIVATE "-Wl,-soname,_rtld_c18n_policy.so")

add_custom_command(
  OUTPUT "${CMAKE_SOURCE_DIR}/qps/policy.so"
  COMMAND cp "${CMAKE_BINARY_DIR}/libqps_policy.so" "${CMAKE_SOURCE_DIR}/qps/policy.so"
  DEPENDS qps_policy
  COMMENT "Generate QPS policy"
)
add_custom_target(gen_policy
  ALL
  DEPENDS "${CMAKE_SOURCE_DIR}/qps/policy.so")
