# =============================================================================
#  disasm.cmake —— 由 CMakeLists.txt 的 disasm 目标以脚本模式调用：
#      cmake -DOBJDUMP=... -DINPUT=... -DOUTPUT=... -P cmake/disasm.cmake
#
#  单独放在脚本里，是因为 add_custom_target 的 COMMAND 不经过 shell，
#  "objdump ... > file" 这种重定向写法不会生效。
# =============================================================================
foreach(_required OBJDUMP INPUT OUTPUT)
  if(NOT DEFINED ${_required})
    message(FATAL_ERROR "disasm.cmake 缺少参数 -D${_required}=...")
  endif()
endforeach()

if(NOT EXISTS "${INPUT}")
  message(FATAL_ERROR "找不到输入文件：${INPUT}")
endif()

get_filename_component(_out_dir "${OUTPUT}" DIRECTORY)
file(MAKE_DIRECTORY "${_out_dir}")

execute_process(
  COMMAND "${OBJDUMP}" --disassemble --source --line-numbers "${INPUT}"
  OUTPUT_FILE "${OUTPUT}"
  ERROR_VARIABLE _err
  RESULT_VARIABLE _rc)

if(NOT _rc EQUAL 0)
  message(FATAL_ERROR "objdump 执行失败（${_rc}）：${_err}")
endif()

message(STATUS "反汇编已生成：${OUTPUT}")
