cmake_minimum_required(VERSION 3.10)
project(slim2upnp VERSION 0.1.21)

set(CMAKE_CXX_STANDARD 17)

# ============================================
# Architecture Detection
# ============================================

message(STATUS "")
message(STATUS "═══════════════════════════════════════════════════════")
message(STATUS "  slim2UPnP - Build Configuration")
message(STATUS "═══════════════════════════════════════════════════════")

execute_process(
    COMMAND uname -m
    OUTPUT_VARIABLE UNAME_M
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

if(UNAME_M STREQUAL "x86_64")
    set(BASE_ARCH "x64")
    set(ARCH_DESC_BASE "x86_64 (Intel/AMD 64-bit)")
elseif(UNAME_M STREQUAL "aarch64" OR UNAME_M STREQUAL "arm64")
    set(BASE_ARCH "aarch64")
    set(ARCH_DESC_BASE "ARM64 (aarch64)")
elseif(UNAME_M STREQUAL "riscv64")
    set(BASE_ARCH "riscv64")
    set(ARCH_DESC_BASE "RISC-V 64-bit")
else()
    set(BASE_ARCH "unknown")
    set(ARCH_DESC_BASE "Unknown: ${UNAME_M}")
endif()

message(STATUS "Architecture: ${ARCH_DESC_BASE}")

# ============================================
# Architecture-Specific Variant Detection
# ============================================

if(BASE_ARCH STREQUAL "x64")
    execute_process(
        COMMAND grep -q avx2 /proc/cpuinfo
        RESULT_VARIABLE HAS_AVX2_RESULT
    )
    execute_process(
        COMMAND grep -q avx512 /proc/cpuinfo
        RESULT_VARIABLE HAS_AVX512_RESULT
    )
    execute_process(
        COMMAND sh -c "lscpu 2>/dev/null | grep -qi 'AMD.*Zen 4'"
        RESULT_VARIABLE IS_ZEN4_RESULT
    )

    if(IS_ZEN4_RESULT EQUAL 0)
        set(CPU_DESC "AMD Zen 4 detected")
    elseif(HAS_AVX512_RESULT EQUAL 0)
        set(CPU_DESC "AVX512 detected (x86-64-v4)")
    elseif(HAS_AVX2_RESULT EQUAL 0)
        set(CPU_DESC "AVX2 detected (x86-64-v3)")
    else()
        set(CPU_DESC "Basic x64 (x86-64-v2)")
    endif()

elseif(BASE_ARCH STREQUAL "aarch64")
    set(CPU_DESC "ARM64")
endif()

message(STATUS "CPU: ${CPU_DESC}")

# ============================================
# Find Required Packages
# ============================================

find_package(Threads REQUIRED)
find_package(PkgConfig QUIET)

# Passthrough mode: only libupnp required (no decoder libraries)

# --- libupnp (required) ---
if(PKG_CONFIG_FOUND)
    pkg_check_modules(UPNP libupnp)
endif()
if(NOT UPNP_FOUND)
    find_library(UPNP_LIB NAMES upnp)
    find_library(IXML_LIB NAMES ixml)
    find_path(UPNP_INC NAMES upnp/upnp.h)
    if(UPNP_LIB AND IXML_LIB AND UPNP_INC)
        set(UPNP_LIBRARIES ${UPNP_LIB} ${IXML_LIB})
        set(UPNP_INCLUDE_DIRS ${UPNP_INC})
        set(UPNP_FOUND TRUE)
        message(STATUS "libupnp found via find_library: ${UPNP_LIB}")
    else()
        message(FATAL_ERROR
            "libupnp not found! Install with:\n"
            "  Ubuntu/Debian: sudo apt-get install libupnp-dev\n"
            "  Fedora: sudo dnf install libupnp-devel\n"
            "  Arch: sudo pacman -S libupnp\n"
        )
    endif()
endif()

# Passthrough mode: no optional codecs needed
# All audio is proxied directly to the renderer

# ============================================
# Include Directories (simplified)
# ============================================

include_directories(
    ${CMAKE_SOURCE_DIR}/src
    ${UPNP_INCLUDE_DIRS}
)

link_directories(${UPNP_LIBRARY_DIRS})

set(SLIM2UPNP_SOURCES
    src/main.cpp
    src/SlimprotoClient.cpp
    src/HttpStreamClient.cpp
    src/AudioHttpServer.cpp
    src/UPnPController.cpp
)
# Passthrough mode: no decoders needed

# ============================================
# Create Executable
# ============================================

add_executable(slim2upnp ${SLIM2UPNP_SOURCES})

# ============================================
# Static Build Option
# ============================================

option(STATIC_BUILD "Build a statically linked binary" OFF)
if(STATIC_BUILD)
    set(CMAKE_FIND_LIBRARY_SUFFIXES ".a")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -static")
    target_link_options(slim2upnp PRIVATE -static)
    message(STATUS "Static build: ENABLED")
endif()

# ============================================
# Link Libraries
# ============================================

target_link_libraries(slim2upnp
    ${CMAKE_THREAD_LIBS_INIT}
    ${UPNP_LIBRARIES}
)
# ============================================
# Compiler Flags
# ============================================

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -O2")
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Link-Time Optimization (LTO)
# LTO_MODE: OFF (default), thin, full
set(LTO_MODE "OFF" CACHE STRING "LTO mode: OFF, thin, full")
if(NOT LTO_MODE STREQUAL "OFF")
    # With Clang, point CMake at llvm-ar/llvm-ranlib. GNU binutils ar can't
    # read LLVM bitcode, which makes CMake's IPO check fail on Fedora/Arch
    # with "CMAKE_CXX_COMPILER_AR-NOTFOUND" and silently disables LTO.
    if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
        # Ask Clang directly — handles versioned names (llvm-ar-18) and
        # non-standard install paths (/usr/lib/llvm-18/bin/llvm-ar).
        execute_process(
            COMMAND ${CMAKE_CXX_COMPILER} -print-prog-name=llvm-ar
            OUTPUT_VARIABLE LLVM_AR
            OUTPUT_STRIP_TRAILING_WHITESPACE)
        execute_process(
            COMMAND ${CMAKE_CXX_COMPILER} -print-prog-name=llvm-ranlib
            OUTPUT_VARIABLE LLVM_RANLIB
            OUTPUT_STRIP_TRAILING_WHITESPACE)
        # Clang returns the bare name unchanged if not found — check it's a real path
        if(LLVM_AR AND EXISTS "${LLVM_AR}")
            set(CMAKE_AR "${LLVM_AR}" CACHE FILEPATH "llvm-ar for LTO" FORCE)
            set(CMAKE_CXX_COMPILER_AR "${LLVM_AR}" CACHE FILEPATH "llvm-ar for LTO" FORCE)
        else()
            # Fallback: search PATH (versioned and unversioned)
            find_program(LLVM_AR_FALLBACK
                NAMES llvm-ar llvm-ar-20 llvm-ar-19 llvm-ar-18 llvm-ar-17)
            if(LLVM_AR_FALLBACK)
                set(CMAKE_AR "${LLVM_AR_FALLBACK}" CACHE FILEPATH "llvm-ar for LTO" FORCE)
                set(CMAKE_CXX_COMPILER_AR "${LLVM_AR_FALLBACK}" CACHE FILEPATH "llvm-ar for LTO" FORCE)
            else()
                message(WARNING "llvm-ar not found — Clang LTO may fail. Install the 'llvm' package.")
            endif()
        endif()
        if(LLVM_RANLIB AND EXISTS "${LLVM_RANLIB}")
            set(CMAKE_RANLIB "${LLVM_RANLIB}" CACHE FILEPATH "llvm-ranlib for LTO" FORCE)
            set(CMAKE_CXX_COMPILER_RANLIB "${LLVM_RANLIB}" CACHE FILEPATH "llvm-ranlib for LTO" FORCE)
        else()
            find_program(LLVM_RANLIB_FALLBACK
                NAMES llvm-ranlib llvm-ranlib-20 llvm-ranlib-19 llvm-ranlib-18 llvm-ranlib-17)
            if(LLVM_RANLIB_FALLBACK)
                set(CMAKE_RANLIB "${LLVM_RANLIB_FALLBACK}" CACHE FILEPATH "llvm-ranlib for LTO" FORCE)
                set(CMAKE_CXX_COMPILER_RANLIB "${LLVM_RANLIB_FALLBACK}" CACHE FILEPATH "llvm-ranlib for LTO" FORCE)
            endif()
        endif()
    endif()

    if(LTO_MODE STREQUAL "thin")
        include(CheckIPOSupported)
        check_ipo_supported(RESULT LTO_SUPPORTED OUTPUT LTO_ERROR)
        if(LTO_SUPPORTED)
            set_property(TARGET slim2upnp PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)
            message(STATUS "LTO: ThinLTO (via CMake IPO)")
        else()
            message(WARNING "ThinLTO requested but not supported: ${LTO_ERROR}")
        endif()
    elseif(LTO_MODE STREQUAL "full")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -flto")
        set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -flto")
        message(STATUS "LTO: Full LTO (manual flags)")
    else()
        message(WARNING "Unknown LTO_MODE '${LTO_MODE}' — use OFF, thin, or full")
    endif()
endif()

# Linker selection (useful with Clang + LTO)
set(LINKER "" CACHE STRING "Linker to use: lld, mold, gold, or empty for default")
if(NOT LINKER STREQUAL "")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fuse-ld=${LINKER}")
    message(STATUS "Linker: ${LINKER}")
endif()

# Architecture-specific SIMD flags
if(BASE_ARCH STREQUAL "x64")
    if(DEFINED TARGET_MARCH)
        set(MARCH_LEVEL ${TARGET_MARCH})
    elseif(IS_ZEN4_RESULT EQUAL 0)
        set(MARCH_LEVEL "zen4")
    elseif(HAS_AVX512_RESULT EQUAL 0)
        set(MARCH_LEVEL "v4")
    elseif(HAS_AVX2_RESULT EQUAL 0)
        set(MARCH_LEVEL "v3")
    else()
        set(MARCH_LEVEL "v2")
    endif()

    if(MARCH_LEVEL STREQUAL "zen4")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=znver4 -mtune=znver4")
    elseif(MARCH_LEVEL STREQUAL "v4")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=x86-64-v4 -mavx512f -mavx512bw -mavx512vl -mavx512dq")
    elseif(MARCH_LEVEL STREQUAL "v3")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=x86-64-v3 -mavx2 -mfma")
    elseif(MARCH_LEVEL STREQUAL "v2")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=x86-64-v2")
    elseif(MARCH_LEVEL STREQUAL "native")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=native")
    endif()
    message(STATUS "SIMD: ${MARCH_LEVEL}")

elseif(BASE_ARCH STREQUAL "aarch64")
    if(DEFINED TARGET_MARCH AND NOT TARGET_MARCH STREQUAL "native")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mcpu=${TARGET_MARCH}")
    else()
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mcpu=native")
    endif()
    message(STATUS "SIMD: ARM64 native")
endif()

# ============================================
# Production Build (NOLOG)
# ============================================

option(NOLOG "Disable verbose logging for production builds" OFF)
if(NOLOG)
    target_compile_definitions(slim2upnp PRIVATE NOLOG)
    message(STATUS "NOLOG: Verbose logging disabled (production build)")
endif()

# ============================================
# Install
# ============================================

install(TARGETS slim2upnp DESTINATION bin)

# ============================================
# Print Summary
# ============================================

message(STATUS "")
message(STATUS "═══════════════════════════════════════════════════════")
message(STATUS "  Build Configuration Summary")
message(STATUS "═══════════════════════════════════════════════════════")
message(STATUS "")
message(STATUS "System:")
message(STATUS "  uname -m:       ${UNAME_M}")
message(STATUS "  Base Arch:      ${BASE_ARCH}")
message(STATUS "")
message(STATUS "Mode:             Passthrough (no decoding)")
message(STATUS "")
message(STATUS "Dependencies:")
message(STATUS "  libupnp:        ${UPNP_LIBRARIES}")
message(STATUS "")
message(STATUS "Build:")
message(STATUS "  Compiler:       ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION} (${CMAKE_CXX_COMPILER})")
message(STATUS "  LTO:            ${LTO_MODE}")
message(STATUS "  Linker:         ${LINKER}")
message(STATUS "  Target:         slim2upnp")
message(STATUS "")
message(STATUS "═══════════════════════════════════════════════════════")
message(STATUS "")
