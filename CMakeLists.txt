# =============================================================================
#  MCU-Template / CMakeLists.txt —— 通用 Cortex-M 工程构建脚本
#
#  三条设计原则：
#    1. 芯片相关参数全部来自 mcu.json（单点配置），本文件不含任何芯片信息
#    2. 源文件按目录递归收集，CubeMX 新增文件后无需改脚本
#    3. 自己的代码放 App/，CubeMX 重新生成代码不会覆盖它
# =============================================================================
cmake_minimum_required(VERSION 3.22)

# 工程名 = 目录名，这样才能和 launch.json 里的 ${workspaceFolderBasename} 对上
get_filename_component(_proj_name "${CMAKE_CURRENT_SOURCE_DIR}" NAME)
project("${_proj_name}" LANGUAGES C ASM)

if(NOT DEFINED MCU_CPU)
  message(FATAL_ERROR
    "没有读到 MCU 配置。请通过 CMakePresets 配置工程：\n"
    "    cmake --preset Debug\n"
    "并确认 cmake/gcc-arm-none-eabi.cmake 与 mcu.json 都在工程根目录下。")
endif()

message(STATUS "── MCU 配置 ───────────────────────────────────")
message(STATUS "  device        : ${MCU_DEVICE}")
message(STATUS "  cpu / fpu     : ${MCU_CPU} / ${MCU_FPU}")
message(STATUS "  float-abi     : ${MCU_FLOAT_ABI}")
message(STATUS "  linker script : ${MCU_LDSCRIPT_FILE}")
message(STATUS "  defines       : ${MCU_DEFINES_LIST}")
message(STATUS "───────────────────────────────────────────────")

# -----------------------------------------------------------------------------
# 1. 收集源文件
#    想新增源码目录时，只改下面这一行
# -----------------------------------------------------------------------------
set(MCU_SOURCE_DIRS Core Drivers App)

set(_sources "")
foreach(_dir IN LISTS MCU_SOURCE_DIRS)
  if(IS_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/${_dir}")
    file(GLOB_RECURSE _found CONFIGURE_DEPENDS
      "${CMAKE_CURRENT_SOURCE_DIR}/${_dir}/*.c"
      "${CMAKE_CURRENT_SOURCE_DIR}/${_dir}/*.s"
      "${CMAKE_CURRENT_SOURCE_DIR}/${_dir}/*.S")
    list(APPEND _sources ${_found})
  endif()
endforeach()

# 排除 HAL 自带的 *_template.c 与 CMSIS 模板目录里重复的 system_xxx.c
list(FILTER _sources EXCLUDE REGEX "_template[.](c|s|S)$")
list(FILTER _sources EXCLUDE REGEX "CMSIS/Device/.*/Source/Templates/")

if(NOT _sources)
  message(FATAL_ERROR
    "在目录 [${MCU_SOURCE_DIRS}] 中没有找到任何源文件。\n"
    "请先用 STM32CubeMX 生成代码，或确认 MCU_SOURCE_DIRS 配置正确。")
endif()

list(LENGTH _sources _n_sources)
message(STATUS "源文件数量：${_n_sources}")

add_executable(${PROJECT_NAME} ${_sources})

# -----------------------------------------------------------------------------
# 2. 头文件目录：自动收集 Core/Drivers/App 下名为 Inc / Include / Legacy 的目录
#    兼容 STM32 各系列（HAL Inc、CMSIS Include、Inc/Legacy ...）
# -----------------------------------------------------------------------------
set(_scan_dirs "")
foreach(_dir IN LISTS MCU_SOURCE_DIRS)
  if(IS_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/${_dir}")
    list(APPEND _scan_dirs "${CMAKE_CURRENT_SOURCE_DIR}/${_dir}/*")
  endif()
endforeach()

set(_all_dirs "")
if(_scan_dirs)
  file(GLOB_RECURSE _all_dirs LIST_DIRECTORIES true ${_scan_dirs})
endif()

set(_include_dirs "")
foreach(_d IN LISTS _all_dirs)
  if(IS_DIRECTORY "${_d}")
    get_filename_component(_name "${_d}" NAME)
    if(_name STREQUAL "Inc" OR _name STREQUAL "Include" OR _name STREQUAL "Legacy")
      list(APPEND _include_dirs "${_d}")
    endif()
  endif()
endforeach()
list(REMOVE_DUPLICATES _include_dirs)

target_include_directories(${PROJECT_NAME} PRIVATE ${_include_dirs})

# -----------------------------------------------------------------------------
# 3. 宏定义（来自 mcu.json 的 defines）
# -----------------------------------------------------------------------------
if(MCU_DEFINES_LIST)
  target_compile_definitions(${PROJECT_NAME} PRIVATE ${MCU_DEFINES_LIST})
endif()

# -----------------------------------------------------------------------------
# 4. 编译选项
# -----------------------------------------------------------------------------
option(MCU_USE_PRINTF_FLOAT "启用 newlib-nano 的浮点 printf（体积会增大）" OFF)

target_compile_options(${PROJECT_NAME} PRIVATE
  # Debug / Release 分别设置，避免反复 configure 时参数重复累加
  $<$<CONFIG:Debug>:-Og>
  $<$<CONFIG:Debug>:-g3>
  $<$<CONFIG:Debug>:-gdwarf-2>
  $<$<CONFIG:Release>:-Os>
  $<$<CONFIG:Release>:-g0>
  # 每个函数/变量单独分段，配合 --gc-sections 剔除无用代码
  $<$<COMPILE_LANGUAGE:C>:-ffunction-sections>
  $<$<COMPILE_LANGUAGE:C>:-fdata-sections>
  $<$<COMPILE_LANGUAGE:C>:-Wall>
)

# -----------------------------------------------------------------------------
# 5. 链接选项
# -----------------------------------------------------------------------------
target_link_options(${PROJECT_NAME} PRIVATE
  "-Wl,-Map=$<TARGET_FILE_DIR:${PROJECT_NAME}>/${PROJECT_NAME}.map"
)

if(MCU_USE_PRINTF_FLOAT)
  # 写成两个参数，避免拼接形式在不同 ld 版本上行为不一致
  target_link_options(${PROJECT_NAME} PRIVATE "-u" "_printf_float")
endif()

# 生成 .hex / .bin 并打印固件大小
add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
  COMMAND ${CMAKE_OBJCOPY} -O ihex
          $<TARGET_FILE:${PROJECT_NAME}>
          $<TARGET_FILE_DIR:${PROJECT_NAME}>/${PROJECT_NAME}.hex
  COMMAND ${CMAKE_OBJCOPY} -O binary
          $<TARGET_FILE:${PROJECT_NAME}>
          $<TARGET_FILE_DIR:${PROJECT_NAME}>/${PROJECT_NAME}.bin
  COMMAND ${CMAKE_SIZE} $<TARGET_FILE:${PROJECT_NAME}>
  COMMENT "生成 .hex / .bin 并统计固件大小"
  VERBATIM)

# -----------------------------------------------------------------------------
# 6. 烧录目标：cmake --build --preset Debug --target flash
# -----------------------------------------------------------------------------
find_program(OPENOCD_EXECUTABLE NAMES openocd)

if(OPENOCD_EXECUTABLE)
  message(STATUS "OpenOCD       : ${OPENOCD_EXECUTABLE}")
  add_custom_target(flash
    COMMAND "${OPENOCD_EXECUTABLE}"
            -f "interface/stlink.cfg"
            -f "${MCU_OPENOCD}"
            -c "adapter speed 4000"
            -c "program $<TARGET_FILE:${PROJECT_NAME}> verify reset exit"
    DEPENDS ${PROJECT_NAME}
    COMMENT "使用 OpenOCD 烧录 ${PROJECT_NAME}.elf"
    VERBATIM)
else()
  message(STATUS "OpenOCD       : 未找到（flash 目标不可用时请用调试面板的下载按钮）")
  add_custom_target(flash
    COMMAND ${CMAKE_COMMAND} -E echo
            "未找到 openocd。请安装 OpenOCD 并加入 PATH，或直接用 VSCode 调试面板烧录。"
    COMMENT "flash 目标不可用"
    VERBATIM)
endif()

# 反汇编，方便排查启动 / HardFault 问题
# 注意：add_custom_target 的 COMMAND 不经过 shell，输出重定向必须交给 -P 脚本处理
add_custom_target(disasm
  COMMAND ${CMAKE_COMMAND}
          "-DOBJDUMP=${CMAKE_OBJDUMP}"
          "-DINPUT=$<TARGET_FILE:${PROJECT_NAME}>"
          "-DOUTPUT=$<TARGET_FILE_DIR:${PROJECT_NAME}>/${PROJECT_NAME}.asm"
          -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/disasm.cmake"
  DEPENDS ${PROJECT_NAME}
  COMMENT "生成 ${PROJECT_NAME}.asm"
  VERBATIM)
