/* Code generated by cmd/cgo; DO NOT EDIT. */

/* package github.com/siyuan-note/siyuan/kernel/harmony */


#line 1 "cgo-builtin-export-prolog"

#include <stddef.h>

#ifndef GO_CGO_EXPORT_PROLOGUE_H
#define GO_CGO_EXPORT_PROLOGUE_H

#ifndef GO_CGO_GOSTRING_TYPEDEF
typedef struct { const char *p; ptrdiff_t n; } _GoString_;
#endif

#endif

/* Start of preamble from import "C" comments.  */




/* End of preamble from import "C" comments.  */


/* Start of boilerplate cgo prologue.  */
#line 1 "cgo-gcc-export-header-prolog"

#ifndef GO_CGO_PROLOGUE_H
#define GO_CGO_PROLOGUE_H

typedef signed char GoInt8;
typedef unsigned char GoUint8;
typedef short GoInt16;
typedef unsigned short GoUint16;
typedef int GoInt32;
typedef unsigned int GoUint32;
typedef long long GoInt64;
typedef unsigned long long GoUint64;
typedef GoInt64 GoInt;
typedef GoUint64 GoUint;
typedef size_t GoUintptr;
typedef float GoFloat32;
typedef double GoFloat64;
#ifdef _MSC_VER
#include <complex.h>
typedef _Fcomplex GoComplex64;
typedef _Dcomplex GoComplex128;
#else
typedef float _Complex GoComplex64;
typedef double _Complex GoComplex128;
#endif

/*
  static assertion to make sure the file is being used on architecture
  at least with matching size of GoInt.
*/
typedef char _check_for_64_bit_pointer_matching_GoInt[sizeof(void*)==64/8 ? 1:-1];

#ifndef GO_CGO_GOSTRING_TYPEDEF
typedef _GoString_ GoString;
#endif
typedef void *GoMap;
typedef void *GoChan;
typedef struct { void *t; void *v; } GoInterface;
typedef struct { void *data; GoInt len; GoInt cap; } GoSlice;

#endif

/* End of boilerplate cgo prologue.  */

#ifdef __cplusplus
extern "C" {
#endif

extern void StartKernelFast(char* container, char* appDir, char* workspaceBaseDir, char* localIPs);
extern void StartKernel(char* container, char* appDir, char* workspaceBaseDir, char* timezoneID, char* localIPs, char* lang, char* osVer);
extern GoString Language(GoInt num);
extern void ShowMsg(GoString msg, GoInt timeout);
extern GoUint8 IsHttpServing();
extern void SetHttpServerPort(GoInt port);
extern GoString GetCurrentWorkspacePath();
extern GoString GetAssetAbsPath(GoString asset);
extern GoString GetMimeTypeByExt(GoString ext);
extern void SetTimezone(GoString container, GoString appDir, GoString timezoneID);
extern void DisableFeature(GoString feature);

#ifdef __cplusplus
}
#endif
