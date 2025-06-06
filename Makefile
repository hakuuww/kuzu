.PHONY: \
	release debug all alldebug \
	test lcov \
	java nodejs python rust \
	javatest nodejstest pytest rusttest \
	benchmark example \
	clangd tidy clangd-diagnostics \
	install \
	clean-extension clean-python-api clean-java clean \
	extension-test shell-test

.ONESHELL:
.SHELLFLAGS = -ec

CLANGD_DIAGNOSTIC_INSTANCES ?= 4
NUM_THREADS ?= 1
PREFIX ?= install
TEST_JOBS ?= 10
EXTENSION_LIST ?= httpfs;duckdb;json;postgres;sqlite;fts;delta;iceberg;azure;unity_catalog;vector;neo4j;algo;llm
EXTENSION_TEST_EXCLUDE_FILTER ?= ""

export CMAKE_BUILD_PARALLEL_LEVEL=$(NUM_THREADS)

ifeq ($(OS),Windows_NT)
	GEN ?= Ninja
	SHELL := cmd.exe
	.SHELLFLAGS := /c
endif

ifdef GEN
	CMAKE_FLAGS += -G "$(GEN)"
endif

ifdef ASAN
	CMAKE_FLAGS += -DENABLE_ADDRESS_SANITIZER=$(ASAN)
endif
ifdef TSAN
	CMAKE_FLAGS += -DENABLE_THREAD_SANITIZER=$(TSAN)
endif
ifdef UBSAN
	CMAKE_FLAGS += -DENABLE_UBSAN=$(UBSAN)
endif

ifdef ENABLE_DESER_DEBUG
	CMAKE_FLAGS += -DENABLE_DESER_DEBUG=$(ENABLE_DESER_DEBUG)
endif
ifdef RUNTIME_CHECKS
	CMAKE_FLAGS += -DENABLE_RUNTIME_CHECKS=$(RUNTIME_CHECKS)
endif
ifdef WERROR
	CMAKE_FLAGS += -DENABLE_WERROR=$(WERROR)
endif
ifdef LTO
	CMAKE_FLAGS += -DENABLE_LTO=$(LTO)
endif

ifdef SKIP_SINGLE_FILE_HEADER
	CMAKE_FLAGS += -DBUILD_SINGLE_FILE_HEADER=FALSE
endif

ifdef PAGE_SIZE_LOG2
	CMAKE_FLAGS += -DKUZU_PAGE_SIZE_LOG2=$(PAGE_SIZE_LOG2)
endif

ifdef DEFAULT_REL_STORAGE_DIRECTION
	CMAKE_FLAGS += -DKUZU_DEFAULT_REL_STORAGE_DIRECTION=$(DEFAULT_REL_STORAGE_DIRECTION)
endif

ifdef VECTOR_CAPACITY_LOG2
	CMAKE_FLAGS += -DKUZU_VECTOR_CAPACITY_LOG2=$(VECTOR_CAPACITY_LOG2)
endif

ifdef NODE_GROUP_SIZE_LOG2
	CMAKE_FLAGS += -DKUZU_NODE_GROUP_SIZE_LOG2=$(NODE_GROUP_SIZE_LOG2)
endif

ifdef SINGLE_THREADED
	CMAKE_FLAGS += -DSINGLE_THREADED=$(SINGLE_THREADED)
endif

ifdef WASM_NODEFS
	CMAKE_FLAGS += -DWASM_NODEFS=$(WASM_NODEFS)
endif

CMAKE_FLAGS += -DUSE_STD_FORMAT=$(if $(USE_STD_FORMAT),TRUE,FALSE)

# Must be first in the Makefile so that it is the default target.
release:
	$(call run-cmake-release,)

relwithdebinfo:
	$(call run-cmake-relwithdebinfo,)

debug:
	$(call run-cmake-debug,)

allconfig:
	$(call config-cmake-release, \
		-DBUILD_BENCHMARK=TRUE \
		-DBUILD_EXAMPLES=TRUE \
		-DBUILD_EXTENSIONS="$(EXTENSION_LIST)" \
		-DBUILD_JAVA=TRUE \
		-DBUILD_NODEJS=TRUE \
		-DBUILD_PYTHON=TRUE \
		-DBUILD_SHELL=TRUE \
		-DBUILD_TESTS=TRUE \
	)

all: allconfig
	$(call build-cmake-release)

alldebug:
	$(call run-cmake-debug, \
		-DBUILD_BENCHMARK=TRUE \
		-DBUILD_EXAMPLES=TRUE \
		-DBUILD_EXTENSIONS="$(EXTENSION_LIST)" \
		-DBUILD_JAVA=TRUE \
		-DBUILD_NODEJS=TRUE \
		-DBUILD_PYTHON=TRUE \
		-DBUILD_SHELL=TRUE \
		-DBUILD_TESTS=TRUE \
	)

# Main tests
test-build:
	$(call run-cmake-relwithdebinfo, -DBUILD_TESTS=TRUE -DENABLE_BACKTRACES=TRUE)

test: test-build
	python3 dataset/ldbc-1/download_data.py
	ctest --test-dir build/relwithdebinfo/test --output-on-failure -j ${TEST_JOBS}

lcov:
	python3 dataset/ldbc-1/download_data.py
	$(call run-cmake-release, -DBUILD_TESTS=TRUE -DBUILD_LCOV=TRUE)
	ctest --test-dir build/release/test --output-on-failure -j ${TEST_JOBS}

# Language APIs

# Required for clangd-related tools.
java_native_header:
	cmake --build build/release --target kuzu_java

java:
	$(call run-cmake-release, -DBUILD_JAVA=TRUE)

nodejs:
	$(call run-cmake-release, -DBUILD_NODEJS=TRUE)

python:
	$(call run-cmake-release, -DBUILD_PYTHON=TRUE -DBUILD_SHELL=FALSE)

python-debug:
	$(call run-cmake-debug, -DBUILD_PYTHON=TRUE)

wasm:
	mkdir -p build/wasm && cd build/wasm &&\
	emcmake cmake $(CMAKE_FLAGS) -DCMAKE_BUILD_TYPE=Release -DBUILD_WASM=TRUE -DBUILD_BENCHMARK=FALSE -DBUILD_TESTS=FALSE -DBUILD_SHELL=FALSE  ../.. && \
	cmake --build . --config Release -j $(NUM_THREADS)

# Language API tests
javatest:
ifeq ($(OS),Windows_NT)
	cd tools/java_api &&\
	gradlew.bat test -i
else
	cd tools/java_api &&\
	./gradlew test -i
endif

nodejstest: nodejs
	cd tools/nodejs_api && npm test

pytest: python
	cmake -E env PYTHONPATH=tools/python_api/build python3 -m pytest -vv tools/python_api/test

pytest-debug: python-debug
	cmake -E env PYTHONPATH=tools/python_api/build python3 -m pytest -vv tools/python_api/test

rusttest:
ifeq ($(OS),Windows_NT)
	set CARGO_BUILD_JOBS=$(NUM_THREADS)
else
	export CARGO_BUILD_JOBS=$(NUM_THREADS)
endif
	cd tools/rust_api && cargo test --release --locked --all-features

wasmtest:
	mkdir -p build/wasm && cd build/wasm &&\
	emcmake cmake $(CMAKE_FLAGS) -DCMAKE_BUILD_TYPE=Release -DBUILD_WASM=TRUE -DBUILD_BENCHMARK=FALSE -DBUILD_TESTS=TRUE -DBUILD_SHELL=FALSE  ../.. && \
	cmake --build . --config Release -j $(NUM_THREADS) &&\
	cd ../.. && ctest --test-dir  build/wasm/test/ --output-on-failure -j ${TEST_JOBS} --timeout 600

# Other misc build targets
benchmark:
	$(call run-cmake-release, -DBUILD_BENCHMARK=TRUE)

example:
	$(call run-cmake-release, -DBUILD_EXAMPLES=TRUE)

extension-test-build:
	$(call run-cmake-relwithdebinfo, \
		-DBUILD_EXTENSIONS="$(EXTENSION_LIST)" \
		-DBUILD_EXTENSION_TESTS=TRUE \
		-DBUILD_TESTS=TRUE \
	)

extension-json-test-build:
	$(call run-cmake-relwithdebinfo, \
		-DBUILD_EXTENSIONS="json" \
		-DBUILD_EXTENSION_TESTS=TRUE \
		-DENABLE_ADDRESS_SANITIZER=TRUE \
	)

# This should be removed and be replaced with something more flexible with any given extension names.
extension-test: extension-test-build
ifeq ($(OS),Windows_NT)
	set "E2E_TEST_FILES_DIRECTORY=extension" && ctest --test-dir build/relwithdebinfo/test/runner --output-on-failure -j ${TEST_JOBS} --exclude-regex "${EXTENSION_TEST_EXCLUDE_FILTER}"
else
	E2E_TEST_FILES_DIRECTORY=extension ctest --test-dir build/relwithdebinfo/test/runner --output-on-failure -j ${TEST_JOBS} --exclude-regex "${EXTENSION_TEST_EXCLUDE_FILTER}"
endif
	aws s3 rm s3://kuzu-dataset-us/${RUN_ID}/ --recursive

extension-json-test: extension-json-test-build
	ctest --test-dir build/relwithdebinfo/extension --output-on-failure -j ${TEST_JOBS} -R json
	aws s3 rm s3://kuzu-dataset-us/${RUN_ID}/ --recursive

extension-debug:
	$(call run-cmake-debug, \
		-DBUILD_EXTENSIONS="$(EXTENSION_LIST)" \
		-DBUILD_KUZU=FALSE \
	)

extension-release:
	$(call run-cmake-release, \
		-DBUILD_EXTENSIONS="$(EXTENSION_LIST)" \
		-DBUILD_KUZU=FALSE \
	)

shell-test:
	$(call run-cmake-relwithdebinfo, \
		-DBUILD_SHELL=TRUE \
	)
	cd tools/shell/test && python3 -m pytest -v

# Clang-related tools and checks

# Must build the java native header to avoid missing includes. Pipe character
# `|` ensures these targets build in this order, even in the presence of
# parallelism.
tidy: | allconfig java_native_header
	run-clang-tidy -p build/release -quiet -j $(NUM_THREADS) \
		"^$(realpath src)|$(realpath extension)/(?!fts/third_party/snowball/)|$(realpath tools)/(?!shell/linenoise.cpp)"

tidy-analyzer: | allconfig java_native_header
	run-clang-tidy -config-file .clang-tidy-analyzer -p build/release -quiet -j $(NUM_THREADS) \
		"^$(realpath src)/(?!function/vector_cast_functions.cpp)|$(realpath extension)/(?!fts/third_party/snowball/)|$(realpath tools)/(?!shell/linenoise.cpp)"

clangd-diagnostics: | allconfig java_native_header
	find src -name *.h -or -name *.cpp | xargs \
		./scripts/get-clangd-diagnostics.py --compile-commands-dir build/release \
		-j $(NUM_THREADS) --instances $(CLANGD_DIAGNOSTIC_INSTANCES)


# Installation
install:
	cmake --install build/release --prefix $(PREFIX)


# Cleaning
clean-extension:
	cmake -E rm -rf extension/algo/build
	cmake -E rm -rf extension/httpfs/build
	cmake -E rm -rf extension/duckdb/build
	cmake -E rm -rf extension/postgres/build
	cmake -E rm -rf extension/sqlite/build
	cmake -E rm -rf extension/fts/build
	cmake -E rm -rf extension/delta/build
	cmake -E rm -rf extension/iceberg/build
	cmake -E rm -rf extension/azure/build
	cmake -E rm -rf extension/llm/build
	cmake -E rm -rf extension/unity_catalog/build
	cmake -E rm -rf extension/vector/build
	cmake -E rm -rf extension/neo4j/build
	cmake -E rm -rf extension/gds/build

clean-python-api:
	cmake -E rm -rf tools/python_api/build

clean-java:
	cmake -E rm -rf tools/java_api/build

clean: clean-extension clean-python-api clean-java
	cmake -E rm -rf build


# Utils
define config-cmake
	cmake -B build/$1 $(CMAKE_FLAGS) -DCMAKE_BUILD_TYPE=$2 $3 .
endef

define build-cmake
	cmake --build build/$1 --config $2
endef

define run-cmake
	$(call config-cmake,$1,$2,$3)
	$(call build-cmake,$1,$2)
endef

define run-cmake-debug
	$(call run-cmake,debug,Debug,$1)
endef

define build-cmake-release
	$(call build-cmake,release,Release,$1)
endef

define build-cmake-relwithdebinfo
	$(call build-cmake,relwithdebinfo,RelWithDebInfo,$1)
endef

define config-cmake-release
	$(call config-cmake,release,Release,$1)
endef

define config-cmake-relwithdebinfo
	$(call config-cmake,relwithdebinfo,RelWithDebInfo,$1)
endef

define run-cmake-release
	$(call config-cmake-release,$1)
	$(call build-cmake-release,$1)
endef

define run-cmake-relwithdebinfo
	$(call config-cmake-relwithdebinfo,$1)
	$(call build-cmake-relwithdebinfo,$1)
endef
