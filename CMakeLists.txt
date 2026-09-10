# =============================================================================
#  MCU-Template / CMakeLists.txt —— 通用 Cortex-M 工程构建脚本
#
#  三条设计原则：
#    1. 芯片相关参数全部来自 mcu.json（单点配置），本文件不含任何芯片信息
#    2. 源文件按目录递归收集，CubeMX 新增文件后无需改脚本
#    3. 自己的代码放 App/，CubeMX 重新生成代码不会覆盖它
# =============================================================================
cmake_minimum_required(VERSION 3.22)

# -----------------------------------------------------------------------------
# 工程名 = 目录名（同时也是产物名），但必须先"消毒"。
#
# CMake 的 target 名字只允许 字母 / 数字 / _ / - / . / +，
# 而真实工程目录名经常带空格和括号（比如 "JY.RFM-0A-U575(24G)"），
# 直接拿来当 target 名会 configure 失败，所以把非法字符统一换成下划线。
#
# 产物名会跟着变成消毒后的名字（括号→下划线）。.vscode/launch.json 里的
# executable 由 scripts/sync-mcu 写入同一个名字，两边永远一致。
# -----------------------------------------------------------------------------
get_filename_component(_dir_name "${CMAKE_CURRENT_SOURCE_DIR}" NAME)
string(REGEX REPLACE "[^A-Za-z0-9_.+-]" "_" _proj_name "${_dir_name}")
if(NOT _proj_name)
  set(_proj_name "mcu_firmware")
endif()

project(${_proj_name} LANGUAGES C ASM)

if(NOT _dir_name STREQUAL _proj_name)
  message(STATUS "目录名 \"${_dir_name}\" 含 CMake 不允许的字符，工程/产物名改用 \"${_proj_name}\"")
endif()

if(NOT DEFINED MCU_CPU)
  message(FATAL_ERROR
    "没有读到 MCU 配置。请通过 CMakePresets 配置工程：\n"
    "    cmake --preset Debug\n"
    "并确认 cmake/gcc-arm-none-eabi.cmake 与 mcu.json 都在工程根目录下。")
endif()

message(STATUS "── MCU 配置 ───────────────────────────────────")
message(STATUS "  产物名        : ${PROJECT_NAME}.elf")
message(STATUS "  device        : ${MCU_DEVICE}")
message(STATUS "  cpu / fpu     : ${MCU_CPU} / ${MCU_FPU}")
message(STATUS "  float-abi     : ${MCU_FLOAT_ABI}")
message(STATUS "  linker script : ${MCU_LDSCRIPT_FILE}")
message(STATUS "  defines       : ${MCU_DEFINES_LIST}")
message(STATUS "───────────────────────────────────────────────")

# 链接脚本缺失不是致命错误（先 configure 再让 CubeMX 生成代码是常见顺序），
# 但要明确提示，否则最后会在链接阶段报一堆莫名其妙的错误。
if(NOT MCU_LDSCRIPT_FILE OR MCU_LDSCRIPT_FILE MATCHES "-NOTFOUND$")
  message(WARNING
    "在工程中找不到链接脚本 \"${MCU_LDSCRIPT}\"。\n"
    "  * 已经用 CubeMX 生成过代码：把 .ld 放到工程根目录，或改 mcu.json 的 linkerScript\n"
    "  * 还没生成：忽略本警告，生成后再重新 configure")
endif()

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

# 裸机工程（CMAKE_SYSTEM_NAME = Generic）默认的可执行文件后缀是空的，
# 产物会叫 "<项目名>" 而不是 "<项目名>.elf"。
# 而 launch.json / 调试器都按 .elf 找文件，这里统一补上后缀。
set_target_properties(${PROJECT_NAME} PROPERTIES SUFFIX ".elf")

# -----------------------------------------------------------------------------
# 2. 头文件目录
#
#    按"这个目录里有没有头文件"来判断，而不是按 Inc / Include 这种固定名字去找。
#
#    原因：ST 的库是 Core/Inc + Drivers/.../Inc 这种规范布局，但**你自己的代码**
#    通常不是——头文件和源文件放在同一个目录里（Protocol/、Sensor/、User/inc ...）。
#    只认固定目录名会漏掉一大批，结果是编译器和 clangd 都找不到头文件。
# -----------------------------------------------------------------------------
set(_header_globs "")
foreach(_dir IN LISTS MCU_SOURCE_DIRS)
  if(IS_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/${_dir}")
    list(APPEND _header_globs "${CMAKE_CURRENT_SOURCE_DIR}/${_dir}/*.h")
    list(APPEND _header_globs "${CMAKE_CURRENT_SOURCE_DIR}/${_dir}/*.hpp")
  endif()
endforeach()

set(_include_dirs "")
if(_header_globs)
  file(GLOB_RECURSE _headers CONFIGURE_DEPENDS ${_header_globs})
  foreach(_h IN LISTS _headers)
    get_filename_component(_h_dir "${_h}" DIRECTORY)
    list(APPEND _include_dirs "${_h_dir}")
  endforeach()
  list(REMOVE_DUPLICATES _include_dirs)
endif()

if(_include_dirs)
  list(LENGTH _include_dirs _n_inc)
  message(STATUS "头文件目录：${_n_inc} 个")
  target_include_directories(${PROJECT_NAME} PRIVATE ${_include_dirs})
endif()

# -----------------------------------------------------------------------------
# 3. 宏定义（来自 mcu.json 的 defines）
# -----------------------------------------------------------------------------
if(MCU_DEFINES_LIST)
  target_compile_definitions(${PROJECT_NAME} PRIVATE ${MCU_DEFINES_LIST})
endif()

# -----------------------------------------------------------------------------
# 4. 编译选项
# -----------------------------------------------------------------------------
# MCU_USE_PRINTF_FLOAT 由工具链文件根据 mcu.json 的 floatIo 设置（缺省 true）。
# 单独提一行提一下，免得在这里找不到它的定义。

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
#
# 凡是"含工程路径"的参数都必须走 target_link_options，不能写进
# CMAKE_EXE_LINKER_FLAGS_INIT —— 后者是按空格拆分的字符串，
# 工程路径里一有空格（"E:/keil5 project/..."）就会被拆坏。
# -----------------------------------------------------------------------------
target_link_options(${PROJECT_NAME} PRIVATE
  "-Wl,-Map=$<TARGET_FILE_DIR:${PROJECT_NAME}>/${PROJECT_NAME}.map"
)

# 链接脚本（-T）；每个元素是独立参数，路径含空格也没问题
if(MCU_LDSCRIPT_FILE AND NOT MCU_LDSCRIPT_FILE MATCHES "-NOTFOUND$")
  target_link_options(${PROJECT_NAME} PRIVATE "-T${MCU_LDSCRIPT_FILE}")
endif()

# libm：sinf/cosf/sqrtf 这类数学函数不是 GCC 默认链接的，必须显式加。
# 没有引用时链接器不会从库里取任何东西，所以加着没有副作用。
target_link_options(${PROJECT_NAME} PRIVATE "-lm")

if(MCU_USE_PRINTF_FLOAT)
  # newlib-nano 默认不带浮点版 stdio，必须显式要求把实现链接进来。
  #
  # 这里用 -Wl,--undefined=<符号> 而不用 "-u" "<符号>"：
  # CMake 会对 target_link_options 里的重复项去重，"-u _printf_float -u _scanf_float"
  # 里的第二个 "-u" 会被删掉，结果 _scanf_float 被当成输入文件报
  # "cannot find _scanf_float"。写成两个不同的长选项就没这个问题。
  target_link_options(${PROJECT_NAME} PRIVATE
    "-Wl,--undefined=_printf_float"
    "-Wl,--undefined=_scanf_float")
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

# CubeIDE / CubeCLT 自带的 OpenOCD 不在 PATH 里，找不到时自动探测一下
if(NOT OPENOCD_EXECUTABLE AND CMAKE_HOST_WIN32)
  set(_openocd_patterns
    "C:/ST/STM32CubeCLT_*/OpenOCD/bin/openocd.exe"
    "C:/ST/STM32CubeIDE_*/STM32CubeIDE/plugins/com.st.stm32cube.ide.mcu.externaltools.openocd.*/tools/bin/openocd.exe"
    "C:/Program Files/STMicroelectronics/STM32Cube/STM32CubeIDE/plugins/com.st.stm32cube.ide.mcu.externaltools.openocd.*/tools/bin/openocd.exe"
  )
  file(GLOB _openocd_candidates ${_openocd_patterns})
  if(_openocd_candidates)
    list(SORT _openocd_candidates ORDER DESCENDING)
  endif()
  foreach(_cand IN LISTS _openocd_candidates)
    if(EXISTS "${_cand}")
      set(OPENOCD_EXECUTABLE "${_cand}")
      break()
    endif()
  endforeach()
endif()

# ST 版 OpenOCD 需要显式指定脚本目录，否则报 Can't find interface/stlink.cfg
# （脚本在 com.st.stm32cube.ide.mcu.debug.openocd 插件里，不在 OpenOCD 自己的目录下）
set(OPENOCD_SCRIPTS_DIR "")
if(OPENOCD_EXECUTABLE)
  get_filename_component(_openocd_dir "${OPENOCD_EXECUTABLE}" DIRECTORY)

  # 标准发行版（xPack 等）的脚本在 openocd 同级或上一层
  foreach(_guess "${_openocd_dir}/scripts" "${_openocd_dir}/../share/openocd/scripts")
    if(EXISTS "${_guess}/interface/stlink.cfg")
      set(OPENOCD_SCRIPTS_DIR "${_guess}")
      break()
    endif()
  endforeach()

  # CubeIDE 自带的脚本位置
  if(NOT OPENOCD_SCRIPTS_DIR)
    file(GLOB _ocd_script_candidates
      "C:/ST/STM32CubeIDE_*/STM32CubeIDE/plugins/com.st.stm32cube.ide.mcu.debug.openocd_*/resources/openocd/st_scripts"
      "C:/Program Files/STMicroelectronics/STM32Cube/STM32CubeIDE/plugins/com.st.stm32cube.ide.mcu.debug.openocd_*/resources/openocd/st_scripts"
      "C:/ST/STM32CubeCLT_*/OpenOCD/share/openocd/scripts")
    if(_ocd_script_candidates)
      list(SORT _ocd_script_candidates ORDER DESCENDING)
    endif()
    foreach(_cand IN LISTS _ocd_script_candidates)
      if(EXISTS "${_cand}/interface/stlink.cfg")
        set(OPENOCD_SCRIPTS_DIR "${_cand}")
        break()
      endif()
    endforeach()
  endif()
endif()

if(OPENOCD_EXECUTABLE)
  message(STATUS "OpenOCD       : ${OPENOCD_EXECUTABLE}")
  if(OPENOCD_SCRIPTS_DIR)
    message(STATUS "OpenOCD scripts: ${OPENOCD_SCRIPTS_DIR}")
  endif()

  set(_ocd_args "")
  if(OPENOCD_SCRIPTS_DIR)
    list(APPEND _ocd_args -s "${OPENOCD_SCRIPTS_DIR}")
  endif()
  list(APPEND _ocd_args
    -f "interface/stlink.cfg"
    -f "${MCU_OPENOCD}"
    -c "adapter speed 4000"
    -c "program $<TARGET_FILE:${PROJECT_NAME}> verify reset exit")

  add_custom_target(flash
    COMMAND "${OPENOCD_EXECUTABLE}" ${_ocd_args}
    DEPENDS ${PROJECT_NAME}
    COMMENT "使用 OpenOCD 烧录 ${PROJECT_NAME}.elf"
    VERBATIM)
else()
  message(STATUS "OpenOCD       : 未找到（请用 VSCode 调试面板的下载按钮，或把 openocd 加入 PATH）")
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
