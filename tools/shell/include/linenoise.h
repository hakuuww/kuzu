#pragma once
/* linenoise.h -- VERSION 1.0
 *
 * Guerrilla line editing library against the idea that a line editing lib
 * needs to be 20,000 lines of C code.
 *
 * See linenoise.c for more information.
 *
 * ------------------------------------------------------------------------
 *
 * Copyright (c) 2010-2014, Salvatore Sanfilippo <antirez at gmail dot com>
 * Copyright (c) 2010-2013, Pieter Noordhuis <pcnoordhuis at gmail dot com>
 *
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *  *  Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *
 *  *  Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>

#define LINENOISE_MAX_LINE 65536

typedef struct linenoiseCompletions {
    size_t len;
    char** cvec;
} linenoiseCompletions;

enum class tokenType : uint8_t {
    TOKEN_IDENTIFIER,
    TOKEN_NUMERIC_CONSTANT,
    TOKEN_STRING_CONSTANT,
    TOKEN_OPERATOR,
    TOKEN_KEYWORD,
    TOKEN_COMMENT,
    TOKEN_CONTINUATION,
    TOKEN_CONTINUATION_SELECTED,
    TOKEN_BRACKET,
    TOKEN_ERROR
};

enum class HighlightingType {
    KEYWORD,
    CONSTANT,
    COMMENT,
    ERROR,
    CONTINUATION,
    CONTINUATION_SELECTED
};

struct highlightToken {
    tokenType type{};
    size_t start = 0;
    size_t length = 0;
};

typedef void(linenoiseCompletionCallback)(const char*, linenoiseCompletions*);
typedef char*(linenoiseHintsCallback)(const char*, int* color, int* bold);
typedef void(linenoiseFreeHintsCallback)(void*);
typedef void(linenoiseHighlightCallback)(char*, char*, uint32_t, uint32_t);
void linenoiseSetCompletionCallback(linenoiseCompletionCallback*);
void linenoiseSetHintsCallback(linenoiseHintsCallback*);
void linenoiseSetFreeHintsCallback(linenoiseFreeHintsCallback*);
void linenoiseSetHighlightCallback(linenoiseHighlightCallback*);
void linenoiseSetErrors(int enabled);
void linenoiseSetHighlighting(int enabled);
void linenoiseSetCompletion(int enabled);
void linenoiseAddCompletion(linenoiseCompletions*, const char*);

char* linenoise(const char* prompt, const char* continuePrompt, const char* selectedContinuePrompt);
void linenoiseFree(void* ptr);
int linenoiseHistoryAdd(const char* line);
int linenoiseHistorySetMaxLen(int len);
int linenoiseHistorySave(const char* filename);
int linenoiseHistoryLoad(const char* filename);
void linenoiseClearScreen(void);
void linenoiseSetMultiLine(int ml, const char* filename);
void linenoisePrintKeyCodes(void);
void linenoiseMaskModeEnable(void);
void linenoiseMaskModeDisable(void);
uint32_t linenoiseComputeRenderWidth(const char* buf, size_t len);
int getColumns(int ifd, int ofd);
bool cypherComplete(const char* z);

#ifdef __cplusplus
}
#endif
