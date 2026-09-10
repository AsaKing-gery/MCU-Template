# =============================================================================
#  gcc-arm-none-eabi.cmake —— Cortex-M 通用工具链文件
#
#  唯一配置来源：工程根目录的 mcu.json
#  改芯片只需要改 mcu.json，本文件不用动。
#
#  工具链定位优先级：
#    1. 环境变量 ARM_GCC_PATH（指向 Arm GNU Toolchain 根目录，其下有 bin/）
#    2. 系统 PATH 中的 arm-none-eabi-gcc
# =============================================================================
cmake_minimum_required(VERSION 3.22)

set(CMAKE_SYSTEM_NAME       Generic)
set(CMAKE_SYSTEM_PROCESSOR  arm)

# 裸机工程无法完成链接测试（没有默认启动文件），用静态库代替
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(_proj_root "${CMAKE_CURRENT_LIST_DIR}/..")
get_filename_component(_proj_root "${_proj_root}" ABSOLUTE)

# 链接脚本是以 "-T<路径>" 形式拼进链接参数的，路径含空格会被拆开
if(_proj_root MATCHES " ")
  message(WARNING
    "工程路径含有空格：${_proj_root}\n"
    "  -T<路径> 这类参数会因空格被拆开，建议把工程放在不含空格的目录下。")
endif()

# -----------------------------------------------------------------------------
# 1. 读取 mcu.json
# -----------------------------------------------------------------------------
set(_mcu_json "${_proj_root}/mcu.json")

if(NOT EXISTS "${_mcu_json}")
  message(FATAL_ERROR
    "找不到单点配置文件：${_mcu_json}\n"
    "请把模板中的 mcu.json 复制到工程根目录，或运行 scripts/new-project 生成工程。")
endif()

file(READ "${_mcu_json}" _mcu_raw)

foreach(_key device cpu fpu floatAbi linkerScript svd openocdTarget)
  string(JSON _check ERROR_VARIABLE _err GET "${_mcu_raw}" "${_key}")
  if(_err)
    message(FATAL_ERROR "mcu.json 缺少字段 \"${_key}\"，请参照模板补全。")
  endif()
endforeach()

string(JSON MCU_DEVICE  GET "${_mcu_raw}" device)
string(JSON MCU_CPU     GET "${_mcu_raw}" cpu)
string(JSON MCU_FPU     GET "${_mcu_raw}" fpu)
string(JSON MCU_FLOAT_ABI GET "${_mcu_raw}" floatAbi)
string(JSON MCU_LDSCRIPT  GET "${_mcu_raw}" linkerScript)
string(JSON MCU_SVD       GET "${_mcu_raw}" svd)
string(JSON MCU_OPENOCD   GET "${_mcu_raw}" openocdTarget)

# defines 可能是 JSON 数组，也可能被写成 "A B C" 字符串，两种都兼容
string(JSON MCU_DEFINES ERROR_VARIABLE _defines_err GET "${_mcu_raw}" defines)
if(_defines_err)
  set(MCU_DEFINES "")
endif()
separate_arguments(MCU_DEFINES_LIST UNIX_COMMAND "${MCU_DEFINES}")

# 导出为 cache 变量，保证 CMakeLists.txt 里一定能读到。
# 必须带 FORCE：mcu.json 是唯一事实来源，重新 configure 时要让新值覆盖旧缓存。
set(MCU_DEVICE          "${MCU_DEVICE}"          CACHE STRING "MCU 型号（来自 mcu.json）"        FORCE)
set(MCU_CPU             "${MCU_CPU}"             CACHE STRING "内核（来自 mcu.json）"            FORCE)
set(MCU_FPU             "${MCU_FPU}"             CACHE STRING "FPU（来自 mcu.json）"             FORCE)
set(MCU_FLOAT_ABI       "${MCU_FLOAT_ABI}"       CACHE STRING "浮点 ABI（来自 mcu.json）"        FORCE)
set(MCU_LDSCRIPT        "${MCU_LDSCRIPT}"        CACHE STRING "链接脚本文件名（来自 mcu.json）"  FORCE)
set(MCU_SVD             "${MCU_SVD}"             CACHE STRING "SVD 文件名（来自 mcu.json）"      FORCE)
set(MCU_OPENOCD         "${MCU_OPENOCD}"         CACHE STRING "OpenOCD target 配置（来自 mcu.json）" FORCE)
set(MCU_DEFINES_LIST    "${MCU_DEFINES_LIST}"    CACHE STRING "预处理宏（来自 mcu.json）"        FORCE)

# -----------------------------------------------------------------------------
# 2. 生成架构相关编译参数
# -----------------------------------------------------------------------------
set(_arch_flags "-mcpu=${MCU_CPU}" "-mthumb")

if(MCU_FLOAT_ABI STREQUAL "soft")
  list(APPEND _arch_flags "-mfloat-abi=soft")
else()
  list(APPEND _arch_flags "-mfloat-abi=${MCU_FLOAT_ABI}")
  if(NOT MCU_FPU STREQUAL "" AND NOT MCU_FPU STREQUAL "none")
    list(APPEND _arch_flags "-mfpu=${MCU_FPU}")
  endif()
endif()

string(REPLACE ";" " " _arch_flags_str "${_arch_flags}")

# -----------------------------------------------------------------------------
# 3. 定位 arm-none-eabi-* 可执行文件
# -----------------------------------------------------------------------------
if(CMAKE_HOST_WIN32)
  set(_exe_suffix ".exe")
else()
  set(_exe_suffix "")
endif()

if(DEFINED ENV{ARM_GCC_PATH} AND NOT "$ENV{ARM_GCC_PATH}" STREQUAL "")
  set(ARM_GCC_BIN "$ENV{ARM_GCC_PATH}/bin")
  message(STATUS "工具链来源：环境变量 ARM_GCC_PATH = $ENV{ARM_GCC_PATH}")
else()
  find_program(ARM_GCC_PROGRAM arm-none-eabi-gcc)
  if(NOT ARM_GCC_PROGRAM)
    message(FATAL_ERROR
      "未找到 arm-none-eabi-gcc。\n"
      "  1) 安装 Arm GNU Toolchain（或使用 STM32CubeCLT 自带的工具链）\n"
      "  2) 把它的 bin 目录加入 PATH，或设置环境变量 ARM_GCC_PATH 指向工具链根目录\n"
      "     例如：setx ARM_GCC_PATH \"C:/Program Files/Arm/GNU Toolchain mingw-w64-x86_64-arm-none-eabi\"")
  endif()
  get_filename_component(ARM_GCC_BIN "${ARM_GCC_PROGRAM}" DIRECTORY)
  message(STATUS "工具链来源：PATH -> ${ARM_GCC_BIN}")
endif()

set(CMAKE_C_COMPILER    "${ARM_GCC_BIN}/arm-none-eabi-gcc${_exe_suffix}")
set(CMAKE_ASM_COMPILER  "${ARM_GCC_BIN}/arm-none-eabi-gcc${_exe_suffix}")
set(CMAKE_CXX_COMPILER  "${ARM_GCC_BIN}/arm-none-eabi-g++${_exe_suffix}")
set(CMAKE_AR            "${ARM_GCC_BIN}/arm-none-eabi-ar${_exe_suffix}"      CACHE FILEPATH "" FORCE)
set(CMAKE_OBJCOPY       "${ARM_GCC_BIN}/arm-none-eabi-objcopy${_exe_suffix}" CACHE FILEPATH "" FORCE)
set(CMAKE_OBJDUMP       "${ARM_GCC_BIN}/arm-none-eabi-objdump${_exe_suffix}" CACHE FILEPATH "" FORCE)
set(CMAKE_SIZE          "${ARM_GCC_BIN}/arm-none-eabi-size${_exe_suffix}"    CACHE FILEPATH "" FORCE)

# -----------------------------------------------------------------------------
# 4. 定位链接脚本（CubeMX 通常放在工程根目录，也兼容 Core/ 与 ld/）
# -----------------------------------------------------------------------------
find_file(MCU_LDSCRIPT_FILE
  NAMES "${MCU_LDSCRIPT}"
  PATHS "${_proj_root}" "${_proj_root}/Core" "${_proj_root}/ld" "${_proj_root}/LinkerScript"
  NO_DEFAULT_PATH)

if(NOT MCU_LDSCRIPT_FILE)
  message(WARNING
    "在工程中找不到链接脚本 \"${MCU_LDSCRIPT}\"。\n"
    "请检查 mcu.json 的 linkerScript 字段，或先用 STM32CubeMX 生成代码。")
endif()
set(MCU_LDSCRIPT_FILE "${MCU_LDSCRIPT_FILE}" CACHE FILEPATH "链接脚本绝对路径" FORCE)

# -----------------------------------------------------------------------------
# 5. 写入全局编译/链接参数（*_FLAGS_INIT 会作用于所有目标与 try_compile）
# -----------------------------------------------------------------------------
set(CMAKE_C_FLAGS_INIT   "${_arch_flags_str}")
set(CMAKE_CXX_FLAGS_INIT "${_arch_flags_str}")
set(CMAKE_ASM_FLAGS_INIT "${_arch_flags_str} -x assembler-with-cpp")

set(_ld_flags "${_arch_flags_str} --specs=nano.specs -Wl,--gc-sections -Wl,--print-memory-usage")
if(MCU_LDSCRIPT_FILE)
  set(_ld_flags "${_ld_flags} -T${MCU_LDSCRIPT_FILE}")
endif()
set(CMAKE_EXE_LINKER_FLAGS_INIT "${_ld_flags}")

# 编译该工具链时不要把宿主机路径当成目标系统路径搜索
set(CMAKE_FIND_ROOT_PATH "${ARM_GCC_BIN}/..")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
