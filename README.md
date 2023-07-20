# Background

This software is a small demonstration of library compartmentalisation with gRPC.

There are two main programs here:
    - The ping-pong client and server which are just a toy test to explore how library compartmentalisation
      behaves in a very simple setup. 
    - The red and blue service example. Functionally this is not interesting as it is just two ping-pong services
      in the same server. Here, however, library compartmentalisation is used to isolate each service in its own
      compartment. While this example is functionally unintresting, it should be possible to augment it to
      demonstrate that an exploit on the red service will not compromise private state in the blue compartment.

In each case, we build two variants of the binaries: a normal CheriABI version and one that uses library
compartmentalisation, prefixed by `c18n_`.

## Build instructions

It is assumed that gRPC is built from the CheriBSD ports collection.
The demo programs can be build as follows:

```
$ cmake -B out -G Ninja
$ ninja -C out
```

## Library compartmentalization

The variants that use library compartmentalisation can be run without any specific flag, assuming that the
CheriBSD release contains the c18n run-time linker at /libexec/ld-elf-c18n.so.1.

It is interesting to use the `ktrace` tool to capture domain transitions that occur during the test.
This can be done as follows:

```
$ ktrace -t u ./out/c18n_rb_server
Server listening at 0.0.0.0:50051
```

In another terminal, run:

```
$ ./out/c18n_rb_client
Red 0 Responds1
Blue 0 Responds1
Red 1 Responds2
Blue 1 Responds2
Red 2 Responds3
Blue 2 Responds3
Red 3 Responds4
Blue 3 Responds4
Red 4 Responds5
Blue 4 Responds5
...
```

Now stop the `c18n_rb_server` and produce a text trace from ktrace.out:

```
$ kdump > trace.txt
$ head trace.txt
 68622 ping_server USER  RTLD: c18n: enter libc.so.7 at <unknown> (0x42318751)

 68622 ping_server USER  RTLD: c18n: enter libc.so.7 at memset (0x4236a1f9)

 68622 ping_server USER  RTLD: c18n: leave libc.so.7 at memset

 68622 ping_server USER  RTLD: c18n: enter libc.so.7 at readlink (0x422d4bcd)

 68622 ping_server USER  RTLD: c18n: leave libc.so.7 at readlink
```

Note that the trace content may vary depending on the version of the library compartmentalisation
run-time linker being run.

## Notes and Limitations

This is a very simple toy implementation that is not representative of a real gRPC API service.
The main goal of this demo is to provide insight about the behaviour of library compartmentalisation
with a complex C++ library (gRPC) using a very simple setup that is easy to understand and control.
The evaluation of the performance and security implications for these examples is an open question.

## Acknowledgement

This work has been undertaken within DSTL contract
ACC6036483: CHERI-based compartmentalisation for web services on Morello.
