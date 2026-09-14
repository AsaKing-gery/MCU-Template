# =============================================================================
#  report_size.cmake —— 彩色固件体积报告
#
#  由 CMakeLists.txt 的 POST_BUILD 步骤调用：
#      cmake -DSIZE=<arm-none-eabi-size> -DELF=<elf> -DMAP=<map>
#            -DLDSCRIPT=<链接脚本> -DMCU_COLOR_OUTPUT=ON -P report_size.cmake
#
#  为什么要单独写这个：
#    * arm-none-eabi-size 的输出是一张白字表格，混在 ninja 的一堆输出里
#      根本找不到。构建结束时最该看到的就是"固件多大"，所以这里上色 + 算占用率。
#    * FLASH / RAM 总容量优先从链接器生成的 .map 里读——那里的
#      "Memory Configuration" 表是链接器自己算出来的，最权威；
#      读不到再退回解析链接脚本的 MEMORY 块。
# =============================================================================

foreach(_v SIZE ELF)
  if(NOT DEFINED ${_v})
    message(FATAL_ERROR "report_size.cmake 需要 -D${_v}=<值>")
  endif()
endforeach()

# tools/build/build.ps1 会在跑构建前设上这个环境变量，让 POST_BUILD 那次报告闭嘴 ——
# 否则同一份体积会显示两次：ninja 里那次是白字（ANSI 被 ninja 剥掉），
# 脚本末尾那次才是彩色的。脚本打印自己那份之前会把它清掉。
if(DEFINED ENV{MCU_SIZE_QUIET})
  return()
endif()

# -----------------------------------------------------------------------------
# 颜色
#
# 取值优先级：
#   1. 运行时环境变量 MCU_COLOR_OUTPUT
#      —— 由 .vscode/tasks.json 的 options.env 设置。这样不管上一次是谁
#         configure 的（终端任务还是 CMake Tools），只要是在终端里构建，
#        这份报告就有颜色。
#   2. 配置时烘焙进来的 -DMCU_COLOR_OUTPUT（CMakeLists.txt 传的）
#
# 注意：CMake 里 `;` 是【列表分隔符】而不是语句分隔符，
# 所以必须一行一条命令，不能写成 set(a "") ; set(b "")
# -----------------------------------------------------------------------------
set(_color "${MCU_COLOR_OUTPUT}")
if(DEFINED ENV{MCU_COLOR_OUTPUT} AND NOT "$ENV{MCU_COLOR_OUTPUT}" STREQUAL "")
  set(_color "$ENV{MCU_COLOR_OUTPUT}")
endif()

if(_color)
  string(ASCII 27 _esc)
  set(_c_t  "${_esc}[1;36m")  # 标题
  set(_c_k  "${_esc}[36m")    # 字段名
  set(_c_ok "${_esc}[1;32m")  # 正常（绿）
  set(_c_w  "${_esc}[1;33m")  # 偏满（黄）
  set(_c_e  "${_esc}[1;31m")  # 超了（红）
  set(_c_d  "${_esc}[2m")     # 次要
  set(_c_x  "${_esc}[0m")
else()
  set(_c_t  "")
  set(_c_k  "")
  set(_c_ok "")
  set(_c_w  "")
  set(_c_e  "")
  set(_c_d  "")
  set(_c_x  "")
endif()

# -----------------------------------------------------------------------------
# 跑 size 取用量
# -----------------------------------------------------------------------------
execute_process(
  COMMAND "${SIZE}" "${ELF}"
  OUTPUT_VARIABLE _size_out
  ERROR_VARIABLE  _size_err
  RESULT_VARIABLE _size_rc)

if(NOT _size_rc EQUAL 0)
  message(WARNING "${_c_w}arm-none-eabi-size 执行失败：${_size_err}${_c_x}")
  return()
endif()

string(REPLACE "\r\n" "\n" _size_out "${_size_out}")
string(REPLACE "\n" ";" _size_lines "${_size_out}")
list(REMOVE_ITEM _size_lines "")

list(LENGTH _size_lines _n_lines)
if(_n_lines LESS 2)
  message(WARNING "${_c_w}无法解析 size 的输出：\n${_size_out}${_c_x}")
  return()
endif()

# 第 0 行是表头（text data bss dec hex filename），第 1 行才是数值
list(GET _size_lines 1 _vals)

# 这里【不能】用 separate_arguments：它按"命令行"规则解析，会把 Windows 路径
# 里的反斜杠当成转义字符（...\build\Debug\xxx.elf），拆出来的是 "105148\t"
# 这种带制表符的碎片，math() 直接报语法错误。
# size 的列之间是制表符，直接提数字最简单也最稳：前三个数就是 text/data/bss。
string(REGEX MATCHALL "[0-9]+" _nums "${_vals}")
list(LENGTH _nums _n_nums)
if(_n_nums LESS 3)
  message(WARNING "${_c_w}size 输出格式不认识：${_vals}${_c_x}")
  return()
endif()

list(GET _nums 0 _text)
list(GET _nums 1 _data)
list(GET _nums 2 _bss)

# .text + .data 要烧进 Flash；.data + .bss 占用 RAM
math(EXPR _flash_used "${_text} + ${_data}")
math(EXPR _ram_used   "${_data} + ${_bss}")

# -----------------------------------------------------------------------------
# 容量：优先读 .map 的 "Memory Configuration" 表
#
#   Memory Configuration
#
#   Name             Origin             Length             Attributes
#   FLASH            0x0000000008010000 0x00000000000f0000 xr
#   RAM              0x0000000002000000 0x00000000000c0000 xrw
#
# 这是链接器自己算的，最权威。读不到再退回解析链接脚本的 MEMORY 块。
# -----------------------------------------------------------------------------
function(_region_total out_var)
  set(_val 0)

  if(DEFINED MAP AND EXISTS "${MAP}")
    file(READ "${MAP}" _map_raw)
    string(REGEX MATCH
      "(^|\n)[ \t]*${ARGV1}[ \t]+0x[0-9a-fA-F]+[ \t]+0x([0-9a-fA-F]+)"
      _mm "${_map_raw}")
    if(_mm)
      # math(EXPR) 支持 0x 前缀的十六进制字面量
      math(EXPR _val "0x${CMAKE_MATCH_2}")
    endif()
  endif()

  # 退回：解析链接脚本的 MEMORY 块（备选名必须加括号，否则 | 会把整个模式拆散）
  if(_val EQUAL 0 AND DEFINED LDSCRIPT AND EXISTS "${LDSCRIPT}")
    file(READ "${LDSCRIPT}" _ld_raw)
    string(REGEX MATCH
      "(${ARGV1})[ \t]*\\([^)]*\\)[ \t]*:[ \t]*ORIGIN[ \t]*=[ \t]*[^,\r\n]+,[ \t]*LENGTH[ \t]*=[ \t]*([0-9]+)[ \t]*([KkMmGg]?)"
      _lm "${_ld_raw}")
    if(_lm)
      set(_num "${CMAKE_MATCH_2}")
      string(TOUPPER "${CMAKE_MATCH_3}" _unit)
      if(_unit STREQUAL "K")
        math(EXPR _num "${_num} * 1024")
      elseif(_unit STREQUAL "M")
        math(EXPR _num "${_num} * 1024 * 1024")
      elseif(_unit STREQUAL "G")
        math(EXPR _num "${_num} * 1024 * 1024 * 1024")
      endif()
      set(_val ${_num})
    endif()
  endif()

  set(${out_var} ${_val} PARENT_SCOPE)
endfunction()

_region_total(_flash_total "FLASH")
_region_total(_ram_total   "RAM")

# -----------------------------------------------------------------------------
# 输出
# -----------------------------------------------------------------------------
function(_report label used total)
  if(total EQUAL 0)
    message("  ${_c_k}${label}${_c_x} : ${_c_ok}${used}${_c_x} B")
    return()
  endif()

  math(EXPR _p     "${used} * 10000 / ${total}")
  math(EXPR _whole "${_p} / 100")
  math(EXPR _frac  "${_p} % 100")
  if(_frac LESS 10)
    set(_frac "0${_frac}")
  endif()

  # 选颜色：>=100% 红，>=85% 黄，其余绿
  math(EXPR _pp "${used} * 100 / ${total}")
  if(_pp GREATER_EQUAL 100)
    set(_col "${_c_e}")
  elseif(_pp GREATER_EQUAL 85)
    set(_col "${_c_w}")
  else()
    set(_col "${_c_ok}")
  endif()

  message("  ${_c_k}${label}${_c_x} : ${_col}${_whole}.${_frac}%${_c_x}   ${used} / ${total} B")
endfunction()

message("${_c_t}━━━ 固件体积 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_c_x}")
_report("FLASH" "${_flash_used}" "${_flash_total}")
_report("RAM  " "${_ram_used}"   "${_ram_total}")
if(_flash_total EQUAL 0)
  message("  ${_c_d}未能读出容量（.map 与链接脚本都没解析到），只显示用量${_c_x}")
endif()
message("${_c_t}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_c_x}")
