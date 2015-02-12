; Raspberry Pi 2 'Bare Metal' Julia Fractal Animation Demo by krom (Peter Lemon):
; 1. Turn On L1 Cache
; 2. Turn On Advanced SIMD & Vector Floating Point Unit (NEON MPE)
; 3. Setup Frame Buffer
; 4. Plot Fractal Using Single-Precision
; 5. Change Julia Settings & Redraw To Animate

format binary as 'img'
include 'LIB\FASMARM.INC'
include 'LIB\R_PI2.INC'

; Setup Frame Buffer
SCREEN_X       = 640
SCREEN_Y       = 480
BITS_PER_PIXEL = 32

org $8000

; Start L1 Cache
mrc p15,0,r0,c1,c0,0 ; R0 = System Control Register
orr r0,$0004 ; Data Cache (Bit 2)
orr r0,$0800 ; Branch Prediction (Bit 11)
orr r0,$1000 ; Instruction Caches (Bit 12)
mcr p15,0,r0,c1,c0,0 ; System Control Register = R0

; Enable Advanced SIMD & Vector Floating Point Calculations (NEON MPE)
mrc p15,0,r0,c1,c0,2 ; R0 = Access Control Register
orr r0,$300000 + $C00000 ; Enable Single & Double Precision
mcr p15,0,r0,c1,c0,2 ; Access Control Register = R0
mov r0,$40000000 ; R0 = Enable VFP
vmsr fpexc,r0 ; FPEXC = R0

FB_Init:
  imm32 r0,FB_STRUCT + MAIL_TAGS
  imm32 r1,PERIPHERAL_BASE + MAIL_BASE + MAIL_WRITE + MAIL_TAGS
  str r0,[r1] ; Mail Box Write

  ldr r0,[FB_POINTER] ; R0 = Frame Buffer Pointer
  cmp r0,0 ; Compare Frame Buffer Pointer To Zero
  beq FB_Init ; IF Zero Re-Initialize Frame Buffer

ldr r1,[LAST_PIXEL]
add r1,r0 ; R1 = Frame Buffer Pointer Last Pixel

mov r2,SCREEN_X ; Load Single Screen X
fmsr s31,r2
fsitos s0,s31 ; S0 = X%
fcpys s2,s0   ; S2 = SX

mov r2,SCREEN_Y ; Load Single Screen Y
fmsr s31,r2
fsitos s1,s31 ; S1 = Y%
fcpys s3,s1   ; S3 = SY

flds s4,[XMAX] ; S4 = XMax
flds s5,[YMAX] ; S5 = YMax
flds s6,[XMIN] ; S6 = XMin
flds s7,[YMIN] ; S7 = YMin
flds s8,[ANIM] ; S8 = Anim
flds s9,[ONE]  ; S9 = 1.0

fcpys s12,s9 ; S12 = CX (1.0)
fcpys s13,s7 ; S13 = CY (-2.0)

ldr r12,[COL_MUL] ; R12 = Multiply Colour

Refresh:
  mov r2,r0 ; R2 = Frame Buffer Pointer
  mov r3,r1 ; R3 = Frame Buffer Pointer Last Pixel
  fcpys s1,s3 ; S1 = Y%
  LoopY:
    fcpys s0,s2 ; S0 = X%
    LoopX:
      vsub.f32 d5,d2,d3 ; ZX = XMin + ((X% * (XMax - XMin)) / SX)
      vmul.f32 d5,d0	; ZY = YMin + ((Y% * (YMax - YMin)) / SY)
      fdivs s10,s2
      fdivs s11,s3
      vadd.f32 d5,d3 ; S10 = ZX, S11 = ZY

      mov r4,192 ; R4 = IT (Iterations)
      Iterate:
	fmuls s14,s11,s11 ; XN = ((ZX * ZX) - (ZY * ZY)) + CX
	fmscs s14,s10,s10
	fadds s14,s12 ; S14 = XN

	fmuls s15,s10,s11 ; YN = (2 * ZX * ZY) + CY
	fadds s15,s15
	fadds s15,s13 ; S15 = YN

	fcpyd d5,d7 ; Copy XN & YN To ZX & ZY For Next Iteration

	fmuls s14,s14 ; R = (XN * XN) + (YN * YN)
	fmacs s14,s15,s15 ; S14 = R

	ftouis s31,s14 ; IF (R > 4) Plot
	fmrs r5,s31
	cmp r5,4
	bgt Plot

	subs r4,1 ; IT -= 1
	bne Iterate ; IF (IT != 0) Iterate

      Plot:
	mul r4,r12 ; R3 = Pixel Colour
	orr r4,$FF000000 ; Force Alpha To $FF
	str r4,[r2],4  ; Store Pixel Colour To Frame Buffer (Top)
	str r4,[r3],-4 ; Store Pixel Colour To Frame Buffer (Bottom)

	fsubs s0,s9 ; Decrement X%
	fcmpzs s0
	fmstat
	bne LoopX ; IF (X% != 0) LoopX

	fsubs s1,s9 ; Decrement Y%
	cmp r2,r3
	blt LoopY ; IF (Y% != 0) LoopY

	fsubs s12,s8 ; Change Julia Settings
	fadds s13,s8
	b Refresh

XMAX: dw 3.0
YMAX: dw 2.0
XMIN: dw -3.0
YMIN: dw -2.0
ANIM: dw 0.001
ONE:  dw 1.0

COL_MUL: dw $231AF9 ; Multiply Colour
LAST_PIXEL: dw (SCREEN_X * SCREEN_Y * (BITS_PER_PIXEL / 8)) - (BITS_PER_PIXEL / 8)

align 16
FB_STRUCT: ; Mailbox Property Interface Buffer Structure
  dw FB_STRUCT_END - FB_STRUCT ; Buffer Size In Bytes (Including The Header Values, The End Tag And Padding)
  dw $00000000 ; Buffer Request/Response Code
	       ; Request Codes: $00000000 Process Request Response Codes: $80000000 Request Successful, $80000001 Partial Response
; Sequence Of Concatenated Tags
  dw Set_Physical_Display ; Tag Identifier
  dw $00000008 ; Value Buffer Size In Bytes
  dw $00000008 ; 1 bit (MSB) Request/Response Indicator (0=Request, 1=Response), 31 bits (LSB) Value Length In Bytes
  dw SCREEN_X ; Value Buffer
  dw SCREEN_Y ; Value Buffer

  dw Set_Virtual_Buffer ; Tag Identifier
  dw $00000008 ; Value Buffer Size In Bytes
  dw $00000008 ; 1 bit (MSB) Request/Response Indicator (0=Request, 1=Response), 31 bits (LSB) Value Length In Bytes
  dw SCREEN_X ; Value Buffer
  dw SCREEN_Y ; Value Buffer

  dw Set_Depth ; Tag Identifier
  dw $00000004 ; Value Buffer Size In Bytes
  dw $00000004 ; 1 bit (MSB) Request/Response Indicator (0=Request, 1=Response), 31 bits (LSB) Value Length In Bytes
  dw BITS_PER_PIXEL ; Value Buffer

  dw Set_Virtual_Offset ; Tag Identifier
  dw $00000008 ; Value Buffer Size In Bytes
  dw $00000008 ; 1 bit (MSB) Request/Response Indicator (0=Request, 1=Response), 31 bits (LSB) Value Length In Bytes
FB_OFFSET_X:
  dw 0 ; Value Buffer
FB_OFFSET_Y:
  dw 0 ; Value Buffer

  dw Allocate_Buffer ; Tag Identifier
  dw $00000008 ; Value Buffer Size In Bytes
  dw $00000008 ; 1 bit (MSB) Request/Response Indicator (0=Request, 1=Response), 31 bits (LSB) Value Length In Bytes
FB_POINTER:
  dw 0 ; Value Buffer
  dw 0 ; Value Buffer

dw $00000000 ; $0 (End Tag)
FB_STRUCT_END: