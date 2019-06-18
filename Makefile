## The lines below can be uncommented for debugging the make rules
#
# OLD_SHELL := $(SHELL)
# SHELL = $(warning Building $@$(if $<, (from $<))$(if $?, ($? newer)))$(OLD_SHELL)
#
# print-%:
# 	@echo $* = $($*)

.PHONY: build fmt test vet clean go_protos grafeas_go_v1alpha1 swagger_docs

SRC = $(shell find . -type f -name '*.go' -not -path "./vendor/*")
CLEAN := *~

default: .check_makefile_in_gopath build

.install.tools: .install.protoc-gen-go .install.grpc-gateway protoc/bin/protoc
	@touch $@

EXPECTED_MAKE = ${GOPATH}/src/github.com/grafeas/grafeas/Makefile

.check_makefile_in_gopath:
	if [ "$(realpath ${EXPECTED_MAKE})" != "$(realpath $(lastword $(MAKEFILE_LIST)))" ]; \
	then  \
	echo "Makefile is not in GOPATH root"; \
	false; \
	fi

CLEAN += .install.protoc-gen-go .install.grpc-gateway
.install.protoc-gen-go:
	cd tools && GO111MODULE=on go install -v github.com/golang/protobuf/protoc-gen-go
	touch $@

.install.grpc-gateway:
	cd tools && GO111MODULE=on go install -v github.com/grpc-ecosystem/grpc-gateway/protoc-gen-grpc-gateway
	cd tools && GO111MODULE=on go install -v github.com/grpc-ecosystem/grpc-gateway/protoc-gen-swagger
	touch $@

build: vet fmt go_protos swagger_docs
	go build -v ./...

# http://golang.org/cmd/go/#hdr-Run_gofmt_on_package_sources
fmt:
	@gofmt -l -w $(SRC)

test: go_protos
	@go test -v ./...

vet: go_protos
	@go vet -composites=false ./...

protoc/bin/protoc:
	mkdir -p protoc
	curl https://github.com/google/protobuf/releases/download/v3.3.0/protoc-3.3.0-linux-x86_64.zip -o protoc/protoc.zip -L
	unzip protoc/protoc -d protoc

CLEAN += protoc proto/*/*_go_proto

GO_PROTO_DIRS_V1BETA1 := $(patsubst %.proto,%_go_proto/.done,$(wildcard proto/v1beta1/*.proto))
GO_PROTO_FILES_V1 := $(filter-out proto/v1/grafeas_go_proto/project.pb.go, $(patsubst proto/v1/%.proto,proto/v1/grafeas_go_proto/%.pb.go,$(wildcard proto/v1/*.proto)))

cel/syntax.pb.go:
	cd cel && go generate

# v1alpha1 has a different codebase structure than v1beta1 and v1,
# so it's generated separately
go_protos: cel/syntax.pb.go v1alpha1/proto/grafeas.pb.go $(GO_PROTO_DIRS_V1BETA1) $(GO_PROTO_FILES_V1)

PROTOC_CMD=protoc/bin/protoc -I ./ \
	-I vendor/github.com/grpc-ecosystem/grpc-gateway/third_party/googleapis \
	-I vendor/github.com/grpc-ecosystem/grpc-gateway \
	-I vendor/github.com/googleapis/googleapis

v1alpha1/proto/grafeas.pb.go: v1alpha1/proto/grafeas.proto .install.tools
	$(PROTOC_CMD) \
		--go_out=plugins=grpc:. \
		--grpc-gateway_out=logtostderr=true:. \
		--swagger_out=logtostderr=true:. \
		v1alpha1/proto/grafeas.proto

# Builds go proto packages from protos
# Example:
#      $ make proto/v1beta1/grafeas_go_proto/.done
#      Builds: proto/v1beta1/grafeas_go_proto/grafeas.pb.go and proto/v1beta1/grafeas_go_proto/grafeas.pb.gw.go
#      Using: proto/v1beta1/grafeas.proto
proto/v1beta1/%_go_proto/.done: proto/v1beta1/%.proto .install.tools
	$(PROTOC_CMD) \
		--go_out=plugins=grpc,paths=source_relative:. \
		--grpc-gateway_out=logtostderr=true,paths=source_relative:. \
		$<
	@mkdir -p $(@D)
	mv proto/v1beta1/$*.pb.go $(@D)
	if [ -f proto/v1beta1/$*.pb.gw.go ]; then mv proto/v1beta1/$*.pb.gw.go $(@D); fi
	@touch $@

# Builds go proto packages from protos
# Example:
#      $ make proto/v1/grafeas_go_proto/grafeas.pb.go
#      Builds: proto/v1/grafeas_go_proto/grafeas.pb.go and proto/v1/grafeas_go_proto/grafeas.pb.gw.go
#      Using: proto/v1/grafeas.proto
proto/v1/grafeas_go_proto/%.pb.go: proto/v1/%.proto .install.tools
	$(PROTOC_CMD) \
		--go_out=plugins=grpc,paths=source_relative:. \
		--grpc-gateway_out=logtostderr=true,paths=source_relative:. \
		$<
	@mkdir -p proto/v1/grafeas_go_proto
	mv proto/v1/$*.pb.go proto/v1/grafeas_go_proto
	if [ -f proto/v1/$*.pb.gw.go ]; then mv proto/v1/$*.pb.gw.go proto/v1/grafeas_go_proto; fi
	@touch $@


swagger_docs: proto/v1beta1/swagger/*.swagger.json

proto/v1beta1/swagger/%.swagger.json: proto/v1beta1/%.proto protoc/bin/protoc .install.tools
	$(PROTOC_CMD) --swagger_out=logtostderr=true:. $<
	mv $(<D)/*.swagger.json $@

clean:
	go clean ./...
	rm -rf $(CLEAN)
