// +build gc,!purego

#include "textflag.h"

// Register allocation.
#define digest	R1
#define h	R2	// Return value.
#define p	R3	// Input pointer.
#define len	R4
#define nblocks	R5	// len / 32.
#define prime1	R7
#define prime2	R8
#define prime3	R9
#define prime4	R10
#define prime5	R11
#define v1	R12
#define v2	R13
#define v3	R14
#define v4	R15
#define x1	R20
#define x2	R21
#define x3	R22
#define x4	R23

#define round(acc, x) 			\
	MADD prime2, acc, x, acc	\
	ROR  $33, acc			\
	MUL  prime1, acc		\

// x = round(0, x).
#define round0(x)	\
	MUL prime2, x	\
	ROR $33, x	\
	MUL prime1, x	\

#define mergeRound(x)			\
	round0(x)			\
	EOR  x, h			\
	MADD h, prime4, prime1, h	\

// Update v[1-4] with 32-byte blocks. Assumes len >= 32.
#define blocksLoop(label)	\
	LSR  $5, len, nblocks	\
label:				\
	SUBS $1, nblocks	\
				\
	LDP.P 32(p), (x1, x2)	\
	round(v1, x1)		\
	round(v2, x2)		\
				\
	LDP  -16(p), (x3, x4)	\
	round(v3, x3)		\
	round(v4, x4)		\
				\
	BNE  label		\

// func Sum64(b []byte) uint64
TEXT ·Sum64(SB), NOFRAME+NOSPLIT, $0-32
	LDP  b_base+0(FP), (p, len)

	MOVD ·prime1v(SB), prime1
	MOVD ·prime2v(SB), prime2
	MOVD ·prime3v(SB), prime3
	MOVD ·prime4v(SB), prime4
	MOVD ·prime5v(SB), prime5

	CMP  $32, len
	CSEL LO, prime5, ZR, h // if len < 32 { h = prime5 } else { h = 0 }
	BLO  afterLoop32

	ADD  prime1, prime2, v1
	MOVD prime2, v2
	MOVD $0, v3
	NEG  prime1, v4

	blocksLoop(loop32)

	ROR $63, v1, x1
	ROR $57, v2, x2
	ADD x1, x2
	ROR $52, v3, x3
	ROR $46, v4, x4
	ADD x3, x4
	ADD x2, x4, h

	mergeRound(v1)
	mergeRound(v2)
	mergeRound(v3)
	mergeRound(v4)

afterLoop32:
	ADD len, h

	AND $31, len
	CMP $8, len
	BLO try4

	LSR $3, len, nblocks
loop8:
	SUBS   $1, nblocks
	MOVD.P 8(p), x1
	round0(x1)
	EOR    x1, h
	ROR    $37, h
	MADD   h, prime4, prime1, h
	BNE    loop8

try4:
	CMP $4, len
	BLO beforeLoop1

	MOVWU.P 4(p), x2
	MUL     prime1, x2
	EOR     x2, h
	ROR     $41, h
	MADD    h, prime3, prime2, h

beforeLoop1:
	ANDS $3, len
	BEQ  end
loop1:
	SUBS    $1, len
	MOVBU.P 1(p), x3
	MUL     prime5, x3
	EOR     x3, h
	ROR     $53, h
	MUL     prime1, h
	BNE     loop1

end:
	EOR h >> 33, h
	MUL prime2,  h
	EOR h >> 29, h
	MUL prime3,  h
	EOR h >> 32, h

	MOVD h, ret+24(FP)
	RET

// func writeBlocks(d *Digest, b []byte) int
//
// Assumes len(b) >= 32.
TEXT ·writeBlocks(SB), NOFRAME+NOSPLIT, $0-40
	MOVD ·prime1v(SB), prime1
	MOVD ·prime2v(SB), prime2

	// Load state. Assume v[1-4] are stored contiguously.
	MOVD d+0(FP), digest
	LDP   0(digest), (v1, v2)
	LDP  16(digest), (v3, v4)

	LDP b_base+8(FP), (p, len)

	blocksLoop(loop)

	// Store updated state.
	STP (v1, v2),  0(digest)
	STP (v3, v4), 16(digest)

	BIC  $31, len
	MOVD len, ret+32(FP)
	RET
