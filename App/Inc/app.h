/**
 * @file    app.h
 * @brief   用户代码入口。CubeMX 重新生成代码不会覆盖 App/ 目录。
 *
 * 用法：在 CubeMX 生成的 Core/Src/main.c 里加上
 *     #include "app.h"
 *     App_Init();                       // 放在 MX_xxx_Init() 之后
 *     while (1) { App_Loop(); }         // 替换原来的空 while(1)
 */
#ifndef __APP_H
#define __APP_H

#ifdef __cplusplus
extern "C" {
#endif

/** 上电初始化：在外设初始化完成后调用一次 */
void App_Init(void);

/** 主循环：在 while(1) 中反复调用 */
void App_Loop(void);

#ifdef __cplusplus
}
#endif

#endif /* __APP_H */
