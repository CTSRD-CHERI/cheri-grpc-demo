cmake_minimum_required(VERSION 3.24)

project(cheri-grpc-demo C CXX)

set(CMAKE_CXX_STANDARD 17)

find_package(Protobuf REQUIRED MODULE)
message(STATUS "Use protobuf ${Protobuf_VERSION}")
find_package(gRPC REQUIRED)
message(STATUS "Use grpc ${gRPC_VERSION}")

include_directories("${CMAKE_CURRENT_BINARY_DIR}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -g -Xclang -morello-bounded-memargs=caller-only")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -g -Xclang -morello-bounded-memargs=caller-only")
set(C18N_LINK_CFLAGS "-Wl,--dynamic-linker=/libexec/ld-elf-c18n.so.1")

# Simple ping-pong test

set(proto_srcs "${CMAKE_CURRENT_BINARY_DIR}/test.pb.cc")
set(proto_hdrs "${CMAKE_CURRENT_BINARY_DIR}/test.pb.h")
set(grpc_srcs "${CMAKE_CURRENT_BINARY_DIR}/test.grpc.pb.cc")
set(grpc_hdrs "${CMAKE_CURRENT_BINARY_DIR}/test.grpc.pb.h")
set(proto_path "${CMAKE_SOURCE_DIR}/proto")

add_custom_command(
  OUTPUT "${proto_srcs}" "${proto_hdrs}" "${grpc_srcs}" "${grpc_hdrs}"
  COMMAND protoc
  ARGS --grpc_out ${CMAKE_CURRENT_BINARY_DIR}
  --cpp_out ${CMAKE_CURRENT_BINARY_DIR}
  -I ${proto_path}
  --plugin=protoc-gen-grpc="$<TARGET_FILE:gRPC::grpc_cpp_plugin>"
  "${proto_path}/test.proto"
)

add_library(grpc_proto_lib
  "${proto_srcs}"
  "${proto_hdrs}"
  "${grpc_srcs}"
  "${grpc_hdrs}"
)
target_link_libraries(grpc_proto_lib
  PUBLIC
  gRPC::grpc++_reflection
  gRPC::grpc++
  protobuf::libprotobuf
)

add_executable(c18n_ping_client "ping_client.cc")
target_link_options(c18n_ping_client PRIVATE "${C18N_LINK_CFLAGS}")
target_link_libraries(c18n_ping_client grpc_proto_lib)

add_executable(c18n_ping_server "ping_server.cc")
target_link_options(c18n_ping_server PRIVATE "${C18N_LINK_CFLAGS}")
target_link_libraries(c18n_ping_server grpc_proto_lib)

add_executable(ping_client "ping_client.cc")
target_link_libraries(ping_client grpc_proto_lib)

add_executable(ping_server "ping_server.cc")
target_link_libraries(ping_server grpc_proto_lib)


# red/blue service compartmentalisation toy

set(rb_proto_srcs "${CMAKE_CURRENT_BINARY_DIR}/redblue.pb.cc")
set(rb_proto_hdrs "${CMAKE_CURRENT_BINARY_DIR}/redblue.pb.h")
set(rb_grpc_srcs "${CMAKE_CURRENT_BINARY_DIR}/redblue.grpc.pb.cc")
set(rb_grpc_hdrs "${CMAKE_CURRENT_BINARY_DIR}/redblue.grpc.pb.h")
set(rb_proto_path "${CMAKE_SOURCE_DIR}/proto")

add_custom_command(
  OUTPUT "${rb_proto_srcs}" "${rb_proto_hdrs}" "${rb_grpc_srcs}" "${rb_grpc_hdrs}"
  COMMAND protoc
  ARGS --grpc_out ${CMAKE_CURRENT_BINARY_DIR}
  --cpp_out ${CMAKE_CURRENT_BINARY_DIR}
  -I ${proto_path}
  --plugin=protoc-gen-grpc="$<TARGET_FILE:gRPC::grpc_cpp_plugin>"
  "${proto_path}/redblue.proto"
)

add_library(rb_grpc_proto_lib
  "${rb_proto_srcs}"
  "${rb_proto_hdrs}"
  "${rb_grpc_srcs}"
  "${rb_grpc_hdrs}"
)
target_link_libraries(rb_grpc_proto_lib
  PUBLIC
  gRPC::grpc++_reflection
  gRPC::grpc++
  protobuf::libprotobuf
)

add_library(red_service SHARED "red_service.cc")
target_link_libraries(red_service rb_grpc_proto_lib)

add_library(blue_service SHARED "blue_service.cc")
target_link_libraries(blue_service rb_grpc_proto_lib)

add_executable(c18n_rb_client "redblue_client.cc")
target_link_options(c18n_rb_client PRIVATE "${C18N_LINK_CFLAGS}")
target_link_libraries(c18n_rb_client rb_grpc_proto_lib)

add_executable(c18n_rb_server "redblue_server.cc")
target_link_options(c18n_rb_server PRIVATE "${C18N_LINK_CFLAGS}")
target_link_libraries(c18n_rb_server red_service blue_service)

add_executable(rb_client "redblue_client.cc")
target_link_libraries(rb_client rb_grpc_proto_lib)

# Note, here we don't have shared libraries because they are not needed
add_executable(rb_server "redblue_server.cc" "red_service.cc" "blue_service.cc")
target_link_libraries(rb_server rb_grpc_proto_lib)
