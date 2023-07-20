/*-
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2023 Alfredo Mazzinghi
 *
 * This software was developed by the University of Cambridge Computer
 * Laboratory (Department of Computer Science and Technology) under
 * DSTL contract ACC6036483: CHERI-based compartmentalisation for web
 * services on Morello.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <iostream>
#include <memory>
#include <string>
#include <grpcpp/grpcpp.h>

#include "redblue.grpc.pb.h"
#include "redblue.pb.h"


using grpc::ClientContext;
using grpc::Status;
using cheri_demo::RedService;
using cheri_demo::RedReq;
using cheri_demo::RedRes;
using cheri_demo::BlueService;
using cheri_demo::BlueReq;
using cheri_demo::BlueRes;


class RedBlueClient {
 public:
  RedBlueClient(std::shared_ptr<grpc::Channel> channel)
      : red_stub_(RedService::NewStub(channel)),
        blue_stub_(BlueService::NewStub(channel)) {}

  int SendRO(int value) {
    RedReq req;
    RedRes res;
    ClientContext context;

    req.set_value(value);
    Status status = red_stub_->ReadonlyAPI(&context, req, &res);

    if (status.ok()) {
      return res.value();
    } else {
      return -1;
    }
  }

  int SendRW(int value) {
    BlueReq req;
    BlueRes res;
    ClientContext context;

    req.set_value(value);
    Status status = blue_stub_->ReadWriteAPI(&context, req, &res);

    if (status.ok()) {
      return res.value();
    } else {
      return -1;
    }
  }

 private:
  std::unique_ptr<RedService::Stub> red_stub_;
  std::unique_ptr<BlueService::Stub> blue_stub_;
};

int main(int argc, char* argv[]) {
  std::string server_addr("localhost:50051");

  RedBlueClient client(grpc::CreateChannel(server_addr, grpc::InsecureChannelCredentials()));

  for (int i = 0; i < 100; i++) {
    int r_value = client.SendRO(i);
    std::cout << "Red " << i << " Responds" << r_value << std::endl;
    int b_value = client.SendRW(i);
    std::cout << "Blue " << i << " Responds" << b_value << std::endl;
  }

  return 0;
}
